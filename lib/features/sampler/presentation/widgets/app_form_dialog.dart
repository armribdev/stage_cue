import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

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
            tooltip: 'Fermer',
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
