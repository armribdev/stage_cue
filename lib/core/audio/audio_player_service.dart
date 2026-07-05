import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_file_validation.dart';
import 'soloud_file_loader.dart';
import 'audio_load_log.dart';

/// Service de gestion des lecteurs audio (basé sur flutter_soloud)
/// Préchargement des sources pour une latence minimale au déclenchement.
///
/// Supporte deux modes de lecture sur une même source préchargée :
/// - mono-voix (`play`, `playFromPosition`, `playAtVolume`) : arrête la voix
///   précédente avant d'en lancer une nouvelle — utilisé par la musique
///   (seek, pause/reprise, fondus) ;
/// - polyphonique (`playOverlapping`) : superpose une nouvelle voix sans couper
///   les précédentes — utilisé par les pads non-musique (bruitages).
///
/// [_handles] contient toutes les voix actives (insertion-ordered).
/// [_currentHandle] est la voix la plus récente : cible des opérations
/// mono-voix (seek, position, fondu). En mode polyphonique il reste unique par
/// commodité mais [isPlaying] reflète l'ensemble des voix.
class AudioPlayerService {
  final AudioSource _source;
  final Set<SoundHandle> _handles = {};
  SoundHandle? _currentHandle;
  bool _paused = false;
  final _stateController = StreamController<bool>.broadcast();
  StreamSubscription? _soundEventsSubscription;

