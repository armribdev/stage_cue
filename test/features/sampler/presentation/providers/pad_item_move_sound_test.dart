import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';

Sound _sound(int id) => Sound(
  id: id,
  title: 'Son $id',
  filePath: '/tmp/son_$id.mp3',
  createdAt: DateTime(2026),
);

PadItem _padItem(List<int> ids) => PadItem(
  pad: Pad(
    id: 1,
    boardId: 1,
    sortOrder: 0,
    createdAt: DateTime(2026),
    sounds: [for (final id in ids) _sound(id)],
  ),
);

void main() {
  test('moveSound déplace le son et son emplacement audio ensemble', () {
    final item = _padItem([10, 11, 12]);
    final slotOf10 = item.slots[0];

    item.moveSound(0, 2);

    expect(item.pad.sounds.map((s) => s.id), [11, 12, 10]);
    expect(item.slots.last, same(slotOf10));
    expect(item.slots.length, 3);
  });

  test('moveSound vers le haut décale les autres vers le bas', () {
    final item = _padItem([10, 11, 12]);

    item.moveSound(2, 0);

    expect(item.pad.sounds.map((s) => s.id), [12, 10, 11]);
  });

  test('moveSound garde les index de lecture sur le même son', () {
    final item = _padItem([10, 11, 12, 13]);
    item.pausedPlayerIndex = 1; // son 11
    item.downloadingSlotIndex = 3; // son 13

    item.moveSound(0, 2); // 11, 12, 10, 13

    expect(item.pad.sounds[item.pausedPlayerIndex!].id, 11);
    expect(item.pad.sounds[item.downloadingSlotIndex!].id, 13);

    item.moveSound(1, 0); // 12, 11, 10, 13
    expect(item.pad.sounds[item.pausedPlayerIndex!].id, 11);
  });

  test('moveSound ignore un index hors limites ou identique', () {
    final item = _padItem([10, 11]);

    item.moveSound(0, 0);
    item.moveSound(0, 5);
    item.moveSound(-1, 1);

    expect(item.pad.sounds.map((s) => s.id), [10, 11]);
  });
}
