import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_load_log.dart';
import 'audio_player_service.dart';
import 'preview_playback.dart';

/// Un périphérique de sortie disponible pour la pré-écoute (cue).
///
/// [id] est l'identifiant stable persisté (nom media_kit) ; [label] est le
/// libellé lisible affiché dans les réglages. On expose ce DTO plutôt que le
/// type `AudioDevice` de media_kit pour garder le moteur cue confiné à ce
/// fichier (l'UI et les préférences n'importent pas media_kit).
@immutable
class CueDevice {
  final String id;
  final String label;

  const CueDevice({required this.id, required this.label});
}

/// La pré-écoute au casque est impossible : aucun device choisi, device
/// débranché ou média illisible sur ce device.
///
/// Levée à la place d'un repli sur la sortie salle : une pré-écoute destinée au
/// casque ne doit jamais devenir audible du public
/// ([décision 0027](../../docs/decisions/0027-preecoute-casque-stricte.md)).
/// [message] est lisible tel quel par l'utilisateur.
class CueUnavailableException implements Exception {
  final String message;

  const CueUnavailableException(this.message);

  @override
  String toString() => 'CueUnavailableException: $message';
}

/// Gère la sortie de **pré-écoute (cue)** séparée, sur Windows.
///
/// flutter_soloud pilote un moteur unique (pads + régie = sortie « salle ») :
/// impossible d'y router une seconde sortie simultanée. media_kit fournit donc
/// un moteur indépendant, dédié aux auditions, capable de cibler un device
/// distinct (casque) pendant que la salle continue sur le device système.
///
/// Le cue est **opt-in** : tant qu'aucun device n'est choisi
/// ([selectedDeviceId] `null`), la pré-écoute ordinaire retombe sur
/// flutter_soloud (comportement historique). Dès qu'un device est choisi, elle
/// est **stricte** : si le casque est indisponible, [createPreviewPlayer] lève
/// [CueUnavailableException] au lieu de basculer sur la salle. Support limité à
/// Windows : ailleurs [isSupported] est faux et le repli ordinaire s'applique.
class CueAudioService {
  CueAudioService._();

  static final CueAudioService instance = CueAudioService._();

  /// Override tests : `true`/`false` force le support ; `null` = détection
  /// plateforme réelle (Windows hors web).
  @visibleForTesting
  static bool? debugOverrideSupported;

  /// Sortie séparée disponible uniquement sur Windows.
  static bool get isSupported =>
      debugOverrideSupported ?? (!kIsWeb && Platform.isWindows);

  /// Libellé du périphérique de sortie par défaut du système — celui sur lequel
  /// flutter_soloud joue, donc la salle. `null` si indéterminable.
  ///
  /// Relu à chaque appel : le défaut Windows change quand on branche un casque
  /// qui s'impose comme sortie par défaut.
  static String? _roomDeviceName() {
    try {
      for (final d in SoLoud.instance.listPlaybackDevices()) {
        if (d.isDefault) return d.name;
      }
    } catch (e) {
      AudioLoadLog.warn('Périphérique par défaut introuvable : $e');
    }
    return null;
  }

  /// Vrai si [label] désigne la sortie de la salle. Les deux moteurs lisent le
  /// nom convivial du périphérique Windows : on compare sur ce libellé.
  static bool _isRoomDevice(String label, String? roomName) =>
      roomName != null &&
      label.trim().toLowerCase() == roomName.trim().toLowerCase();

  /// Retire de [devices] la sortie de la salle ([roomName]) : la proposer comme
  /// casque ferait entendre les pré-écoutes au public. Sans [roomName]
  /// (indéterminable), la liste est rendue telle quelle.
  @visibleForTesting
  static List<CueDevice> excludeRoomDevice(
    List<CueDevice> devices,
    String? roomName,
  ) => [
    for (final d in devices)
      if (!_isRoomDevice(d.label, roomName)) d,
  ];

  String? _selectedDeviceId;
  List<CueDevice> _cachedDevices = const [];

  /// Identifiant du device cue courant, ou `null` pour « défaut système »
  /// (dans ce cas la pré-écoute passe par flutter_soloud).
  String? get selectedDeviceId => _selectedDeviceId;

  /// Vrai si un device cue distinct est configuré (donc media_kit est utilisé).
  bool get isCueActive => isSupported && _selectedDeviceId != null;

  /// Dernière liste de devices connue (peuplée par [refreshDevices]).
  List<CueDevice> get cachedDevices => _cachedDevices;

  String? _excludedRoomLabel;

  /// Libellé de la sortie par défaut du système retirée de la dernière liste
  /// (la salle), ou `null` si [refreshDevices] n'a rien exclu. Sert à expliquer
  /// pourquoi un périphérique branché n'est pas proposé.
  String? get excludedRoomLabel => _excludedRoomLabel;

