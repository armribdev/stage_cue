import 'package:flutter/material.dart';

/// Capture le [BuildContext] d'une section pour un usage externe (défilement,
/// hit-test), sans [GlobalKey].
///
/// Utile sous un [AnimatedSwitcher] qui conserve brièvement l'ancien enfant :
/// une GlobalKey partagée serait alors dupliquée dans l'arbre.
class SectionContextAnchor extends StatefulWidget {
  const SectionContextAnchor({
    super.key,
    required this.onAttached,
    required this.onDetached,
    required this.child,
  });

  final ValueChanged<BuildContext> onAttached;
  final ValueChanged<BuildContext> onDetached;
  final Widget child;

  @override
  State<SectionContextAnchor> createState() => _SectionContextAnchorState();
}

class _SectionContextAnchorState extends State<SectionContextAnchor> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_register);
  }

  @override
  void didUpdateWidget(covariant SectionContextAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_register);
  }

  void _register(Duration _) {
    if (!mounted) return;
    widget.onAttached(context);
  }

  @override
  void dispose() {
    widget.onDetached(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
