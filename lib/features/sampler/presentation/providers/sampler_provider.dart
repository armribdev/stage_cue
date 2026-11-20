import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/autotag/auto_tag_analysis.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/audio/audio_load_log.dart';
import '../../../../core/logging/app_log.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/cue_audio_service.dart';
import '../../../../core/audio/preview_playback.dart';
import '../../../../core/audio/audio_file_validation.dart';
import '../../../../core/audio/local_sound_probe.dart';
import '../../../../core/audio/loudness_analyzer.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/sync/download_queue.dart';
import '../../../../core/sync/sync_log.dart';
import '../../../../core/utils/title_tag_matcher.dart';
import '../../data/repositories/library_repository.dart'
    show
        LibraryRepository,
        LibraryRepositoryDriveSession,
        LibraryRepositoryLibraries,
        LibraryRepositoryPlayback,
        LibraryRepositorySoundDeletion,
        SoundNotAvailableLocallyException;
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/library.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/saved_multipad.dart';
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
part 'music_fades.dart';
part 'music_offstage_pads.dart';
part 'music_availability.dart';
part 'ambiance_controller.dart';
part 'sampler_pad_availability.dart';
part 'sampler_pad_audio_engine.dart';
part 'sampler_previews_and_session.dart';
part 'sampler_pad_downloads.dart';
part 'sampler_pad_editing.dart';
part 'sampler_library_queries.dart';
part 'sampler_waveform_volume.dart';
part 'sampler_boards.dart';
part 'sampler_pad_playback.dart';

class SamplerNotifier extends ChangeNotifier {
  final SoundRepository _repository;
  final LoadSoundsUseCase _loadPadsUseCase;
  final RemoveSoundFromBoardUseCase? _removePadUseCase;

  /// Optionnel : résout le chemin local jouable d'un son de bibliothèque Drive
  /// (download/cache à la demande). Null = sons purement locaux.
  final LibraryRepository? _libraryRepository;

  final AppPreferences? _appPreferences;

  /// État et déclenchement de l'analyse automatique des tags, pour la fiche d'un
  /// son. Posé après construction (comme les callbacks de `AutoSyncCoordinator`) ;
  /// `null` = fonction absente (mobile, tests).
  AutoTagAnalysis? autoTagAnalysis;

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

  /// Début de la session live courante, pour la durée journalisée à la sortie.
  DateTime? _liveSessionStartedAt;

  /// Quand vrai, un slot `availability == ready` compte comme éligible même
  /// sans `AudioPlayerService` natif — permet d'exercer [_pickSoundIndex]
  /// (live / random / sequential) en test unitaire.
  @visibleForTesting
  bool debugTreatReadyAvailabilityAsEligible = false;

  /// Pads de bruitage hors-scène (id négatif) lancés depuis la recherche-éclair
  /// sans pad sur le plateau (voir `playSoundFromQuickSearch`). Ce sont de vraies
  /// lectures : le bouton « Tout arrêter » les coupe, contrairement à l'aperçu.
  final Map<int, PadItem> _offStageSfxPads = {};

  /// Tour de rôle des multipads enregistrés joués depuis la recherche-éclair
  /// (modèle → sons déjà tirés pour l'aléatoire sans répétition, modèle →
  /// dernier son joué pour le séquentiel). Mémoire de session : un modèle n'a
  /// pas de pad, donc pas de `PadItem` pour porter ce curseur.
  final Map<int, Set<int>> _savedMultipadPlayedIds = {};
  final Map<int, int> _savedMultipadLastSoundId = {};

  /// Lecteur d'aperçu unique (play/pause, un son à la fois), indépendant des
  /// pads, de la régie et du bouton « Tout arrêter » : il ne se pilote que par
  /// ses propres boutons (voir `toggleLibraryPreview`).
  PreviewPlayback? _libraryPreviewPlayer;
  int? _libraryPreviewSoundId;
  StreamSubscription<bool>? _libraryPreviewSub;

  /// Dernier refus de pré-écoute au casque ([CueUnavailableException]), à
  /// afficher une fois à l'utilisateur. Hors `copyWith` comme les autres
  /// drapeaux de session : pur message éphémère, pas un état rendu.
  String? _lastPreviewError;

  /// File de téléchargement priorisée à concurrence bornée (refonte UX P2).
  final DownloadQueue _downloadQueue = DownloadQueue(
    maxConcurrent: 2,
    onDrained: (summary) => SyncLog.downloadQueueDrained(
      succeeded: summary.succeeded,
      failed: summary.failed,
      cancelled: summary.cancelled,
      elapsed: summary.elapsed,
    ),
  );

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
  late final SoundSearchIndex _searchIndex = SoundSearchIndex(
    _repository,
    _libraryRepository,
  );

