import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/audio/cue_audio_service.dart';

void main() {
  late CueAudioService cue;

  setUp(() {
    CueAudioService.debugOverrideSupported = null;
    cue = CueAudioService.instance;
    cue.init(selectedDeviceId: null);
  });

  tearDown(() {
    CueAudioService.debugOverrideSupported = null;
    cue.init(selectedDeviceId: null);
  });

  group('CueDevice', () {
    test('conserve id et label', () {
      const device = CueDevice(id: 'Speakers', label: 'Haut-parleurs');
      expect(device.id, 'Speakers');
      expect(device.label, 'Haut-parleurs');
    });
  });

  group('CueAudioService — état', () {
    test('init et setSelectedDevice persistent l\'identifiant', () {
      cue.init(selectedDeviceId: 'Headset');
      expect(cue.selectedDeviceId, 'Headset');

      cue.setSelectedDevice(null);
      expect(cue.selectedDeviceId, isNull);

      cue.setSelectedDevice('Casque USB');
      expect(cue.selectedDeviceId, 'Casque USB');
    });

    test('isCueActive exige support + device non null', () {
      CueAudioService.debugOverrideSupported = true;
      cue.setSelectedDevice(null);
      expect(cue.isCueActive, isFalse);

      cue.setSelectedDevice('Speakers');
      expect(cue.isCueActive, isTrue);

      CueAudioService.debugOverrideSupported = false;
      expect(cue.isCueActive, isFalse);
    });

    test('refreshDevices hors support → liste vide', () async {
      CueAudioService.debugOverrideSupported = false;
      cue.setSelectedDevice('ignored');

      final devices = await cue.refreshDevices();
      expect(devices, isEmpty);
      expect(cue.cachedDevices, isEmpty);
    });
  });
}