  /// Applique le device persisté au démarrage (appelé depuis `main`).
  void init({String? selectedDeviceId}) {
    _selectedDeviceId = selectedDeviceId;
  }

  /// Change le device cue courant (`null` = défaut système → flutter_soloud).
  void setSelectedDevice(String? deviceId) {
    final changed = _selectedDeviceId != deviceId;
    _selectedDeviceId = deviceId;
    if (changed) AudioLoadLog.cueOutputChanged(configured: deviceId != null);
  }

  /// Énumère les périphériques de sortie disponibles (best-effort).
  ///
  /// Crée un lecteur media_kit éphémère le temps de lire la liste puis le
  /// libère — on ne garde pas de moteur inactif en permanence. Retourne le
  /// cache précédent en cas d'échec.
  Future<List<CueDevice>> refreshDevices() async {
    if (!isSupported) return const [];
    Player? player;
    try {
      player = Player();
      final devices = await _awaitAudioDevices(player);
      final roomName = _roomDeviceName();
      final all = [
        for (final d in devices)
          if (d.name != 'auto')
            CueDevice(
              id: d.name,
              label: d.description.isNotEmpty ? d.description : d.name,
            ),
      ];
      _cachedDevices = excludeRoomDevice(all, roomName);
      // Seulement si l'exclusion a réellement retiré un périphérique : sinon
      // l'afficher laisserait croire qu'un casque est écarté à tort.
      _excludedRoomLabel = _cachedDevices.length < all.length ? roomName : null;
      // Une ligne par actualisation : sans elle, une liste vide est
      // indiscernable d'une énumération qui n'a rien vu.
      AudioLoadLog.info(
        'Sorties cue : media_kit voit ${all.length} périphérique(s) '
        '[${all.map((d) => d.label).join(' | ')}], défaut système (salle) = '
        '${roomName ?? 'inconnu'}, ${_cachedDevices.length} proposée(s)'
        '${_excludedRoomLabel != null ? ', salle exclue' : ''}.',
      );
      return _cachedDevices;
    } catch (e) {
      AudioLoadLog.cueDevicesEnumerationFailed(e);
      return _cachedDevices;
    } finally {
      await player?.dispose();
    }
  }

  /// Vrai si [devices] contient autre chose que l'entrée virtuelle « auto ».
  ///
  /// L'état initial d'un lecteur media_kit est `[auto]` — jamais vide : tester
  /// `isNotEmpty` prenait ce faux départ pour la vraie liste (mpv la publie plus
  /// tard par événement) et ne voyait alors aucun périphérique.
  @visibleForTesting
  static bool hasRealDevice(List<AudioDevice> devices) =>
      devices.any((d) => d.name != 'auto');

  /// Liste des devices que [player] voit, en attendant brièvement la première
  /// énumération (vide à la création du lecteur, peuplée de façon asynchrone).
  static Future<List<AudioDevice>> _awaitAudioDevices(Player player) async {
    final known = player.state.audioDevices;
    if (hasRealDevice(known)) return known;
    return player.stream.audioDevices
        .firstWhere(hasRealDevice)
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => player.state.audioDevices,
        );
  }

  /// Résout le device media_kit sélectionné, ou `null` s'il faut rester sur
  /// flutter_soloud (non supporté, ou aucun device choisi).
  AudioDevice? _resolveSelectedDevice() {
    if (!isCueActive) return null;
    final id = _selectedDeviceId!;
    var label = '';
    for (final d in _cachedDevices) {
      if (d.id == id) {
        label = d.label;
        break;
      }
    }
    // media_kit ne se sert que du nom. Le libellé importe peu ici : la
    // présence réelle du device est vérifiée à la création du lecteur
    // ([CuePreviewPlayer.create]), car media_kit retomberait sinon en silence
    // sur le défaut système — la salle.
    return AudioDevice(id, label);
  }

  /// Fabrique un lecteur de pré-écoute routé sur le bon moteur :
  /// media_kit (device cue) si le cue est actif, sinon flutter_soloud.
  ///
  /// Quand le cue est actif, il n'y a **aucun repli** sur flutter_soloud : un
  /// échec lève [CueUnavailableException]. [requireCue] étend cette rigueur au
  /// cas « aucun device choisi » — pour les écoutes qui n'ont de sens qu'au
  /// casque (pad du plateau) et ne doivent jamais sortir en salle.
  ///
  /// [ephemeral] n'a d'effet que sur le chemin soloud (source isolée du cache
  /// des pads) ; media_kit ne partage aucun cache, la distinction est inutile.
  Future<PreviewPlayback> createPreviewPlayer(
    String filePath, {
    bool ephemeral = false,
    bool requireCue = false,
  }) async {
    final device = _resolveSelectedDevice();
    if (device == null) {
      if (requireCue) {
        throw const CueUnavailableException(
          'Aucune sortie casque configurée — choisissez-en une dans '
          'Paramètres.',
        );
      }
      return ephemeral
          ? AudioPlayerService.createEphemeral(filePath)
          : AudioPlayerService.create(filePath);
    }
    try {
      return await CuePreviewPlayer.create(filePath, device: device);
    } on CueUnavailableException catch (e) {
      AudioLoadLog.cueRefused(e.message);
      rethrow;
    } catch (e) {
      AudioLoadLog.cueRefused('$e');
      throw const CueUnavailableException(
        'Sortie casque indisponible — pré-écoute annulée.',
      );
    }
  }
}

