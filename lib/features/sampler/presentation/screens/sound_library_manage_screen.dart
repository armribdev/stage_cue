import 'package:flutter/material.dart';

import '../../../../core/database/database.dart' as db;
import '../../data/repositories/sound_repository.dart';
import '../providers/sampler_provider.dart';
import '../widgets/sound_picker_overlay.dart';

/// Écran plein écran de gestion de la bibliothèque.
///
/// Sur tablette/desktop : volet scindé, sons à gauche et infos du son
/// sélectionné à droite. Sur mobile : liste, puis page d'édition au tap.
/// Le rendu vit dans [SoundPickerOverlay] (mode gestion), qui partage la
/// recherche, les filtres et la pré-écoute avec les autres sélecteurs de sons.
class SoundLibraryManageScreen {
  SoundLibraryManageScreen._();

  static Future<void> open(
    BuildContext context, {
    required SamplerNotifier notifier,
    required db.AppDatabase database,
    VoidCallback? onReconnect,
  }) {
    return SoundPickerOverlay.showForManage(
      context,
      notifier: notifier,
      repository: SoundRepository.fromDatabase(database),
      onReconnect: onReconnect,
    );
  }
}
