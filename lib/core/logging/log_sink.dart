import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'log_redactor.dart';

enum LogLevel {
  trace('TRACE'),
  info('INFO'),
  warn('WARN'),
  severe('ERROR');

  final String label;
  const LogLevel(this.label);
}

typedef LogFileWriter = Future<void> Function(File file, String text);

/// Journal fichier persistant (cf. ADR 0025).
///
/// Alimenté par `SyncLog`, `AudioLoadLog`, `UpdateLog` et `AppLog` : ces
/// classes gardent leur `developer.log` et transmettent en plus ici. Classe à
/// méthodes statiques comme elles — pas d'injection, pas de gestionnaire d'état.
///
/// Règle d'or : **un log ne casse jamais l'app et ne ralentit jamais la
/// lecture.**
/// - [log] ne fait aucune E/S et ne retourne pas de Future : il formate, masque
///   les secrets et pousse dans un buffer mémoire.
/// - L'écriture se fait en tâche de fond (flush périodique ~1 s, immédiat sur
///   `severe` et à la mise en arrière-plan), via l'API asynchrone de `dart:io`,
///   sur une chaîne sérialisée.
/// - Toute erreur d'E/S (disque plein, fichier verrouillé) est avalée et
///   comptée dans [lostLines] ; la ligne perdue est signalée à la prochaine
///   écriture réussie.
///
/// Format d'une ligne : `2026-10-19T21:04:11.482 WARN  Audio  message`, les
/// lignes de continuation (stack trace, message multiligne) indentées dessous.
///
/// Rotation bornée : `stage-cue.log` + 2 archives (`.1.log`, `.2.log`) de
/// ~[maxFileBytes] chacune, tournées au démarrage de session et au
/// dépassement.
class LogSink {
  LogSink._();

  static const String currentFileName = 'stage-cue.log';
  static const int archiveCount = 2;
  static const int defaultMaxFileBytes = 1024 * 1024;

  /// Plafond du buffer d'avant-[init] : l'app démarre sans disque prêt, mais un
  /// démarrage qui boucle ne doit pas non plus faire grossir la mémoire.
  static const int _maxBufferedLines = 2000;

  /// Au-delà, l'en-tête de session est jugé perdu (initialisation interrompue)
  /// et on écrit quand même ce qu'on a.
  static const Duration _headerDeadline = Duration(seconds: 15);

  static Directory? _directory;
  static DateTime Function() _clock = DateTime.now;
  static LogFileWriter _writer = _defaultWriter;
  static int _maxFileBytes = defaultMaxFileBytes;
  static Timer? _flushTimer;
  static Timer? _headerTimer;

  static final List<String> _buffer = [];
  static int _droppedBeforeInit = 0;

  /// Tant que l'en-tête de session n'est pas posé, rien n'est écrit : il doit
  /// rester la première chose du fichier, alors que le sink démarre avant
  /// `AppServices` (donc avant de connaître le schéma, le cue, etc.).
  static bool _headerPending = false;
  static List<String> _headerLines = const [];

  /// Instant du démarrage de session : l'en-tête est posé plus tard (une fois
  /// `AppServices` prêt) mais doit rester daté d'avant les premiers événements.
  static DateTime _sessionStart = DateTime.now();

  static Future<void> _chain = Future<void>.value();
  static int _currentSize = 0;
  static int _lostLines = 0;
  static int _lostReported = 0;
  static bool _ready = false;

  /// Lignes jamais écrites sur disque (erreur d'E/S ou buffer saturé).
  static int get lostLines => _lostLines + _droppedBeforeInit;

  static bool get isReady => _ready;

  static Directory? get directory => _directory;

  /// Instant de démarrage de la session courante.
  static DateTime get sessionStart => _sessionStart;

  /// En-tête de la session courante (vide tant qu'il n'est pas posé).
  static String get sessionHeader => _headerLines.join('\n');

  /// Prépare le dossier et fait tourner les fichiers (début de session).
  ///
  /// Ne lève jamais : un dossier inutilisable laisse le sink en mode « tout est
  /// perdu » plutôt que d'empêcher l'app de démarrer.
  static Future<void> init({
    required Directory directory,
    DateTime Function()? clock,
    LogFileWriter? writer,
    int maxFileBytes = defaultMaxFileBytes,
    Duration? flushInterval = const Duration(seconds: 1),
    bool rotateOnStart = true,
  }) async {
    _directory = directory;
    _clock = clock ?? DateTime.now;
    _writer = writer ?? _defaultWriter;
    _maxFileBytes = maxFileBytes;
    _headerPending = true;
    _headerLines = const [];
    _sessionStart = _clock();

    try {
      await directory.create(recursive: true);
      if (rotateOnStart) await _rotate();
      _currentSize = 0;
    } catch (_) {
      // Dossier inutilisable : chaque flush échouera et sera compté.
    }
    _ready = true;

    _flushTimer?.cancel();
    if (flushInterval != null) {
      _flushTimer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
    }
    _headerTimer?.cancel();
    _headerTimer = Timer(_headerDeadline, () {
      if (_headerPending) {
        _setHeader(const ['Session — en-tête incomplet (initialisation interrompue).']);
        unawaited(flush());
      }
    });
  }

  /// Pose l'en-tête de session : première chose écrite dans le fichier, avant
  /// tout événement déjà mis en buffer.
  static void writeSessionHeader(List<String> lines) {
    if (!_headerPending) return;
    _setHeader(lines);
  }

