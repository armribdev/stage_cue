import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

typedef BoardCreationResult = ({String name, int? color});

/// Dialog réutilisable pour uniformiser les formulaires de l'application.
class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.onClose,
    this.width = 620,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    const dialogRadius = 16.0;
    const dialogInset = 24.0;
    const dialogPadding = 16.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogRadius),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: dialogInset,
        vertical: dialogInset * 0.8,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        dialogPadding,
        dialogPadding,
        dialogPadding,
        dialogPadding * 0.5,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        dialogPadding,
        dialogPadding * 0.5,
        dialogPadding,
        dialogPadding,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        dialogPadding,
        0,
        dialogPadding,
        dialogPadding,
      ),
      actionsAlignment: MainAxisAlignment.end,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            onPressed: onClose ?? () => Navigator.of(context).pop(false),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(width: width, child: content),
      actions: actions,
    );
  }
}

/// Dialogue de saisie d'un nom court (créer / renommer / dupliquer une scène…).
///
/// Centralise un pattern qui était dupliqué presque à l'identique à plusieurs
/// endroits (ex. les dialogues "Nouvelle scène" / "Renommer" / "Dupliquer" de
/// `sampler_screen.dart`) : champ unique, validation sur Entrée, focus auto.
class AppTextInputDialog extends StatefulWidget {
  const AppTextInputDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.initialValue,
    this.hint,
    this.icon,
  });

  final String title;
  final String confirmLabel;
  final String? initialValue;
  final String? hint;
  final IconData? icon;

  /// Affiche le dialogue et renvoie le texte saisi (rogné), ou `null` si annulé.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String? initialValue,
    String? hint,
    IconData? icon,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AppTextInputDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
        hint: hint,
        icon: icon,
      ),
    );
  }

  @override
  State<AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<AppTextInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dialogWidth = min(560.0, MediaQuery.sizeOf(context).width - 48);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusLg),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg + 6,
        AppSpacing.xl,
        AppSpacing.sm + 2,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm + 2,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs + 2,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      buttonPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.icon == null
                ? null
                : Icon(widget.icon, color: scheme.primary.withValues(alpha: 0.9)),
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Dialogue de confirmation réutilisable (suppression, action irréversible…).
///
/// Centralise un pattern dupliqué (ex. confirmation de suppression de scène
/// dans `sampler_screen.dart`) avec un style cohérent et une option
/// "destructive" pour mettre en avant les actions à risque.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.cancelLabel = 'Annuler',
    this.confirmLabel = 'Confirmer',
    this.isDestructive = false,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;

  /// Affiche le dialogue et renvoie `true` si l'utilisateur a confirmé.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String cancelLabel = 'Annuler',
    String confirmLabel = 'Confirmer',
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: title,
        message: message,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusLg),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive
              ? TextButton.styleFrom(foregroundColor: scheme.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

// ── Palette de couleurs ───────────────────────────────────────────────────────

const _kBoardColors = <int>[
  0xFFEF5350,
  0xFFFF7043,
  0xFFFFCA28,
  0xFF66BB6A,
  0xFF26A69A,
  0xFF42A5F5,
  0xFF5C6BC0,
  0xFFAB47BC,
  0xFFEC407A,
  0xFF8D6E63,
  0xFF78909C,
];

// ── Dialog ────────────────────────────────────────────────────────────────────

/// Dialogue de création de scène avec saisie du nom et choix de couleur.
class AppBoardCreationDialog extends StatefulWidget {
  const AppBoardCreationDialog({super.key, required this.suggestedName});

  final String suggestedName;

  static Future<BoardCreationResult?> show(
    BuildContext context, {
    required String suggestedName,
  }) {
    return showDialog<BoardCreationResult>(
      context: context,
      builder: (_) => AppBoardCreationDialog(suggestedName: suggestedName),
    );
  }

  @override
  State<AppBoardCreationDialog> createState() => _AppBoardCreationDialogState();
}

class _AppBoardCreationDialogState extends State<AppBoardCreationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    final name = raw.isEmpty ? widget.suggestedName : raw;
    Navigator.of(context).pop((name: name, color: _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dialogWidth = min(480.0, MediaQuery.sizeOf(context).width - 48);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusLg),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg + 6,
        AppSpacing.xl,
        AppSpacing.sm + 2,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      buttonPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      title: const Text('Nouvelle scène'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.suggestedName,
                prefixIcon: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Couleur',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _ColorRow(
              colors: _kBoardColors,
              selected: _selectedColor,
              onSelect: (c) => setState(() => _selectedColor = c),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

// ── Sous-widgets ──────────────────────────────────────────────────────────────

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  final List<int> colors;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ColorSwatch(
            color: null,
            isSelected: selected == null,
            scheme: scheme,
            onTap: () => onSelect(null),
          ),
          ...colors.map(
            (c) => _ColorSwatch(
              color: Color(c),
              isSelected: selected == c,
              scheme: scheme,
              onTap: () => onSelect(selected == c ? null : c),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.scheme,
    required this.onTap,
  });

  final Color? color;
  final bool isSelected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    const radius = AppRadius.md;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs + 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color ?? scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.all(Radius.circular(radius)),
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: isSelected ? 2.5 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.block_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                )
              : isSelected
              ? Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: color!.computeLuminance() > 0.4
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
