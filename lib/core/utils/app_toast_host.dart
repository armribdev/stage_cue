import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_icons.dart';
import '../theme/app_tokens.dart';
import 'app_snackbar.dart';
import 'layout_utils.dart';

/// Largeur max d'un toast — au-delà, il paraît démesuré sur un écran de bureau
/// large ; en dessous, il s'adapte pour ne pas déborder sur un téléphone étroit.
const double _maxToastWidth = 420;

const Duration _enterDuration = Duration(milliseconds: 140);
const Duration _exitDuration = Duration(milliseconds: 100);

/// Hôte unique des toasts, posé dans `MaterialApp.builder` **au-dessus du
/// `Navigator`** : le toast reste donc visible au-dessus de toutes les routes
/// (pages, dialogues, barrières modales) sans `ScaffoldMessenger` local.
///
/// Lit [AppSnackBar.controller]. Ne capte jamais un tap hors de la carte : le
/// reste de l'hôte n'est qu'un `Align`, sans cible de hit-test.
class AppToastHost extends StatefulWidget {
  const AppToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  final AppToastController _controller = AppSnackBar.controller;

  late final AnimationController _anim;
  late final CurvedAnimation _curve;

  /// Toast dessiné. Reste renseigné pendant l'animation de sortie, alors que
  /// `_controller.current` est déjà `null`.
  AppToast? _shown;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: _enterDuration,
      reverseDuration: _exitDuration,
      // `preserve` : les durées sont gérées ici (voir didChangeDependencies),
      // pas par le facteur d'échelle implicite de Flutter.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onAnimationStatus);
    _curve = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // Toast déjà présent au montage : affiché d'emblée, sans entrée animée.
    _shown = _controller.current;
    if (_shown != null) _anim.value = 1;
    _controller.addListener(_onToastChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _anim.duration = reduceMotion ? Duration.zero : _enterDuration;
    _anim.reverseDuration = reduceMotion ? Duration.zero : _exitDuration;
  }

  @override
  void dispose() {
    _controller.removeListener(_onToastChanged);
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onToastChanged() {
    if (!mounted) return;
    final next = _controller.current;
    if (next == null) {
      // Sortie animée ; `_shown` est vidé une fois l'animation terminée.
      if (_shown != null) unawaited(_anim.reverse());
      return;
    }
    setState(() => _shown = next);
    // Remplacement d'un toast déjà visible : on change le contenu sur place,
    // sans rejouer sortie puis entrée. Seul un toast absent (ou en train de
    // sortir) repart de l'animation d'entrée.
    if (_anim.status == AnimationStatus.dismissed ||
        _anim.status == AnimationStatus.reverse) {
      unawaited(_anim.forward());
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !mounted) return;
    if (_controller.current == null) setState(() => _shown = null);
  }

  @override
  Widget build(BuildContext context) {
    final toast = _shown;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (toast != null)
          Positioned.fill(
            child: _positioned(
              context,
              FadeTransition(
                opacity: _curve,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(_curve),
                  child: MouseRegion(
                    onEnter: (_) => _controller.pause(),
                    onExit: (_) => _controller.resume(),
                    // Un tap sur le toast ne doit pas défocaliser le champ de
                    // recherche de l'overlay (même groupe que ses champs).
                    child: TextFieldTapRegion(
                      child: _ToastCard(toast: toast, controller: _controller),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Bas à droite sur desktop, bas centré sur mobile ; au-dessus des barres
  /// système et du clavier.
  Widget _positioned(BuildContext context, Widget card) {
    final media = MediaQuery.of(context);
    final bottomInset = math.max(
      media.viewPadding.bottom,
      media.viewInsets.bottom,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg + media.viewPadding.left,
        AppSpacing.lg,
        AppSpacing.lg + media.viewPadding.right,
        AppSpacing.lg + bottomInset,
      ),
      child: Align(
        alignment: context.prefersDesktopUi
            ? Alignment.bottomRight
            : Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxToastWidth),
          child: card,
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.toast, required this.controller});

  final AppToast toast;
  final AppToastController controller;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: toast.message));
    // Un autre toast est arrivé pendant la copie : ne pas l'écraser.
    if (controller.current?.id != toast.id) return;
    controller.show(
      'Message copié',
      severity: AppToastSeverity.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _runAction(AppToastAction action) {
    controller.dismiss(toast.id);
    action.onPressed();
  }

  (IconData, Color) _icon(ColorScheme scheme) => switch (toast.severity) {
    AppToastSeverity.info => (AppIcons.info, scheme.onSurfaceVariant),
    AppToastSeverity.success => (AppIcons.checkCircle, AppColors.success),
    AppToastSeverity.error => (AppIcons.error, scheme.error),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, iconColor) = _icon(scheme);
    final action = toast.action;

    Widget message = Text(
      toast.message,
      style: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 13,
        height: 1.35,
        color: scheme.onSurface,
      ),
    );
    if (toast.copyable) {
      message = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_copy()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: message),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                AppIcons.copy,
                size: 14,
                color: scheme.onSurfaceVariant,
                semanticLabel: 'Copier le message',
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: AppColors.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusMd,
          side: AppElevation.border(scheme),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: message),
              if (action != null) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () => _runAction(action),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  child: Text(action.label),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: () => controller.dismiss(toast.id),
                icon: const Icon(
                  AppIcons.close,
                  size: 14,
                  semanticLabel: 'Fermer',
                ),
                color: scheme.onSurfaceVariant,
                padding: EdgeInsets.zero,
                // Sans cela, Material impose une zone de tap de 48 px qui
                // décale la croix du bord de la carte.
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
