// Wrapper de rétrocompatibilité — délègue à SoundPickerOverlay.
export 'sound_picker_overlay.dart'
    show SoundPickerOverlay, QuickSearchMode, MusicPickerMode, PadPickerMode, LibraryMode, ManageMode;

import 'package:flutter/material.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/quick_search_prepare.dart';
import 'sound_picker_overlay.dart';

/// @deprecated Utiliser [SoundPickerOverlay.show] directement.
class QuickSearchOverlay {
  QuickSearchOverlay._();

  static Future<QuickSearchPrepareResult?> show(
    BuildContext context, {
    required SamplerNotifier notifier,
    SoundType? initialTypeFilter,
  }) =>
      SoundPickerOverlay.show(
        context,
        notifier: notifier,
        initialTypeFilter: initialTypeFilter,
      );
}
