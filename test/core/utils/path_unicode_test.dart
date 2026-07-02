import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/utils/path_unicode.dart';

void main() {
  group('PathUnicode', () {
    test('sameName rapproche NFC et NFD', () {
      const nfc = 'D\u00e9bile';
      const nfd = 'De\u0301bile';
      expect(PathUnicode.sameName(nfc, nfd), isTrue);
    });

    test('canonicalizeLocalPath retrouve un fichier NFD via un chemin NFC',
        () async {
      final temp = await Directory.systemTemp.createTemp('stage_cue_paths_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final nfdName = 'De\u0301bile test.mp3';
      final nfdFile = File('${temp.path}${Platform.pathSeparator}$nfdName');
      await nfdFile.writeAsBytes(List<int>.filled(600, 0x41));

      final nfcPath =
          '${temp.path}${Platform.pathSeparator}D\u00e9bile test.mp3';
      final resolved = await PathUnicode.canonicalizeLocalPath(nfcPath);

      expect(resolved, nfdFile.path);
    });
  });
}
