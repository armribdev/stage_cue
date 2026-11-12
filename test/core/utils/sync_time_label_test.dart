import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/sync_time_label.dart';

void main() {
  // 12 nov. 2026, 14:32 — l'heure de référence de tous les cas.
  final now = DateTime(2026, 11, 12, 14, 32, 30);

  String label(Duration ago) =>
      formatDriveSyncTimestamp(now.subtract(ago), now: now);

  group('formatDriveSyncTimestamp', () {
    test('moins d\'une minute : « à l\'instant »', () {
      expect(label(Duration.zero), "à l'instant");
      expect(label(const Duration(seconds: 59)), "à l'instant");
    });

    test('moins d\'une heure : durée relative en minutes', () {
      expect(label(const Duration(seconds: 60)), 'il y a 1 min');
      expect(label(const Duration(minutes: 3, seconds: 20)), 'il y a 3 min');
      expect(label(const Duration(minutes: 59, seconds: 59)), 'il y a 59 min');
    });

    test('à partir d\'une heure : retour au format absolu', () {
      expect(label(const Duration(hours: 1)), "aujourd'hui à 13:32");
      expect(label(const Duration(hours: 2)), "aujourd'hui à 12:32");
    });

    test('la veille et les jours plus anciens restent absolus', () {
      expect(label(const Duration(hours: 20)), 'hier à 18:32');
      expect(label(const Duration(days: 3)), 'le 09/11 à 14:32');
    });

    test(
      'horloge réglée en arrière : « à l\'instant », pas de durée négative',
      () {
        expect(
          formatDriveSyncTimestamp(
            now.add(const Duration(minutes: 5)),
            now: now,
          ),
          "à l'instant",
        );
      },
    );
  });

  group('syncAge', () {
    test('ne descend jamais sous zéro', () {
      expect(
        syncAge(now.add(const Duration(hours: 1)), now: now),
        Duration.zero,
      );
    });
  });
}
