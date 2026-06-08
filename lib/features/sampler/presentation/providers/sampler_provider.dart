import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/local_sound_probe.dart';
import '../../../../core/sync/download_queue.dart';
import '../../data/repositories/library_repository.dart'
    show LibraryRepository, SoundNotAvailableLocallyException;
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_board.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../../domain/entities/tag_item.dart';
import '../../domain/usecases/load_sounds_usecase.dart';
import '../../domain/usecases/remove_sound_from_board_usecase.dart';
import '../models/pad_sound_slot.dart';

/// Raison pour laquelle un pad ne peut pas être joué.
enum PadUnavailabilityReason {
  /// Sons présents en DB mais fichiers non encore téléchargés (connexion disponible).
  needsDownload,
  /// Appareil hors-ligne et fichiers absents du cache local.
  offline,
  /// Fichier local introuvable (supprimé ou déplacé).
  missingFile,
}

/// État du sampler
class SamplerState {
  static const Object _unset = Object();

  final List<PadItem> pads;
  final bool isLoading;
  final String? error;
  final List<SoundBoard> boards;
  final SoundBoard? selectedBoard;
  final bool isBoardsLoading;
  final String? boardsError;
  final PadItem? currentMusicPad;
  final List<int> musicQueuePadIds;
  /// true pendant la préparation hors-ligne du board (téléchargements en cours).
  final bool isBoardPreparing;
  /// Nombre de pads déjà téléchargés pendant la préparation.
  final int boardPrepareDone;
  /// Nombre total de pads à télécharger pendant la préparation.
  final int boardPrepareTotal;

  SamplerState({
    required this.pads,
    this.isLoading = false,
    this.error,
    this.boards = const [],
    this.selectedBoard,
    this.isBoardsLoading = false,
    this.boardsError,
    this.currentMusicPad,
    this.musicQueuePadIds = const [],
    this.isBoardPreparing = false,
    this.boardPrepareDone = 0,
    this.boardPrepareTotal = 0,
  });

  /// Prochaine musique en file d'attente.
  PadItem? queuedMusicPad(PadItem? Function(int padId) resolve) {
    if (musicQueuePadIds.isEmpty) return null;
    return resolve(musicQueuePadIds.first);
  }

  /// File d'attente résolue.
  List<PadItem> musicQueue(PadItem? Function(int padId) resolve) {
    return musicQueuePadIds
        .map(resolve)
        .whereType<PadItem>()
        .toList(growable: false);
  }

  SamplerState copyWith({
    List<PadItem>? pads,
    bool? isLoading,
    Object? error = _unset,
    List<SoundBoard>? boards,
    Object? selectedBoard = _unset,
    bool? isBoardsLoading,
    Object? boardsError = _unset,
    Object? currentMusicPad = _unset,
    List<int>? musicQueuePadIds,
    bool clearCurrentMusicPad = false,
    bool clearMusicQueue = false,
    bool? isBoardPreparing,
    int? boardPrepareDone,
    int? boardPrepareTotal,
  }) {
    return SamplerState(
      pads: pads ?? this.pads,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      boards: boards ?? this.boards,
      selectedBoard: identical(selectedBoard, _unset)
          ? this.selectedBoard
          : selectedBoard as SoundBoard?,
      isBoardsLoading: isBoardsLoading ?? this.isBoardsLoading,
      boardsError: identical(boardsError, _unset)
          ? this.boardsError
          : boardsError as String?,
      currentMusicPad: clearCurrentMusicPad
          ? null
          : identical(currentMusicPad, _unset)
          ? this.currentMusicPad
          : currentMusicPad as PadItem?,
      musicQueuePadIds: clearMusicQueue
          ? const []
          : musicQueuePadIds ?? this.musicQueuePadIds,
      isBoardPreparing: isBoardPreparing ?? this.isBoardPreparing,
      boardPrepareDone: boardPrepareDone ?? this.boardPrepareDone,
      boardPrepareTotal: boardPrepareTotal ?? this.boardPrepareTotal,
    );
  }
}

/// Item de pad — un [PadSoundSlot] par son, index aligné sur [Pad.sounds].
class PadItem {
  Pad pad;
  final List<PadSoundSlot> slots;
  bool isPlaying;
  int _nextSoundIndex;
  int? _currentPlayerIndex;
  int? pausedPlayerIndex;
  Duration? pausedPlaybackPosition;
  PadUnavailabilityReason? unavailabilityReason;
  bool isDownloading = false;
  int downloadDone = 0;
  int downloadTotal = 0;
  /// Index du slot en cours de téléchargement (détail pad, variante unique).
  int? downloadingSlotIndex;

  /// Révision par pad : incrémentée à chaque changement propre au pad (download,
  /// disponibilité). Permet un rebuild ciblé du seul PadButton via un
  /// [ListenableBuilder], sans reconstruire toute la grille (refonte UX P2).
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  Listenable get revision => _revision;
  void bumpRevision() => _revision.value++;

  PadItem({
    required this.pad,
    List<PadSoundSlot>? slots,
    this.isPlaying = false,
    int nextSoundIndex = 0,
    this.unavailabilityReason,
  })  : slots = slots ?? [],
        _nextSoundIndex = nextSoundIndex {
    syncSlotCount();
  }

  void syncSlotCount() {
    while (slots.length < pad.sounds.length) {
      slots.add(PadSoundSlot());
    }
    while (slots.length > pad.sounds.length) {
      slots.removeLast().dispose();
    }
  }

  int get totalSoundCount => pad.sounds.length;

  int get readySoundCount => slots.where((s) => s.appearsReady).length;

  bool get isPlayable => slots.any((s) => s.isReady);

  bool get appearsReady => slots.any((s) => s.appearsReady);

  bool get isFullyReady =>
      pad.sounds.isNotEmpty &&
      slots.every((s) => s.isReady || s.isCached);

  bool get isPartiallyReady => appearsReady && !isFullyReady;

  int get pendingDownloadCount => slots
      .where((s) => s.availability == PadSoundAvailability.needsDownload)
      .length;

  /// true pendant un téléchargement actif pour la régie.
  bool get showsRegieDownloadProgress => isDownloading;

  /// Progression normalisée [0–1] pendant le téléchargement, sinon null.
  double? get regieDownloadProgress => isDownloading && downloadTotal > 0
      ? downloadDone / downloadTotal
      : null;

