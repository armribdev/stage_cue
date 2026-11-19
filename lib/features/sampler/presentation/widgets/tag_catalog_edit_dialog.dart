import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../../../../core/autotag/mood_tagging.dart';
import '../../../../core/theme/app_dialog.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/string_utils.dart';
import '../../data/datasources/local_tag_editing_datasource.dart';
import '../../domain/entities/tag_catalog_change.dart';
import '../providers/tag_catalog_editor_controller.dart';
import 'app_form_dialog.dart';
import 'settings_layout.dart';
import 'tag_pill.dart';

/// Édition d'un tag depuis l'éditeur de catalogue de développement (décision
/// 0047) : renommer, gérer les alias, fusionner dans un autre tag, supprimer.
///
/// Reste ouvert après un ajout ou un retrait d'alias (il relit le contrôleur) ;
/// se ferme après un renommage, une fusion ou une suppression.
class TagCatalogEditDialog extends StatefulWidget {
  final TagCatalogEditorController controller;
  final int tagId;

  const TagCatalogEditDialog({
    super.key,
    required this.controller,
    required this.tagId,
  });

  static Future<void> show(
    BuildContext context, {
    required TagCatalogEditorController controller,
    required int tagId,
  }) {
    return showAppDialog<void>(
      context: context,
      builder: (_) =>
          TagCatalogEditDialog(controller: controller, tagId: tagId),
    );
  }

  @override
  State<TagCatalogEditDialog> createState() => _TagCatalogEditDialogState();
}

class _TagCatalogEditDialogState extends State<TagCatalogEditDialog> {
  late final TextEditingController _nameController;
  final TextEditingController _aliasController = TextEditingController();
  bool _busy = false;

  TagCatalogEditorController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _controller.find(widget.tagId)?.entry.tag.name ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  /// Exécute [operation] ; un refus est affiché, rien n'est alors fermé.
  /// Renvoie vrai si elle a abouti.
  Future<bool> _run(Future<void> Function() operation) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await operation();
      return true;
    } on TagEditException catch (e) {
      if (mounted) {
        AppSnackBar.show(context, e.message, severity: AppToastSeverity.error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _rename() async {
    final ok = await _run(
      () => _controller.renameTag(widget.tagId, _nameController.text),
    );
    if (ok && mounted) _close();
  }

  Future<void> _addAlias() async {
    final ok = await _run(
      () => _controller.addAlias(widget.tagId, _aliasController.text),
    );
    if (ok) _aliasController.clear();
  }

  Future<void> _merge(String category, String name, int usage) async {
    final targetId = await showAppDialog<int>(
      context: context,
      builder: (_) => _TagPickerDialog(
        controller: _controller,
        excludedTagId: widget.tagId,
      ),
    );
    if (targetId == null || !mounted) return;
    final target = _controller.find(targetId);
    if (target == null) return;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Fusionner « $name » ?',
      message:
          '« $name » ($category) disparaît au profit de '
          '« ${target.entry.tag.name} » (${target.category}). Ses $usage '
          'usage(s), suggestions et alias passent sur ce tag ; son nom devient '
          'un alias.',
      confirmLabel: 'Fusionner',
    );
    if (!confirmed || !mounted) return;
    final ok = await _run(
      () => _controller.mergeTag(fromId: widget.tagId, intoId: targetId),
    );
    if (ok && mounted) _close();
  }

  Future<void> _delete(String name, int usage) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer « $name » ?',
      message:
          'Retire le tag de $usage son(s), avec ses suggestions et ses alias. '
          'Pour ne rien perdre, fusionnez-le plutôt dans un tag voisin.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await _run(() => _controller.deleteTag(widget.tagId));
    if (ok && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final found = _controller.find(widget.tagId);
        if (found == null) {
          // Supprimé ou fusionné : plus rien à éditer.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) _close();
          });
          return const SizedBox.shrink();
        }
        return _buildDialog(context, found.category, found.entry);
      },
    );
  }

  Widget _buildDialog(
    BuildContext context,
    String category,
    TagEditorEntry entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tag = entry.tag;
    final isMood = isMoodTag(category: category, tag: tag.name);
    final width = min(480.0, MediaQuery.sizeOf(context).width - 80);

    return AppFormDialog(
      title: tag.name,
      width: width,
      onClose: _close,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsNote('$category · ${entry.usage} son(s)'),
            if (isMood) ...[
              const SizedBox(height: AppSpacing.sm),
              const SettingsNote(
                'Ambiance de l\'analyse automatique (kMoods) : seuls les '
                'alias se modifient.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _label(context, 'Nom'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    enabled: !isMood,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _rename(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SettingsButton(
                  label: 'Renommer',
                  icon: AppIcons.edit,
                  busy: _busy,
                  onPressed: isMood ? null : _rename,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1),
            ),
            _label(context, 'Alias'),
            const SizedBox(height: AppSpacing.sm),
            if (entry.aliases.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs + 2,
                  children: [
                    for (final alias in entry.aliases)
                      TagPill(
                        key: ValueKey('alias-${alias.id}'),
                        label: alias.alias,
                        onRemove: _busy
                            ? null
                            : () =>
                                  _run(() => _controller.removeAlias(alias.id)),
                        removeTooltip: 'Retirer l\'alias',
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _aliasController,
                    decoration: const InputDecoration(
                      hintText: 'Ajouter un alias',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addAlias(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SettingsButton(
                  label: 'Ajouter',
                  icon: AppIcons.add,
                  busy: _busy,
                  onPressed: _addAlias,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Divider(height: 1),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SettingsButton(
                  label: 'Fusionner dans…',
                  icon: AppIcons.merge,
                  busy: _busy,
                  onPressed: isMood
                      ? null
                      : () => _merge(category, tag.name, entry.usage),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 34),
                    foregroundColor: scheme.error,
                  ),
                  onPressed: _busy || isMood
                      ? null
                      : () => _delete(tag.name, entry.usage),
                  icon: const StrokeIcon(AppIcons.delete, size: AppIconSize.sm),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) =>
      Text(text.toUpperCase(), style: AppTextStyles.sectionLabel(context));
}

/// Choix du tag d'accueil d'une fusion : tous les tags, filtrables, groupés par
/// leur catégorie. Renvoie l'identifiant choisi.
class _TagPickerDialog extends StatefulWidget {
  final TagCatalogEditorController controller;
  final int excludedTagId;

  const _TagPickerDialog({
    required this.controller,
    required this.excludedTagId,
  });

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = min(420.0, MediaQuery.sizeOf(context).width - 80);
    final normalized = normalizeForSearch(_filter);
    final rows = <Widget>[
      for (final category in widget.controller.categories)
        for (final entry in category.entries)
          if (entry.tag.id != widget.excludedTagId &&
              (normalized.isEmpty ||
                  entry.tag.normalizedName.contains(normalized)))
            ListTile(
              dense: true,
              title: Text(entry.tag.name),
              trailing: Text(
                category.category.name,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              onTap: () => Navigator.of(context).pop(entry.tag.id),
            ),
    ];
    return AppFormDialog(
      title: 'Fusionner dans…',
      width: width,
      onClose: () => Navigator.of(context).pop(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Filtrer les tags'),
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: min(360.0, MediaQuery.sizeOf(context).height * 0.45),
            child: ListView(children: rows),
          ),
        ],
      ),
    );
  }
}
