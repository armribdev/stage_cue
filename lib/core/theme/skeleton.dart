import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Kit de placeholders de chargement — pulsation d'alpha sobre.
///
/// Plutôt que des `CircularProgressIndicator`, on affiche des blocs gris qui
/// épousent la forme du contenu à venir et « respirent » doucement. Rendu
/// discret, cohérent avec l'esthétique outil pro (proche VS Code / Figma).
///
/// Usage : envelopper le sous-arbre de placeholders dans un [Skeleton] (qui
/// possède l'unique contrôleur d'animation partagé), puis composer avec
/// [SkeletonBox] / [SkeletonLine].
///
/// ```dart
/// Skeleton(
///   child: Column(children: [
///     SkeletonLine(widthFactor: 0.6),
///     SkeletonBox(width: 40, height: 40, shape: BoxShape.circle),
///   ]),
/// )
/// ```
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();

  /// Animation partagée par les placeholders descendants.
  static Animation<double> of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    assert(
      scope != null,
      'SkeletonBox/SkeletonLine doivent avoir un ancêtre Skeleton.',
    );
    return scope!.animation;
  }
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonScope(animation: _controller, child: widget.child);
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      animation != oldWidget.animation;
}

/// Bloc placeholder animé. Doit avoir un ancêtre [Skeleton].
///
/// Par défaut un rectangle à coins `AppRadius.sm` ; passer
/// `shape: BoxShape.circle` pour une pastille (avatar, bouton rond).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.intensity = 1.0,
  });

  final double? width;
  final double? height;
  final BoxShape shape;
  final BorderRadius? borderRadius;

  /// Module l'opacité (0–1) pour hiérarchiser les blocs entre eux
  /// (ex. un sous-titre plus pâle que le titre).
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animation = Skeleton.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final alpha = (0.14 + animation.value * 0.1) * intensity;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: alpha),
            shape: shape,
            borderRadius: shape == BoxShape.rectangle
                ? (borderRadius ?? AppRadius.radiusSm)
                : null,
          ),
        );
      },
    );
  }
}

/// Ligne de texte placeholder. `widthFactor` limite la largeur à une fraction
/// du parent (aligné à gauche) — pratique pour simuler des lignes inégales.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.widthFactor,
    this.height = 12,
    this.intensity = 1.0,
  });

  final double? width;
  final double? widthFactor;
  final double height;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final box = SkeletonBox(
      width: width,
      height: height,
      intensity: intensity,
    );
    if (widthFactor == null) return box;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: widthFactor, child: box),
    );
  }
}