  /// Lecteur actuellement actif (celui qui joue ou vient de jouer).
  AudioPlayerService? get currentPlayer {
    final idx = _currentPlayerIndex;
    if (idx == null || idx >= slots.length) return null;
    return slots[idx].player;
  }

  /// Index du son actuellement joué (aligné sur [Pad.sounds]).
  int? get currentSoundIndex => _currentPlayerIndex;

  /// Lecteur de la piste en pause ou en cours (pour la barre de progression).
  AudioPlayerService? get progressPlayer {
    final idx = _currentPlayerIndex;
    if (idx != null && idx < slots.length && slots[idx].player != null) {
      return slots[idx].player;
    }
    final paused = pausedPlayerIndex;
    if (paused != null && paused < slots.length && slots[paused].player != null) {
      return slots[paused].player;
    }
    for (final slot in slots) {
      if (slot.player != null) return slot.player;
    }
    return null;
  }

  PadSoundAvailability availabilityForSound(int soundId) {
    final idx = pad.sounds.indexWhere((s) => s.id == soundId);
    if (idx < 0) return PadSoundAvailability.missingFile;
    return slots[idx].availability;
  }

  void disposeAllSlots() {
    for (final slot in slots) {
      slot.dispose();
    }
    slots.clear();
  }

  /// Libère le pad définitivement (slots + notifier de révision). À appeler
  /// quand le pad disparaît de l'état (changement de plateau, suppression).
  void dispose() {
    disposeAllSlots();
    _revision.dispose();
  }

  void clearPausedPlayback() {
    pausedPlayerIndex = null;
    pausedPlaybackPosition = null;
  }
}

class _RemovedPadSnapshot {
  final int boardId;
  final Pad pad;
  final int index;

