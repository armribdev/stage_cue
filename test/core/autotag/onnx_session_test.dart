import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/autotag/onnx_session.dart';

import 'native_libs.dart';

const _model = 'test/fixtures/autotag/double.onnx';

void main() {
  final lib = onnxRuntimeLibraryPath();
  final skip = lib == null
      ? 'ONNX Runtime introuvable : lancer `flutter build windows --debug` (ou linux) une fois'
      : null;

  group('OnnxSession (modèle y = 2x)', () {
    test('exécute le modèle et renvoie la sortie', () {
      final s = OnnxSession.open(_model, libraryPath: lib);
      addTearDown(s.close);
      final out = s.runFloat(Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8.5]), [
        1,
        8,
      ]);
      expect(out, orderedEquals([2, 4, 6, 8, 10, 12, 14, 17]));
    }, skip: skip);

    test('plusieurs exécutions successives, sortie indépendante', () {
      final s = OnnxSession.open(_model, libraryPath: lib, intraOpThreads: 1);
      addTearDown(s.close);
      final a = s.runFloat(Float32List.fromList(List.filled(8, 1)), [1, 8]);
      final b = s.runFloat(Float32List.fromList(List.filled(8, 3)), [1, 8]);
      expect(a, everyElement(2));
      expect(b, everyElement(6));
    }, skip: skip);

    test('mauvaise forme : ArgumentError avant tout appel natif', () {
      final s = OnnxSession.open(_model, libraryPath: lib);
      addTearDown(s.close);
      expect(() => s.runFloat(Float32List(8), [1, 7]), throwsArgumentError);
    }, skip: skip);

    test('forme refusée par le modèle : OnnxRuntimeException lisible', () {
      final s = OnnxSession.open(_model, libraryPath: lib);
      addTearDown(s.close);
      expect(
        () => s.runFloat(Float32List(4), [1, 4]),
        throwsA(isA<OnnxRuntimeException>()),
      );
      // La session reste utilisable après une erreur.
      expect(s.runFloat(Float32List(8), [1, 8]), everyElement(0));
    }, skip: skip);

    test('nom d\'entrée inconnu : erreur', () {
      final s = OnnxSession.open(_model, libraryPath: lib);
      addTearDown(s.close);
      expect(
        () => s.runFloat(Float32List(8), [1, 8], inputName: 'nope'),
        throwsA(isA<OnnxRuntimeException>()),
      );
    }, skip: skip);

    test('modèle absent ou corrompu : OnnxRuntimeException', () {
      expect(
        () => OnnxSession.open(
          'test/fixtures/autotag/absent.onnx',
          libraryPath: lib,
        ),
        throwsA(isA<OnnxRuntimeException>()),
      );
      final bad = File('${Directory.systemTemp.path}/bad_model.onnx')
        ..writeAsBytesSync([1, 2, 3, 4]);
      addTearDown(bad.deleteSync);
      expect(
        () => OnnxSession.open(bad.path, libraryPath: lib),
        throwsA(isA<OnnxRuntimeException>()),
      );
    }, skip: skip);

    test('après close : session fermée, close idempotent', () {
      final s = OnnxSession.open(_model, libraryPath: lib)..close();
      s.close();
      expect(
        () => s.runFloat(Float32List(8), [1, 8]),
        throwsA(isA<OnnxRuntimeException>()),
      );
    }, skip: skip);

    test('bibliothèque introuvable : OnnxRuntimeException', () {
      expect(
        () => OnnxSession.open(_model, libraryPath: 'n_existe_pas.dll'),
        throwsA(isA<OnnxRuntimeException>()),
      );
    });
  });
}
