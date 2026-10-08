import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/cue_audio_service.dart';
import '../../../../core/audio/preview_playback.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/local_sound_probe.dart';
import '../../../../core/audio/loudness_analyzer.dart';
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
import 'sound_search_index.dart';

part 'sampler_state.dart';
part 'music_controller.dart';
part 'ambiance_controller.dart';
part 'sampler_pad_availability.dart';
part 'sampler_pad_audio_engine.dart';
part 'sampler_previews_and_session.dart';
part 'sampler_pad_downloads.dart';
part 'sampler_pad_editing.dart';
part 'sampler_library_queries.dart';

/// Provider/Notifier pour la gestion de l'état du sampler
class SamplerNotifier extends ChangeNotifier {
  final SoundRepository _repository;
  final LoadSoundsUseCase _loadPadsUseCase;
  final RemoveSoundFromBoardUseCase? _removePadUseCase;

  /// Optionnel : résout le chemin local jouable d'un son de bibliothèque Drive
  /// (download/cache à la demande). Null = sons purement locaux.
  final LibraryRepository? _libraryRepository;

  final AppPreferences? _appPreferences;

  int? _activeBoardIdValue;

  int? get _activeBoardId => _activeBoardIdValue;

  /// Propage le plateau actif au cache audio, qui épingle ses sons contre
  /// l'éviction LRU. Sans ça, une passe de téléchargement massif rebat la
  /// récence et peut supprimer sous les pieds du régisseur des sons du plateau
  /// qu'il est en train de jouer (ils ne sont protégés que s'ils sont favoris).
  set _activeBoardId(int? value) {
    _activeBoardIdValue = value;
    _libraryRepository?.activeBoardId = value;
  }
  _RemovedPadSnapshot? _lastRemovedPad;

  /// Réinitialisé à chaque entrée en mode live (Mode Spectacle) : force le
  /// tout premier pad ajouté via la recherche-éclair sur une nouvelle ligne
  /// plutôt qu'à la suite de la dernière ligne déjà en place sur scène.
  bool _forceNewRowOnNextQuickAdd = false;
  int _draftPadIdSeq = -1;
  final _random = Random();

  /// Session live (Mode Spectacle) en cours : tant qu'elle est active, chaque
  /// lecture réelle (hors pré-écoute) incrémente [_sessionPlayCounts], et le
  /// choix automatique d'un multipad favorise les sons les moins joués de la
  /// session plutôt que l'algorithme habituel (aléatoire sans répétition ou
  /// séquentiel) — voir décision 0014.
  bool _isLiveSessionActive = false;

  /// Compteur de lectures réelles par son (soundId → nombre de lectures) pour
  /// la durée de la session live courante. Gelé (non remis à zéro) à la
  /// sortie du Mode Spectacle ; remis à zéro seulement à la prochaine entrée.
  final Map<int, int> _sessionPlayCounts = {};

  /// Quand vrai, un slot `availability == ready` compte comme éligible même
  /// sans `AudioPlayerService` natif — permet d'exercer [_pickSoundIndex]
  /// (live / random / sequential) en test unitaire.
  @visibleForTesting
  bool debugTreatReadyAvailabilityAsEligible = false;

  /// Lecteurs dédiés à la pré-écoute (recherche-éclair) : indépendants des pads,
  /// du master musique et de la file. Plusieurs bruitages/ambiances peuvent
  /// jouer simultanément ; chacun se libère seul à la fin de sa lecture.
  final Set<PreviewPlayback> _previewPlayers = {};

  /// Lecteur unique pour l'aperçu bibliothèque (play/pause, un son à la fois).
  PreviewPlayback? _libraryPreviewPlayer;
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

  /// Contrôleur ambiance : une ambiance en boucle à la fois, volume de voie.
  late final AmbianceController _ambiance;

  /// Index mémoire de la bibliothèque pour le sélecteur de sons : ouvrir la
  /// recherche en spectacle ne doit pas attendre la base ni le disque.
  late final SoundSearchIndex _searchIndex =
      SoundSearchIndex(_repository, _libraryRepository);

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;
  bool get offlineMode => isLiveOfflineMode;
  bool get isLiveOfflineMode =>
      _appPreferences?.isLiveOfflineMode ?? false;
  bool get allowsSoundDownload =>
      _appPreferences?.allowsSoundDownload ?? true;

