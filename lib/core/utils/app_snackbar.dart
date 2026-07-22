import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Point d'entrée unique pour toutes les snackbars de l'app.
///
/// Remplace la snackbar courante plutôt que de l'empiler, applique un
/// `behavior: floating` cohérent, et **garantit la fermeture** après [duration].
/// Centraliser ici évite que chaque site ré-implémente ces détails.
///
/// La fermeture garantie est nécessaire car l'auto-dismiss natif de Flutter ne
/// s'arme pas dans certains cas (navigation accessible active, ou `Scaffold`
/// recouvert dont le ticker est gelé) — la snackbar resterait alors indéfiniment.
/// Le filet de sécurité ferme *uniquement* sa propre snackbar via son controller
/// (jamais une plus récente) et est un no-op si elle est déjà fermée.
///
/// Pour un overlay/dialog, utiliser [showOn] avec le `ScaffoldMessenger` **local**
/// de l'overlay : affichée via `.of(context)`, la snackbar serait rendue par le
/// `Scaffold` de l'écran, derrière la barrière modale.
class AppSnackBar {
  const AppSnackBar._();

  /// Affiche depuis un écran (route courante). Voir [showOn] pour un overlay.
  ///
  /// [copyable] rend le texte cliquable-à-copier (messages d'erreur longs).
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    bool copyable = false,
    Duration duration = const Duration(seconds: 4),
  }) =>
      showOn(
        ScaffoldMessenger.of(context),
        message,
        action: action,
        copyable: copyable,
        duration: duration,
      );

  /// Affiche sur un [messenger] explicite — typiquement le `ScaffoldMessenger`
  /// local d'un overlay, hors du `Scaffold` de l'écran.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOn(
    ScaffoldMessengerState messenger,
    String message, {
    SnackBarAction? action,
    bool copyable = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: action,
        content: copyable
            ? _CopyableSnackBarContent(message: message, messenger: messenger)
            : Text(message),
      ),
    );
    // Filet de sécurité : ferme *cette* snackbar après [duration] via un `Timer`
    // Dart, indépendant du ticker — donc effectif même quand l'auto-dismiss natif
    // ne s'arme pas (navigation accessible / Scaffold recouvert). No-op si déjà
    // fermée (action, swipe, ou remplacée par une snackbar plus récente).
    Future<void>.delayed(duration, () {
      try {
        controller.close();
      } catch (_) {}
    });
    return controller;
  }
}

/// Raccourci historique : snackbar copiable. Équivaut à
/// `AppSnackBar.show(context, message, copyable: true)`.
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  AppSnackBar.show(context, message, copyable: true, duration: duration);
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
    AppSnackBar.showOn(
      messenger,
      'Message copié',
      duration: const Duration(seconds: 2),
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