  AudioPlayerService._(this._source) {
    _soundEventsSubscription = _source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid) {
        final removed = _handles.remove(event.handle);
        if (event.handle == _currentHandle) {
          _currentHandle = _handles.isNotEmpty ? _handles.last : null;
        }
        debugPrint(
          '[AUDIO-EVT] handleIsNoMoreValid handle=${event.handle} '
          'removed=$removed remaining=${_handles.length}',
        );
        // Émettre l'arrêt uniquement quand la dernière voix se termine.
        if (removed && _handles.isEmpty) {
          _paused = false;
          _stateController.add(false);
        }
      }
    });
  }

  /// Crée un service en préchargeant le fichier audio (latence minimale au play)
  static Future<AudioPlayerService> create(String filePath) async {
    final file = File(filePath);
    try {
      final source = await loadAudioSourceFromFile(file);
      return AudioPlayerService._(source);
    } on UnsupportedAudioFormatException {
      rethrow;
    } catch (e) {
      if (e is! StateError) {
        AudioLoadLog.loadMemFailed(path: file.absolute.path, error: e);
      }
      throw StateError(
        'Impossible de charger le fichier audio : ${file.absolute.path} ($e)',
      );
    }
  }

  /// Lecteur éphémère (aperçu UI) : source SoLoud isolée du cache des pads.
  /// À utiliser pour l'éditeur de point d'entrée — évite qu'un [dispose] ne
  /// invalide les sources partagées par clé de chemin avec les pads préchargés.
  static Future<AudioPlayerService> createEphemeral(String filePath) async {
    final file = File(filePath);
    try {
      final source = await loadAudioSourceFromFile(
        file,
        memKeySuffix: '#ephemeral',
      );
      return AudioPlayerService._(source);
    } on UnsupportedAudioFormatException {
      rethrow;
    } catch (e) {
      if (e is! StateError) {
        AudioLoadLog.loadMemFailed(path: file.absolute.path, error: e);
      }
      throw StateError(
        'Impossible de charger le fichier audio : ${file.absolute.path} ($e)',
      );
    }
  }

  /// Joue le son (quasi instantané car préchargé), en mode mono-voix.
  Future<void> play() async {
    await playFromPosition(Duration.zero);
  }

  /// Lance la lecture à [position] (reprise après pause), en mode mono-voix :
  /// coupe la voix précédente avant d'en lancer une nouvelle.
  /// Retourne false si la voix n'a pas pu démarrer.
  Future<bool> playFromPosition(Duration position) async {
    debugPrint('[AUDIO-PLAY] playFromPosition pos=$position handles=${_handles.length}');
    try {
      await _stopAllHandles();
      final seekFirst = position > Duration.zero;
      final handle = await SoLoud.instance.play(_source, paused: seekFirst);
      _handles.add(handle);
      _currentHandle = handle;
      if (seekFirst) {
        SoLoud.instance.seek(handle, position);
        SoLoud.instance.setPause(handle, false);
      }
      if (!SoLoud.instance.getIsValidVoiceHandle(handle)) {
        _handles.remove(handle);
        _currentHandle = null;
        _paused = false;
        return false;
      }
      _paused = false;
      _stateController.add(true);
      return true;
    } catch (e) {
      debugPrint('[AUDIO-PLAY] ERROR: $e');
      return false;
    }
  }

  /// Superpose une nouvelle voix sans couper les précédentes (polyphonie).
  /// Utilisé par les pads non-musique : chaque déclenchement empile un son.
  /// [startOffset] démarre la voix à ce point d'entrée (via pause → seek →
  /// reprise, pour un départ net sans blip audible).
  Future<void> playOverlapping({
    double volume = 1.0,
    Duration startOffset = Duration.zero,
  }) async {
    try {
      final seekFirst = startOffset > Duration.zero;
      final handle = await SoLoud.instance.play(_source, paused: seekFirst);
      _handles.add(handle);
      _currentHandle = handle;
      SoLoud.instance.setVolume(handle, volume.clamp(0.0, 1.0));
      if (seekFirst) {
        SoLoud.instance.seek(handle, startOffset);
        SoLoud.instance.setPause(handle, false);
      }
      debugPrint('[AUDIO-PLAY] overlapping new handle=$handle total=${_handles.length}');
      // Ne notifier le passage à « en cours » que sur la première voix : les
      // suivantes ne changent pas l'état booléen du lecteur.
      if (_handles.length == 1) {
        _stateController.add(true);
      }
    } catch (e) {
      debugPrint('[AUDIO-PLAY] playOverlapping ERROR: $e');
    }
  }

  /// Met en pause la voix courante (mono-voix).
  Future<void> pause() async {
    if (!_hasActiveHandle || _paused) return;
    SoLoud.instance.setPause(_currentHandle!, true);
    _paused = true;
    _stateController.add(false);
  }

  /// Reprend la voix courante après [pause].
  Future<void> resume() async {
    if (!_hasActiveHandle || !_paused) return;
    SoLoud.instance.setPause(_currentHandle!, false);
    _paused = false;
    _stateController.add(true);
  }

  /// Arrête toutes les voix en cours.
  Future<void> stop() async {
    await _stopAllHandles();
    _paused = false;
    _stateController.add(false);
  }

  /// Arrête toutes les voix actives sans émettre d'état (usage interne).
  Future<void> _stopAllHandles() async {
    if (_handles.isEmpty) {
      _currentHandle = null;
      return;
    }
    // Vider d'abord : le listener soundEvents ne ré-émettra pas d'arrêt.
    final handles = List<SoundHandle>.from(_handles);
    _handles.clear();
    _currentHandle = null;
    _paused = false;
    for (final handle in handles) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        await SoLoud.instance.stop(handle);
      }
    }
  }

  /// Définit le volume (0.0 -> 1.0) sur toutes les voix actives.
  void setVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    for (final handle in _handles) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.setVolume(handle, clamped);
      }
    }
  }

  bool get _hasActiveHandle =>
      _currentHandle != null &&
      SoLoud.instance.getIsValidVoiceHandle(_currentHandle!);

  /// Lance la lecture à un volume initial donné (mode mono-voix).
  /// [startOffset] positionne la voix à ce point d'entrée avant de la rendre
  /// audible (départ net) — utilisé par les fondus enchaînés de la régie.
  Future<void> playAtVolume(double volume, {Duration startOffset = Duration.zero}) async {
    try {
      await _stopAllHandles();
      final seekFirst = startOffset > Duration.zero;
      final handle = await SoLoud.instance.play(_source, paused: seekFirst);
      _handles.add(handle);
      _currentHandle = handle;
      SoLoud.instance.setVolume(handle, volume.clamp(0.0, 1.0));
      if (seekFirst) {
        SoLoud.instance.seek(handle, startOffset);
        SoLoud.instance.setPause(handle, false);
      }
      _paused = false;
      _stateController.add(true);
    } catch (e) {
      debugPrint('Erreur lors de la lecture: $e');
    }
  }

  /// Fond le volume vers [to] sur [duration] (SoLoud gère l'interpolation).
  void fadeVolumeTo(double to, Duration duration) {
    if (!_hasActiveHandle) return;
    SoLoud.instance.fadeVolume(_currentHandle!, to.clamp(0.0, 1.0), duration);
  }

  /// Fondu sortant puis arrêt du lecteur.
  Future<void> fadeOutAndStop(Duration duration) async {
    if (!_hasActiveHandle) return;
    SoLoud.instance.fadeVolume(_currentHandle!, 0, duration);
    await Future<void>.delayed(duration);
    if (_hasActiveHandle) {
      await stop();
    }
  }

  /// Écoute les changements d'état du lecteur (true = en cours, false = arrêté)
  Stream<bool> get onPlayerStateChanged => _stateController.stream;

  /// Obtient la durée du fichier audio
  Duration get duration {
    try {
      return SoLoud.instance.getLength(_source);
    } catch (e) {
      debugPrint('Durée audio indisponible: $e');
      return Duration.zero;
    }
  }

  /// Position actuelle de lecture de la voix courante (0 si aucune active).
  Duration get position {
    if (!_hasActiveHandle) return Duration.zero;
    return SoLoud.instance.getPosition(_currentHandle!);
  }

  /// Indique si au moins une voix est audible (hors pause).
  bool get isPlaying => _handles.isNotEmpty && !_paused;

  /// Indique si la voix courante est en pause.
  bool get isPaused => _paused && _hasActiveHandle;

  /// Dispose les ressources
  void dispose() {
    _soundEventsSubscription?.cancel();
    try {
      for (final handle in _handles) {
        if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
          SoLoud.instance.stop(handle);
        }
      }
      _handles.clear();
      _currentHandle = null;
      _paused = false;
      SoLoud.instance.disposeSource(_source);
    } catch (e) {
      debugPrint('Erreur lors du dispose audio: $e');
    }
    _stateController.close();
  }
}
