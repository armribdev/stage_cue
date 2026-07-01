part of 'sampler_provider.dart';

/// Raison pour laquelle un pad ne peut pas être joué.
enum PadUnavailabilityReason {
  /// Sons présents en DB mais fichiers non encore téléchargés (connexion disponible).
  needsDownload,
  /// Appareil hors-ligne et fichiers absents du cache local.
  offline,
  /// Fichier local introuvable (supprimé ou déplacé).
  missingFile,
  /// Fichier présent mais format non décodable par SoLoud sur cette plateforme.
  unsupportedFormat,
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
  /// Masque les pads sans son local et n'autorise que la lecture hors-ligne.
  final bool offlineMode;

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
    this.offlineMode = false,
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
    bool? offlineMode,
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
      offlineMode: offlineMode ?? this.offlineMode,
    );
  }
}

/// Voix non-musique en cours, pour l'affichage des barres de progression
/// superposées : chaque déclenchement empile un ticket (id unique, durée du son,
/// instant de départ) qui pilote une barre indépendante jusqu'à sa fin.
class PadPlaybackTicket {
  final int id;
  final Duration duration;
  final DateTime startedAt;

  const PadPlaybackTicket({
    required this.id,
    required this.duration,
    required this.startedAt,
  });
}

/// Item de pad — un [PadSoundSlot] par son, index aligné sur [Pad.sounds].
class PadItem {
  Pad pad;
  /// Numéro du multipad sur le plateau (1-based), null si pad simple.
  int? multipadNumber;
  final List<PadSoundSlot> slots;
  bool isPlaying;
  int _nextSoundIndex;
  /// Indices déjà joués en mode aléatoire pendant la session courante du pad.
  final Set<int> _playedSoundIndices = {};
  int? _currentPlayerIndex;
  int? pausedPlayerIndex;
  Duration? pausedPlaybackPosition;

  /// Voix non-musique actuellement affichées (barres superposées). Chaque ticket
  /// a un timer d'auto-suppression aligné sur la durée du son.
  final List<PadPlaybackTicket> playbackTickets = [];
  final Map<int, Timer> _ticketTimers = {};
  int _ticketSeq = 0;
  PadUnavailabilityReason? unavailabilityReason;
  bool isDownloading = false;
  int downloadDone = 0;
  int downloadTotal = 0;
  /// Index du slot en cours de téléchargement (détail pad, variante unique).
  int? downloadingSlotIndex;

  /// Pad temporaire affiché pendant le choix des sons (id négatif, hors base).
  bool isDraft = false;

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

  /// Réinitialise le cycle aléatoire (tous les sons redeviennent éligibles).
  void resetRandomPlaySession() {
    _playedSoundIndices.clear();
  }

  String get displayName =>
      pad.resolveDisplayName(multipadNumber: multipadNumber);

  int get totalSoundCount => pad.sounds.length;

  int get readySoundCount => slots.where((s) => s.appearsReady).length;

  /// Au moins une variante a un fichier local validé (prêt ou en cache).
  bool get hasLocallyAvailableSound => slots.any((s) => s.appearsReady);

  bool get isPlayable => slots.any((s) => s.isReady);

  bool get appearsReady => slots.any((s) => s.appearsReady);

  bool get isFullyReady =>
      pad.sounds.isNotEmpty &&
      slots.every((s) => s.isReady || s.isCached);

  bool get isPartiallyReady => appearsReady && !isFullyReady;

  /// Pad musique mis en pause (position mémorisée, audio arrêté).
  bool get isPaused => !isPlaying && pausedPlaybackPosition != null;

  int get pendingDownloadCount => slots
      .where((s) => s.availability == PadSoundAvailability.needsDownload)
      .length;

  bool get hasMissingFileSlot => slots.any(
        (s) =>
            s.availability == PadSoundAvailability.missingFile ||
            s.availability == PadSoundAvailability.unsupportedFormat,
      );

  /// Pad visuellement bloqué (fichier introuvable / hors-ligne).
  bool get isBlockedForPlayback {
    if (isPlayable || appearsReady || isDownloading) return false;
    if (hasMissingFileSlot) return true;
    return switch (unavailabilityReason) {
      PadUnavailabilityReason.offline => true,
      PadUnavailabilityReason.missingFile => true,
      PadUnavailabilityReason.unsupportedFormat => true,
      _ => false,
    };
  }

  /// Éligible au bandeau « Préparer » (téléchargement encore possible).
  bool get isPreparableForDownload {
    if (isDraft || isFullyReady || isBlockedForPlayback) return false;
    return pendingDownloadCount > 0 ||
        unavailabilityReason == PadUnavailabilityReason.needsDownload;
  }

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
    clearPlaybackTickets();
    disposeAllSlots();
    _revision.dispose();
  }

  void clearPausedPlayback() {
    pausedPlayerIndex = null;
    pausedPlaybackPosition = null;
  }

  /// Enregistre une nouvelle voix (barre de progression) de [duration] et
  /// programme son auto-suppression. [onExpire] est appelé à la fin du son.
  int addPlaybackTicket(Duration duration, {required void Function() onExpire}) {
    final id = ++_ticketSeq;
    playbackTickets.add(
      PadPlaybackTicket(id: id, duration: duration, startedAt: DateTime.now()),
    );
    if (duration > Duration.zero) {
      _ticketTimers[id] = Timer(duration, () {
        _ticketTimers.remove(id);
        playbackTickets.removeWhere((t) => t.id == id);
        onExpire();
      });
    }
    return id;
  }

  /// Annule tous les tickets en cours (arrêt manuel du pad ou global).
  void clearPlaybackTickets() {
    for (final timer in _ticketTimers.values) {
      timer.cancel();
    }
    _ticketTimers.clear();
    playbackTickets.clear();
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