  SamplerState _state = SamplerState(pads: []);
  SamplerState get state => _state;

  /// Téléchargements à la demande permis : réseau autorisé (Paramètres) **et**
  /// hors Mode Spectacle — en scène, un fichier absent du cache n'est jamais
  /// tiré de Drive au déclenchement (0037).
  bool get allowsSoundDownload =>
      !_isLiveSessionActive && (_appPreferences?.allowsSoundDownload ?? true);

  /// Session Google révoquée/expirée : un OAuth interactif est requis. Permet à
  /// l'UI de distinguer un échec « token mort » d'un simple « hors-ligne » quand
  /// une lecture/aperçu échoue, et de proposer une reconnexion plutôt que
  /// « vérifiez la connexion ».
  bool get driveSessionExpired =>
      _libraryRepository?.requiresInteractiveReconnect ?? false;

  double get musicVolume => _music.musicVolume;
  double get ambianceVolume => _ambiance.ambianceVolume;
  AmbianceTransition? get ambianceTransition => _ambiance.transition;

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

  /// Volume (0–1) envoyé au lecteur d'un pad : celui de sa voie pour la musique
  /// et l'ambiance, 1.0 sinon (le gain du son s'applique dans le lecteur).
  double _busVolume(PadItem padItem) => _music._busVolume(padItem);

  /// Pad affiché sur le plateau en Mode Spectacle (au moins un son local).
  bool isPadVisibleInLiveSession(PadItem padItem) {
    if (padItem.isDraft) return true;
    return padItem.hasLocallyAvailableSound;
  }

  Iterable<PadItem> _padsForMultipadNumbering() {
    return _state.pads.where(
      (item) =>
          !item.isDraft &&
          (!_isLiveSessionActive || item.hasLocallyAvailableSound),
    );
  }

  /// Le réglage réseau a changé : plus de téléchargement permis, la file
  /// déjà en attente n'a plus lieu d'être.
  void _onConnectivityModeChanged() {
    if (!allowsSoundDownload) _downloadQueue.cancelQueued((_, _) => true);
    notifyListeners();
  }

  /// Entrée en Mode Spectacle : retire de la scène ce qui n'est plus jouable
  /// (musique, ambiance et file dont le pad n'a aucun son en cache).
  Future<void> _applyLiveSessionConstraints() async {
    final current = _state.currentMusicPad;
    if (current != null && !isPadVisibleInLiveSession(current)) {
      await _music._stopMusicPad(current, manual: true);
    }
    final visibleIds = _padsForMultipadNumbering()
        .map((item) => item.pad.id)
        .toSet();
    final ambiance = _state.currentAmbiancePad;
    if (ambiance != null && !isPadVisibleInLiveSession(ambiance)) {
      await _ambiance._stopImmediately();
    }
    final newQueue = _state.musicQueuePadIds
        .where(visibleIds.contains)
        .toList();
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
    // Gain du son (décision 0045) : appliqué à la frontière de lecture, donc
    // posé sur le lecteur — à la création du slot comme après un « Enregistrer »
    // de la fiche. Une voix déjà lancée ne bouge pas avant son prochain volume.
    if (index < padItem.slots.length) {
      padItem.slots[index].player?.setGain(updated.gain);
    }
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
        final existing =
            previousItemsById[pad.id] ??
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
            existing.currentPlayer?.setVolume(_busVolume(existing));
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
        padItems
            .where((item) => !item.isDraft)
            .map(
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
          .where(
            (item) =>
                !keptIds.contains(item.pad.id) && !_isKeptOffStage(item.pad.id),
          )
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
  Future<void> fadeOutCurrentMusic(Duration d) => _music.fadeOutCurrentMusic(d);
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
  }) => _ambiance.stopCurrentAmbiance(fade: fade);
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
      AudioLoadLog.warn(
        'Impossible de préparer le son ${sound.id} pour la régie : $e',
      );
      return null;
    }
  }

  @override
  void dispose() {
    _appPreferences?.removeListener(_onConnectivityModeChanged);
    _downloadQueue.dispose();
    stopLibraryPreview(notify: false);
    for (final padItem in _state.pads) {
      padItem.dispose();
    }
    for (final padItem in _offStageSfxPads.values) {
      padItem.dispose();
    }
    _offStageSfxPads.clear();
    _music._disposeOffStagePads();
    _ambiance._disposeOffStagePads();
    super.dispose();
  }
}
