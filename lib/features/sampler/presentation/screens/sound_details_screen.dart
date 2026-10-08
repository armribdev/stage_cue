import 'package:flutter/material.dart';

import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/sound_edit_form.dart';

/// Page plein écran d'édition d'un son (mobile). Sur tablette/desktop,
/// l'écran de gestion de la bibliothèque affiche le même [SoundEditForm] dans
/// son volet de droite.
class SoundDetailsScreen extends StatefulWidget {
  final Sound sound;
  final List<TagCategoryWithTags> tagCatalog;
  final SoundRepository repository;
  final SamplerNotifier? notifier;

  const SoundDetailsScreen({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.repository,
    this.notifier,
  });

  @override
  State<SoundDetailsScreen> createState() => _SoundDetailsScreenState();
}

class _SoundDetailsScreenState extends State<SoundDetailsScreen> {
  bool _isDirty = false;

  Future<void> _confirmDiscard() async {
    final discard = await AppConfirmDialog.show(
      context,
      title: 'Abandonner les modifications',
      message: 'Les modifications de ce son ne sont pas enregistrées.',
      confirmLabel: 'Abandonner',
      isDestructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _isDirty = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Édition du son "${widget.sound.title}"')),
        body: SoundEditForm(
          key: ValueKey(widget.sound.id),
          sound: widget.sound,
          tagCatalog: widget.tagCatalog,
          repository: widget.repository,
          notifier: widget.notifier,
          onDirtyChanged: (dirty) => setState(() => _isDirty = dirty),
          onSaved: () => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}
