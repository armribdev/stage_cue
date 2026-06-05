import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Affiche une snackbar dont le texte peut être copié en cliquant dessus.
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      content: _CopyableSnackBarContent(
        message: message,
        messenger: messenger,
      ),
    ),
  );
}

class _CopyableSnackBarContent extends StatelessWidget {
  const _CopyableSnackBarContent({
    required this.message,
    required this.messenger,
  });

  final String message;
  final ScaffoldMessengerState messenger;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: message));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Message copié'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  TextStyle _contentStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.snackBarTheme.contentTextStyle ??
        TextStyle(color: theme.colorScheme.onSurface, fontSize: 14);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = _contentStyle(context);
    final iconColor = textStyle.color?.withValues(alpha: 0.7);

    return InkWell(
      onTap: _copy,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(message, style: textStyle)),
          const SizedBox(width: 8),
          Icon(Icons.copy_rounded, size: 18, color: iconColor),
        ],
      ),
    );
  }
}
