import 'package:flutter/material.dart';

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
