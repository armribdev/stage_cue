import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/disk_space.dart';

void main() {
  group('availableDiskBytes', () {
    test('chemin inexistant → null', () async {
      final missing = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'stagecue_missing_${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(await missing.exists(), isFalse);
      expect(await availableDiskBytes(missing.path), isNull);
    });

    test('répertoire temporaire existant → octets positifs (desktop)', () async {
      final bytes = await availableDiskBytes(Directory.systemTemp.path);
      // Windows / Linux / macOS mesurent ; mobile renverrait null.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        expect(bytes, isNotNull);
        expect(bytes!, greaterThan(0));
      } else {
        expect(bytes, isNull);
      }
    });
  });
}
