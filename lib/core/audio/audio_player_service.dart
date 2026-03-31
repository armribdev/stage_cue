import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Service de gestion des lecteurs audio (basé sur flutter_soloud)
/// Préchargement des sources pour une latence minimale au déclenchement
class AudioPlayerService {
  final AudioSource _source;
  SoundHandle? _currentHandle;
  final _stateController = StreamController<bool>.broadcast();
  StreamSubscription? _soundEventsSubscription;

  AudioPlayerService._(this._source) {
    _soundEventsSubscription = _source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid &&
          event.handle == _currentHandle) {
        _currentHandle = null;
        _stateController.add(false);
      }
    });
  }

  /// Crée un service en préchargeant le fichier audio (latence minimale au play)
  static Future<AudioPlayerService> create(String filePath) async {
    final source = await SoLoud.instance.loadFile(
      filePath,
      mode: LoadMode.memory,
    );
    return AudioPlayerService._(source);
  }

  /// Joue le son (quasi instantané car préchargé)
  Future<void> play() async {
    try {
      if (_currentHandle != null && SoLoud.instance.getIsValidVoiceHandle(_currentHandle!)) {
        await SoLoud.instance.stop(_currentHandle!);
      }
      _currentHandle = await SoLoud.instance.play(_source);
      _stateController.add(true);
    } catch (e) {
      debugPrint('Erreur lors de la lecture: $e');
    }
  }

  /// Arrête la lecture
  Future<void> stop() async {
    if (_currentHandle != null && SoLoud.instance.getIsValidVoiceHandle(_currentHandle!)) {
      await SoLoud.instance.stop(_currentHandle!);
    }
    _currentHandle = null;
    _stateController.add(false);
  }

  /// Définit le volume (0.0 -> 1.0)
  void setVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    if (_currentHandle != null && SoLoud.instance.getIsValidVoiceHandle(_currentHandle!)) {
      SoLoud.instance.setVolume(_currentHandle!, clamped);
    }
  }

  /// Écoute les changements d'état du lecteur (true = en cours, false = arrêté)
  Stream<bool> get onPlayerStateChanged => _stateController.stream;

  /// Obtient la durée du fichier audio
  Duration get duration => SoLoud.instance.getLength(_source);

  /// Indique si le son est actuellement en cours de lecture
  bool get isPlaying =>
      _currentHandle != null &&
      SoLoud.instance.getIsValidVoiceHandle(_currentHandle!);

  /// Dispose les ressources
  void dispose() {
    _soundEventsSubscription?.cancel();
    if (_currentHandle != null && SoLoud.instance.getIsValidVoiceHandle(_currentHandle!)) {
      SoLoud.instance.stop(_currentHandle!);
    }
    SoLoud.instance.disposeSource(_source);
    _stateController.close();
  }
}