  const _RemovedPadSnapshot({
    required this.boardId,
    required this.pad,
    required this.index,
  });
}

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
  double _musicVolume = 1.0;
  double _musicVolumeBeforeMute = 1.0;
  static const _musicVolumeSliderFadeDuration = Duration(milliseconds: 120);
  _RemovedPadSnapshot? _lastRemovedPad;
  final _random = Random();
  bool _skipMusicAutoAdvance = false;

  /// Pads musique "hors-scène" : créés à la volée depuis le sélecteur pour
  /// jouer une musique dans la régie sans l'ajouter au plateau.
  final Map<int, PadItem> _offStageMusicPads = {};

  /// Lecteur dédié à la pré-écoute (recherche-éclair) : indépendant des pads,
  /// du master musique et de la file — auditionner ou déclencher un son sans
  /// l'ajouter au plateau.
  AudioPlayerService? _previewPlayer;

  /// File de téléchargement priorisée à concurrence bornée (refonte UX P2) :
  /// un tap utilisateur double un prefetch en attente, et changer de plateau
  /// annule le prefetch encore en file. La déduplication par padId remplace
  /// l'ancien suivi manuel des tâches en vol.
  final DownloadQueue _downloadQueue = DownloadQueue(maxConcurrent: 2);

  /// Priorités de téléchargement : tap utilisateur > préparation manuelle >
  /// prefetch d'arrière-plan.
  static const int _downloadPriorityTap = 100;
  static const int _downloadPriorityManualPrepare = 50;
  static const int _downloadPriorityPrefetch = 10;

  /// Génération de préchargement courante : tout changement de plateau ou
  /// rechargement l'incrémente, ce qui annule le prefetch en cours.
  int _prefetchGeneration = 0;

  /// Sérialise les rechargements de plateau pour éviter les courses async.
  Future<void>? _loadSoundsChain;

  /// Annule le préchargement audio quand le plateau change.
  int _padPreloadGeneration = 0;

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;
  double get musicVolume => _musicVolume;

  /// Dernière erreur de lecture musique (picker / régie), sans bloquer la grille.
  String? _lastMusicPlaybackError;

  /// Consomme le message d'erreur musique le plus récent (usage UI ponctuel).
  String? consumeLastMusicPlaybackError() {
    final message = _lastMusicPlaybackError;
    _lastMusicPlaybackError = null;
    return message;
  }

  /// Volume effectif d'un pad : les pads musique sont en plus soumis
  /// au volume musique global, les autres pads jouent à leur volume propre.
  double _effectiveVolume(PadItem padItem) =>
      padItem.pad.isMusicPad
          ? padItem.pad.volume * _musicVolume
          : padItem.pad.volume;
  bool get canUndoLastRemoval =>
      _lastRemovedPad != null && _lastRemovedPad!.boardId == _activeBoardId;

  SamplerNotifier(
    this._repository,
    this._loadPadsUseCase, [
    this._removePadUseCase,
    this._libraryRepository,
    AppPreferences? appPreferences,
  ]) : _appPreferences = appPreferences;

  /// Résout le chemin local jouable d'un son (cache Drive si bibliothèque).
  ///
  /// [downloadIfNeeded] false (défaut) : lève [SoundNotAvailableLocallyException]
  /// si le fichier n'est pas en cache, sans déclencher de téléchargement.
  /// [downloadIfNeeded] true : télécharge depuis Drive si nécessaire.
  Future<String> _resolvePlayablePath(
    Sound sound, {
    bool downloadIfNeeded = false,
  }) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null) {
      // SoundNotAvailableLocallyException remonte intentionnellement.
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
        // Sons de bibliothèque : pas de repli sur filePath (chemin d'un autre appareil).
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

  Future<PadSoundAvailability> _probeSoundLocalAvailability(Sound sound) async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository != null &&
        sound.libraryId != null &&
        sound.relativePath != null &&
        sound.relativePath!.isNotEmpty) {
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
    if (await file.exists()) {
      return PadSoundAvailability.missingFile;
    }
    return PadSoundAvailability.missingFile;
  }

  Future<void> _probePadLocalAvailability(PadItem padItem) async {
    padItem.syncSlotCount();
    for (var i = 0; i < padItem.pad.sounds.length; i++) {
      final slot = padItem.slots[i];
      if (slot.isReady || slot.isCached) continue;
      final availability = await _probeSoundLocalAvailability(
        padItem.pad.sounds[i],
      );
      slot.dispose();
      padItem.slots[i] = PadSoundSlot(availability: availability);
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

  /// Pad du plateau courant par id (évite les références périmées après reload).
  PadItem? findPadItemById(int padId) {
    for (final item in _state.pads) {
      if (item.pad.id == padId) return item;
    }
    return null;
  }

  PadItem _resolveBoardPadItem(PadItem padItem) =>
      findPadItemById(padItem.pad.id) ?? padItem;

  /// Recharge le type (et métadonnées) d'un son dans le pad après résolution du fichier.
  Future<void> _syncPadSoundMetadata(PadItem padItem, int index) async {
    if (index < 0 || index >= padItem.pad.sounds.length) return;
    final soundId = padItem.pad.sounds[index].id;
    final updated = await _repository.getSoundById(soundId);
    if (updated == null) return;
    final sounds = List<Sound>.from(padItem.pad.sounds);
    sounds[index] = updated;
    padItem.pad = padItem.pad.copyWith(sounds: sounds);
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

    // Conserver l'apparence « prêt » (phase 0) pendant le warm SoLoud.
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
    } on SoundNotAvailableLocallyException catch (e) {
      padItem.slots[index] = PadSoundSlot(
        availability: _availabilityFromException(e),
      );
    } catch (e, stack) {
      if (resolvedPath != null) {
        markPathUnloadable(resolvedPath);
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
    final padLabel = pad.displayName;
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
      if (padItem.slots[i].isReady) continue;
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
      final player = padItem.slots[i].player;
      if (player == null) continue;
      attachedCount++;
      final idx = i;
      player.onPlayerStateChanged.listen((playing) {
        debugPrint(
          '[LISTENER] pad="${padItem.pad.displayName}" slot=$idx playing=$playing '
          'currentPlayerIndex=${padItem._currentPlayerIndex} isPlaying=${padItem.isPlaying}',
        );
        if (playing) {
          padItem._currentPlayerIndex = idx;
          padItem.isPlaying = true;
          if (padItem.pad.isMusicPad) {
            _state = _state.copyWith(currentMusicPad: padItem);
          }
        } else if (padItem._currentPlayerIndex == idx) {
          padItem.isPlaying = false;
          padItem._currentPlayerIndex = null;
          if (padItem.pad.isMusicPad) {
            _handleMusicPlaybackEnded(padItem);
          }
        } else {
          debugPrint(
            '[LISTENER] ↩ false ignored: currentPlayerIndex=${padItem._currentPlayerIndex} != slot=$idx',
          );
        }
        debugPrint(
          '[LISTENER] after: isPlaying=${padItem.isPlaying} '
          'currentPlayerIndex=${padItem._currentPlayerIndex}',
        );
        notifyListeners();
      });
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
    _state = _state.copyWith(selectedBoard: board);
    _activeBoardId = board.id;
    notifyListeners();
    await loadSounds();
  }

  Future<SoundBoard?> createBoard(String name, {int? color}) async {
    try {
      final libraryId = await _libraryRepository?.singleConnectedLibraryId();
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
    if (boardId != null) _activeBoardId = boardId;
    _lastRemovedPad = null;
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

      await Future.wait(
        padItems.map(_probePadLocalAvailability),
      );

      _state = _state.copyWith(pads: padItems, isLoading: false, error: null);
      final keptIds = padItems.map((item) => item.pad.id).toSet();
      final removedItems =
          previousItems.where((item) => !keptIds.contains(item.pad.id)).toList();
      _disposePadItems(removedItems);
      _syncMusicStateWithPads();

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

  /// Précharge en arrière-plan les pads téléchargeables du plateau courant, dans
  /// l'ordre de la grille (les plus accessibles d'abord), pour que l'opérateur
  /// trouve des pads PRÊT sans rien demander (refonte UX P1 — « le système
  /// anticipe »).
  ///
  /// Silencieux et non bloquant ; annulé dès qu'on change de plateau ou qu'un
  /// nouveau chargement démarre (garde de génération + annulation de la file) ;
  /// inopérant hors-ligne — seuls les pads `needsDownload` sont visés, les
  /// `offline`/`missingFile` sont ignorés. Les pads sont mis en file à priorité
  /// basse : la [DownloadQueue] borne la concurrence et un tap utilisateur passe
  /// devant. La priorité aux favoris viendra avec P3.
  Future<void> _prefetchActiveBoard() async {
    final libraryRepository = _libraryRepository;
    if (libraryRepository == null) return;

    final generation = ++_prefetchGeneration;
    final boardId = _activeBoardId;
    if (boardId == null) return;
    if (_state.isBoardPreparing) return; // la préparation manuelle prime.

    // Une seule vérification de connexion : inutile de marteler Drive hors-ligne.
    if (!await libraryRepository.ensureDriveConnected()) return;
    if (generation != _prefetchGeneration || _activeBoardId != boardId) return;

    // Annule le prefetch encore en file d'un plateau précédent (les tâches déjà
    // démarrées finissent en cache, sans gâchis ; les tap restent prioritaires).
    _downloadQueue.cancelQueued(
      (key, priority) => priority <= _downloadPriorityPrefetch,
    );

    for (final padItem in List<PadItem>.from(_state.pads)) {
      if (padItem.pendingDownloadCount == 0) continue; // déjà prêt ou bloqué.
      unawaited(
        downloadAndLoadPad(padItem, priority: _downloadPriorityPrefetch)
            .catchError((_) => false),
      );
    }
  }

  /// Recharge les lecteurs d'un pad depuis le cache local (après téléchargement).
  Future<void> refreshPadPlayback(int padId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;
    await _loadPlayersForPad(padItem, padItem.pad);
    notifyListeners();
  }

  /// Joue ou arrête le pad selon son mode de lecture.
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
      await _toggleMusicPad(resolved);
      return;
    }

    if (resolved.isPlaying) {
      debugPrint('[TOGGLE] → stopping current player (idx=${resolved._currentPlayerIndex})');
      await resolved.currentPlayer?.stop();
      return;
    }

    final soundIndex = _pickSoundIndex(resolved);
    final player = resolved.slots[soundIndex].player;
    debugPrint(
      '[TOGGLE] → play soundIndex=$soundIndex '
      'playerNull=${player == null} '
      '_nextSoundIndex=${resolved._nextSoundIndex}',
    );
    if (player == null) return;
    player.setVolume(_effectiveVolume(resolved));
    await player.play();
    _markPlayedAt(resolved, soundIndex);
    notifyListeners();
  }

  /// Enregistre l'instant de dernière lecture du son joué (tri par récence en
  /// recherche). Fire-and-forget ; l'écriture est débouncée côté sync.
  void _markPlayed(int soundId) {
    unawaited(_repository.markSoundPlayed(soundId));
  }

  void _markPlayedAt(PadItem padItem, int soundIndex) {
    if (soundIndex < 0 || soundIndex >= padItem.pad.sounds.length) return;
    _markPlayed(padItem.pad.sounds[soundIndex].id);
  }

  /// Change le type d'un son puis recharge le plateau : `isMusicPad` (et donc
  /// le routage musique vs déclenchement) en dépend directement.
  ///
  /// La mise à jour en mémoire est synchrone (notifyListeners immédiat) pour
  /// éviter une fenêtre où le routage utilise encore l'ancien type alors que
  /// l'UI a déjà reflété le changement (race condition : `_changeType` est async
  /// mais son appelant ne peut pas awaiter via `ValueChanged<SoundType>`).
  Future<void> updateSoundType(int soundId, SoundType type) async {
    // 1. Mise à jour en mémoire immédiate — routage correct sans attendre la DB.
    for (final padItem in _state.pads) {
      final sounds = padItem.pad.sounds;
      final idx = sounds.indexWhere((s) => s.id == soundId);
      if (idx >= 0) {
        final s = sounds[idx];
        final updated = List<Sound>.from(sounds);
        updated[idx] = Sound(
          id: s.id,
          title: s.title,
          displayName: s.displayName,
          filePath: s.filePath,
          type: type,
          colorValue: s.colorValue,
          volume: s.volume,
          createdAt: s.createdAt,
          libraryId: s.libraryId,
          relativePath: s.relativePath,
          contentHash: s.contentHash,
          isFavorite: s.isFavorite,
          lastPlayedAt: s.lastPlayedAt,
          typeDetected: true,
        );
        padItem.pad = padItem.pad.copyWith(sounds: updated);
        _notifyPad(padItem);
      }
    }
    notifyListeners();
    // 2. Persistance DB + rechargement complet pour synchroniser le reste.
    await _repository.updateSoundType(soundId, type);
    await loadSounds();
  }

  /// Bascule l'état favori d'un son et persiste. Retourne le nouvel état.
  Future<bool> toggleSoundFavorite(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    final next = !sound.isFavorite;
    await _repository.setSoundFavorite(soundId, next);
    return next;
  }

  /// Notifie le rebuild d'un seul pad (progression de download, disponibilité)
  /// sans reconstruire toute la grille : chaque PadButton écoute `revision`.
  void _notifyPad(PadItem padItem) => padItem.bumpRevision();

  /// Télécharge les variantes manquantes puis recharge les slots concernés via
  /// la file priorisée. Retourne true si au moins une variante est jouable.
  ///
  /// [priority] : tap utilisateur par défaut (double tout prefetch en attente).
  /// Une tâche annulée (changement de plateau) retourne l'état jouable courant.
  /// Télécharge une variante précise du pad (tap depuis l'écran de détails).
  Future<bool> downloadPadSoundAtIndex(PadItem padItem, int index) async {
    final resolved = _resolveBoardPadItem(padItem);
    if (index < 0 || index >= resolved.slots.length) return false;
    final slot = resolved.slots[index];
    if (slot.isReady) return true;
    if (slot.availability == PadSoundAvailability.missingFile) return false;

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
    if (slot.availability == PadSoundAvailability.missingFile) return false;

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
      // Fichier local corrompu / illisible : inutile de boucler sur le téléchargement.
      if (slot.availability == PadSoundAvailability.missingFile) continue;
      pendingIndices.add(i);
    }
    if (pendingIndices.isEmpty) {
      if (padItem.isPlayable) return true;
      await _loadPlayersForPad(padItem, padItem.pad);
      _notifyPad(padItem);
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
          _notifyPad(padItem);
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
    _notifyPad(padItem);
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
        padItem.slots[i] = PadSoundSlot(
          availability: PadSoundAvailability.missingFile,
        );
      }
    }
    _finalizePadAvailability(padItem);
  }

  /// Télécharge toutes les variantes manquantes du board actif.
  Future<void> prepareBoardForOffline() async {
    if (_state.isBoardPreparing) return;

    final toDownload = _state.pads.where((p) => !p.isFullyReady).toList();
    if (toDownload.isEmpty) return;

    _state = _state.copyWith(
      isBoardPreparing: true,
      boardPrepareDone: 0,
      boardPrepareTotal: toDownload.length,
    );
    notifyListeners();

    for (var i = 0; i < toDownload.length; i++) {
      await downloadAndLoadPad(
        toDownload[i],
        priority: _downloadPriorityManualPrepare,
      );
      _state = _state.copyWith(boardPrepareDone: i + 1);
      notifyListeners();
    }

    _state = _state.copyWith(isBoardPreparing: false);
    notifyListeners();
  }

  int _pickSoundIndex(PadItem padItem) {
    final readyIndices = <int>[
      for (var i = 0; i < padItem.slots.length; i++)
        if (padItem.slots[i].isReady) i,
    ];
    debugPrint(
      '[PICK] pad="${padItem.pad.displayName}" '
      'slots=${padItem.slots.length} readyIndices=$readyIndices '
      '_nextSoundIndex=${padItem._nextSoundIndex} '
      'playMode=${padItem.pad.playMode}',
    );
    if (readyIndices.isEmpty) return 0;
    if (readyIndices.length == 1) return readyIndices.first;

    final chosen = switch (padItem.pad.playMode) {
      PadPlayMode.random =>
        readyIndices[_random.nextInt(readyIndices.length)],
      PadPlayMode.sequential => () {
          final total = padItem.slots.length;
          for (var step = 0; step < total; step++) {
            final idx = (padItem._nextSoundIndex + step) % total;
            if (padItem.slots[idx].isReady) {
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

  Future<void> _toggleMusicPad(PadItem padItem) async {
    if (!padItem.isPlayable) return;

    final currentMusic = _state.currentMusicPad;

    if (padItem.isPlaying) {
      await _stopMusicPad(padItem, manual: true);
      return;
    }

    if (_state.musicQueuePadIds.contains(padItem.pad.id)) {
      _removeFromMusicQueue(padItem.pad.id);
      return;
    }

    if (currentMusic != null &&
        currentMusic.pad.id != padItem.pad.id &&
        currentMusic.isPlaying) {
      enqueueMusicPad(padItem);
      return;
    }

    await playMusicNow(padItem);
  }

  void _removeFromMusicQueue(int padId) {
    final nextQueue =
        _state.musicQueuePadIds.where((id) => id != padId).toList();
    if (nextQueue.length == _state.musicQueuePadIds.length) return;
    _state = _state.copyWith(musicQueuePadIds: nextQueue);
    notifyListeners();
  }

  void enqueueMusicPad(PadItem padItem) {
    if (padItem.pad.id == _state.currentMusicPad?.pad.id) return;
    if (_state.musicQueuePadIds.contains(padItem.pad.id)) return;
    _state = _state.copyWith(
      musicQueuePadIds: [..._state.musicQueuePadIds, padItem.pad.id],
    );
    notifyListeners();
  }

  Future<void> playMusicNow(PadItem padItem) async {
    if (!padItem.isPlayable) return;

    final current = _state.currentMusicPad;
    if (current != null &&
        current.pad.id != padItem.pad.id &&
        current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    _state = _state.copyWith(
      musicQueuePadIds: _state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );
    await _playMusicPad(padItem);
  }

  Future<PadItem?> playMusicBySoundId(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) {
      _setMusicLoadError();
      return null;
    }
    if (sound.type != SoundType.music) {
      _lastMusicPlaybackError = 'Ce son n\'est pas une musique.';
      notifyListeners();
      return null;
    }

    final padItem = await _findOrCreateMusicPadForSound(soundId);
    if (padItem == null) return null;
    final ready = await _prepareMusicPadForPlayback(
      padItem,
      downloadIfNeeded: true,
    );
    if (!ready) {
      _setMusicLoadError(padItem);
      return null;
    }
    await playMusicNow(padItem);
    return padItem;
  }

  Future<PadItem?> enqueueMusicBySoundId(int soundId) async {
    final padItem = await _findOrCreateMusicPadForSound(soundId);
    if (padItem == null) return null;

    await _refreshPadAvailability(padItem);
    if (_isMusicPadPermanentlyUnavailable(padItem)) {
      _setMusicLoadError(padItem);
      return null;
    }

    final padId = padItem.pad.id;
    final current = _state.currentMusicPad;

    if (current?.pad.id == padId && (current?.isPlaying ?? false)) {
      return padItem;
    }
    if (_state.musicQueuePadIds.contains(padId)) {
      _scheduleMusicPadDownload(padItem);
      return padItem;
    }

    enqueueMusicPad(padItem);
    _scheduleMusicPadDownload(padItem);
    return padItem;
  }

  Future<PadItem?> _findOrCreateMusicPadForSound(int soundId) async {
    var existing = _findPadItemForSound(soundId);
    if (existing != null) {
      for (var i = 0; i < existing.pad.sounds.length; i++) {
        await _syncPadSoundMetadata(existing, i);
      }
      return existing;
    }

    final boardId = _activeBoardId;
    if (boardId != null) {
      final padIdBySound =
          await _repository.getSoundIdToFirstPadIdInBoard(boardId);
      if (padIdBySound.containsKey(soundId)) {
        await loadSounds(boardId: boardId);
        existing = _findPadItemForSound(soundId);
        if (existing != null) return existing;
      }
    }

    return _createOffStageMusicPad(soundId);
  }

  Future<void> _refreshPadAvailability(PadItem padItem) async {
    if (padItem.isPlayable) return;
    await _loadPlayersForPad(padItem, padItem.pad);
  }

  Future<bool> _prepareMusicPadForPlayback(
    PadItem padItem, {
    required bool downloadIfNeeded,
  }) async {
    if (padItem.isPlayable) return true;
    await _loadPlayersForPad(padItem, padItem.pad);
    if (padItem.isPlayable) return true;
    if (!downloadIfNeeded) return false;
    return downloadAndLoadPad(padItem);
  }

  bool _isMusicPadPermanentlyUnavailable(PadItem padItem) {
    return padItem.unavailabilityReason == PadUnavailabilityReason.offline ||
        padItem.unavailabilityReason == PadUnavailabilityReason.missingFile;
  }

  void _scheduleMusicPadDownload(PadItem padItem) {
    if (padItem.isPlayable) return;
    if (_isMusicPadPermanentlyUnavailable(padItem)) return;
    if (padItem.pendingDownloadCount == 0) return;
    unawaited(downloadAndLoadPad(padItem));
  }

  /// Prépare une musique pour la régie sans l'ajouter au plateau — un son
  /// peut être joué directement sans être lié à un pad sur la scène.
  Future<PadItem?> _createOffStageMusicPad(int soundId) async {
    try {
      final sound = await _repository.getSoundById(soundId);
      if (sound == null) {
        _setMusicLoadError();
        return null;
      }
      if (sound.type != SoundType.music) {
        _lastMusicPlaybackError = 'Ce son n\'est pas une musique.';
        notifyListeners();
        return null;
      }

      final pad = Pad(
        id: -soundId,
        boardId: -1,
        sortOrder: 0,
        createdAt: DateTime.now(),
        sounds: [sound],
      );
      final padItem = PadItem(pad: pad);
      await _loadPlayersForPad(padItem, pad);
      _offStageMusicPads[pad.id] = padItem;
      return padItem;
    } catch (e) {
      debugPrint('Impossible de préparer la musique pour la régie: $e');
      _lastMusicPlaybackError = 'Impossible de préparer cette musique.';
      notifyListeners();
      return null;
    }
  }

  void _setMusicLoadError([PadItem? padItem]) {
    _lastMusicPlaybackError = switch (padItem?.unavailabilityReason) {
      PadUnavailabilityReason.offline => 'Son indisponible hors-ligne.',
      PadUnavailabilityReason.missingFile => 'Fichier audio introuvable.',
      _ => 'Fichier audio introuvable ou indisponible hors-ligne.',
    };
    notifyListeners();
  }

  PadItem? _findPadItemForSound(int soundId) {
    for (final padItem in _state.pads) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      if (padItem.pad.sounds.any((sound) => sound.id == soundId)) {
        return padItem;
      }
    }
    return null;
  }

  /// Pad musique correspondant à un son, sur la scène ou hors-scène.
  PadItem? findMusicPadForSound(int soundId) => _findPadItemForSound(soundId);

  void _capturePausedPlayback(PadItem padItem) {
    final player = padItem.currentPlayer;
    if (player == null) return;
    padItem.pausedPlaybackPosition = player.position;
    padItem.pausedPlayerIndex = padItem._currentPlayerIndex;
  }

  Future<bool> _playMusicPad(
    PadItem padItem, {
    Duration? fromPosition,
    int? soundIndex,
  }) async {
    if (!padItem.pad.isMusicPad) {
      return false;
    }

    if (!padItem.isPlayable) {
      final ready = await _prepareMusicPadForPlayback(
        padItem,
        downloadIfNeeded: true,
      );
      if (!ready) {
        _setMusicLoadError(padItem);
        return false;
      }
    }

    final resumePosition = fromPosition;
    final resumeIndex = soundIndex;

    final index = () {
      if (resumeIndex != null &&
          resumeIndex < padItem.slots.length &&
          padItem.slots[resumeIndex].isReady) {
        return resumeIndex;
      }
      return _pickSoundIndex(padItem);
    }();
    final player = padItem.slots[index].player;
    if (player == null) {
      _setMusicLoadError(padItem);
      return false;
    }

    padItem.clearPausedPlayback();
    _state = _state.copyWith(
      currentMusicPad: padItem,
      musicQueuePadIds: _state.musicQueuePadIds
          .where((id) => id != padItem.pad.id)
          .toList(),
    );

    player.setVolume(_effectiveVolume(padItem));
    if (resumePosition != null && resumePosition > Duration.zero) {
      await player.playFromPosition(resumePosition);
    } else {
      await player.play();
    }
    _markPlayedAt(padItem, index);
    notifyListeners();
    return true;
  }

  Future<void> _stopMusicPad(
    PadItem padItem, {
    required bool manual,
    bool clearOnAir = true,
  }) async {
    if (manual) {
      _skipMusicAutoAdvance = true;
    }
    if (!clearOnAir && manual) {
      _capturePausedPlayback(padItem);
    }
    try {
      await padItem.currentPlayer?.stop();
    } finally {
      if (manual) {
        _skipMusicAutoAdvance = false;
      }
    }

    var nextState = _state;
    if (clearOnAir && _state.currentMusicPad?.pad.id == padItem.pad.id) {
      nextState = nextState.copyWith(clearCurrentMusicPad: true);
    }
    if (_state.musicQueuePadIds.contains(padItem.pad.id)) {
      nextState = nextState.copyWith(
        musicQueuePadIds: nextState.musicQueuePadIds
            .where((id) => id != padItem.pad.id)
            .toList(),
      );
    }
    _state = nextState;
    notifyListeners();
  }

  void _handleMusicPlaybackEnded(PadItem padItem) {
    if (_skipMusicAutoAdvance) return;
    if (_state.currentMusicPad?.pad.id != padItem.pad.id) return;

    final queue = _state.musicQueuePadIds;
    _state = _state.copyWith(clearCurrentMusicPad: true);
    notifyListeners();

    if (queue.isEmpty) return;

    final nextId = queue.first;
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _setMusicLoadError();
      return;
    }
    unawaited(_playMusicPad(next));
  }

  Future<void> removeFromMusicQueue(int padId) async {
    _removeFromMusicQueue(padId);
  }

  void reorderMusicQueue(int oldIndex, int newIndex) {
    final ids = List<int>.from(_state.musicQueuePadIds);
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    if (newIndex < 0 || newIndex >= ids.length) return;
    if (oldIndex == newIndex) return;

    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    _state = _state.copyWith(musicQueuePadIds: ids);
    notifyListeners();
  }

  Future<void> clearMusicQueue() async {
    if (_state.musicQueuePadIds.isEmpty) return;
    _state = _state.copyWith(clearMusicQueue: true);
    notifyListeners();
  }

  Future<bool> playNextInQueueNow() async {
    if (_state.musicQueuePadIds.isEmpty) return false;

    final nextId = _state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return false;

    final current = _state.currentMusicPad;
    if (current != null && current.isPlaying) {
      await _stopMusicPad(current, manual: true);
    }

    return _playMusicPad(next);
  }

  Future<void> stopCurrentMusic() async {
    final current = _state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    await _stopMusicPad(current, manual: true);
  }

  /// Fondu sortant de la musique en cours (sans lancer la file).
  /// Une durée nulle coupe immédiatement.
  Future<void> fadeOutCurrentMusic(Duration duration) async {
    final current = _state.currentMusicPad;
    if (current == null || !current.isPlaying) return;
    if (duration == Duration.zero) {
      await _stopMusicPad(current, manual: true, clearOnAir: false);
      return;
    }
    final player = current.currentPlayer;
    if (player == null) return;

    _skipMusicAutoAdvance = true;
    try {
      player.fadeVolumeTo(0, duration);
      await Future<void>.delayed(duration);
      _capturePausedPlayback(current);
      await player.stop();
      current.isPlaying = false;
      current._currentPlayerIndex = null;
      notifyListeners();
    } finally {
      _skipMusicAutoAdvance = false;
    }
  }

  /// Enchaîne vers la musique suivante en file, avec un fondu enchaîné.
  /// Une durée nulle passe directement à la suivante.
  /// « À l'antenne » n'est mis à jour qu'à la fin du fondu.
  Future<void> crossfadeToNextMusic(Duration duration) async {
    if (_state.musicQueuePadIds.isEmpty) return;

    if (duration == Duration.zero) {
      await playNextInQueueNow();
      return;
    }

    final current = _state.currentMusicPad;
    if (current == null || !current.isPlaying) {
      await _fadeInNextFromQueue(duration);
      return;
    }

    final nextId = _state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return;

    final currentPlayer = current.currentPlayer;
    if (currentPlayer == null) return;

    final soundIndex = _pickSoundIndex(next);
    final nextPlayer = next.slots[soundIndex].player;
    if (nextPlayer == null) {
      _setMusicLoadError(next);
      return;
    }
    final targetVolume = _effectiveVolume(next);

    _skipMusicAutoAdvance = true;
    try {
      _state = _state.copyWith(
        musicQueuePadIds: _state.musicQueuePadIds.sublist(1),
      );
      notifyListeners();

      await nextPlayer.playAtVolume(0);
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;

      currentPlayer.fadeVolumeTo(0, duration);
      nextPlayer.fadeVolumeTo(targetVolume, duration);

      await Future<void>.delayed(duration);

      if (currentPlayer.isPlaying) {
        await currentPlayer.stop();
      }
      current.isPlaying = false;
      current._currentPlayerIndex = null;

      _state = _state.copyWith(currentMusicPad: next);
      notifyListeners();
    } finally {
      _skipMusicAutoAdvance = false;
    }
  }

  /// Lance la tête de file avec fondu entrant — sans couper l'antenne avant la fin.
  Future<void> _fadeInNextFromQueue(Duration duration) async {
    if (_state.musicQueuePadIds.isEmpty) return;

    final nextId = _state.musicQueuePadIds.first;
    final next = await _prepareNextQueuedMusic(nextId);
    if (next == null) return;

    final previous = _state.currentMusicPad;

    _skipMusicAutoAdvance = true;
    try {
      _state = _state.copyWith(
        musicQueuePadIds: _state.musicQueuePadIds.sublist(1),
      );
      notifyListeners();

      final soundIndex = _pickSoundIndex(next);
      final nextPlayer = next.slots[soundIndex].player;
      if (nextPlayer == null) {
        _setMusicLoadError(next);
        return;
      }
      final targetVolume = _effectiveVolume(next);

      await nextPlayer.playAtVolume(0);
      next._currentPlayerIndex = soundIndex;
      next.isPlaying = true;
      nextPlayer.fadeVolumeTo(targetVolume, duration);

      await Future<void>.delayed(duration);

      if (previous != null && previous.pad.id != next.pad.id) {
        await previous.currentPlayer?.stop();
        previous.isPlaying = false;
        previous._currentPlayerIndex = null;
      }

      _state = _state.copyWith(currentMusicPad: next);
      notifyListeners();
    } finally {
      _skipMusicAutoAdvance = false;
    }
  }

  /// Prépare la tête de file pour une transition — ne retire pas l'entrée en cas d'échec.
  Future<PadItem?> _prepareNextQueuedMusic(int nextId) async {
    final next = _resolvePadItem(nextId);
    if (next == null) {
      _setMusicLoadError();
      return null;
    }

    if (!next.isPlayable) {
      final ready = await _prepareMusicPadForPlayback(
        next,
        downloadIfNeeded: true,
      );
      if (!ready) {
        _setMusicLoadError(next);
        return null;
      }
    }

    return next;
  }

  Future<void> toggleCurrentMusicPlayback() async {
    final current = _state.currentMusicPad;
    if (current == null) {
      if (_state.musicQueuePadIds.isNotEmpty) {
        await playNextInQueueNow();
      }
      return;
    }
    if (current.isPlaying) {
      await _stopMusicPad(current, manual: true, clearOnAir: false);
      return;
    }
    await _playMusicPad(
      current,
      fromPosition: current.pausedPlaybackPosition,
      soundIndex: current.pausedPlayerIndex,
    );
  }

  Future<void> restartCurrentMusic() async {
    final current = _state.currentMusicPad;
    if (current == null || !current.isPlayable) return;
    if (current.isPlaying) {
      _skipMusicAutoAdvance = true;
      try {
        await current.currentPlayer?.stop();
      } finally {
        _skipMusicAutoAdvance = false;
      }
    }
    await _playMusicPad(current);
  }

  Future<void> skipToNextMusic() async {
    if (_state.musicQueuePadIds.isEmpty) {
      await stopCurrentMusic();
      return;
    }
    await playNextInQueueNow();
  }

  void _clearMusicState() {
    _state = _state.copyWith(
      clearCurrentMusicPad: true,
      clearMusicQueue: true,
    );
  }

  PadItem? _resolvePadItem(int? padId) {
    if (padId == null) return null;
    for (final padItem in _state.pads) {
      if (padItem.pad.id == padId) return padItem;
    }
    return _offStageMusicPads[padId];
  }

  /// Résout un pad musique par id — sur la scène ou hors-scène (régie seule).
  PadItem? resolveMusicPad(int padId) => _resolvePadItem(padId);

  void _syncMusicStateWithPads() {
    final currentId = _state.currentMusicPad?.pad.id;
    final nextCurrent = _resolvePadItem(currentId);
    final nextQueue = _state.musicQueuePadIds
        .where((id) => _resolvePadItem(id) != null && id != nextCurrent?.pad.id)
        .toList();

    if (nextCurrent == _state.currentMusicPad &&
        _listEquals(nextQueue, _state.musicQueuePadIds)) {
      return;
    }

    _state = _state.copyWith(
      currentMusicPad: nextCurrent,
      musicQueuePadIds: nextQueue,
      clearCurrentMusicPad: nextCurrent == null && currentId != null,
    );
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Met à jour les réglages d'un pad et persiste en base.
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
              ? nextVolume * _musicVolume
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

  void _applyMusicVolumeToPlayingPads({bool smooth = false}) {
    for (final padItem in _state.pads) {
      if (padItem.isPlaying && padItem.pad.isMusicPad) {
        _applyEffectiveVolumeToPlayer(padItem, smooth: smooth);
      }
    }
    for (final padItem in _offStageMusicPads.values) {
      if (padItem.isPlaying) {
        _applyEffectiveVolumeToPlayer(padItem, smooth: smooth);
      }
    }
  }

  void _applyEffectiveVolumeToPlayer(
    PadItem padItem, {
    bool smooth = false,
  }) {
    final player = padItem.currentPlayer;
    if (player == null) return;

    final volume = _effectiveVolume(padItem);
    if (smooth) {
      player.fadeVolumeTo(volume, _musicVolumeSliderFadeDuration);
    } else {
      player.setVolume(volume);
    }
  }

  /// Volume global de la musique — n'affecte que les pads musique.
  ///
  /// [smooth] : fondu court via SoLoud (slider) ; instantané pour mute, etc.
  Future<void> setMusicVolume(double value, {bool smooth = false}) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_musicVolume == clamped) return;
    if (clamped > 0) {
      _musicVolumeBeforeMute = clamped;
    }
    _musicVolume = clamped;
    _applyMusicVolumeToPlayingPads(smooth: smooth);
    notifyListeners();
  }

  /// Coupe ou rétablit le volume musique global.
  Future<void> toggleMusicMute() async {
    if (_musicVolume > 0) {
      _musicVolumeBeforeMute = _musicVolume;
      await setMusicVolume(0);
      return;
    }
    await setMusicVolume(
      _musicVolumeBeforeMute > 0 ? _musicVolumeBeforeMute : 1.0,
    );
  }

  Future<void> stopAllSounds() async {
    _skipMusicAutoAdvance = true;
    try {
      for (final padItem in _state.pads) {
        if (padItem.isPlaying) {
          await padItem.currentPlayer?.stop();
          padItem.isPlaying = false;
          padItem._currentPlayerIndex = null;
        }
      }
    } finally {
      _skipMusicAutoAdvance = false;
    }
    _clearMusicState();
    notifyListeners();
  }

  Future<void> reorderSoundsFromList(List<PadItem> newOrder) async {
    if (_activeBoardId == null) return;
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

  /// Retire un pad de la board.
  Future<bool> removeSound(PadItem padItem) async {
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

    _state = _state.copyWith(
      pads: _state.pads.where((p) => p != padItem).toList(),
      error: null,
    );
    _syncMusicStateWithPads();
    notifyListeners();
    return true;
  }

  /// Annule la dernière suppression de pad.
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

      // Retourner l'id du pad restauré (le nouvel id après recréation)
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

  /// Met à jour le pad en mémoire dès qu'un son est ajouté ou retiré, sans
  /// attendre un rechargement complet du plateau (évite le délai perceptible
  /// sur la grille pendant le chargement des lecteurs audio).
  void _applySoundAddedToPad(PadItem padItem, Sound sound) {
    if (padItem.pad.sounds.any((s) => s.id == sound.id)) return;
    padItem.pad = padItem.pad.copyWith(
      sounds: [...padItem.pad.sounds, sound],
    );
    padItem.syncSlotCount();
    _finalizePadAvailability(padItem);
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
    _notifyPad(padItem);
    notifyListeners();
  }

  /// Charge les lecteurs du pad en arrière-plan après un changement de liste.
  Future<void> _reloadPadPlayersInBackground(PadItem padItem) async {
    await _loadPlayersForPadSafe(padItem, padItem.pad);
    notifyListeners();
  }

  /// Ajoute un son à un pad existant et recharge.
  Future<void> addSoundToPad(int padId, int soundId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;

    await _repository.addSoundToPad(padId, soundId);

    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return;

    _applySoundAddedToPad(padItem, sound);
    final slotIndex = padItem.pad.sounds.length - 1;
    unawaited(_reloadPadPlayersInBackground(padItem));
    _maybeAutoDownloadPadSound(padItem, slotIndex);
  }

  void _maybeAutoDownloadPadSound(PadItem padItem, int slotIndex) {
    if (_appPreferences?.autoDownloadPadSounds != true) return;
    if (_libraryRepository == null) return;
    if (slotIndex < 0 || slotIndex >= padItem.slots.length) return;
    final slot = padItem.slots[slotIndex];
    if (slot.isReady || slot.availability == PadSoundAvailability.missingFile) {
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

  /// Retire un son d'un pad. Si c'est le dernier son, supprime le pad.
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
    _downloadQueue.dispose();
    _previewPlayer?.dispose();
    _previewPlayer = null;
    for (final padItem in _state.pads) {
      padItem.dispose();
    }
    for (final padItem in _offStageMusicPads.values) {
      padItem.dispose();
    }
    super.dispose();
  }

  // ── Sons (bibliothèque) ───────────────────────────────────────────────────

  Future<List<Sound>> getAllSounds() async {
    return await _repository.getAllSounds();
  }

  /// Recherche les ids de sons par requête de tags (normalisée, sans accents).
  Future<Set<int>> findSoundIdsByTagQuery(String query) {
    return _repository.findSoundIdsByTagQuery(query);
  }

  /// Ids des sons jouables immédiatement en local (cache présent ou fichier
  /// legacy existant), pour le filtre « disponible hors-ligne » de la recherche.
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
      // downloadIfNeeded:false → lève si non disponible localement.
      await _resolvePlayablePath(sound, downloadIfNeeded: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Joue immédiatement un son par id sur le lecteur de pré-écoute, sans toucher
  /// au plateau ni à la file musique (recherche-éclair). Télécharge à la demande.
  /// Retourne false si le son est introuvable ou indisponible.
  Future<bool> previewSound(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    try {
      final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
      await stopPreview();
      final player = await AudioPlayerService.create(path);
      _previewPlayer = player;
      await player.play();
      _markPlayed(soundId);
      return true;
    } catch (e) {
      debugPrint('Pré-écoute échouée pour ${sound.title}: $e');
      return false;
    }
  }

  /// Coupe la pré-écoute en cours (fermeture de la recherche, nouveau son…).
  Future<void> stopPreview() async {
    final player = _previewPlayer;
    _previewPlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      player.dispose();
    } catch (_) {}
  }

  /// Ajoute un son au plateau actif comme nouveau pad (recherche-éclair) et
  /// recharge. Retourne l'id du pad créé, ou null si aucun plateau actif.
  Future<int?> addSoundToActiveBoard(int soundId) async {
    final boardId = _activeBoardId;
    if (boardId == null) return null;
    final padId = await _repository.createPad(boardId, soundId);
    await loadSounds(boardId: boardId);
    final padItem = _resolvePadItem(padId);
    if (padItem != null) _maybeAutoDownloadPadSound(padItem, 0);
    return padId;
  }

  /// Crée un pad avec les sons donnés sur le plateau actif et recharge.
  /// Retourne le [PadItem] résolu, ou null si aucun plateau actif.
  Future<PadItem?> createPadWithSoundsOnActiveBoard(
    List<int> soundIds,
  ) async {
    if (soundIds.isEmpty) return null;
    final boardId = _activeBoardId;
    if (boardId == null) return null;
    final padId = await _repository.createPadWithSettings(
      boardId: boardId,
      soundIds: soundIds,
    );
    await loadSounds(boardId: boardId);
    final padItem = _resolvePadItem(padId);
    if (padItem != null) _maybeAutoDownloadPad(padItem);
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
