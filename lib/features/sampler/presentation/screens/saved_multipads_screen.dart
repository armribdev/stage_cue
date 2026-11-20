import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/saved_multipad.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';
import 'saved_multipad_edit_screen.dart';

/// Gestion des multipads enregistrés dans la bibliothèque (décision 0051) :
/// les lister, les modifier, les supprimer. Les pads déjà posés sur un plateau
/// n'en dépendent pas — c'est une copie qui y a été posée.
class SavedMultipadsScreen extends StatefulWidget {
  final SamplerNotifier notifier;
  final bool isModal;

  const SavedMultipadsScreen({
    super.key,
    required this.notifier,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, fenêtre modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required SamplerNotifier notifier,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) =>
          SavedMultipadsScreen(notifier: notifier, isModal: isModal),
    );
  }

  @override
  State<SavedMultipadsScreen> createState() => _SavedMultipadsScreenState();
}

class _SavedMultipadsScreenState extends State<SavedMultipadsScreen> {
  List<SavedMultipad>? _items;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final items = await widget.notifier.loadSavedMultipads();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _edit(SavedMultipad saved) async {
    await SavedMultipadEditScreen.open(
      context,
      notifier: widget.notifier,
      saved: saved,
    );
    if (mounted) await _reload();
  }

  Future<void> _delete(SavedMultipad saved) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer le multipad enregistré',
      message:
          '« ${saved.name} » sera retiré de la bibliothèque. Les pads déjà '
          'posés sur vos plateaux ne changent pas.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.notifier.deleteSavedMultipad(saved.id);
    } catch (error) {
      if (mounted) {
        showCopyableSnackBar(context, 'Suppression impossible : $error');
      }
      return;
    }
    if (mounted) await _reload();
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    if (_loadError != null) {
      return _centered(
        context,
        'Multipads illisibles : $_loadError',
        color: scheme.error,
      );
    }
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) {
      return _centered(
        context,
        'Aucun multipad enregistré.\nDans les détails d\'un multipad, '
        '« Enregistrer dans la bibliothèque » en crée un.',
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final saved = items[index];
        final count = saved.sounds.length;
        final mode = saved.playMode == PadPlayMode.random
            ? 'aléatoire'
            : 'séquentiel';
        return InkWell(
          canRequestFocus: false,
          onTap: () => unawaited(_edit(saved)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                SoundTypeAvatar(
                  type: saved.commonType,
                  colorValue: saved.colorValue,
                  radius: 16,
                  iconSize: 18,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        saved.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        count == 0
                            ? 'Aucun son — à compléter ou supprimer'
                            : '$count son${count > 1 ? 's' : ''} · $mode',
                        style: TextStyle(
                          fontSize: 12,
                          color: count == 0
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: () => unawaited(_delete(saved)),
                  icon: StrokeIcon(
                    AppIcons.close,
                    size: AppIconSize.sm,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _centered(BuildContext context, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Multipads enregistrés';
    final body = _buildBody(context);
    if (widget.isModal) {
      return AppModalShell(title: title, body: body);
    }
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: body,
    );
  }
}