  /// Session Google révoquée/expirée : un OAuth interactif est requis. Permet à
  /// l'UI de distinguer un échec « token mort » d'un simple « hors-ligne » quand
  /// une lecture/aperçu échoue, et de proposer une reconnexion plutôt que
  /// « vérifiez la connexion ».
  bool get driveSessionExpired =>
      _libraryRepository?.requiresInteractiveReconnect ?? false;

  double get musicVolume => _music.musicVolume;
  double get ambianceVolume => _ambiance.ambianceVolume;

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
    _ambiance = AmbianceController(this);
    appPreferences?.addListener(_onConnectivityModeChanged);
  }

  /// Wrapper non-protected sur [notifyListeners] — permet à [MusicController]
  /// (même bibliothèque) d'émettre des notifications sans déclencher un warning
  /// sur l'annotation @protected de ChangeNotifier.
  void _notify() => notifyListeners();

  /// Volume effectif du son à [soundIndex] dans un pad (override du pad-son ou
  /// volume par défaut du son) ; pads musique et ambiance soumis au volume
  /// de leur voie.
  double _effectiveVolume(PadItem padItem, {int? soundIndex}) =>
      _music._effectiveVolume(padItem, soundIndex: soundIndex);

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
    final ambiance = _state.currentAmbiancePad;
    if (ambiance != null && !isPadVisibleInOfflineMode(ambiance)) {
      await _ambiance._stopImmediately();
    }
    final newQueue =
        _state.musicQueuePadIds.where(visibleIds.contains).toList();
    if (newQueue.length != _state.musicQueuePadIds.length) {
      _state = _state.copyWith(musicQueuePadIds: newQueue);
    }
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

  /// Calcule et persiste l'enveloppe waveform d'un son (tout type) dont le
  /// fichier vient d'être chargé, si elle manque encore. Réinjecte ensuite le
  /// son (avec sa waveform) dans le pad en mémoire et notifie — la régie
  /// l'affiche dès qu'elle est prête, sans bloquer le démarrage de la lecture.
  Future<void> _ensureWaveformForSound(
    PadItem padItem,
    int index,
    String filePath,
  ) async {
    if (index < 0 || index >= padItem.pad.sounds.length) return;
    final sound = padItem.pad.sounds[index];
    if (sound.waveform != null) return;
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

  /// Force une nouvelle extraction de l'enveloppe waveform d'un son, même si
  /// une enveloppe existe déjà — contrairement à [_ensureWaveformForSound],
  /// paresseux et gaté sur `waveform == null`. Action explicite demandée par
  /// l'opérateur depuis l'écran d'édition d'un son : télécharge le fichier si
  /// nécessaire (bibliothèque Drive non encore mise en cache).
  ///
  /// Peut lever [SoundNotAvailableLocallyException] ou [StateError] si le
  /// fichier est introuvable/hors ligne — laissé à l'appelant pour affichage.
  Future<WaveformProbeStatus> regenerateWaveform(Sound sound) async {
    final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
    final probe = await extractWaveform(path);
    if (probe.status != WaveformProbeStatus.transient) {
      await _repository.persistWaveformProbe(sound.id, probe);
    }
    return probe.status;
  }

  /// Volume « auto » d'un son : mesure sa sonie et renvoie le volume qui la
  /// ramène à la sonie cible (normalisation). Ne persiste rien — l'appelant
  /// applique la valeur au formulaire, enregistrée au « Enregistrer » habituel.
  /// `null` si le fichier ne peut pas être mesuré (moteur non prêt, format non
  /// décodable, audio silencieux).
  ///
  /// Même contrat d'erreur que [regenerateWaveform] (fichier hors ligne).
  Future<double?> computeAutoVolume(Sound sound) async {
    final path = await _resolvePlayablePath(sound, downloadIfNeeded: true);
    final rms = await measureRms(path);
    return rms == null ? null : autoVolumeForRms(rms);
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
        // Plateau vide : ne pas créer de « Scène 1 » par défaut tant que le pull
        // de lancement peut encore fusionner des boards distants. Sinon une
        // lecture transitoirement vide (race avec la synchro de démarrage) crée
        // une scène fantôme qui pollue les vrais boards. On laisse le skeleton
        // affiché (isBoardsLoading reste true) : la fin du pull relance
        // `loadBoards` (via onInitialPullSettled/onLibraryMerged). Exception :
        // aucune bibliothèque connectée → usage local, rien à attendre.
        final settled = _libraryRepository?.initialSyncSettled ?? true;
        if (!settled && (await getConnectedLibraries()).isNotEmpty) {
          return; // en attente de la fin du pull, skeleton conservé
        }
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

    // Tapis sonore : la musique en cours survit au changement de scène et reste
    // pilotable depuis la régie. On ne coupe que les bruitages (SFX) et les
    // pré-écoutes ; le pad musique qui joue est détaché hors-scène pour ne pas
    // être disposé par le rechargement du plateau.
    await stopAllNonMusicSounds();
    _music._detachPlayingMusicToOffStage();
    _ambiance._detachPlayingToOffStage();
    // Annule les téléchargements encore EN FILE des pads qui quittent la scène
    // (bande passante Drive inutile pour un plateau qu'on abandonne). Les tâches
    // déjà démarrées finissent en cache ; le pad musique détaché hors-scène
    // (tapis sonore) est exclu pour poursuivre son éventuel téléchargement.
    final leavingPadIds = _state.pads
        .map((item) => item.pad.id)
        .where((id) => !_isKeptOffStage(id))
        .toSet();
    _downloadQueue.cancelQueued((key, _) => leavingPadIds.contains(key));
    _lastRemovedPad = null;
    _music.cleanupOffStagePads();
    _ambiance.cleanupOffStagePads();
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
      // Ne conserver que les drafts du plateau courant : un draft porte le
      // boardId sur lequel il a été ouvert (voir beginDraftPad). Ceux d'un autre
      // plateau ne sont pas ré-ajoutés ici, donc absents de keptIds → disposés
      // via removedItems (évite qu'un draft « traverse » vers une autre scène).
      final draftPads = previousItems
          .where((item) => item.isDraft && item.pad.boardId == currentBoardId)
          .toList(growable: false);

      for (final pad in pads) {
        // Ré-adopte un pad musique/ambiance détaché hors-scène (tapis sonore)
        // si l'on revient sur son plateau d'origine : évite un second lecteur
        // pour un son déjà en cours de lecture.
        final existing = previousItemsById[pad.id] ??
            _music._reclaimOffStagePad(pad.id) ??
            _ambiance._reclaimOffStagePad(pad.id);
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
      // Ne pas disposer un pad musique/ambiance conservé hors-scène : il
      // continue de jouer en tapis sonore et reste piloté par la régie.
      final removedItems = previousItems
          .where((item) =>
              !keptIds.contains(item.pad.id) &&
              !_isKeptOffStage(item.pad.id))
          .toList();
      _disposePadItems(removedItems);
      _syncVoicesWithPads();

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
    unawaited(_prewarmSearchIndex());
  }

  Future<void> refreshPadPlayback(int padId) async {
    final padItem = findPadItemById(padId);
    if (padItem == null) return;
    await _loadPlayersForPad(padItem, padItem.pad);
    notifyListeners();
  }

  Future<void> toggleSound(PadItem padItem) async {
    final resolved = _resolveBoardPadItem(padItem);
    AudioLoadLog.trace(
      '[TOGGLE] pad="${resolved.pad.displayName}" id=${resolved.pad.id} '
      'isPlayable=${resolved.isPlayable} isPlaying=${resolved.isPlaying} '
      'isMusicPad=${resolved.pad.isMusicPad} '
      'slots=${resolved.slots.length} readySlots=${resolved.slots.where((s) => s.isReady).length} '
      '_currentPlayerIndex=${resolved._currentPlayerIndex}',
    );
    if (!resolved.isPlayable) {
      AudioLoadLog.trace('[TOGGLE] ↩ not playable, ignoring');
      return;
    }
    if (resolved.pad.isMusicPad) {
      await _music._toggleMusicPad(resolved);
      return;
    }
    if (resolved.pad.isAmbiancePad) {
      await _ambiance._toggleAmbiancePad(resolved);
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
    if (resolved.pad.isAmbiancePad) {
      await _ambiance.playAmbianceNow(resolved, soundIndex: soundIndex);
      return;
    }

    await _playOverlappingSoundAtIndex(resolved, soundIndex);
  }

  Future<void> _playOverlappingSoundAtIndex(
    PadItem resolved,
    int soundIndex,
  ) async {
    final player = resolved.slots[soundIndex].player;
    AudioLoadLog.trace(
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
      volume: _effectiveVolume(resolved, soundIndex: soundIndex),
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
    if (resolved.pad.isAmbiancePad) {
      await _ambiance._stopPadPlayers(resolved);
      notifyListeners();
      return;
    }
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

  /// Coupe tous les bruitages en cours (bouton panique « Tout arrêter »).
  /// Laisse jouer musique et ambiance : utile en live pour tuer un bruitage
  /// sans casser le tapis sonore.
  Future<void> stopAllNonMusicSounds() async {
    var changed = false;
    for (final padItem in _state.pads) {
      if (padItem.pad.isExclusiveVoicePad) continue;
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

  /// Au moins un bruitage (ni musique ni ambiance) joue actuellement, ou une
  /// pré-écoute (recherche rapide / bibliothèque) est en cours.
  bool get hasNonMusicSoundsPlaying =>
      _state.pads.any((p) => !p.pad.isExclusiveVoicePad && p.isPlaying) ||
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
    // Patch de l'index plutôt qu'invalidation : en spectacle chaque
    // déclenchement passe ici, et reconstruire l'index à chaque son ferait
    // repartir la recherche sur la base au pire moment. Seul le tri par
    // récence dépend de ce champ.
    final playedAt = DateTime.now();
    _searchIndex.patchSound(
      soundId,
      (sound) => sound.copyWith(lastPlayedAt: playedAt),
    );
  }

  void _markPlayedAt(PadItem padItem, int soundIndex) {
    if (soundIndex < 0 || soundIndex >= padItem.pad.sounds.length) return;
    final soundId = padItem.pad.sounds[soundIndex].id;
    _markPlayed(soundId);
    if (_isLiveSessionActive) {
      _sessionPlayCounts[soundId] = (_sessionPlayCounts[soundId] ?? 0) + 1;
    }
  }

  Future<void> updateSoundType(int soundId, SoundType type) async {
    await _repository.updateSoundType(soundId, type);
    _searchIndex.patchSound(soundId, (sound) => sound.copyWith(type: type));
    await _ambiance.refreshOffStageSoundMetadata(soundId);
    await _music.refreshSoundMetadata(soundId);
  }

  Future<bool> toggleSoundFavorite(int soundId) async {
    final sound = await _repository.getSoundById(soundId);
    if (sound == null) return false;
    final next = !sound.isFavorite;
    await _repository.setSoundFavorite(soundId, next);
    _searchIndex.patchSound(soundId, (s) => s.copyWith(isFavorite: next));
    return next;
  }

  void _notifyPad(PadItem padItem) => padItem.bumpRevision();

  void _notifyPadAndBoard(PadItem padItem) {
    _notifyPad(padItem);
    notifyListeners();
  }
  bool _slotEligibleForPlayback(PadItem padItem, int index) {
    final slot = padItem.slots[index];
    final ready = slot.isReady ||
        (debugTreatReadyAvailabilityAsEligible &&
            slot.availability == PadSoundAvailability.ready);
    if (!ready) return false;
    if (isLiveOfflineMode && !slot.appearsReady) return false;
    return true;
  }

  int _pickSoundIndex(PadItem padItem) {
    final readyIndices = <int>[
      for (var i = 0; i < padItem.slots.length; i++)
        if (_slotEligibleForPlayback(padItem, i)) i,
    ];
    AudioLoadLog.trace(
      '[PICK] pad="${padItem.pad.displayName}" '
      'slots=${padItem.slots.length} readyIndices=$readyIndices '
      '_nextSoundIndex=${padItem._nextSoundIndex} '
      'playedIndices=${padItem._playedSoundIndices} '
      'playMode=${padItem.pad.playMode}',
    );
    if (readyIndices.isEmpty) return 0;
    if (readyIndices.length == 1) return readyIndices.first;

    if (_isLiveSessionActive) {
      final chosen = _pickLowestSessionCountIndex(padItem, readyIndices);
      AudioLoadLog.trace('[PICK] → chosen(live)=$chosen');
      return chosen;
    }

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
    AudioLoadLog.trace('[PICK] → chosen=$chosen _nextSoundIndex(after)=${padItem._nextSoundIndex}');
    return chosen;
  }

  /// Mode live : ignore `playMode`, pioche parmi les sons du multipad au
  /// compte de lecture de session le plus bas (égalité → tirage aléatoire
  /// parmi les ex-æquo). Ne mute volontairement PAS `_playedSoundIndices`/
  /// `_nextSoundIndex` : l'algorithme habituel doit reprendre sainement une
  /// fois la session terminée (voir décision 0014).
  int _pickLowestSessionCountIndex(PadItem padItem, List<int> readyIndices) {
    var minCount = 1 << 31;
    for (final i in readyIndices) {
      final count = sessionPlayCountFor(padItem.pad.sounds[i].id);
      if (count < minCount) minCount = count;
    }
    final lowest = [
      for (final i in readyIndices)
        if (sessionPlayCountFor(padItem.pad.sounds[i].id) == minCount) i,
    ];
    return lowest[_random.nextInt(lowest.length)];
  }

  // ── Délégués musique (API publique) ───────────────────────────────────────

  bool get hasPendingMusicPlaybackError => _music.hasPendingPlaybackError;
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

  Future<PadItem?> playAmbianceBySoundId(int id) =>
      _ambiance.playAmbianceBySoundId(id);
  Future<void> stopCurrentAmbiance({
    Duration fade = AmbianceController.stopFadeDuration,
  }) =>
      _ambiance.stopCurrentAmbiance(fade: fade);
  PadItem? resolveAmbiancePad(int id) => _ambiance.resolveAmbiancePad(id);
  Future<void> setAmbianceVolume(double v, {bool smooth = false}) =>
      _ambiance.setAmbianceVolume(v, smooth: smooth);
  Future<void> toggleAmbianceMute() => _ambiance.toggleAmbianceMute();

  /// Pad conservé hors-scène par la régie (musique ou ambiance) : ne pas le
  /// disposer au rechargement du plateau.
  bool _isKeptOffStage(int padId) =>
      _music._isKeptOffStage(padId) || _ambiance._isKeptOffStage(padId);

  /// Réaligne musique et ambiance à l'antenne sur les pads du plateau.
  void _syncVoicesWithPads() {
    _music._syncMusicStateWithPads();
    _ambiance._syncStateWithPads();
  }

  /// Crée un pad éphémère hors-scène (id négatif) pour un son lancé depuis la
  /// régie sans pad sur le plateau, et précharge ses lecteurs.
  Future<PadItem?> _buildOffStagePad(Sound sound) async {
    try {
      final pad = Pad(
        id: -sound.id,
        boardId: -1,
        sortOrder: 0,
        createdAt: DateTime.now(),
        sounds: [sound],
      );
      final padItem = PadItem(pad: pad);
      // Sonde le cache local d'abord (comme les pads du plateau) : sinon, en
      // mode live hors-ligne, `_loadPlayersForPad` saute un slot dont
      // `appearsReady` est faux, même si le fichier est déjà en cache.
      await _probePadLocalAvailability(padItem);
      await _loadPlayersForPad(padItem, pad);
      return padItem;
    } catch (e) {
      debugPrint('Impossible de préparer le son ${sound.id} pour la régie: $e');
      return null;
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
    _ambiance._disposeOffStagePads();
    super.dispose();
  }

}
