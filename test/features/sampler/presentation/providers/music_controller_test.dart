import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound_board.dart';
import 'package:stage_cue/features/sampler/domain/usecases/load_sounds_usecase.dart';
import 'package:stage_cue/features/sampler/data/repositories/sound_repository.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';

// ignore: subtype_of_sealed_class
class MockSoundRepository extends Mock implements SoundRepository {}

class MockLoadSoundsUseCase extends Mock implements LoadSoundsUseCase {}

Pad _pad(int id) => Pad(
      id: id,
      boardId: 1,
      sortOrder: id,
      createdAt: DateTime(2026),
    );

Sound _sound(int id) => Sound(
      id: id,
      title: 'Son $id',
      filePath: '/tmp/son_$id.mp3',
      type: SoundType.music,
      volume: 1.0,
      createdAt: DateTime(2026),
    );

SamplerNotifier _notifier() {
  final repo = MockSoundRepository();
  final useCase = MockLoadSoundsUseCase();
  // getSoundById peut être appelé lors de la résolution de sons.
  when(() => repo.getSoundById(any())).thenAnswer((_) async => null);
  when(() => useCase.call(any())).thenAnswer((_) async => []);
  return SamplerNotifier(repo, useCase);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_pad(0));
    registerFallbackValue(_sound(0));
  });

  // ── Volume ────────────────────────────────────────────────────────────────

  group('setMusicVolume', () {
    test('met à jour musicVolume', () async {
      final n = _notifier();
      expect(n.musicVolume, 1.0);

      await n.setMusicVolume(0.5);
      expect(n.musicVolume, 0.5);
    });

    test('clamp à [0, 1]', () async {
      final n = _notifier();

      await n.setMusicVolume(1.5);
      expect(n.musicVolume, 1.0);

      await n.setMusicVolume(-0.2);
      expect(n.musicVolume, 0.0);
    });

    test('émet une notification', () async {
      final n = _notifier();
      var notified = false;
      n.addListener(() => notified = true);

      await n.setMusicVolume(0.3);
      expect(notified, isTrue);
    });

    test('idempotent si valeur identique', () async {
      final n = _notifier();
      var count = 0;
      n.addListener(() => count++);

      await n.setMusicVolume(1.0); // inchangé
      expect(count, 0);

      await n.setMusicVolume(0.8);
      expect(count, 1);
    });
  });

  group('toggleMusicMute', () {
    test('coupe puis restaure le volume', () async {
      final n = _notifier();
      await n.setMusicVolume(0.7);

      await n.toggleMusicMute();
      expect(n.musicVolume, 0.0);

      await n.toggleMusicMute();
      expect(n.musicVolume, 0.7);
    });

    test('restaure à 1.0 si aucun volume mémorisé', () async {
      final n = _notifier();
      // Volume initial à 0 sans valeur mémorisée
      await n.setMusicVolume(0.0);

      await n.toggleMusicMute(); // devrait restaurer à 1.0
      expect(n.musicVolume, 1.0);
    });
  });

  // ── File d'attente ────────────────────────────────────────────────────────

  group('enqueueMusicPad', () {
    test('ajoute un pad à la file', () {
      final n = _notifier();
      final item = PadItem(pad: _pad(42));

      n.enqueueMusicPad(item);

      expect(n.state.musicQueuePadIds, [42]);
    });

    test('ne duplique pas un pad déjà en file', () {
      final n = _notifier();
      final item = PadItem(pad: _pad(42));

      n.enqueueMusicPad(item);
      n.enqueueMusicPad(item);

      expect(n.state.musicQueuePadIds, [42]);
    });

    test('peut enqueuer plusieurs pads distincts', () {
      final n = _notifier();

      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));
      n.enqueueMusicPad(PadItem(pad: _pad(3)));

      expect(n.state.musicQueuePadIds, [1, 2, 3]);
    });

    test('émet une notification', () {
      final n = _notifier();
      var notified = false;
      n.addListener(() => notified = true);

      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      expect(notified, isTrue);
    });
  });

  group('removeFromMusicQueue', () {
    test('retire le pad ciblé', () async {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));

      await n.removeFromMusicQueue(1);

      expect(n.state.musicQueuePadIds, [2]);
    });

    test('sans effet si pad absent', () async {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      var count = 0;
      n.addListener(() => count++);

      await n.removeFromMusicQueue(99); // inconnu

      expect(count, 0);
      expect(n.state.musicQueuePadIds, [1]);
    });
  });

  group('reorderMusicQueue', () {
    test('déplace le premier vers la fin', () {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));
      n.enqueueMusicPad(PadItem(pad: _pad(3)));

      n.reorderMusicQueue(0, 2);

      expect(n.state.musicQueuePadIds, [2, 3, 1]);
    });

    test('sans effet si indices hors-bornes', () {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));

      n.reorderMusicQueue(-1, 0);
      n.reorderMusicQueue(0, 5);

      expect(n.state.musicQueuePadIds, [1, 2]);
    });

    test('sans effet si même indice', () {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));
      var count = 0;
      n.addListener(() => count++);

      n.reorderMusicQueue(0, 0);
      expect(count, 0);
    });
  });

  group('clearMusicQueue', () {
    test('vide la file', () async {
      final n = _notifier();
      n.enqueueMusicPad(PadItem(pad: _pad(1)));
      n.enqueueMusicPad(PadItem(pad: _pad(2)));

      await n.clearMusicQueue();

      expect(n.state.musicQueuePadIds, isEmpty);
    });

    test('sans effet si déjà vide', () async {
      final n = _notifier();
      var count = 0;
      n.addListener(() => count++);

      await n.clearMusicQueue();
      expect(count, 0);
    });
  });

  // ── Erreur de lecture ─────────────────────────────────────────────────────

  group('consumeLastMusicPlaybackError', () {
    test('retourne null initialement', () {
      final n = _notifier();
      expect(n.consumeLastMusicPlaybackError(), isNull);
    });

    test('retourne et efface le message après un échec de chargement', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      // getSoundById renvoie null → _setMusicLoadError est appelé
      when(() => repo.getSoundById(any())).thenAnswer((_) async => null);
      when(() => useCase.call(any())).thenAnswer((_) async => []);
      final n = SamplerNotifier(repo, useCase);

      await n.playMusicBySoundId(99);

      final error = n.consumeLastMusicPlaybackError();
      expect(error, isNotNull);

      // Un second appel doit retourner null (message consommé)
      expect(n.consumeLastMusicPlaybackError(), isNull);
    });
  });

  // ── cleanupOffStagePads ───────────────────────────────────────────────────

  group('cleanupOffStagePads', () {
    test('ne plante pas si aucun pad hors-scène', () async {
      final repo = MockSoundRepository();
      final useCase = MockLoadSoundsUseCase();
      when(() => repo.getSoundById(any())).thenAnswer((_) async => null);
      when(() => repo.getSoundBoards())
          .thenAnswer((_) async => [SoundBoard(id: 1, name: 'A', createdAt: DateTime(2026))]);
      when(() => repo.createSoundBoard(any(),
              color: any(named: 'color'), libraryId: any(named: 'libraryId')))
          .thenAnswer((_) async => 1);
      when(() => useCase.call(any())).thenAnswer((_) async => []);
      final n = SamplerNotifier(repo, useCase);

      // selectBoard appelle cleanupOffStagePads et stopAllSounds
      // Aucune exception attendue
      expect(() async {
        await n.loadBoards();
        await n.selectBoard(SoundBoard(id: 1, name: 'A', createdAt: DateTime(2026)));
      }, returnsNormally);
    });
  });
}
