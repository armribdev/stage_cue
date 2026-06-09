import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/utils/quick_search_prepare.dart';

Pad _pad({
  required int id,
  int rowIndex = 0,
  int sortOrder = 0,
  List<Sound>? sounds,
}) {
  return Pad(
    id: id,
    boardId: 1,
    sortOrder: sortOrder,
    rowIndex: rowIndex,
    createdAt: DateTime(2026, 1, 1),
    sounds: sounds ?? const [],
  );
}

Sound _sound(int id) {
  return Sound(
    id: id,
    title: 'sound-$id',
    filePath: '/tmp/$id.wav',
    type: SoundType.soundEffect,
    createdAt: DateTime(2026, 1, 1),
  );
}

OnStagePadRef _ref({
  required int padId,
  bool isDraft = false,
  List<int> soundIds = const [],
}) {
  return (padId: padId, isDraft: isDraft, soundIds: soundIds);
}

void main() {
  group('findDedicatedOnStagePadId', () {
    test('retourne le pad dédié au son', () {
      final pads = [
        _ref(padId: 10, soundIds: [42]),
        _ref(padId: 11, soundIds: [1, 2]),
      ];

      expect(findDedicatedOnStagePadId(pads, 42), 10);
    });

    test('ignore les multipads contenant le son', () {
      final pads = [_ref(padId: 11, soundIds: [42, 99])];

      expect(findDedicatedOnStagePadId(pads, 42), isNull);
    });

    test('ignore les pads brouillon', () {
      final pads = [_ref(padId: 10, isDraft: true, soundIds: [42])];

      expect(findDedicatedOnStagePadId(pads, 42), isNull);
    });
  });

  group('computeLastRowAppendPlacement', () {
    test('plateau vide → ligne 0, position 0', () {
      final placement = computeLastRowAppendPlacement(const []);

      expect(placement.rowIndex, 0);
      expect(placement.insertionPositionInRow, 0);
      expect(placement.globalSortOrder, 0);
    });

    test('une seule ligne → fin de cette ligne', () {
      final placement = computeLastRowAppendPlacement([
        _pad(id: 1, sortOrder: 0),
        _pad(id: 2, sortOrder: 1),
      ]);

      expect(placement.rowIndex, 0);
      expect(placement.insertionPositionInRow, 2);
      expect(placement.globalSortOrder, 2);
    });

    test('plusieurs lignes → fin de la dernière ligne', () {
      final placement = computeLastRowAppendPlacement([
        _pad(id: 1, rowIndex: 0, sortOrder: 0),
        _pad(id: 2, rowIndex: 0, sortOrder: 1),
        _pad(id: 3, rowIndex: 2, sortOrder: 2),
        _pad(id: 4, rowIndex: 2, sortOrder: 3),
      ]);

      expect(placement.rowIndex, 2);
      expect(placement.insertionPositionInRow, 2);
      expect(placement.globalSortOrder, 4);
    });
  });

  group('prepareSfxOnBoard', () {
    test('pad dédié existant → surbrillance sans création', () async {
      var createCalls = 0;
      final result = await prepareSfxOnBoard(
        soundId: 7,
        padsOnBoard: [
          (pad: _pad(id: 55, sounds: [_sound(7)]), isDraft: false),
        ],
        createPad: (_) async {
          createCalls++;
          return 999;
        },
        reloadPads: () async => const [],
      );

      expect(createCalls, 0);
      expect(result.highlightPadId, 55);
    });

    test('son seulement dans un multipad → crée un pad dédié', () async {
      LastRowPadPlacement? captured;
      final result = await prepareSfxOnBoard(
        soundId: 7,
        padsOnBoard: [
          (
            pad: _pad(id: 55, sounds: [_sound(7), _sound(8)]),
            isDraft: false,
          ),
        ],
        createPad: (placement) async {
          captured = placement;
          return 100;
        },
        reloadPads: () async => [
          (pad: _pad(id: 100, sounds: [_sound(7)]), isDraft: false),
        ],
      );

      expect(captured?.rowIndex, 0);
      expect(captured?.insertionPositionInRow, 1);
      expect(captured?.globalSortOrder, 1);
      expect(result.highlightPadId, 100);
    });

    test('plateau vide → crée en ligne 0', () async {
      LastRowPadPlacement? captured;
      final result = await prepareSfxOnBoard(
        soundId: 3,
        padsOnBoard: const [],
        createPad: (placement) async {
          captured = placement;
          return 200;
        },
        reloadPads: () async => [
          (pad: _pad(id: 200, sounds: [_sound(3)]), isDraft: false),
        ],
      );

      expect(captured?.rowIndex, 0);
      expect(captured?.globalSortOrder, 0);
      expect(result.highlightPadId, 200);
    });

    test('nouveau pad en fin de dernière ligne sur plateau multi-lignes', () async {
      LastRowPadPlacement? captured;
      await prepareSfxOnBoard(
        soundId: 9,
        padsOnBoard: [
          (pad: _pad(id: 1, rowIndex: 0, sortOrder: 0, sounds: [_sound(1)]), isDraft: false),
          (pad: _pad(id: 2, rowIndex: 1, sortOrder: 1, sounds: [_sound(2)]), isDraft: false),
        ],
        createPad: (placement) async {
          captured = placement;
          return 300;
        },
        reloadPads: () async => [
          (pad: _pad(id: 1, rowIndex: 0, sortOrder: 0, sounds: [_sound(1)]), isDraft: false),
          (pad: _pad(id: 2, rowIndex: 1, sortOrder: 1, sounds: [_sound(2)]), isDraft: false),
          (pad: _pad(id: 300, rowIndex: 1, sortOrder: 2, sounds: [_sound(9)]), isDraft: false),
        ],
      );

      expect(captured?.rowIndex, 1);
      expect(captured?.insertionPositionInRow, 1);
      expect(captured?.globalSortOrder, 2);
    });

    test('échec de rechargement → aucun highlight', () async {
      final result = await prepareSfxOnBoard(
        soundId: 4,
        padsOnBoard: const [],
        createPad: (_) async => 400,
        reloadPads: () async => const [],
      );

      expect(result.highlightPadId, isNull);
    });
  });
}
