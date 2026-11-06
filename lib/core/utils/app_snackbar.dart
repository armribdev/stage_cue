import 'dart:async';

import 'package:flutter/widgets.dart';

/// Gravité d'un toast — pilote uniquement l'icône d'état. Elle est passée
/// explicitement par l'appelant (jamais devinée en analysant le texte).
enum AppToastSeverity { info, success, error }

/// Action proposée dans un toast (ex. « Reconnecter »). Remplace
/// `SnackBarAction` pour ne plus dépendre du `ScaffoldMessenger`.
class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Un toast affiché (ou à afficher) par l'`AppToastHost`.
class AppToast {
  const AppToast._({
    required this.id,
    required this.message,
    required this.severity,
    required this.action,
    required this.copyable,
    required this.duration,
  });

  /// Identifiant croissant — permet de ne fermer que *son propre* toast.
  final int id;
  final String message;
  final AppToastSeverity severity;
  final AppToastAction? action;
  final bool copyable;
  final Duration duration;
}

/// État du toast courant : un seul à la fois, un nouveau remplace l'ancien.
///
/// Il porte aussi la **fermeture garantie** après [AppToast.duration], via un
/// `Timer` Dart indépendant de tout ticker : elle reste effective même quand
/// l'animation est gelée ou que la navigation accessible est active (cas où
/// l'auto-dismiss natif d'un `SnackBar` ne s'armait pas). Elle ne ferme que
/// son propre toast — jamais un plus récent — et est sans effet s'il est déjà
/// fermé.
///
/// Le survol (desktop) suspend le compte à rebours ; à la sortie du pointeur
/// il repart de la durée complète.
class AppToastController extends ChangeNotifier {
  AppToast? _current;
  int _lastId = 0;
  Timer? _timer;
  bool _paused = false;

  /// Toast actuellement affiché, `null` si aucun.
  AppToast? get current => _current;

  /// Affiche un toast en remplaçant le courant. Retourne le toast créé.
  AppToast show(
    String message, {
    AppToastAction? action,
    bool copyable = false,
    AppToastSeverity severity = AppToastSeverity.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final toast = AppToast._(
      id: ++_lastId,
      message: message,
      severity: severity,
      action: action,
      copyable: copyable,
      duration: duration,
    );
    _current = toast;
    _paused = false;
    _arm(toast);
    notifyListeners();
    return toast;
  }

  /// Ferme le toast d'identifiant [id] s'il est encore le courant ; sinon rien
  /// (il a déjà été fermé ou remplacé).
  void dismiss(int id) {
    if (_current?.id != id) return;
    _timer?.cancel();
    _current = null;
    _paused = false;
    notifyListeners();
  }

  /// Ferme le toast courant, quel qu'il soit.
  void dismissCurrent() {
    final current = _current;
    if (current != null) dismiss(current.id);
  }

  /// Suspend le compte à rebours (pointeur au-dessus du toast).
  void pause() {
    if (_current == null) return;
    _paused = true;
    _timer?.cancel();
  }

  /// Relance le compte à rebours après un [pause].
  void resume() {
    final current = _current;
    if (!_paused || current == null) return;
    _paused = false;
    _arm(current);
  }

  void _arm(AppToast toast) {
    _timer?.cancel();
    _timer = Timer(toast.duration, () => dismiss(toast.id));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Point d'entrée unique pour toutes les notifications de l'app (toasts).
///
/// Les toasts sont rendus par l'`AppToastHost` posé dans `MaterialApp.builder`,
/// au-dessus du `Navigator` : visibles quelle que soit la route courante, y
/// compris au-dessus d'une barrière modale. Ne jamais appeler
/// `ScaffoldMessenger.showSnackBar` directement.
class AppSnackBar {
  const AppSnackBar._();

  /// Contrôleur global lu par l'`AppToastHost`.
  static final AppToastController controller = AppToastController();

  /// Affiche un toast. [context] n'est plus nécessaire (l'hôte est global) ; il
  /// est conservé pour ne pas toucher les appelants.
  ///
  /// [copyable] rend le texte cliquable-à-copier (messages d'erreur longs).
  static void show(
    BuildContext context,
    String message, {
    AppToastAction? action,
    bool copyable = false,
    AppToastSeverity severity = AppToastSeverity.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    controller.show(
      message,
      action: action,
      copyable: copyable,
      severity: severity,
      duration: duration,
    );
  }
}

/// Raccourci pour un message d'erreur copiable. Équivaut à
/// `AppSnackBar.show(context, message, copyable: true, severity: error)`.
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  AppSnackBar.show(
    context,
    message,
    copyable: true,
    severity: AppToastSeverity.error,
    duration: duration,
  );
}
