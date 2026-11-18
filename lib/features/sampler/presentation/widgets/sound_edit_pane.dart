import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/autotag/auto_tag_analysis.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import 'sound_edit_preload.dart';

/// Construit le formulaire d'un son avec ce qu'il faut pour qu'il s'affiche
/// complet dès sa première image.
typedef SoundEditPaneBuilder =
    Widget Function(
      BuildContext context,
      Sound sound,
      SoundEditPreload? preload,
      SoundFormMemory memory,
    );

/// Volet d'édition du son sélectionné : lit d'abord ce que la section « Tags »
/// affiche ([SoundEditPreload]) et ne remplace le formulaire qu'ensuite.
///
/// Le formulaire est recréé à chaque son (son état est propre à un son) ; sans
/// cette étape, la nouvelle section démarrerait vide avant de se remplir. Ici,
/// le formulaire précédent reste affiché les quelques millisecondes de la
/// lecture, et son successeur arrive déjà rempli, en partant de la hauteur de
/// la section précédente ([SoundFormMemory]).
///
/// Ce volet, lui, n'est pas recréé d'un son à l'autre : c'est lui qui porte la
/// continuité.
class SoundEditPane extends StatefulWidget {
  /// Change quand il faut recréer le formulaire (autre son, ou état « traité »
  /// modifié en masse) ; sert aussi de clé au formulaire.
  final Object identity;
  final Sound sound;
  final SoundRepository repository;
  final AutoTagAnalysis? autoTag;
  final SoundEditPaneBuilder builder;

  const SoundEditPane({
    super.key,
    required this.identity,
    required this.sound,
    required this.repository,
    required this.autoTag,
    required this.builder,
  });

  @override
  State<SoundEditPane> createState() => _SoundEditPaneState();
}

class _SoundEditPaneState extends State<SoundEditPane> {
  final _memory = SoundFormMemory();

  Object? _shownIdentity;
  Sound? _shownSound;
  SoundEditPreload? _shownPreload;

  @override
  void initState() {
    super.initState();
    unawaited(_show());
  }

  @override
  void didUpdateWidget(SoundEditPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity) unawaited(_show());
  }

  Future<void> _show() async {
    final identity = widget.identity;
    SoundEditPreload? preload;
    try {
      preload = await SoundEditPreload.load(
        sound: widget.sound,
        repository: widget.repository,
        autoTag: widget.autoTag,
      );
    } catch (_) {
      // Tags illisibles : le formulaire refait la lecture lui-même et en
      // signale l'échec.
    }
    // Un son plus récent a été demandé entre-temps : c'est lui qui s'affichera.
    if (!mounted || widget.identity != identity) return;
    setState(() {
      _shownIdentity = identity;
      _shownSound = widget.sound;
      _shownPreload = preload;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shownSound = _shownSound;
    if (shownSound == null) return const SizedBox.shrink();
    // Même son : on suit les mises à jour de l'appelant (favori…). Sinon, on
    // garde l'ancien jusqu'à ce que le nouveau soit prêt.
    final sound = _shownIdentity == widget.identity ? widget.sound : shownSound;
    return widget.builder(context, sound, _shownPreload, _memory);
  }
}