  static void _setHeader(List<String> lines) {
    _headerPending = false;
    _headerTimer?.cancel();
    final formatted = <String>[
      for (final line in lines)
        _format(_sessionStart, LogLevel.info, 'Session', line),
    ];
    _headerLines = List.unmodifiable(lines);
    _buffer.insertAll(0, formatted);
  }

  /// Enregistre un événement. Synchrone, sans E/S, ne lève jamais.
  static void log(
    String channel,
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    try {
      final buffer = StringBuffer(message);
      if (error != null) buffer.write(' | $error');
      if (stackTrace != null) buffer.write('\n$stackTrace');
      _buffer.add(_format(_clock(), level, channel, buffer.toString()));
      if ((!_ready || _headerPending) && _buffer.length > _maxBufferedLines) {
        _buffer.removeAt(0);
        _droppedBeforeInit++;
      }
      if (_ready && level == LogLevel.severe) {
        // Un incident peut précéder un crash : on n'attend pas l'en-tête ni le
        // prochain tick.
        if (_headerPending) {
          _setHeader(const ['Session — en-tête non encore disponible (erreur précoce).']);
        }
        unawaited(flush());
      }
    } catch (_) {
      // Un log ne plante jamais l'app.
    }
  }

  static String _format(
    DateTime at,
    LogLevel level,
    String channel,
    String message,
  ) {
    final safe = LogRedactor.redact(message);
    final prefix =
        '${at.toIso8601String()} ${level.label.padRight(5)} ${channel.padRight(6)} ';
    final lines = safe.trimRight().split('\n');
    final out = StringBuffer(prefix)..write(lines.first.trimRight());
    for (final line in lines.skip(1)) {
      out
        ..write('\n    ')
        ..write(line.trimRight());
    }
    return out.toString();
  }

  /// Écrit le buffer sur disque. Le Future résolu signale que l'écriture
  /// (réussie ou perdue) est terminée ; les appelants n'ont jamais à l'attendre
  /// sur le chemin d'une lecture audio.
  static Future<void> flush() {
    if (!_ready || _headerPending || _buffer.isEmpty) return _chain;
    final lines = List<String>.of(_buffer);
    _buffer.clear();
    _chain = _chain.then((_) => _write(lines)).catchError((_) {});
    return _chain;
  }

  static Future<void> _write(List<String> lines) async {
    final directory = _directory;
    if (directory == null) {
      _lostLines += lines.length;
      return;
    }
    try {
      final reportable = _lostLines - _lostReported;
      final head = reportable > 0
          ? '${_format(_clock(), LogLevel.warn, 'Log', '$reportable ligne(s) de journal perdue(s) (erreur d\'écriture).')}\n'
          : '';
      final text = '$head${lines.join('\n')}\n';
      final bytes = utf8.encode(text).length;

      if (_currentSize > 0 && _currentSize + bytes > _maxFileBytes) {
        await _rotate();
        _currentSize = 0;
      }
      await _writer(File(p.join(directory.path, currentFileName)), text);
      _currentSize += bytes;
      _lostReported += reportable;
    } catch (_) {
      _lostLines += lines.length;
    }
  }

  /// `stage-cue.log` → `.1.log` → `.2.log` (l'ancienne `.2` disparaît).
  static Future<void> _rotate() async {
    final directory = _directory;
    if (directory == null) return;
    String archive(int n) =>
        p.join(directory.path, 'stage-cue.$n.log');
    final current = File(p.join(directory.path, currentFileName));
    try {
      final oldest = File(archive(archiveCount));
      if (await oldest.exists()) await oldest.delete();
      for (var n = archiveCount - 1; n >= 1; n--) {
        final from = File(archive(n));
        if (await from.exists()) await from.rename(archive(n + 1));
      }
      if (await current.exists()) {
        if (await current.length() > 0) {
          await current.rename(archive(1));
        } else {
          await current.delete();
        }
      }
    } catch (_) {
      // Rotation ratée (fichier verrouillé) : on continue d'écrire dans le
      // fichier courant, la taille reste bornée au prochain essai.
    }
  }

  /// Fichiers de journal existants, du plus ancien au plus récent.
  static List<File> logFiles() {
    final directory = _directory;
    if (directory == null) return const [];
    final files = <File>[
      for (var n = archiveCount; n >= 1; n--)
        File(p.join(directory.path, 'stage-cue.$n.log')),
      File(p.join(directory.path, currentFileName)),
    ];
    return files.where((f) => f.existsSync()).toList();
  }

  /// Vide le buffer et arrête le timer (fermeture propre).
  static Future<void> shutdown() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _headerTimer?.cancel();
    _headerTimer = null;
    if (_headerPending) {
      _setHeader(const ['Session — en-tête non disponible (arrêt précoce).']);
    }
    await flush();
  }

  static Future<void> _defaultWriter(File file, String text) =>
      file.writeAsString(text, mode: FileMode.append, flush: false);

  /// Remet le sink à zéro entre deux tests.
  @visibleForTesting
  static Future<void> resetForTest() async {
    _flushTimer?.cancel();
    _headerTimer?.cancel();
    _flushTimer = null;
    _headerTimer = null;
    try {
      await _chain;
    } catch (_) {}
    _chain = Future<void>.value();
    _buffer.clear();
    _directory = null;
    _clock = DateTime.now;
    _writer = _defaultWriter;
    _maxFileBytes = defaultMaxFileBytes;
    _droppedBeforeInit = 0;
    _lostLines = 0;
    _lostReported = 0;
    _currentSize = 0;
    _headerPending = false;
    _headerLines = const [];
    _ready = false;
  }
}
