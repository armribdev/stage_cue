import 'package:flutter/material.dart';

import '../../../data/repositories/sound_repository.dart';
import '../../../domain/entities/sound.dart';
import '../../providers/sampler_provider.dart';

// ── Modes ─────────────────────────────────────────────────────────────────────

sealed class SoundPickerMode {
  const SoundPickerMode();
}

/// Recherche-éclair (Ctrl+F) : preview + préparer un bruitage/ambiance.
final class QuickSearchMode extends SoundPickerMode {
  /// Filtre de type pré-appliqué (Ctrl+G/H/J) — modifiable ensuite via les chips.
  final SoundType? initialTypeFilter;

  const QuickSearchMode({this.initialTypeFilter});
}

/// Sélecteur de musique : joue ou met en file d'attente.
final class MusicPickerMode extends SoundPickerMode {
  /// `true` (bouton lecture de la régie) : la musique choisie part tout de
  /// suite et le sélecteur se ferme. `false` (« Ajouter à la file ») : mise
  /// en file, le sélecteur reste ouvert pour en ajouter d'autres.
  final bool playNow;

  const MusicPickerMode({this.playNow = false});
}

/// Sélecteur d'ambiance de la régie : l'ambiance choisie part tout de suite
/// (fondu enchaîné avec celle en cours) et le sélecteur se ferme.
final class AmbiancePickerMode extends SoundPickerMode {
  const AmbiancePickerMode();
}

/// Sélecteur de sons pour un pad existant ou un nouveau pad brouillon.
final class PadPickerMode extends SoundPickerMode {
  final int? padId;
  final int? draftPadId;
  final List<int>? draftSelectedIds;
  final VoidCallback? onPadUpdated;

  const PadPickerMode({
    this.padId,
    this.draftPadId,
    this.draftSelectedIds,
    this.onPadUpdated,
  }) : assert(
         padId != null || draftPadId != null,
         'padId ou draftPadId requis',
       );
}

/// Parcours de la bibliothèque : ajoute un son au plateau courant.
/// Équivalent de SoundLibraryScreen pour les contextes avec SamplerNotifier.
final class LibraryMode extends SoundPickerMode {
  const LibraryMode();
}

/// Gestion de la bibliothèque : écran plein écran. Large (tablette/desktop) :
/// sons à gauche, formulaire d'édition du son sélectionné à droite. Étroit
/// (mobile) : le tap ouvre la page d'édition.
final class ManageMode extends SoundPickerMode {
  final SoundRepository repository;

  const ManageMode({required this.repository});
}

/// Sélecteur de variante d'un multipad : choisir précisément quel son parmi
/// ceux déjà assignés au pad va être joué. Liste courte et déjà connue → pas
/// de recherche ni de filtres, contrairement aux autres modes.
final class PadVariantMode extends SoundPickerMode {
  final PadItem padItem;

  const PadVariantMode({required this.padItem});
}
