import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/local_sound_probe.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/sync/download_queue.dart';
import '../../data/repositories/library_repository.dart'
    show LibraryRepository, SoundNotAvailableLocallyException;
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';
import '../models/pad_sound_slot.dart';
import '../utils/quick_search_prepare.dart';

part 'sampler_state.dart';
part 'music_controller.dart';

/// Provider/Notifier pour la gestion de l'état du sampler
class SamplerNotifier extends ChangeNotifier {
  final SoundRepository _repository;
  final LoadSoundsUseCase _loadPadsUseCase;
  final RemoveSoundFromBoardUseCase? _removePadUseCase;

  /// Optionnel : résout le chemin local jouable d'un son de bibliothèque Drive
  /// (download/cache à la demande). Null = sons purement locaux.
  final LibraryRepository? _libraryRepository;

  final AppPreferences? _appPreferences;

  int? _activeBoardId;
  _RemovedPadSnapshot? _lastRemovedPad;

  /// Réinitialisé à chaque entrée en mode live (Mode Spectacle) : force le
  /// tout premier pad ajouté via la recherche-éclair sur une nouvelle ligne
  /// plutôt qu'à la suite de la dernière ligne déjà en place sur scène.
  bool _forceNewRowOnNextQuickAdd = false;
  int _draftPadIdSeq = -1;
  final _random = Random();

  /// Lecteurs dédiés à la pré-écoute (recherche-éclair) : indépendants des pads,
  /// du master musique et de la file. Plusieurs bruitages/ambiances peuvent
  /// jouer simultanément ; chacun se libère seul à la fin de sa lecture.
  final Set<AudioPlayerService> _previewPlayers = {};

  /// Lecteur unique pour l'aperçu bibliothèque (play/pause, un son à la fois).
  AudioPlayerService? _libraryPreviewPlayer;
  int? _libraryPreviewSoundId;
  StreamSubscription<bool>? _libraryPreviewSub;

  /// File de téléchargement priorisée à concurrence bornée (refonte UX P2).
  final DownloadQueue _downloadQueue = DownloadQueue(maxConcurrent: 2);

  static const int _downloadPriorityTap = 100;
  static const int _downloadPriorityManualPrepare = 50;
  static const int _downloadPriorityPrefetch = 10;

  /// Génération de préchargement courante : incrémentée à chaque changement de
  /// plateau pour annuler le prefetch en cours (annulation coopérative).
  int _prefetchGeneration = 0;

  /// Sons dont le fichier est confirmé absent du Drive. Bloque les retentatives
  /// pour la session courante. Réinitialisé à chaque rechargement de plateau.
  final Set<int> _driveNotFoundSoundIds = {};

  /// Sérialise les rechargements de plateau pour éviter les courses async.
  Future<void>? _loadSoundsChain;

  /// Annule le préchargement audio quand le plateau change.
  int _padPreloadGeneration = 0;

  /// Contrôleur musique : file, fondus, volume global musique.
  late final MusicController _music;

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;
  bool get offlineMode => isLiveOfflineMode;
  bool get isLiveOfflineMode =>
      _appPreferences?.isLiveOfflineMode ?? false;
  bool get allowsSoundDownload =>
      _appPreferences?.allowsSoundDownload ?? true;
  double get musicVolume => _music.musicVolume;

  bool get canUndoLastRemoval =>
      _lastRemovedPad != null && _lastRemovedPad!.boardId == _activeBoardId;

  SamplerNotifier(
    this._repository,
    this._loadPadsUseCase, [
    this._removePadUseCase,
    this._libraryRepository,
    AppPreferences? appPreferences,
  ]) : _appPreferences = appPreferences {
    _music = MusicController(this);
    appPreferences?.addListener(_onConnectivityModeChanged);
  }

  /// Wrapper non-protected sur [notifyListeners] — permet à [MusicController]
  /// (même bibliothèque) d'émettre des notifications sans déclencher un warning
  /// sur l'annotation @protected de ChangeNotifier.
  void _notify() => notifyListeners();

  /// Volume effectif d'un pad : pads musique soumis au volume global.
  double _effectiveVolume(PadItem padItem) => _music._effectiveVolume(padItem);

  /// Pad affiché sur le plateau en mode hors-ligne (au moins un son local).
  bool isPadVisibleInOfflineMode(PadItem padItem) {
    if (padItem.isDraft) return true;
    return padItem.hasLocallyAvailableSound;
  }

  /// Index des variantes avec fichier local validé.
  bool isSlotLocallyAvailable(PadItem padItem, int slotIndex) {
    if (slotIndex < 0 || slotIndex >= padItem.slots.length) return false;
    return padItem.slots[slotIndex].appearsReady;
  }

  Iterable<PadItem> _padsForMultipadNumbering() {
    return _state.pads.where(
      (item) =>
          !item.isDraft &&
          (!isLiveOfflineMode || item.hasLocallyAvailableSound),
    );
  }

  void _onConnectivityModeChanged() {
    if (isLiveOfflineMode) {
      _downloadQueue.cancelQueued((_, _) => true);
      unawaited(_applyLiveOfflineConstraints());
    }
    _syncMultipadNumbers(_padsForMultipadNumbering());
    notifyListeners();
  }

  Future<void> _applyLiveOfflineConstraints() async {
    final current = _state.currentMusicPad;
    if (current != null && !isPadVisibleInOfflineMode(current)) {
      await _music._stopMusicPad(current, manual: true);
    }
    final visibleIds = _padsForMultipadNumbering()
        .map((item) => item.pad.id)
        .toSet();
    final newQueue =
        _state.musicQueuePadIds.where(visibleIds.contains).toList();
    if (newQueue.length != _state.musicQueuePadIds.length) {
      _state = _state.copyWith(musicQueuePadIds: newQueue);
    }
  }

