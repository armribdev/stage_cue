import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/features/sampler/domain/entities/pad.dart';
import 'package:stage_cue/features/sampler/domain/entities/sound.dart';
import 'package:stage_cue/features/sampler/presentation/models/board_readiness.dart';
import 'package:stage_cue/features/sampler/presentation/models/pad_sound_slot.dart';
import 'package:stage_cue/features/sampler/presentation/providers/sampler_provider.dart';

Sound _sound(int id) => Sound(
  id: id,
  title: 'Son $id',
  displayName: null,
  filePath: '/tmp/$id.wav',
  type: SoundType.soundEffect,
  createdAt: DateTime(2026, 1, 1),
);

PadItem _pad(int id, List<PadSoundAvailability> slots, {bool isDraft = false}) {
  final pad = Pad(
    id: id,
    boardId: 1,
    name: 'Pad $id',
    sortOrder: id,
    createdAt: DateTime(2026, 1, 1),
    sounds: [for (var i = 0; i < slots.length; i++) _sound(id * 10 + i)],
  );
  return PadItem(
    pad: pad,
    slots: [for (final a in slots) PadSoundSlot(availability: a)],
  )..isDraft = isDraft;
}

BoardReadinessReport _report(
  List<PadItem> pads, {
  CueReadinessInput cue = CueReadinessInput.unsupported,
}) => BoardReadinessReport.build(pads: pads, cue: cue);

void main() {
  group('pads', () {
    test('un plateau entièrement prêt ou en cache est prêt', () {
      final report = _report([
        _pad(1, [PadSoundAvailability.ready]),
        _pad(2, [PadSoundAvailability.cached, PadSoundAvailability.ready]),
      ]);

      expect(report.isReady, isTrue);
      expect(report.issues, isEmpty);
      expect(report.padCount, 2);
      expect(report.playablePadCount, 2);
    });

    test('un son à télécharger est corrigeable, pas bloquant', () {
      final report = _report([
        _pad(1, [PadSoundAvailability.needsDownload]),
      ]);

      expect(report.isReady, isFalse);
      expect(report.blocking, isEmpty);
      expect(report.fixable.single.kind, ReadinessIssueKind.needsDownload);
      expect(report.playablePadCount, 0);
    });

    test('fichier perdu, format non lisible et hors-ligne sont bloquants', () {
      final report = _report([
        _pad(1, [PadSoundAvailability.missingFile]),
        _pad(2, [PadSoundAvailability.unsupportedFormat]),
        _pad(3, [PadSoundAvailability.offline]),
      ]);

      expect(report.blocking.map((i) => i.kind), [
        ReadinessIssueKind.missingFile,
        ReadinessIssueKind.unsupportedFormat,
        ReadinessIssueKind.offline,
      ]);
      expect(report.fixable, isEmpty);
    });

    test(
      'un multipad retient son problème le plus grave et compte les sons',
      () {
        final report = _report([
          _pad(1, [
            PadSoundAvailability.ready,
            PadSoundAvailability.needsDownload,
            PadSoundAvailability.missingFile,
          ]),
        ]);

        final issue = report.issues.single;
        expect(issue.kind, ReadinessIssueKind.missingFile);
        expect(issue.affectedSounds, 2);
        expect(issue.totalSounds, 3);
      },
    );

    test('les brouillons ne comptent pas', () {
      final report = _report([
        _pad(1, [PadSoundAvailability.ready]),
        _pad(-1, [PadSoundAvailability.needsDownload], isDraft: true),
      ]);

      expect(report.padCount, 1);
      expect(report.isReady, isTrue);
    });

    test('un pad sans son est un avertissement, pas un échec', () {
      final report = _report([_pad(1, const [])]);

      expect(report.warnings.single.kind, ReadinessIssueKind.emptyPad);
      expect(report.isReady, isTrue);
    });
  });

  group('casque', () {
    final ready = [
      _pad(1, [PadSoundAvailability.ready]),
    ];

    test('plateforme sans sortie séparée : rien à dire', () {
      expect(_report(ready).issues, isEmpty);
    });

    test('aucun casque choisi : avertissement qui ne bloque pas', () {
      final report = _report(
        ready,
        cue: const CueReadinessInput(isSupported: true),
      );

      expect(report.warnings.single.kind, ReadinessIssueKind.cueNotChosen);
      expect(report.isReady, isTrue);
    });

    test('casque choisi mais introuvable : bloquant, sans pad concerné', () {
      final report = _report(
        ready,
        cue: const CueReadinessInput(
          isSupported: true,
          selectedDeviceId: 'casque',
          visibleDeviceIds: {'autre'},
        ),
      );

      expect(report.blocking.single.kind, ReadinessIssueKind.cueUnavailable);
      expect(report.isReady, isFalse);
      expect(report.playablePadCount, 1);
    });

    test('casque choisi et vu : rien à signaler', () {
      final report = _report(
        ready,
        cue: const CueReadinessInput(
          isSupported: true,
          selectedDeviceId: 'casque',
          visibleDeviceIds: {'casque'},
        ),
      );

      expect(report.issues, isEmpty);
    });
  });
}
