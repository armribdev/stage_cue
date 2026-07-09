import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

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

/// Gère la sortie de **pré-écoute (cue)** séparée, sur desktop.
///
/// flutter_soloud pilote un moteur unique (pads + régie = sortie « salle ») :
/// impossible d'y router une seconde sortie simultanée. media_kit fournit donc
/// un moteur indépendant, dédié aux auditions, capable de cibler un device
/// distinct (casque) pendant que la salle continue sur le device système.
///
/// Le cue est **opt-in** : tant qu'aucun device n'est choisi
/// ([selectedDeviceId] `null`), la pré-écoute retombe sur flutter_soloud —
/// comportement historique, zéro régression. Fonctionnalité Windows d'abord :
/// sur les autres plateformes, [isSupported] est faux et le repli s'applique.
class CueAudioService {
  CueAudioService._();

  static final CueAudioService instance = CueAudioService._();

  /// Sortie séparée disponible uniquement sur desktop Windows pour l'instant.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  String? _selectedDeviceId;
  List<CueDevice> _cachedDevices = const [];

  /// Identifiant du device cue courant, ou `null` pour « défaut système »
  /// (dans ce cas la pré-écoute passe par flutter_soloud).
  String? get selectedDeviceId => _selectedDeviceId;

  /// Vrai si un device cue distinct est configuré (donc media_kit est utilisé).
  bool get isCueActive => isSupported && _selectedDeviceId != null;

  /// Dernière liste de devices connue (peuplée par [refreshDevices]).
  List<CueDevice> get cachedDevices => _cachedDevices;

  /// Applique le device persisté au démarrage (appelé depuis `main`).
  void init({String? selectedDeviceId}) {
    _selectedDeviceId = selectedDeviceId;
  }

  /// Change le device cue courant (`null` = défaut système → flutter_soloud).
  void setSelectedDevice(String? deviceId) {
    _selectedDeviceId = deviceId;
  }

  /// Énumère les périphériques de sortie disponibles (best-effort).
  ///
  /// Crée un lecteur media_kit éphémère le temps de lire la liste puis le
  /// libère — on ne garde pas de moteur inactif en permanence. Retourne le
  /// cache précédent en cas d'échec.
  Future<List<CueDevice>> refreshDevices() async {
    if (!isSupported) return const [];
    final player = Player();
    try {
      var devices = player.state.audioDevices;
      if (devices.isEmpty) {
        devices = await player.stream.audioDevices
            .firstWhere((d) => d.isNotEmpty)
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => player.state.audioDevices,
            );
      }
      _cachedDevices = [
        for (final d in devices)
          if (d.name != 'auto')
            CueDevice(
              id: d.name,
              label: d.description.isNotEmpty ? d.description : d.name,
            ),
      ];
      return _cachedDevices;
    } catch (e) {
      debugPrint('Énumération des devices cue échouée: $e');
      return _cachedDevices;
    } finally {
      await player.dispose();
    }
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
    // Device connu → on réutilise son libellé ; sinon (cache non peuplé ou
    // device débranché) on reconstruit par nom : media_kit ne se sert que du
    // nom, et retombe sur le défaut système s'il est introuvable.
    return AudioDevice(id, label);
  }

  /// Fabrique un lecteur de pré-écoute routé sur le bon moteur :
  /// media_kit (device cue) si le cue est actif, sinon flutter_soloud.
  ///
  /// [ephemeral] n'a d'effet que sur le repli soloud (source isolée du cache
  /// des pads) ; media_kit ne partage aucun cache, la distinction est inutile.
  Future<PreviewPlayback> createPreviewPlayer(
    String filePath, {
    bool ephemeral = false,
  }) async {
    final device = _resolveSelectedDevice();
    if (device == null) {
      return ephemeral
          ? AudioPlayerService.createEphemeral(filePath)
          : AudioPlayerService.create(filePath);
    }
    try {
      return await CuePreviewPlayer.create(filePath, device: device);
    } catch (e) {
      // Repli soloud si media_kit échoue (device indisponible, format…) :
      // la pré-écoute reste fonctionnelle sur la sortie par défaut.
      debugPrint('Pré-écoute cue (media_kit) échouée, repli soloud: $e');
      return ephemeral
          ? AudioPlayerService.createEphemeral(filePath)
          : AudioPlayerService.create(filePath);
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
      debugPrint('CuePreviewPlayer.playFromPosition erreur: $e');
      return false;
    }
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