  /// Résout le chemin local jouable d'un son (cache Drive si bibliothèque).
  Future<String> _resolvePlayablePath(
    Sound sound, {
    bool downloadIfNeeded = false,
  }) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null) {
      try {
        final resolved = await libraryRepository.resolvePlayablePath(
          sound,
          downloadIfNeeded: downloadIfNeeded,
        );
        final file = File(resolved);
        if (!await file.exists()) {
          throw StateError(
            'Fichier audio introuvable : ${sound.displayName ?? sound.title}',
          );
        }
        return file.absolute.path;
      } on SoundNotAvailableLocallyException {
        rethrow;
      } catch (e) {
        debugPrint('Résolution du chemin échouée pour ${sound.title}: $e');
        if (sound.libraryId != null && sound.relativePath != null) rethrow;
        final file = File(sound.filePath);
        if (!await file.exists() || !await isPlausibleAudioFile(file)) {
          throw StateError(
            'Fichier audio introuvable : ${sound.displayName ?? sound.title}',
          );
        }
        return file.absolute.path;
      }
    }

    final file = File(sound.filePath);
    if (!await file.exists() || !await isPlausibleAudioFile(file)) {
      throw StateError(
        'Fichier audio introuvable : ${sound.displayName ?? sound.title}',
      );
    }
    return file.absolute.path;
  }

  PadUnavailabilityReason? _worstReason(
    PadUnavailabilityReason? current,
    PadUnavailabilityReason next,
  ) {
    const priority = {
      PadUnavailabilityReason.offline: 0,
      PadUnavailabilityReason.missingFile: 1,
      PadUnavailabilityReason.unsupportedFormat: 1,
      PadUnavailabilityReason.needsDownload: 2,
    };
    if (current == null) return next;
    return (priority[current] ?? 99) <= (priority[next] ?? 99) ? current : next;
  }

  PadSoundAvailability _availabilityFromException(Object e) {
    if (e is SoundNotAvailableLocallyException) {
      return e.isOffline
          ? PadSoundAvailability.offline
          : PadSoundAvailability.needsDownload;
    }
    return PadSoundAvailability.missingFile;
  }

  PadUnavailabilityReason? _unavailabilityFromAvailability(
    PadSoundAvailability availability,
  ) {
    return switch (availability) {
      PadSoundAvailability.ready => null,
      PadSoundAvailability.cached => null,
      PadSoundAvailability.needsDownload => PadUnavailabilityReason.needsDownload,
      PadSoundAvailability.offline => PadUnavailabilityReason.offline,
      PadSoundAvailability.missingFile => PadUnavailabilityReason.missingFile,
      PadSoundAvailability.unsupportedFormat =>
        PadUnavailabilityReason.unsupportedFormat,
    };
  }

  PadUnavailabilityReason? _unavailabilityFromSlot(PadSoundSlot slot) {
    if (slot.isReady || slot.isCached) return null;
    if (slot.availability == PadSoundAvailability.ready) {
      return PadUnavailabilityReason.missingFile;
    }
    return _unavailabilityFromAvailability(slot.availability);
  }

  PadSoundAvailability _availabilityFromProbe(LocalSoundProbeResult result) {
    return switch (result) {
      LocalSoundProbeResult.cached => PadSoundAvailability.cached,
      LocalSoundProbeResult.needsDownload => PadSoundAvailability.needsDownload,
      LocalSoundProbeResult.offline => PadSoundAvailability.offline,
      LocalSoundProbeResult.missingFile => PadSoundAvailability.missingFile,
    };
  }

  void _blockSoundDriveRetry(int soundId) => _driveNotFoundSoundIds.add(soundId);

  bool _isRetryableMissingLibrarySound(Sound sound) =>
      sound.libraryId != null &&
      sound.relativePath != null &&
      sound.relativePath!.isNotEmpty &&
      !_driveNotFoundSoundIds.contains(sound.id);

  bool isPadRetryableFromDrive(PadItem padItem) =>
      padItem.pad.sounds.any(_isRetryableMissingLibrarySound);

  bool isPadPreparable(PadItem padItem) => padItem.isPreparableForDownload;

  bool isPadTapBlocked(PadItem padItem) => padItem.isBlockedForPlayback;

  Future<void> _prepareRetryForMissingLibrarySound(
    PadItem padItem,
    int index,
  ) async {
    final sound = padItem.pad.sounds[index];
    if (!_isRetryableMissingLibrarySound(sound)) return;

    await _libraryRepository?.clearPlaybackBlockForSound(sound);
    padItem.slots[index] = PadSoundSlot(
      availability: PadSoundAvailability.needsDownload,
    );
    _finalizePadAvailability(padItem);
  }

  Future<PadSoundAvailability> _probeSoundLocalAvailability(Sound sound) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null &&
        sound.libraryId != null &&
        sound.relativePath != null &&
        sound.relativePath!.isNotEmpty) {
      // Sonde uniquement le cache local — pas de requête Drive ici.
      // Si le fichier est absent du cache, on reste en needsDownload.
      // L'état missingFile est établi à l'échec réel du téléchargement,
      // ce qui évite N requêtes Drive au chargement du plateau.
      return _availabilityFromProbe(
        await libraryRepository.probeLocalCache(sound),
      );
    }

    if (isKnownUnloadablePath(sound.filePath)) {
      return PadSoundAvailability.missingFile;
    }
    final file = File(sound.filePath);
    if (await isPlausibleAudioFile(file)) {
      return PadSoundAvailability.cached;
    }
    return PadSoundAvailability.missingFile;
  }

  Future<void> _probeSlotAtIndex(PadItem padItem, int index) async {
    if (index < 0 || index >= padItem.slots.length) return;
    final slot = padItem.slots[index];
    if (slot.isReady || slot.isCached) return;
    if (slot.availability == PadSoundAvailability.missingFile ||
        slot.availability == PadSoundAvailability.unsupportedFormat) {
      return;
    }

    final availability = await _probeSoundLocalAvailability(
      padItem.pad.sounds[index],
    );
    slot.dispose();
    padItem.slots[index] = PadSoundSlot(availability: availability);
  }

  Future<void> _probePadLocalAvailability(PadItem padItem) async {
    padItem.syncSlotCount();
    for (var i = 0; i < padItem.pad.sounds.length; i++) {
      await _probeSlotAtIndex(padItem, i);
    }
    _finalizePadAvailability(padItem);
  }

  void _finalizePadAvailability(PadItem padItem) {
    if (padItem.isPlayable) {
      padItem.unavailabilityReason = null;
      return;
    }
    PadUnavailabilityReason? worst;
    for (final slot in padItem.slots) {
      final reason = _unavailabilityFromSlot(slot);
      if (reason != null) worst = _worstReason(worst, reason);
    }
    padItem.unavailabilityReason = worst;
  }

  PadItem? findPadItemById(int padId) {
    for (final item in _state.pads) {
      if (item.pad.id == padId) return item;
    }
    return null;
  }

  PadItem _resolveBoardPadItem(PadItem padItem) =>
      findPadItemById(padItem.pad.id) ?? padItem;

  void _syncMultipadNumbers(Iterable<PadItem> padItems) {
    final numbers = Pad.multipadNumbersFor(padItems.map((item) => item.pad));
    for (final item in padItems) {
      item.multipadNumber = numbers[item.pad.id];
    }
  }

  Future<void> _syncPadSoundMetadata(PadItem padItem, int index) async {
    if (index < 0 || index >= padItem.pad.sounds.length) return;
    final soundId = padItem.pad.sounds[index].id;
    final updated = await _repository.getSoundById(soundId);
    if (updated == null) return;
    final sounds = List<Sound>.from(padItem.pad.sounds);
    sounds[index] = updated;
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
  }

  /// Calcule et persiste l'enveloppe waveform d'un son musique dont le fichier
  /// vient d'être chargé, si elle manque encore. Réinjecte ensuite le son (avec
  /// sa waveform) dans le pad en mémoire et notifie — la régie l'affiche dès
  /// qu'elle est prête, sans bloquer le démarrage de la lecture.
  Future<void> _ensureWaveformForSound(
    PadItem padItem,
    int index,
    String filePath,
  ) async {
    if (index < 0 || index >= padItem.pad.sounds.length) return;
    final sound = padItem.pad.sounds[index];
    if (sound.type != SoundType.music || sound.waveform != null) return;
    // Échec « format » déjà acté à la génération courante : ne pas re-sonder.
    if (!waveformNeedsProbe(sound.waveformProbeGeneration)) return;

    // Le board peut changer pendant le décodage (tâche de fond) : on capture son
    // identité pour ne pas muter/notifier un plateau devenu obsolète après l'await.
    final boardId = padItem.pad.boardId;

    final probe = await extractWaveform(filePath);
    if (_activeBoardId != boardId) return;
    // Moteur non prêt : rien à persister, on retentera au prochain chargement.
    if (probe.status == WaveformProbeStatus.transient) return;

    try {
      // Persiste soit l'enveloppe (succès), soit le marqueur d'échec (unsupported).
      await _repository.persistWaveformProbe(sound.id, probe);
    } catch (e) {
      debugPrint('Persistance waveform échouée (${sound.title}): $e');
      return;
    }
    if (_activeBoardId != boardId) return;

    // Le pad a pu changer depuis (re-tri, suppression) : relocaliser par id.
    final freshIndex =
        padItem.pad.sounds.indexWhere((s) => s.id == sound.id);
    if (freshIndex < 0) return;
    // Réinjecte le son à jour même sur un échec `unsupported` : l'entité en
    // mémoire porte alors la génération d'échec, ce qui évite de re-sonder le
    // même fichier au prochain chargement de ce slot dans la même session.
    final updated = await _repository.getSoundById(sound.id);
    if (updated == null || _activeBoardId != boardId) return;
    final sounds = List<Sound>.from(padItem.pad.sounds);
    sounds[freshIndex] = updated;
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
    // Ne notifier que sur un vrai changement visuel (nouvelle enveloppe).
    if (probe.status == WaveformProbeStatus.success) notifyListeners();
  }

  Future<void> _loadSlotAtIndex(
    PadItem padItem,
    int index, {
    bool downloadIfNeeded = false,
  }) async {
    final previousSlot = padItem.slots[index];
    final keepReadyAppearance = previousSlot.appearsReady;

    try {
      previousSlot.dispose();
    } catch (e) {
      debugPrint('Dispose slot échoué: $e');
    }

    padItem.slots[index] = keepReadyAppearance
        ? PadSoundSlot(availability: PadSoundAvailability.cached)
        : PadSoundSlot();

    final sound = padItem.pad.sounds[index];
    String? resolvedPath;
    try {
      resolvedPath = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: downloadIfNeeded,
      );
      if (isKnownUnloadablePath(resolvedPath)) {
        throw StateError('Fichier audio déjà signalé illisible');
      }
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.ready,
        player: await AudioPlayerService.create(resolvedPath),
      );
      await _syncPadSoundMetadata(padItem, index);
      // Calcul paresseux de la waveform (régie musique) — en tâche de fond pour
      // ne pas retarder le démarrage de la lecture.
      unawaited(_ensureWaveformForSound(padItem, index, resolvedPath));
    } on SoundNotAvailableLocallyException catch (e) {
      padItem.slots[index] = PadSoundSlot(
        availability: _availabilityFromException(e),
      );
    } on UnsupportedAudioFormatException {
      _blockSoundDriveRetry(sound.id);
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.unsupportedFormat,
      );
    } catch (e, stack) {
      if (resolvedPath != null) {
        markPathUnloadable(resolvedPath);
      }
      if (downloadIfNeeded ||
          (e is StateError && e.message.contains('introuvable sur Drive'))) {
        _blockSoundDriveRetry(sound.id);
      }
      AudioLoadLog.soundLoadFailed(
        soundId: sound.id,
        title: sound.displayName ?? sound.title,
        padId: padItem.pad.id,
        resolvedPath: resolvedPath,
        legacyPath: sound.filePath,
        error: e,
        stackTrace: stack,
      );
      padItem.slots[index] = PadSoundSlot(
        availability: PadSoundAvailability.missingFile,
      );
    }
  }

  Future<void> _loadPlayersForPadSafe(PadItem padItem, Pad pad) async {
    final padLabel = padItem.displayName;
    try {
      await _loadPlayersForPad(padItem, pad);
      _notifyPad(padItem);
    } catch (e, stack) {
      AudioLoadLog.padPlayersFailed(
        padId: pad.id,
        padLabel: padLabel,
        error: e,
        stackTrace: stack,
      );
      _finalizePadAvailability(padItem);
      _notifyPad(padItem);
    }
  }

  Future<void> _preloadPadPlayersSequential(
    List<PadItem> padItems,
    int generation,
  ) async {
    final boardId = _activeBoardId;
    if (boardId == null || padItems.isEmpty) return;

    AudioLoadLog.preloadStarted(boardId: boardId, padCount: padItems.length);
    for (final padItem in padItems) {
      if (generation != _padPreloadGeneration) {
        AudioLoadLog.preloadCancelled(boardId: boardId);
        return;
      }
      await _loadPlayersForPadSafe(padItem, padItem.pad);
    }

    if (generation != _padPreloadGeneration) {
      AudioLoadLog.preloadCancelled(boardId: boardId);
      return;
    }

    AudioLoadLog.preloadFinished(boardId: boardId, padCount: padItems.length);
    notifyListeners();
    unawaited(_prefetchActiveBoard());
  }

  Future<void> _loadPlayersForPad(PadItem padItem, Pad pad) async {
    final alreadyReady = padItem.slots.where((s) => s.isReady).length;
    debugPrint(
      '[LOAD-PAD] pad="${pad.displayName}" id=${pad.id} '
      'sounds=${pad.sounds.length} slotsReady=$alreadyReady',
    );
    padItem.pad = pad;
    padItem.syncSlotCount();

    for (var i = 0; i < pad.sounds.length; i++) {
      if (isLiveOfflineMode && !padItem.slots[i].appearsReady) continue;
      if (padItem.slots[i].isReady) continue;
      if (padItem.slots[i].availability == PadSoundAvailability.missingFile) {
        continue;
      }
      await _loadSlotAtIndex(padItem, i);
    }

    _finalizePadAvailability(padItem);
    _attachPlayerListeners(padItem);
    debugPrint(
      '[LOAD-PAD] done pad="${pad.displayName}" '
      'isPlayable=${padItem.isPlayable} unavailabilityReason=${padItem.unavailabilityReason}',
    );
  }

  void _attachPlayerListeners(PadItem padItem) {
    int attachedCount = 0;
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      final idx = i;
      // attachListener annule toute subscription précédente — exactement un
      // listener actif par player, même si appelé plusieurs fois sur le même pad.
      slot.attachListener((playing) {
        debugPrint(
          '[LISTENER] pad="${padItem.pad.displayName}" slot=$idx playing=$playing '
          'currentPlayerIndex=${padItem._currentPlayerIndex} isPlaying=${padItem.isPlaying}',
        );
        if (padItem.pad.isMusicPad) {
          // Musique : mono-voix, la variante courante est la source de vérité.
          if (playing) {
            padItem._currentPlayerIndex = idx;
            padItem.isPlaying = true;
            // Ne pas mettre à jour currentMusicPad pendant un fondu enchaîné :
            // crossfadeToNextMusic démarre le prochain lecteur à volume 0, ce
            // qui déclenche playing=true avant la fin du fondu. La mise à jour
            // explicite en fin de fondu est la source de vérité.
            if (!_music._skipMusicAutoAdvance) {
              _state = _state.copyWith(currentMusicPad: padItem);
            }
          } else if (padItem._currentPlayerIndex == idx) {
            padItem.isPlaying = false;
            padItem._currentPlayerIndex = null;
            _music._handleMusicPlaybackEnded(padItem);
          } else {
            debugPrint(
              '[LISTENER] ↩ false ignored: currentPlayerIndex=${padItem._currentPlayerIndex} != slot=$idx',
            );
          }
        } else {
          // Non-musique : polyphonie. isPlaying reflète l'ensemble des variantes
          // encore actives (plusieurs voix peuvent se superposer sur un pad).
          if (playing) {
            padItem._currentPlayerIndex = idx;
            padItem.isPlaying = true;
          } else {
            final anyPlaying =
                padItem.slots.any((s) => s.player?.isPlaying ?? false);
            padItem.isPlaying = anyPlaying;
            if (!anyPlaying) padItem._currentPlayerIndex = null;
          }
        }
        debugPrint(
          '[LISTENER] after: isPlaying=${padItem.isPlaying} '
          'currentPlayerIndex=${padItem._currentPlayerIndex}',
        );
        notifyListeners();
      });
      if (slot.player != null) attachedCount++;
    }
    debugPrint(
      '[ATTACH] pad="${padItem.pad.displayName}" attached $attachedCount listeners '
      '(total slots=${padItem.slots.length})',
    );
  }

  bool _padSoundsChanged(PadItem existing, Pad updated) {
    final previousSounds = existing.pad.sounds;
    if (previousSounds.length != updated.sounds.length) return true;
    for (var i = 0; i < updated.sounds.length; i++) {
      if (previousSounds[i].id != updated.sounds[i].id) return true;
    }
    return false;
  }

  void _disposePadItems(List<PadItem> items) {
    for (final item in items) {
      item.dispose();
    }
  }

  void setActiveBoard(int? boardId) {
    _activeBoardId = boardId;
  }

  void clearActiveBoard() {
    _activeBoardId = null;
  }

  // ── Boards ────────────────────────────────────────────────────────────────

  Future<void> loadBoards({int? selectBoardId}) async {
    _state = _state.copyWith(isBoardsLoading: true, boardsError: null);
    notifyListeners();

    try {
      var boards = await _repository.getSoundBoards();
      if (boards.isEmpty) {
        final libraryId = await _libraryRepository?.singleConnectedLibraryId();
        final newBoardId = await _repository.createSoundBoard(
          'Scène 1',
          libraryId: libraryId,
        );
        boards = await _repository.getSoundBoards();
        selectBoardId = newBoardId;
      }

      final targetId =
          selectBoardId ?? _state.selectedBoard?.id ?? boards.first.id;
      final selected = boards.firstWhere(
        (board) => board.id == targetId,
        orElse: () => boards.first,
      );

      _state = _state.copyWith(
        boards: boards,
        selectedBoard: selected,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = selected.id;
      notifyListeners();

      await loadSounds();
    } catch (e) {
      _state = _state.copyWith(
        isBoardsLoading: false,
        boardsError: e.toString(),
      );
      notifyListeners();
    }
  }

  Future<void> selectBoard(SoundBoard board) async {
    if (_state.selectedBoard?.id == board.id) return;

    await stopAllSounds();
    _lastRemovedPad = null;
    _music.cleanupOffStagePads();
    _state = _state.copyWith(selectedBoard: board);
    _activeBoardId = board.id;
    notifyListeners();
    await loadSounds();
  }

  /// Bibliothèques Drive connectées, proposables comme destination d'un board.
  /// Vide si aucune session Drive n'est configurée (le board sera local).
  Future<List<Library>> getConnectedLibraries() async {
    final repository = _libraryRepository;
    if (repository == null) return const [];
    final libraries = await repository.getLibraries();
    return libraries.where((library) => library.isConnectedToDrive).toList();
  }

  /// Crée un board. [libraryId] null = board local ; sinon board rattaché à la
  /// bibliothèque Drive choisie (il ne proposera que les sons de cette biblio).
  Future<SoundBoard?> createBoard(
    String name, {
    int? color,
    int? libraryId,
  }) async {
    try {
      final newBoardId = await _repository.createSoundBoard(
        name,
        color: color,
        libraryId: libraryId,
      );
      final newBoard = SoundBoard(
        id: newBoardId,
        name: name,
        color: color,
        libraryId: libraryId,
        createdAt: DateTime.now(),
      );

      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      notifyListeners();
      await loadSounds();
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<bool> renameBoard(SoundBoard board, String name) async {
    try {
      await _repository.renameSoundBoard(board.id, name);
      final updatedBoards = _state.boards
          .map((b) => b.id == board.id ? b.copyWith(name: name) : b)
          .toList();
      final selected = _state.selectedBoard?.id == board.id
          ? board.copyWith(name: name)
          : _state.selectedBoard;

      _state = _state.copyWith(boards: updatedBoards, selectedBoard: selected);
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteBoard(SoundBoard board) async {
    try {
      await _repository.deleteSoundBoard(board.id);
      final updatedBoards =
          _state.boards.where((b) => b.id != board.id).toList();
      SoundBoard? nextSelected = _state.selectedBoard;
      if (_state.selectedBoard?.id == board.id) {
        nextSelected = updatedBoards.isNotEmpty ? updatedBoards.first : null;
      }

      _state = _state.copyWith(
        boards: updatedBoards,
        selectedBoard: nextSelected,
      );
      _activeBoardId = nextSelected?.id;
      notifyListeners();
      await loadSounds();
      return true;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return false;
    }
  }

  Future<SoundBoard?> duplicateBoard(
    SoundBoard sourceBoard,
    String newName,
  ) async {
    try {
      final newBoardId = await _repository.createSoundBoard(
        newName,
        color: sourceBoard.color,
        libraryId: sourceBoard.libraryId,
      );
      await _repository.duplicatePads(sourceBoard.id, newBoardId);

      final newBoard = SoundBoard(
        id: newBoardId,
        name: newName,
        color: sourceBoard.color,
        libraryId: sourceBoard.libraryId,
        createdAt: DateTime.now(),
      );
      _state = _state.copyWith(
        boards: [..._state.boards, newBoard],
        selectedBoard: newBoard,
        isBoardsLoading: false,
        boardsError: null,
      );
      _activeBoardId = newBoardId;
      notifyListeners();
      await loadSounds(boardId: newBoardId);
      return newBoard;
    } catch (e) {
      _state = _state.copyWith(boardsError: e.toString());
      notifyListeners();
      return null;
    }
  }

  // ── Pads ──────────────────────────────────────────────────────────────────

  Future<void> loadSounds({int? boardId, bool silent = false}) {
    _loadSoundsChain ??= Future<void>.value();
    _loadSoundsChain = _loadSoundsChain!.then(
      (_) => _loadSoundsImpl(boardId, silent: silent),
    );
    return _loadSoundsChain!;
  }

  Future<void> _loadSoundsImpl(int? boardId, {bool silent = false}) async {
    final previousBoardId = _activeBoardId;
    if (boardId != null) _activeBoardId = boardId;
    _lastRemovedPad = null;
    if (boardId != null && boardId != previousBoardId) {
      _driveNotFoundSoundIds.clear();
    }
    final preloadGeneration = ++_padPreloadGeneration;
    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) {
      _disposePadItems(_state.pads);
      _state = _state.copyWith(pads: [], isLoading: false);
      notifyListeners();
      return;
    }

    if (!silent) {
      _state = _state.copyWith(isLoading: true, error: null);
      notifyListeners();
    }

    try {
      final pads = await _loadPadsUseCase(currentBoardId);
      final previousItems = _state.pads;
      final previousItemsById = <int, PadItem>{
        for (final item in previousItems) item.pad.id: item,
      };

      final padItems = <PadItem>[];
      final padsToPreload = <PadItem>[];
      final draftPads =
          previousItems.where((item) => item.isDraft).toList(growable: false);

      for (final pad in pads) {
        final existing = previousItemsById[pad.id];
        if (existing != null) {
          final soundsChanged = _padSoundsChanged(existing, pad);
          existing.pad = pad;
          existing.syncSlotCount();
          padItems.add(existing);
          if (soundsChanged) {
            padsToPreload.add(existing);
          } else if (existing.isPlaying) {
            existing.currentPlayer?.setVolume(_effectiveVolume(existing));
          }
          continue;
        }

        final padItem = PadItem(pad: pad);
        padItems.add(padItem);
        padsToPreload.add(padItem);
      }

      padItems.addAll(draftPads);

      // Sonde la disponibilité locale de chaque pad indépendamment : une erreur
      // sur un pad n'annule pas les autres (Future.wait sans isolation causerait
      // la perte de tous les résultats si l'un échoue).
      await Future.wait(
        padItems.where((item) => !item.isDraft).map(
          (item) => _probePadLocalAvailability(item).catchError((e, st) {
            AudioLoadLog.severe(
              'Sonde pad #${item.pad.id} échouée',
              error: e,
              stackTrace: st,
            );
          }),
        ),
      );

      _syncMultipadNumbers(_padsForMultipadNumbering());
      _state = _state.copyWith(pads: padItems, isLoading: false, error: null);
      final keptIds = padItems.map((item) => item.pad.id).toSet();
      final removedItems =
          previousItems.where((item) => !keptIds.contains(item.pad.id)).toList();
      _disposePadItems(removedItems);
      _music._syncMusicStateWithPads();

      if (preloadGeneration == _padPreloadGeneration) {
        if (padsToPreload.isNotEmpty) {
          unawaited(
            _preloadPadPlayersSequential(padsToPreload, preloadGeneration),
          );
        } else {
          unawaited(_prefetchActiveBoard());
        }
      }
    } catch (e, stack) {
      AudioLoadLog.severe(
        'Échec chargement plateau #$currentBoardId (UI conservée)',
        error: e,
        stackTrace: stack,
      );
      _state = _state.copyWith(isLoading: false, error: null);
    }
    notifyListeners();
  }

  Future<void> _prefetchActiveBoard() async {
    if (!allowsSoundDownload) return;
    final libraryRepository = _libraryRepository;
    if (libraryRepository == null) return;

    final generation = ++_prefetchGeneration;
    final boardId = _activeBoardId;
    if (boardId == null) return;
    if (_state.isBoardPreparing) return;

    if (!await libraryRepository.ensureDriveConnected()) return;
    if (generation != _prefetchGeneration || _activeBoardId != boardId) return;

    _downloadQueue.cancelQueued(
      (key, priority) => priority <= _downloadPriorityPrefetch,
    );

    // Favoris d'abord, puis par dernière lecture (desc), puis par position grille.
    // Les tâches sont enfilées dans cet ordre : à priorité égale la file est FIFO,
    // donc le seq d'enqueue détermine l'ordre effectif de téléchargement.
    final padsToFetch = List<PadItem>.from(_state.pads)
      ..sort((a, b) {
        final aFav = a.pad.sounds.any((s) => s.isFavorite) ? 1 : 0;
        final bFav = b.pad.sounds.any((s) => s.isFavorite) ? 1 : 0;
        if (aFav != bFav) return bFav - aFav;

        DateTime? latestFor(PadItem item) => item.pad.sounds
            .map((s) => s.lastPlayedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (best, d) => best == null || d.isAfter(best) ? d : best,
            );

        final aLast = latestFor(a);
        final bLast = latestFor(b);
        if (aLast == null && bLast == null) return 0;
        if (aLast == null) return 1;
        if (bLast == null) return -1;
        return bLast.compareTo(aLast);
      });

    for (final padItem in padsToFetch) {
      if (padItem.pendingDownloadCount == 0) continue;
      unawaited(
        downloadAndLoadPad(padItem, priority: _downloadPriorityPrefetch)
            .catchError((_) => false),
      );
    }
  }

  Future<void> refreshPadPlayback(int padId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;
    await _loadPlayersForPad(padItem, padItem.pad);
    notifyListeners();
  }

  Future<void> toggleSound(PadItem padItem) async {
    final resolved = _resolveBoardPadItem(padItem);
    debugPrint(
      '[TOGGLE] pad="${resolved.pad.displayName}" id=${resolved.pad.id} '
      'isPlayable=${resolved.isPlayable} isPlaying=${resolved.isPlaying} '
      'isMusicPad=${resolved.pad.isMusicPad} '
      'slots=${resolved.slots.length} readySlots=${resolved.slots.where((s) => s.isReady).length} '
      '_currentPlayerIndex=${resolved._currentPlayerIndex}',
    );
    if (!resolved.isPlayable) {
      debugPrint('[TOGGLE] ↩ not playable, ignoring');
      return;
    }
    if (resolved.pad.isMusicPad) {
      await _music._toggleMusicPad(resolved);
      return;
    }

    // Pads non-musique : polyphonie. Chaque tap empile un nouveau son (superposé)
    // sans couper les précédents ; sur un multipad la variante suivante est
    // choisie selon le mode de lecture. L'arrêt se fait via appui long (ce pad)
    // ou le bouton « Tout arrêter » — jamais par un second tap.
    await _playOverlappingSoundAtIndex(resolved, _pickSoundIndex(resolved));
  }

  /// Joue une variante précise d'un (multi)pad, en dehors du choix automatique
  /// (`_pickSoundIndex`) — ex. sélection explicite depuis la liste des sons
  /// d'un multipad. Pour un pad musique, court-circuite la file/reprise et
  /// joue directement ce son (comme un tap normal sur un pad simple).
  Future<void> playPadSoundAtIndex(PadItem padItem, int soundIndex) async {
    final resolved = _resolveBoardPadItem(padItem);
    if (!resolved.isPlayable) return;
    if (soundIndex < 0 || soundIndex >= resolved.slots.length) return;
    if (!_slotEligibleForPlayback(resolved, soundIndex)) return;

    if (resolved.pad.isMusicPad) {
      // Même mécanisme que « suivant » dans la file (`playNextInQueueNow`) :
      // `playMusicNow` coupe ce qui joue puis démarre cette variante — un seul
      // point d'entrée pour changer de musique, quel que soit le déclencheur.
      await _music.playMusicNow(resolved, soundIndex: soundIndex);
      return;
    }

    await _playOverlappingSoundAtIndex(resolved, soundIndex);
  }

  Future<void> _playOverlappingSoundAtIndex(
    PadItem resolved,
    int soundIndex,
  ) async {
    final player = resolved.slots[soundIndex].player;
    debugPrint(
      '[TOGGLE] → play overlapping soundIndex=$soundIndex '
      'playerNull=${player == null} '
      '_nextSoundIndex=${resolved._nextSoundIndex}',
    );
    if (player == null) return;
    await _syncPadSoundMetadata(resolved, soundIndex);
    // Point d'entrée : le déclenchement démarre à cet offset au lieu du sample 0.
    var startOffsetMs = resolved.pad.sounds[soundIndex].startOffsetMs;
    final duration = player.duration;
    if (duration > Duration.zero) {
      final maxMs = duration.inMilliseconds;
      if (startOffsetMs >= maxMs) {
        startOffsetMs = (maxMs - 1).clamp(0, maxMs);
      }
    }
    final startOffset = Duration(milliseconds: startOffsetMs);
    await player.playOverlapping(
      volume: _effectiveVolume(resolved),
      startOffset: startOffset,
    );
    // Ticket de progression : une barre superposée par voix, auto-supprimée à
    // la fin du son (bump de révision pour rafraîchir le seul PadButton). La
    // durée restante tient compte du point d'entrée sauté en tête.
    final remaining = player.duration - startOffset;
    resolved.addPlaybackTicket(
      remaining > Duration.zero ? remaining : player.duration,
      onExpire: () => _notifyPad(resolved),
    );
    _markPlayedAt(resolved, soundIndex);
    _notifyPad(resolved);
    notifyListeners();
  }

  /// Arrête toutes les voix en cours d'un pad (toutes variantes confondues).
  Future<void> stopPadSounds(PadItem padItem) async {
    final resolved = _resolveBoardPadItem(padItem);
    if (resolved.pad.isMusicPad) {
      await resolved.currentPlayer?.stop();
      resolved.isPlaying = false;
      resolved._currentPlayerIndex = null;
      notifyListeners();
      return;
    }
    await _stopAllSlotPlayers(resolved);
    notifyListeners();
  }

  /// Coupe tous les pads non-musique en cours (bouton panique « Tout arrêter »).
  /// Laisse la musique jouer : utile en live pour tuer un bruitage sans casser
  /// le tapis sonore.
  Future<void> stopAllNonMusicSounds() async {
    var changed = false;
    for (final padItem in _state.pads) {
      if (padItem.pad.isMusicPad) continue;
      if (!padItem.isPlaying) continue;
      await _stopAllSlotPlayers(padItem);
      changed = true;
    }
    if (_libraryPreviewSoundId != null || _previewPlayers.isNotEmpty) {
      changed = true;
    }
    stopAllPreviews();
    if (changed) notifyListeners();
  }

  /// Au moins un pad non-musique joue actuellement, ou une pré-écoute
  /// (recherche rapide / bibliothèque) est en cours.
  bool get hasNonMusicSoundsPlaying =>
      _state.pads.any((p) => !p.pad.isMusicPad && p.isPlaying) ||
      _libraryPreviewSoundId != null ||
      _previewPlayers.isNotEmpty;

  /// Arrête toutes les voix de chaque variante du pad (sans notifier).
  Future<void> _stopAllSlotPlayers(PadItem padItem) async {
    for (final slot in padItem.slots) {
      final player = slot.player;
      if (player != null && player.isPlaying) {
        await player.stop();
      }
    }
    padItem.clearPlaybackTickets();
    padItem.isPlaying = false;
    padItem._currentPlayerIndex = null;
  }

  void _markPlayed(int soundId) {
    unawaited(_repository.markSoundPlayed(soundId));
  }

  void _markPlayedAt(PadItem padItem, int soundIndex) {
    if (soundIndex < 0 || soundIndex >= padItem.pad.sounds.length) return;
    _markPlayed(padItem.pad.sounds[soundIndex].id);
  }

  Future<void> updateSoundType(int soundId, SoundType type) async {
    await _repository.updateSoundType(soundId, type);
    await _music.refreshSoundMetadata(soundId);
  }

  Future<bool> toggleSoundFavorite(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    final next = !sound.isFavorite;
    await _repository.setSoundFavorite(soundId, next);
    return next;
  }

  void _notifyPad(PadItem padItem) => padItem.bumpRevision();

  void _notifyPadAndBoard(PadItem padItem) {
    _notifyPad(padItem);
    notifyListeners();
  }

  Future<bool> downloadPadSoundAtIndex(PadItem padItem, int index) async {
    if (!allowsSoundDownload) return false;
    final resolved = _resolveBoardPadItem(padItem);
    if (index < 0 || index >= resolved.slots.length) return false;
    final slot = resolved.slots[index];
    if (slot.isReady) return true;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return false;
    if (slot.availability == PadSoundAvailability.missingFile) {
      if (!_isRetryableMissingLibrarySound(resolved.pad.sounds[index])) {
        return false;
      }
      await _prepareRetryForMissingLibrarySound(resolved, index);
    }

    try {
      return await _downloadQueue.enqueue<bool>(
        key: resolved.pad.id,
        priority: _downloadPriorityTap,
        task: () => _downloadPadSoundAtIndexImpl(resolved, index),
      );
    } on DownloadCancelledException {
      final current = _resolveBoardPadItem(padItem);
      return index < current.slots.length && current.slots[index].isReady;
    }
  }

  Future<bool> _downloadPadSoundAtIndexImpl(PadItem padItem, int index) async {
    if (padItem.isDownloading) {
      return padItem.slots[index].isReady;
    }

    final slot = padItem.slots[index];
    if (slot.isReady) return true;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return false;
    if (slot.availability == PadSoundAvailability.missingFile &&
        !_isRetryableMissingLibrarySound(padItem.pad.sounds[index])) {
      return false;
    }
    if (slot.availability == PadSoundAvailability.missingFile) {
      await _prepareRetryForMissingLibrarySound(padItem, index);
    }

    padItem.downloadingSlotIndex = index;
    _notifyPad(padItem);

    try {
      final libraryRepository = _libraryRepository;
      if (libraryRepository != null) {
        final connected = await libraryRepository.ensureDriveConnected();
        if (!connected) {
          if (slot.availability == PadSoundAvailability.needsDownload ||
              slot.availability == PadSoundAvailability.offline) {
            padItem.slots[index] = PadSoundSlot(
              availability: PadSoundAvailability.offline,
            );
          }
          _finalizePadAvailability(padItem);
          _notifyPad(padItem);
          notifyListeners();
          return false;
        }
      }

      await _loadSlotAtIndex(padItem, index, downloadIfNeeded: true);

      if (padItem.isPlayable) {
        await _loadPlayersForPad(padItem, padItem.pad);
      } else {
        _finalizePadAvailability(padItem);
      }
      _notifyPad(padItem);
      notifyListeners();
      return padItem.slots[index].isReady;
    } finally {
      padItem.downloadingSlotIndex = null;
      _notifyPad(padItem);
    }
  }

  Future<bool> downloadAndLoadPad(
    PadItem padItem, {
    int priority = _downloadPriorityTap,
  }) async {
    if (isLiveOfflineMode) return _resolveBoardPadItem(padItem).isPlayable;
    final resolved = _resolveBoardPadItem(padItem);
    try {
      return await _downloadQueue.enqueue<bool>(
        key: resolved.pad.id,
        priority: priority,
        task: () => _downloadAndLoadPadImpl(resolved),
      );
    } on DownloadCancelledException {
      return _resolveBoardPadItem(padItem).isPlayable;
    }
  }

  Future<bool> _downloadAndLoadPadImpl(PadItem padItem) async {
    if (padItem.isDownloading) return padItem.isPlayable;

    final pendingIndices = <int>[];
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      if (slot.isReady) continue;
      if (slot.availability == PadSoundAvailability.unsupportedFormat) continue;
      if (slot.availability == PadSoundAvailability.missingFile) {
        if (!_isRetryableMissingLibrarySound(padItem.pad.sounds[i])) continue;
        await _prepareRetryForMissingLibrarySound(padItem, i);
      }
      pendingIndices.add(i);
    }
    if (pendingIndices.isEmpty) {
      if (padItem.isPlayable) return true;
      _finalizePadAvailability(padItem);
      _notifyPadAndBoard(padItem);
      return padItem.isPlayable;
    }

    padItem.isDownloading = true;
    padItem.downloadDone = 0;
    padItem.downloadTotal = pendingIndices.length;
    _notifyPad(padItem);

    try {
      final libraryRepository = _libraryRepository;
      if (libraryRepository != null) {
        final connected = await libraryRepository.ensureDriveConnected();
        if (!connected) {
          _markSlotsOffline(padItem);
          _notifyPadAndBoard(padItem);
          return false;
        }
      }

      for (final index in pendingIndices) {
        padItem.downloadingSlotIndex = index;
        _notifyPad(padItem);
        await _loadSlotAtIndex(padItem, index, downloadIfNeeded: true);
        padItem.downloadDone++;
        _notifyPad(padItem);
      }
    } finally {
      padItem.isDownloading = false;
      padItem.downloadDone = 0;
      padItem.downloadTotal = 0;
      padItem.downloadingSlotIndex = null;
      _notifyPad(padItem);
    }

    if (padItem.isPlayable) {
      await _loadPlayersForPad(padItem, padItem.pad);
    } else if (padItem.pendingDownloadCount > 0) {
      _markSlotsMissingAfterFailedDownload(padItem);
    } else {
      _finalizePadAvailability(padItem);
    }
    _notifyPadAndBoard(padItem);
    return padItem.isPlayable;
  }

  void _markSlotsOffline(PadItem padItem) {
    for (var i = 0; i < padItem.slots.length; i++) {
      final slot = padItem.slots[i];
      if (slot.availability == PadSoundAvailability.needsDownload ||
          slot.availability == PadSoundAvailability.offline) {
        padItem.slots[i] = PadSoundSlot(
          availability: PadSoundAvailability.offline,
        );
      }
    }
    _finalizePadAvailability(padItem);
  }

  void _markSlotsMissingAfterFailedDownload(PadItem padItem) {
    for (var i = 0; i < padItem.slots.length; i++) {
      if (padItem.slots[i].availability == PadSoundAvailability.needsDownload) {
        _blockSoundDriveRetry(padItem.pad.sounds[i].id);
        padItem.slots[i] = PadSoundSlot(
          availability: PadSoundAvailability.missingFile,
        );
      }
    }
    _finalizePadAvailability(padItem);
  }

  Future<void> prepareBoardForOffline() async {
    if (!allowsSoundDownload) return;
    if (_state.isBoardPreparing) return;

    final toDownload = _state.pads.where(isPadPreparable).toList();
    if (toDownload.isEmpty) return;

    _state = _state.copyWith(
      isBoardPreparing: true,
      boardPrepareDone: 0,
      boardPrepareTotal: toDownload.length,
    );
    notifyListeners();

    try {
      for (var i = 0; i < toDownload.length; i++) {
        await downloadAndLoadPad(
          toDownload[i],
          priority: _downloadPriorityManualPrepare,
        );
        _state = _state.copyWith(boardPrepareDone: i + 1);
        notifyListeners();
      }
    } finally {
      _state = _state.copyWith(isBoardPreparing: false);
      notifyListeners();
    }
  }

  bool _slotEligibleForPlayback(PadItem padItem, int index) {
    if (!padItem.slots[index].isReady) return false;
    if (isLiveOfflineMode && !padItem.slots[index].appearsReady) return false;
    return true;
  }

  int _pickSoundIndex(PadItem padItem) {
    final readyIndices = <int>[
      for (var i = 0; i < padItem.slots.length; i++)
        if (_slotEligibleForPlayback(padItem, i)) i,
    ];
    debugPrint(
      '[PICK] pad="${padItem.pad.displayName}" '
      'slots=${padItem.slots.length} readyIndices=$readyIndices '
      '_nextSoundIndex=${padItem._nextSoundIndex} '
      'playedIndices=${padItem._playedSoundIndices} '
      'playMode=${padItem.pad.playMode}',
    );
    if (readyIndices.isEmpty) return 0;
    if (readyIndices.length == 1) return readyIndices.first;

    final chosen = switch (padItem.pad.playMode) {
      PadPlayMode.random => () {
          var available = readyIndices
              .where((i) => !padItem._playedSoundIndices.contains(i))
              .toList();
          if (available.isEmpty) {
            padItem.resetRandomPlaySession();
            available = List<int>.from(readyIndices);
          }
          final idx = available[_random.nextInt(available.length)];
          padItem._playedSoundIndices.add(idx);
          return idx;
        }(),
      PadPlayMode.sequential => () {
          final total = padItem.slots.length;
          for (var step = 0; step < total; step++) {
            final idx = (padItem._nextSoundIndex + step) % total;
            if (_slotEligibleForPlayback(padItem, idx)) {
              padItem._nextSoundIndex = (idx + 1) % total;
              return idx;
            }
          }
          return readyIndices.first;
        }(),
    };
    debugPrint('[PICK] → chosen=$chosen _nextSoundIndex(after)=${padItem._nextSoundIndex}');
    return chosen;
  }

  // ── Délégués musique (API publique) ───────────────────────────────────────

  String? consumeLastMusicPlaybackError() => _music.consumeLastPlaybackError();

  void enqueueMusicPad(PadItem p) => _music.enqueueMusicPad(p);
  Future<void> playMusicNow(PadItem p) => _music.playMusicNow(p);
  Future<PadItem?> playMusicBySoundId(int id) => _music.playMusicBySoundId(id);
  Future<PadItem?> enqueueMusicBySoundId(int id) =>
      _music.enqueueMusicBySoundId(id);
  Future<bool> playNextInQueueNow() => _music.playNextInQueueNow();
  Future<void> clearMusicQueue() => _music.clearMusicQueue();
  Future<void> removeFromMusicQueue(int padId) =>
      _music.removeFromMusicQueue(padId);
  void reorderMusicQueue(int oldIndex, int newIndex) =>
      _music.reorderMusicQueue(oldIndex, newIndex);
  Future<void> toggleCurrentMusicPlayback() =>
      _music.toggleCurrentMusicPlayback();
  Future<void> restartCurrentMusic() => _music.restartCurrentMusic();
  Future<void> seekPausedMusic(Duration position) =>
      _music.seekPausedMusic(position);
  Future<void> skipToNextMusic() => _music.skipToNextMusic();
  Future<void> stopCurrentMusic() => _music.stopCurrentMusic();
  Future<void> fadeOutCurrentMusic(Duration d) =>
      _music.fadeOutCurrentMusic(d);
  Future<void> crossfadeToNextMusic(Duration d) =>
      _music.crossfadeToNextMusic(d);
  PadItem? findMusicPadForSound(int id) => _music.findMusicPadForSound(id);
  PadItem? resolveMusicPad(int id) => _music.resolveMusicPad(id);
  Future<void> refreshSoundMetadata(int soundId) =>
      _music.refreshSoundMetadata(soundId);
  Future<void> setMusicVolume(double v, {bool smooth = false}) =>
      _music.setMusicVolume(v, smooth: smooth);
  Future<void> toggleMusicMute() => _music.toggleMusicMute();

  // ── Paramètres pad ────────────────────────────────────────────────────────

  Future<void> updatePadItemSettings(
    PadItem padItem, {
    Color? buttonColor,
    bool updateColor = false,
    String? displayName,
    bool updateDisplayName = false,
    double? volume,
    PadPlayMode? playMode,
  }) async {
    var hasChanged = false;
    String? nextName = padItem.pad.name;
    int? nextColor = padItem.pad.colorValue;
    double nextVolume = padItem.pad.volume;
    PadPlayMode? nextPlayMode;

    if (updateColor) {
      nextColor = buttonColor?.toARGB32();
      hasChanged = true;
    }
    if (updateDisplayName) {
      final trimmed = displayName?.trim();
      nextName = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      if (nextName != padItem.pad.name) hasChanged = true;
    }
    if (volume != null) {
      final clamped = volume.clamp(0.0, 1.0);
      if (clamped != padItem.pad.volume) {
        nextVolume = clamped;
        hasChanged = true;
        if (padItem.isPlaying) {
          final effective = padItem.pad.isMusicPad
              ? nextVolume * _music._musicVolume
              : nextVolume;
          padItem.currentPlayer?.setVolume(effective);
        }
      }
    }
    if (playMode != null && playMode != padItem.pad.playMode) {
      nextPlayMode = playMode;
      hasChanged = true;
    }

    if (!hasChanged) return;

    padItem.pad = padItem.pad.copyWith(
      name: nextName,
      clearName: updateDisplayName && nextName == null,
      colorValue: nextColor,
      clearColor: updateColor && nextColor == null,
      volume: nextVolume,
      playMode: nextPlayMode,
    );
    notifyListeners();

    await _repository.updatePadSettings(
      padId: padItem.pad.id,
      name: nextName,
      updateName: updateDisplayName,
      colorValue: updateColor ? nextColor : null,
      updateColor: updateColor,
      volume: volume != null ? nextVolume : null,
      playMode: nextPlayMode,
    );
  }

  Future<void> updatePadRowIndex(int padId, int newRowIndex) async {
    await _repository.updatePadRowIndex(padId, newRowIndex);
    await loadSounds(silent: true);
  }

  Future<void> movePadToPosition(
    int padId,
    int targetRowIndex,
    int insertionPosition,
  ) async {
    final boardId = _activeBoardId;
    if (boardId == null) return;

    final drafts =
        _state.pads.where((item) => item.isDraft).toList(growable: false);

    final byRow = <int, List<PadItem>>{};
    for (final p in _state.pads) {
      if (p.isDraft) continue;
      (byRow[p.pad.rowIndex] ??= []).add(p);
    }
    for (final list in byRow.values) {
      list.sort((a, b) => a.pad.sortOrder.compareTo(b.pad.sortOrder));
    }

    int? sourceRowIndex;
    var sourceIndexInRow = -1;
    for (final entry in byRow.entries) {
      final idx = entry.value.indexWhere((p) => p.pad.id == padId);
      if (idx != -1) {
        sourceRowIndex = entry.key;
        sourceIndexInRow = idx;
        break;
      }
    }
    if (sourceRowIndex == null) return;

    final moved = byRow[sourceRowIndex]!.removeAt(sourceIndexInRow);
    final targetList = byRow[targetRowIndex] ?? <PadItem>[];
    final clampedPos = insertionPosition.clamp(0, targetList.length);

    targetList.insert(clampedPos, moved);
    byRow[targetRowIndex] = targetList;

    final allRows = byRow.keys.toList()..sort();
    final layout = <({int padId, int rowIndex, int sortOrder})>[];
    final newPadItems = <PadItem>[];
    var globalSort = 0;
    for (final rowIdx in allRows) {
      for (final item in byRow[rowIdx]!) {
        item.pad = item.pad.copyWith(
          rowIndex: rowIdx,
          sortOrder: globalSort,
        );
        layout.add((
          padId: item.pad.id,
          rowIndex: rowIdx,
          sortOrder: globalSort,
        ));
        newPadItems.add(item);
        globalSort++;
      }
    }

    _state = _state.copyWith(pads: [...newPadItems, ...drafts]);
    notifyListeners();

    try {
      await _repository.applyPadsLayout(boardId, layout);
    } catch (e) {
      debugPrint('Erreur lors du déplacement du pad: $e');
      await loadSounds();
    }
  }

  Future<void> stopAllSounds() async {
    _music._musicAdvanceLockCount++;
    try {
      for (final padItem in _state.pads) {
        if (padItem.isPlaying) {
          await _stopAllSlotPlayers(padItem);
        }
      }
    } finally {
      if (_music._musicAdvanceLockCount > 0) _music._musicAdvanceLockCount--;
    }
    _music._clearMusicState();
    notifyListeners();
  }

  Future<void> reorderSoundsFromList(List<PadItem> newOrder) async {
    if (_activeBoardId == null) return;
    _syncMultipadNumbers(newOrder);
    _state = _state.copyWith(pads: newOrder);
    notifyListeners();
    try {
      await _repository.reorderBoardPads(
        _activeBoardId!,
        newOrder.map((p) => p.pad.id).toList(),
      );
    } catch (e) {
      debugPrint('Erreur lors du réordonnancement: $e');
      await loadSounds();
    }
  }

  Future<bool> removeSound(PadItem padItem) async {
    if (padItem.isDraft) {
      cancelDraftPad(padItem.pad.id);
      return true;
    }

    final currentBoardId = _activeBoardId;
    if (currentBoardId == null) return false;

    final previousIndex = _state.pads.indexOf(padItem);
    if (previousIndex < 0) return false;

    if (_removePadUseCase != null) {
      try {
        await _removePadUseCase(padItem.pad.id);
      } catch (e) {
        debugPrint('Erreur lors du retrait du pad: $e');
        _state = _state.copyWith(error: 'Impossible de retirer ce pad.');
        notifyListeners();
        return false;
      }
    }

    _lastRemovedPad = _RemovedPadSnapshot(
      boardId: currentBoardId,
      pad: padItem.pad,
      index: previousIndex,
    );
    if (padItem.isPlaying) {
      try {
        await padItem.currentPlayer?.stop();
      } catch (_) {}
    }
    padItem.dispose();

    final remainingPads =
        _state.pads.where((p) => p != padItem).toList();
    _syncMultipadNumbers(remainingPads);
    _state = _state.copyWith(pads: remainingPads, error: null);
    _music._syncMusicStateWithPads();
    notifyListeners();
    return true;
  }

  Future<int?> undoLastRemoval() async {
    final snapshot = _lastRemovedPad;
    final currentBoardId = _activeBoardId;
    if (snapshot == null || currentBoardId == null) return null;
    if (snapshot.boardId != currentBoardId) return null;

    try {
      await _repository.createPadWithSettings(
        boardId: snapshot.boardId,
        soundIds: snapshot.pad.sounds.map((s) => s.id).toList(),
        name: snapshot.pad.name,
        colorValue: snapshot.pad.colorValue,
        volume: snapshot.pad.volume,
        playMode: snapshot.pad.playMode,
        sortOrder: snapshot.index,
      );

      _lastRemovedPad = null;
      await loadSounds(boardId: snapshot.boardId);
      _state = _state.copyWith(error: null);
      notifyListeners();

      final restored = _state.pads
          .where((p) => p.pad.sortOrder == snapshot.index)
          .firstOrNull;
      return restored?.pad.id;
    } catch (e) {
      debugPrint('Erreur lors de l\'annulation de suppression: $e');
      _state = _state.copyWith(
        error: 'Impossible d\'annuler la suppression du pad.',
      );
      notifyListeners();
      return null;
    }
  }

  void _applySoundAddedToPad(
    PadItem padItem,
    Sound sound, {
    bool notify = true,
  }) {
    if (padItem.pad.sounds.any((s) => s.id == sound.id)) return;
    padItem.pad = padItem.pad.copyWith(
      sounds: [...padItem.pad.sounds, sound],
    );
    padItem.syncSlotCount();
    _finalizePadAvailability(padItem);
    _syncMultipadNumbers(_state.pads);
    if (!notify) return;
    _notifyPad(padItem);
    notifyListeners();
  }

  void _applySoundRemovedFromPad(PadItem padItem, int soundId) {
    final index = padItem.pad.sounds.indexWhere((s) => s.id == soundId);
    if (index < 0) return;
    final sounds = List<Sound>.from(padItem.pad.sounds)..removeAt(index);
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
    if (index < padItem.slots.length) {
      padItem.slots.removeAt(index).dispose();
    }
    padItem.syncSlotCount();
    _finalizePadAvailability(padItem);
    _syncMultipadNumbers(_state.pads);
    _notifyPad(padItem);
    notifyListeners();
  }

  Future<void> _reloadPadPlayersInBackground(PadItem padItem) async {
    await _loadPlayersForPadSafe(padItem, padItem.pad);
    notifyListeners();
  }

  Future<void> addSoundToPad(int padId, int soundId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;

    await _repository.addSoundToPad(padId, soundId);

    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return;

    _applySoundAddedToPad(padItem, sound, notify: false);
    final slotIndex = padItem.pad.sounds.length - 1;
    await _probeSlotAtIndex(padItem, slotIndex);
    _finalizePadAvailability(padItem);
    _notifyPadAndBoard(padItem);
    unawaited(_reloadPadPlayersInBackground(padItem));
    _maybeAutoDownloadPadSound(padItem, slotIndex);
  }

  void _maybeAutoDownloadPadSound(PadItem padItem, int slotIndex) {
    if (_appPreferences?.autoDownloadPadSounds != true) return;
    if (_libraryRepository == null) return;
    if (slotIndex < 0 || slotIndex >= padItem.slots.length) return;
    final slot = padItem.slots[slotIndex];
    if (slot.isReady) return;
    if (slot.availability == PadSoundAvailability.unsupportedFormat) return;
    if (slot.availability == PadSoundAvailability.missingFile &&
        !_isRetryableMissingLibrarySound(padItem.pad.sounds[slotIndex])) {
      return;
    }
    unawaited(
      downloadPadSoundAtIndex(padItem, slotIndex).catchError((_) => false),
    );
  }

  void _maybeAutoDownloadPad(PadItem padItem) {
    if (_appPreferences?.autoDownloadPadSounds != true) return;
    if (_libraryRepository == null) return;
    if (padItem.pendingDownloadCount == 0) return;
    unawaited(downloadAndLoadPad(padItem).catchError((_) => false));
  }

  Future<void> removeSoundFromPad(int padId, int soundId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;
    if (padItem.pad.sounds.length <= 1) {
      await removeSound(padItem);
    } else {
      await _repository.removeSoundFromPad(padId, soundId);
      _applySoundRemovedFromPad(padItem, soundId);
    }
  }

  @override
  void dispose() {
    _appPreferences?.removeListener(_onConnectivityModeChanged);
    _downloadQueue.dispose();
    stopAllPreviews();
    for (final padItem in _state.pads) {
      padItem.dispose();
    }
    _music._disposeOffStagePads();
    super.dispose();
  }

  // ── Sons (bibliothèque) ───────────────────────────────────────────────────

  Future<List<Sound>> getAllSounds() async {
    return await _repository.getAllSounds();
  }

  Future<Set<int>> findSoundIdsByTagQuery(String query) {
    return _repository.findSoundIdsByTagQuery(query);
  }

  /// Ids des sons visibles par une bibliothèque (VUE PARTAGÉE) — scope du picker
  /// d'un board Drive : ses dossiers, recouvrements de liens compris.
  Future<Set<int>> getSoundIdsVisibleToLibrary(int libraryId) {
    return _repository.getSoundIdsVisibleToLibrary(libraryId);
  }

  Future<Set<int>> getLocallyAvailableSoundIds() async {
    final sounds = await _repository.getAllSounds();
    final available = <int>{};
    for (final sound in sounds) {
      if (await _isAvailableLocally(sound)) available.add(sound.id);
    }
    return available;
  }

  Future<bool> _isAvailableLocally(Sound sound) async {
    try {
      await _resolvePlayablePath(sound, downloadIfNeeded: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pré-écoute d'un son (recherche-éclair).
  ///
  /// La musique passe par la régie live ; bruitages/ambiances en fire-and-forget
  /// depuis le [Sound.startOffsetMs].
  Future<bool> previewSound(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    if (sound.type == SoundType.music) {
      final padItem = await playMusicBySoundId(soundId);
      return padItem != null;
    }
    return _playEphemeralPreview(sound);
  }

  /// Son en cours d'aperçu dans la bibliothèque, ou `null`.
  int? get libraryPreviewSoundId => _libraryPreviewSoundId;

  /// Indique si l'aperçu bibliothèque de [soundId] est audible.
  bool libraryPreviewIsPlaying(int soundId) =>
      _libraryPreviewSoundId == soundId &&
      (_libraryPreviewPlayer?.isPlaying ?? false);

  /// Bascule play/pause pour l'aperçu bibliothèque (lecteur unique).
  Future<bool> toggleLibraryPreview(int soundId) async {
    final player = _libraryPreviewPlayer;
    if (_libraryPreviewSoundId == soundId && player != null) {
      if (player.isPlaying) {
        await player.pause();
        _notify();
        return true;
      }
      if (player.isPaused) {
        await player.resume();
        _notify();
        return true;
      }
    }

    stopLibraryPreview(notify: false);
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    return _startLibraryPreview(sound);
  }

  /// Arrête et libère l'aperçu bibliothèque.
  void stopLibraryPreview({bool notify = true}) {
    _libraryPreviewSub?.cancel();
    _libraryPreviewSub = null;
    _libraryPreviewPlayer?.dispose();
    _libraryPreviewPlayer = null;
    _libraryPreviewSoundId = null;
    if (notify) _notify();
  }

  Future<bool> _startLibraryPreview(Sound sound) async {
    try {
      final path = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: allowsSoundDownload,
      );
      final player = await AudioPlayerService.create(path);
      _libraryPreviewPlayer = player;
      _libraryPreviewSoundId = sound.id;
      _libraryPreviewSub = player.onPlayerStateChanged.listen((playing) {
        if (playing) return;
        stopLibraryPreview();
      });
      var startOffsetMs = sound.startOffsetMs;
      final duration = player.duration;
      if (duration > Duration.zero) {
        final maxMs = duration.inMilliseconds;
        if (startOffsetMs >= maxMs) {
          startOffsetMs = (maxMs - 1).clamp(0, maxMs);
        }
      }
      await player.playFromPosition(Duration(milliseconds: startOffsetMs));
      _markPlayed(sound.id);
      _notify();
      return true;
    } catch (e) {
      debugPrint('Aperçu bibliothèque échoué pour ${sound.title}: $e');
      stopLibraryPreview(notify: false);
      return false;
    }
  }

  /// Pré-écoute fire-and-forget depuis le point d'entrée du son.
  Future<bool> _playEphemeralPreview(Sound sound) async {
    try {
      final path = await _resolvePlayablePath(
        sound,
        downloadIfNeeded: allowsSoundDownload,
      );
      final player = await AudioPlayerService.create(path);
      _previewPlayers.add(player);
      StreamSubscription<bool>? sub;
      sub = player.onPlayerStateChanged.listen((playing) {
        if (playing) return;
        sub?.cancel();
        _previewPlayers.remove(player);
        player.dispose();
        notifyListeners();
      });
      var startOffsetMs = sound.startOffsetMs;
      final duration = player.duration;
      if (duration > Duration.zero) {
        final maxMs = duration.inMilliseconds;
        if (startOffsetMs >= maxMs) {
          startOffsetMs = (maxMs - 1).clamp(0, maxMs);
        }
      }
      await player.playFromPosition(Duration(milliseconds: startOffsetMs));
      _markPlayed(sound.id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Pré-écoute échouée pour ${sound.title}: $e');
      return false;
    }
  }

  /// Arrête et libère toutes les pré-écoutes en cours.
  void stopAllPreviews() {
    stopLibraryPreview(notify: false);
    if (_previewPlayers.isEmpty) return;
    final players = _previewPlayers.toList();
    _previewPlayers.clear();
    for (final player in players) {
      player.dispose();
    }
  }

  /// À appeler à l'entrée en mode live (Mode Spectacle) : le prochain pad
  /// ajouté via la recherche-éclair démarre une nouvelle ligne plutôt que de
  /// s'ajouter à la suite de la dernière ligne déjà en place.
  void markPerformanceModeEntered() {
    _forceNewRowOnNextQuickAdd = true;
  }

  Future<QuickSearchPrepareResult> prepareSoundFromQuickSearch(
    int soundId,
  ) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return const QuickSearchPrepareResult.none();

    if (sound.type == SoundType.music) {
      await enqueueMusicBySoundId(soundId);
      return const QuickSearchPrepareResult.none();
    }

    return _prepareSfxPadOnBoard(soundId);
  }

  Iterable<({Pad pad, bool isDraft})> _padsOnBoardRefs() {
    return [
      for (final item in _state.pads) (pad: item.pad, isDraft: item.isDraft),
    ];
  }

  Future<QuickSearchPrepareResult> _prepareSfxPadOnBoard(int soundId) async {
    final boardId = _activeBoardId;
    if (boardId == null) return const QuickSearchPrepareResult.none();

    final forceNewRow = _forceNewRowOnNextQuickAdd;

    final result = await prepareSfxOnBoard(
      soundId: soundId,
      padsOnBoard: _padsOnBoardRefs(),
      forceNewRow: forceNewRow,
      createPad: (placement) {
        _forceNewRowOnNextQuickAdd = false;
        return _repository.createPadWithSettings(
          boardId: boardId,
          soundIds: [soundId],
          rowIndex: placement.rowIndex,
          sortOrder: placement.globalSortOrder,
        );
      },
      reloadPads: () async {
        await loadSounds(boardId: boardId, silent: true);
        return _padsOnBoardRefs();
      },
    );

    final highlightId = result.highlightPadId;
    if (highlightId != null) {
      final padItem = findPadItemById(highlightId);
      if (padItem != null) {
        final slotIndex = padItem.pad.sounds.indexWhere((s) => s.id == soundId);
        if (slotIndex >= 0) _maybeAutoDownloadPadSound(padItem, slotIndex);
      }
    }

    return result;
  }

  int? beginDraftPad({required int rowIndex}) {
    final boardId = _activeBoardId;
    if (boardId == null) return null;

    final draftId = _draftPadIdSeq--;
    final pad = Pad(
      id: draftId,
      boardId: boardId,
      sortOrder: _state.pads.where((item) => !item.isDraft).length,
      rowIndex: rowIndex,
      createdAt: DateTime.now(),
    );
    final item = PadItem(pad: pad)..isDraft = true;
    _finalizePadAvailability(item);

    final pads = [..._state.pads, item];
    _syncMultipadNumbers(pads);
    _state = _state.copyWith(pads: pads);
    notifyListeners();
    return draftId;
  }

  Future<void> updateDraftPadSounds(
    int draftPadId,
    List<int> soundIds,
  ) async {
    final item = findPadItemById(draftPadId);
    if (item == null || !item.isDraft) return;

    final sounds = <Sound>[];
    for (final id in soundIds) {
      final sound = await _repository.getSoundById(id);
      if (sound != null) sounds.add(sound);
    }

    item.pad = item.pad.copyWith(sounds: sounds);
    item.syncSlotCount();
    await _probePadLocalAvailability(item);
    _syncMultipadNumbers(_state.pads);
    item.bumpRevision();
    notifyListeners();
  }

  void cancelDraftPad(int draftPadId) {
    final item = findPadItemById(draftPadId);
    if (item == null || !item.isDraft) return;

    item.dispose();
    final pads =
        _state.pads.where((pad) => pad.pad.id != draftPadId).toList();
    _syncMultipadNumbers(pads);
    _state = _state.copyWith(pads: pads);
    notifyListeners();
  }

  Future<PadItem?> commitDraftPad({
    required int draftPadId,
    required List<int> soundIds,
  }) async {
    final draftIndex = _state.pads.indexWhere(
      (item) => item.pad.id == draftPadId && item.isDraft,
    );
    if (draftIndex < 0) return null;

    final draft = _state.pads[draftIndex];
    final boardId = _activeBoardId;
    if (boardId == null) return null;

    final padId = await _repository.createPadWithSettings(
      boardId: boardId,
      soundIds: soundIds,
      rowIndex: draft.pad.rowIndex,
    );

    final pads = await _loadPadsUseCase(boardId);
    Pad? createdPad;
    for (final pad in pads) {
      if (pad.id == padId) {
        createdPad = pad;
        break;
      }
    }
    if (createdPad == null) {
      cancelDraftPad(draftPadId);
      await loadSounds(boardId: boardId, silent: true);
      final fallback = _music._resolvePadItem(padId);
      if (fallback != null) _maybeAutoDownloadPad(fallback);
      return fallback;
    }

    draft.dispose();
    final padItem = PadItem(pad: createdPad);
    await _probePadLocalAvailability(padItem);

    final nextPads = List<PadItem>.from(_state.pads);
    nextPads[draftIndex] = padItem;
    _syncMultipadNumbers(nextPads);
    _state = _state.copyWith(pads: nextPads);
    _music._syncMusicStateWithPads();
    notifyListeners();

    unawaited(_loadPlayersForPadSafe(padItem, createdPad));
    _maybeAutoDownloadPad(padItem);
    return padItem;
  }

  // ── Tags ──────────────────────────────────────────────────────────────────

  Future<List<TagCategoryWithTags>> loadTagCatalog() async {
    return await _repository.getTagCatalog();
  }

  Future<List<TagItem>> getTagsForSound(int soundId) async {
    return await _repository.getTagsForSound(soundId);
  }

  Future<void> updateSoundTags(int soundId, Set<int> tagIds) async {
    await _repository.setTagsForSound(soundId, tagIds.toList());
  }
}
