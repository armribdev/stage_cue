import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/string_utils.dart';
import '../../data/datasources/local_tag_editing_datasource.dart';
import '../../domain/entities/tag_catalog_change.dart';
import '../providers/tag_catalog_editor_controller.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';
import '../widgets/boxed_icon_button.dart';
import '../widgets/settings_layout.dart';
import '../widgets/tag_catalog_edit_dialog.dart';

/// Éditeur du catalogue de tags, **réservé au développeur** (build debug, ouvert
/// depuis Réglages → Maintenance) — décision 0047.
///
/// Il applique chaque modification à la base locale pour en voir l'effet, et en
/// déduit la déclaration à coller dans `database_tag_seed.dart` : le catalogue
/// du code reste la seule source de vérité (0046), sans quoi la base se réaligne
/// dessus au lancement suivant et les utilisateurs ne voient rien.
class TagCatalogEditorScreen extends StatefulWidget {
  final LocalTagEditingDataSource editor;
  final bool isModal;

  const TagCatalogEditorScreen({
    super.key,
    required this.editor,
    this.isModal = false,
  });

  static Future<void> open(
    BuildContext context, {
    required LocalTagEditingDataSource editor,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) =>
          TagCatalogEditorScreen(editor: editor, isModal: isModal),
    );
  }

  @override
  State<TagCatalogEditorScreen> createState() => _TagCatalogEditorScreenState();
}

class _TagCatalogEditorScreenState extends State<TagCatalogEditorScreen> {
  late final TagCatalogEditorController _controller;
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _controller = TagCatalogEditorController(widget.editor)..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _copySnippet() async {
    await Clipboard.setData(ClipboardData(text: _controller.snippet));
    if (!mounted) return;
    _controller.markSnippetCopied();
    AppSnackBar.show(
      context,
      'Code copié : à coller dans database_tag_seed.dart.',
      severity: AppToastSeverity.success,
    );
  }

  Future<void> _createTag(int categoryId, String categoryName) async {
    final name = await AppTextInputDialog.show(
      context,
      title: 'Nouveau tag · $categoryName',
      confirmLabel: 'Créer',
      hint: 'Nom du tag',
    );
    if (name == null || !mounted) return;
    try {
      await _controller.createTag(categoryId: categoryId, name: name);
    } on TagEditException catch (e) {
      if (mounted) {
        AppSnackBar.show(context, e.message, severity: AppToastSeverity.error);
      }
      return;
    }
    if (!mounted) return;
    // Les alias font l'essentiel d'un tag : on ouvre sa fiche tout de suite.
    final normalized = normalizeForSearch(name);
    for (final category in _controller.categories) {
      for (final entry in category.entries) {
        if (category.category.id == categoryId &&
            entry.tag.normalizedName == normalized) {
          await TagCatalogEditDialog.show(
            context,
            controller: _controller,
            tagId: entry.tag.id,
          );
          return;
        }
      }
    }
  }

  /// Quitter avec des modifications non copiées les laisse hors du code : on le
  /// demande avant.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final leave = await AppConfirmDialog.show(
      context,
      title: 'Quitter sans copier le code ?',
      message:
          'Des modifications sont appliquées à la base locale mais pas '
          'encore copiées : sans leur déclaration dans le catalogue du code, '
          'elles ne seront pas livrées (le journal en garde la trace).',
      confirmLabel: 'Quitter',
      isDestructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final body = _buildBody(context);
        return PopScope(
          canPop: !_controller.hasUncopiedChanges,
          onPopInvokedWithResult: _onPopInvoked,
          child: widget.isModal
              ? AppModalShell(
                  title: 'Catalogue de tags (dev)',
                  body: body,
                  onClose: () => Navigator.of(context).maybePop(),
                )
              : Scaffold(
                  appBar: AppBar(title: const Text('Catalogue de tags (dev)')),
                  body: body,
                ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.isLoading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_controller.loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SettingsNote(
          'Lecture du catalogue impossible : ${_controller.loadError}',
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }

    final pending = _controller.changes.length;
    final copied = !_controller.hasUncopiedChanges && pending > 0;
    final hasSnippet = _controller.snippet.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppModalStyle.padding),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  decoration: const InputDecoration(
                    hintText: 'Filtrer (nom ou alias)',
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SettingsButton(
                label: copied
                    ? 'Copié'
                    : pending == 0
                    ? 'Copier le code'
                    : 'Copier le code ($pending)',
                icon: copied ? AppIcons.check : AppIcons.copy,
                onPressed: hasSnippet ? _copySnippet : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(child: _buildCatalog(context)),
      ],
    );
  }

  Widget _buildCatalog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = normalizeForSearch(_filter);
    final children = <Widget>[];

    for (final category in _controller.categories) {
      final entries = [
        for (final entry in category.entries)
          if (normalized.isEmpty ||
              entry.tag.normalizedName.contains(normalized) ||
              entry.aliases.any(
                (a) => normalizeForSearch(a.alias).contains(normalized),
              ))
            entry,
      ];
      if (normalized.isNotEmpty && entries.isEmpty) continue;

      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppModalStyle.padding,
            AppSpacing.md,
            AppModalStyle.padding - 4,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(category.category.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                category.category.name.toUpperCase(),
                style: AppTextStyles.sectionLabel(context),
              ),
              const Spacer(),
              BoxedIconButton(
                icon: AppIcons.add,
                tooltip: 'Nouveau tag',
                framed: false,
                onPressed: () =>
                    _createTag(category.category.id, category.category.name),
              ),
            ],
          ),
        ),
      );

      for (final entry in entries) {
        children.add(
          InkWell(
            onTap: () => TagCatalogEditDialog.show(
              context,
              controller: _controller,
              tagId: entry.tag.id,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppModalStyle.padding,
                vertical: AppSpacing.xs + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.tag.name),
                        if (entry.aliases.isNotEmpty)
                          Text(
                            entry.aliases.map((a) => a.alias).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${entry.usage}',
                    style: AppFonts.monoStyle(
                      Theme.of(context).textTheme.bodySmall ??
                          const TextStyle(),
                    ).copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StrokeIcon(
                    AppIcons.chevronRight,
                    size: AppIconSize.sm,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.sm),
          child: Divider(height: 1),
        ),
      );
    }

    return ListView(shrinkWrap: true, children: children);
  }
}
