import 'package:flutter/material.dart';

import '../../domain/entities/saved_multipad.dart';
import '../providers/sampler_provider.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/saved_multipad_edit_form.dart';

/// Page plein écran d'édition d'un multipad enregistré (mobile). Sur
/// tablette/desktop, l'écran de gestion de la bibliothèque affiche le même
/// [SavedMultipadEditForm] dans son volet de droite — comme pour un son
/// ([SoundDetailsScreen]).
class SavedMultipadDetailsScreen extends StatefulWidget {
  final SamplerNotifier notifier;
  final SavedMultipad saved;

  const SavedMultipadDetailsScreen({
    super.key,
    required this.notifier,
    required this.saved,
  });

  @override
  State<SavedMultipadDetailsScreen> createState() =>
      _SavedMultipadDetailsScreenState();
}

class _SavedMultipadDetailsScreenState
    extends State<SavedMultipadDetailsScreen> {
  bool _isDirty = false;

  Future<void> _confirmDiscard() async {
    final discard = await AppConfirmDialog.show(
      context,
      title: 'Abandonner les modifications',
      message: 'Les modifications de ce multipad ne sont pas enregistrées.',
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
        appBar: AppBar(
          title: Text('Édition du multipad "${widget.saved.name}"'),
        ),
        body: SavedMultipadEditForm(
          key: ValueKey(widget.saved.id),
          notifier: widget.notifier,
          saved: widget.saved,
          onDirtyChanged: (dirty) => setState(() => _isDirty = dirty),
          onSaved: () => Navigator.of(context).pop(true),
          // Le modèle n'existe plus : rien à confirmer à l'abandon, on revient
          // à la liste.
          onDeleted: () => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}
