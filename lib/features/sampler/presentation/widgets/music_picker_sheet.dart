// Wrapper de rétrocompatibilité — délègue à SoundPickerOverlay.
import 'package:flutter/material.dart';
import '../../data/repositories/sound_repository.dart';
import '../providers/sampler_provider.dart';
import 'sound_picker_overlay.dart';

/// @deprecated Utiliser [SoundPickerOverlay.showForMusic] directement.
class MusicPickerSheet {
  MusicPickerSheet._();

  static Future<void> show(
    BuildContext context, {
    // repository conservé pour ne pas casser les callers existants
    SoundRepository? repository,
    required SamplerNotifier notifier,
  }) =>
      SoundPickerOverlay.showForMusic(context, notifier: notifier);
}