/// Lecteur de pré-écoute adossé à media_kit, ciblant un device de sortie
/// précis. Respecte [PreviewPlayback] pour un remplacement transparent de
/// [AudioPlayerService] sur les chemins d'audition.
class CuePreviewPlayer implements PreviewPlayback {
  final Player _player;
  final StreamController<bool> _stateController;
  StreamSubscription<bool>? _playingSub;
  final Duration _duration;
  bool _paused = false;

  CuePreviewPlayer._(this._player, this._duration)
    : _stateController = StreamController<bool>.broadcast() {
    // `playing` reflète l'état audible : true à la lecture, false à l'arrêt,
    // à la pause et en fin de piste — même sémantique que le lecteur soloud.
    _playingSub = _player.stream.playing.listen(_stateController.add);
  }

  /// Charge [filePath] (en pause) sur le [device] choisi et attend que la
  /// durée soit connue, pour aligner le comportement synchrone attendu par les
  /// appelants (`player.duration` juste après la création).
  static Future<CuePreviewPlayer> create(
    String filePath, {
    required AudioDevice device,
  }) async {
    final player = Player();
    try {
      // Sans cette vérification, un device débranché ou introuvable est
      // accepté par mpv qui joue alors sur le défaut système (la salle).
      final available = await CueAudioService._awaitAudioDevices(player);
      final chosen = available.where((d) => d.name == device.name).firstOrNull;
      if (chosen == null) {
        throw const CueUnavailableException(
          'Sortie casque introuvable (débranchée ?) — pré-écoute annulée.',
        );
      }
      // Le casque choisi a pu devenir la sortie par défaut du système depuis
      // (branchement à chaud) : il serait alors la salle.
      final label = chosen.description.isNotEmpty
          ? chosen.description
          : chosen.name;
      if (CueAudioService._isRoomDevice(
        label,
        CueAudioService._roomDeviceName(),
      )) {
        throw const CueUnavailableException(
          'Le périphérique choisi est la sortie par défaut (la salle) — '
          'choisissez un autre casque dans Paramètres.',
        );
      }
      await player.setAudioDevice(device);
      await player.open(Media(filePath), play: false);
      var duration = player.state.duration;
      if (duration <= Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => player.state.duration,
            );
      }
      return CuePreviewPlayer._(player, duration);
    } catch (e) {
      await player.dispose();
      rethrow;
    }
  }

  @override
  Duration get duration => _duration;

  @override
  Duration get position => _player.state.position;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  bool get isPaused => _paused;

  @override
  Stream<bool> get onPlayerStateChanged => _stateController.stream;

  @override
  Future<bool> playFromPosition(
    Duration position, {
    double volume = 1.0,
  }) async {
    try {
      // media_kit : volume sur 0–100 ; le volume applicatif est 0.0–1.0.
      await _player.setVolume(volume.clamp(0.0, 1.0) * 100);
      await _player.seek(position);
      await _player.play();
      _paused = false;
      _stateController.add(true);
      return true;
    } catch (e) {
      AudioLoadLog.warn('Pré-écoute cue : lecture impossible — $e');
      return false;
    }
  }

  @override
  void setVolume(double volume) {
    unawaited(_player.setVolume(volume.clamp(0.0, 1.0) * 100));
  }

  @override
  Future<void> pause() async {
    if (_paused) return;
    await _player.pause();
    _paused = true;
    _stateController.add(false);
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    await _player.play();
    _paused = false;
    _stateController.add(true);
  }

  @override
  Future<void> stop() async {
    // Pause + retour au début plutôt que `stop()` (qui décharge le média) :
    // la source reste chargée pour une éventuelle re-lecture.
    await _player.pause();
    await _player.seek(Duration.zero);
    _paused = false;
    _stateController.add(false);
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    unawaited(_player.dispose());
    _stateController.close();
  }
}
