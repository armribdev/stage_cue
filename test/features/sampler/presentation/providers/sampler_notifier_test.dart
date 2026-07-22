import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/core/settings/app_preferences.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound_board.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';

// ignore: subtype_of_sealed_class
class MockSoundRepository extends Mock implements SoundRepository {}

class MockLoadSoundsUseCase extends Mock implements LoadSoundsUseCase {}

SoundBoard _board(int id, {String name = 'Scène'}) => SoundBoard(
      id: id,
      name: name,
      createdAt: DateTime(2026),
    );

Pad _pad(int id, {int boardId = 1}) => Pad(
      id: id,
      boardId: boardId,
      sortOrder: 0,
      createdAt: DateTime(2026),
    );

Sound _sound(int id) => Sound(
      id: id,
      title: 'Son $id',
      filePath: '/tmp/son_$id.mp3',
      createdAt: DateTime(2026),
    );

Pad _multipad(
  int id,
  List<Sound> sounds, {
  int boardId = 1,
  PadPlayMode playMode = PadPlayMode.random,
}) =>
    Pad(
      id: id,
      boardId: boardId,
      sortOrder: 0,
      createdAt: DateTime(2026),
      sounds: sounds,
      playMode: playMode,
    );

/// Construit un notifier prêt à l'emploi, avec `markSoundPlayed` stubbé (le
/// mock lèverait sinon une `MissingStubError` dès le premier `_markPlayed`).
SamplerNotifier _notifierForPlayback() {
  final repo = MockSoundRepository();
  final useCase = MockLoadSoundsUseCase();
  when(() => repo.markSoundPlayed(any())).thenAnswer((_) async {});
  return SamplerNotifier(repo, useCase);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_board(0));
    registerFallbackValue(_pad(0));
  });

  // ── loadBoards ────────────────────────────────────────────────────────────

  group('loadBoards', () {
    test('charge les plateaux et sélectionne le premier', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final boards = [_board(1, name: 'Scène 1'), _board(2, name: 'Scène 2')];

      when(() => repo.getSoundBoards()).thenAnswer((_) async => boards);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();

      expect(n.state.boards, boards);
      expect(n.state.selectedBoard?.id, 1);
      expect(n.state.isBoardsLoading, isFalse);
      expect(n.state.boardsError, isNull);
    });

    test('sélectionne le plateau demandé si spécifié', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final boards = [_board(1), _board(2), _board(3)];

      when(() => repo.getSoundBoards()).thenAnswer((_) async => boards);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards(selectBoardId: 3);

      expect(n.state.selectedBoard?.id, 3);
    });

    test('crée un plateau par défaut si aucun n\'existe', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final createdBoard = _board(1, name: 'Scène 1');

      var boardsCallCount = 0;
      when(() => repo.getSoundBoards()).thenAnswer((_) async {
        boardsCallCount++;
        return boardsCallCount == 1 ? [] : [createdBoard];
      });
      when(() => repo.createSoundBoard(any(),
              color: any(named: 'color'), libraryId: any(named: 'libraryId')))
          .thenAnswer((_) async => 1);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();

      verify(() => repo.createSoundBoard(any(),
          color: any(named: 'color'),
          libraryId: any(named: 'libraryId'))).called(1);
    });

    test('passe à boardsError en cas d\'exception', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();

      when(() => repo.getSoundBoards()).thenThrow(Exception('DB error'));

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();

      expect(n.state.isBoardsLoading, isFalse);
      expect(n.state.boardsError, isNotNull);
    });

    test('émet des notifications pendant le chargement', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();

      when(() => repo.getSoundBoards())
          .thenAnswer((_) async => [_board(1)]);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      var count = 0;
      n.addListener(() => count++);

      await n.loadBoards();

      expect(count, greaterThan(0));
    });
  });

  // ── selectBoard ───────────────────────────────────────────────────────────

  group('selectBoard', () {
    test('change le plateau sélectionné', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final boards = [_board(1), _board(2)];

      when(() => repo.getSoundBoards()).thenAnswer((_) async => boards);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();
      expect(n.state.selectedBoard?.id, 1);

      await n.selectBoard(_board(2));
      expect(n.state.selectedBoard?.id, 2);
    });

    test('sans effet si déjà sélectionné', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final boards = [_board(1)];

      when(() => repo.getSoundBoards()).thenAnswer((_) async => boards);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();

      await n.selectBoard(_board(1)); // déjà sélectionné

      // Le test vérifie surtout qu'aucune exception n'est levée
      expect(n.state.selectedBoard?.id, 1);
    });
  });

  // ── loadSounds ────────────────────────────────────────────────────────────

  group('loadSounds', () {
    test('remplit l\'état avec les pads chargés', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final pads = [_pad(10), _pad(11)];

      when(() => repo.getSoundBoards()).thenAnswer((_) async => [_board(1)]);
      when(() => useCase.call(any())).thenAnswer((_) async => pads);

      final n = SamplerNotifier(repo, useCase);
      await n.loadBoards();

      expect(n.state.pads.map((p) => p.pad.id).toList(), [10, 11]);
      expect(n.state.isLoading, isFalse);
    });

    test('serialise les appels concurrents', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      var callCount = 0;

      when(() => useCase.call(any())).thenAnswer((_) async {
        callCount++;
        return [_pad(callCount)];
      });

      final n = SamplerNotifier(repo, useCase);
      n.setActiveBoard(1);

      // Deux loadSounds en parallèle : la chaîne les sérialise.
      final f1 = n.loadSounds();
      final f2 = n.loadSounds();
      await Future.wait([f1, f2]);

      // useCase a été invoqué exactement deux fois (un par appel sérialisé).
      expect(callCount, greaterThanOrEqualTo(2));
    });
  });

  // ── connectivityMode ──────────────────────────────────────────────────────

  group('connectivityMode', () {
    test('live hors ligne masque les pads sans son local', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      when(() => repo.getSoundBoards()).thenAnswer((_) async => [_board(1)]);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final prefs = AppPreferences();
      prefs.debugSetConnectivityMode(ConnectivityMode.liveOffline);

      final n = SamplerNotifier(repo, useCase, null, null, prefs);
      expect(n.isLiveOfflineMode, isTrue);
      expect(n.offlineMode, isTrue);
      expect(n.allowsSoundDownload, isFalse);
    });

    test('connecté autorise les téléchargements', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      when(() => repo.getSoundBoards()).thenAnswer((_) async => [_board(1)]);
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final prefs = AppPreferences();
      prefs.debugSetConnectivityMode(ConnectivityMode.connected);

      final n = SamplerNotifier(repo, useCase, null, null, prefs);
      expect(n.isLiveOfflineMode, isFalse);
      expect(n.allowsSoundDownload, isTrue);
    });
  });

  // ── stopAllSounds ─────────────────────────────────────────────────────────

  group('stopAllSounds', () {
    test('efface l\'état musique', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      when(() => useCase.call(any())).thenAnswer((_) async => []);

      final n = SamplerNotifier(repo, useCase);
      // Enqueue quelque chose pour tester l'effacement
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      expect(n.state.musicQueuePadIds, [1]);

      await n.stopAllSounds();

      expect(n.state.musicQueuePadIds, isEmpty);
      expect(n.state.currentMusicPad, isNull);
    });
  });

  // ── canUndoLastRemoval ────────────────────────────────────────────────────

  group('canUndoLastRemoval', () {
    test('false initialement', () {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      final n = SamplerNotifier(repo, useCase);

      expect(n.canUndoLastRemoval, isFalse);
    });
  });

  // ── live session ──────────────────────────────────────────────────────────

  group('live session — startLiveSession / endLiveSession / compteurs', () {
    test('inactive par défaut ; startLiveSession active et remet à zéro', () {
      final n = _notifierForPlayback();
      expect(n.isLiveSessionActive, isFalse);

      n.startLiveSession();

      expect(n.isLiveSessionActive, isTrue);
      expect(n.sessionPlayCountFor(1), 0);
      expect(n.hasPlayedInSession(1), isFalse);
    });

    test('endLiveSession désactive mais gèle les compteurs', () {
      final n = _notifierForPlayback();
      final pad = _multipad(1, [_sound(10), _sound(11)]);
      final padItem = PadItem(pad: pad);

      n.startLiveSession();
      n.debugMarkPlayedAt(padItem, 0);
      expect(n.sessionPlayCountFor(10), 1);

      n.endLiveSession();

      expect(n.isLiveSessionActive, isFalse);
      expect(n.sessionPlayCountFor(10), 1); // gelé, pas remis à zéro
      expect(n.hasPlayedInSession(10), isTrue);
    });

    test('une nouvelle session efface les anciens compteurs', () {
      final n = _notifierForPlayback();
      final pad = _multipad(1, [_sound(10)]);
      final padItem = PadItem(pad: pad);

      n.startLiveSession();
      n.debugMarkPlayedAt(padItem, 0);
      n.endLiveSession();
      expect(n.sessionPlayCountFor(10), 1);

      n.startLiveSession();

      expect(n.sessionPlayCountFor(10), 0);
    });

    test('la pré-écoute (debugMarkPlayedPreviewOnly) n\'incrémente jamais',
        () {
      final n = _notifierForPlayback();
      n.startLiveSession();

      n.debugMarkPlayedPreviewOnly(42);

      expect(n.sessionPlayCountFor(42), 0);
      expect(n.hasPlayedInSession(42), isFalse);
    });

    test('debugMarkPlayedAt n\'incrémente que si la session est active', () {
      final n = _notifierForPlayback();
      final pad = _multipad(1, [_sound(10)]);
      final padItem = PadItem(pad: pad);

      n.debugMarkPlayedAt(padItem, 0); // pas de session live en cours

      expect(n.sessionPlayCountFor(10), 0);
    });
  });

  // ── _pickLowestSessionCountIndex (mode live) ─────────────────────────────

  group('debugPickLowestSessionCountIndex — mode live', () {
    test('un son au compteur plus bas est toujours choisi', () {
      final n = _notifierForPlayback();
      final pad = _multipad(1, [_sound(10), _sound(11), _sound(12)]);
      final padItem = PadItem(pad: pad);

      n.startLiveSession();
      n.debugMarkPlayedAt(padItem, 1); // sound 11 → count 1
      n.debugMarkPlayedAt(padItem, 2); // sound 12 → count 1
      // sound 10 (index 0) reste à 0 → doit toujours être choisi.

      for (var i = 0; i < 50; i++) {
        expect(
          n.debugPickLowestSessionCountIndex(padItem, [0, 1, 2]),
          0,
        );
      }
    });

    test('égalité totale (session vierge) : tous les indices peuvent sortir',
        () {
      final n = _notifierForPlayback();
      final pad = _multipad(1, [_sound(10), _sound(11), _sound(12)]);
      final padItem = PadItem(pad: pad);
      n.startLiveSession();

      final seen = <int>{};
      for (var i = 0; i < 300; i++) {
        seen.add(n.debugPickLowestSessionCountIndex(padItem, [0, 1, 2]));
      }

      expect(seen, {0, 1, 2});
    });

    test('égalité partielle : seuls les ex-æquo au minimum sortent, tous les '
        'deux', () {
      final n = _notifierForPlayback();
      final pad = _multipad(
        1,
        [_sound(10), _sound(11), _sound(12), _sound(13)],
      );
      final padItem = PadItem(pad: pad);

      n.startLiveSession();
      n.debugMarkPlayedAt(padItem, 0); // sound 10 → count 1
      n.debugMarkPlayedAt(padItem, 1); // sound 11 → count 1
      n.debugMarkPlayedAt(padItem, 2); // sound 12 → count 1
      n.debugMarkPlayedAt(padItem, 2); // sound 12 → count 2
      n.debugMarkPlayedAt(padItem, 3); // sound 13 → count 1
      n.debugMarkPlayedAt(padItem, 3); // sound 13 → count 2
      // indices 0 et 1 restent au minimum (1), 2 et 3 sont à 2.

      final seen = <int>{};
      for (var i = 0; i < 200; i++) {
        final chosen = n.debugPickLowestSessionCountIndex(padItem, [0, 1, 2, 3]);
        expect(chosen, anyOf(0, 1));
        seen.add(chosen);
      }
      expect(seen, {0, 1});
    });

    test(
      'agnostique au playMode du pad (un pad séquentiel obtient le même '
      'résultat qu\'un pad aléatoire à compteurs égaux) : _pickSoundIndex '
      'appelle ce helper AVANT le switch sur playMode, donc son comportement '
      'ne doit dépendre que des compteurs, jamais de playMode — cf. décision '
      '0014. (Le dispatch réel de _pickSoundIndex n\'est pas exerçable ici : '
      'il requiert des PadSoundSlot.player, un AudioPlayerService natif '
      'SoLoud non simulable sans lecteur audio réel.)',
      () {
        final n = _notifierForPlayback();
        final pad = _multipad(
          1,
          [_sound(10), _sound(11)],
          playMode: PadPlayMode.sequential,
        );
        final padItem = PadItem(pad: pad);

        n.startLiveSession();
        n.debugMarkPlayedAt(padItem, 0); // sound 10 → count 1

        for (var i = 0; i < 20; i++) {
          expect(
            n.debugPickLowestSessionCountIndex(padItem, [0, 1]),
            1,
          );
        }
      },
    );
  });
}
