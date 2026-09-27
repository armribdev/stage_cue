import 'package:flutter/material.dart';

/// Skeleton de chargement de l'écran Paramètres (carte « Éléments indexés »).
class SettingsLoadingView extends StatefulWidget {
  const SettingsLoadingView({super.key});

  @override
  State<SettingsLoadingView> createState() => _SettingsLoadingViewState();
}

class _SettingsLoadingViewState extends State<SettingsLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar(
    Color color, {
    double width = double.infinity,
    double height = 12,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _sectionCardSkeleton({required Widget title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [title, const SizedBox(height: 14), child],
    );
  }

  Widget _indexedCard(Color color) {
    return _sectionCardSkeleton(
      title: Row(
        children: [
          _bar(color, width: 20, height: 20),
          const SizedBox(width: 8),
          _bar(color, width: 150, height: 18),
          const Spacer(),
          _bar(color, width: 28, height: 28),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _indexedItemRow(color),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _bar(color.withValues(alpha: 0.35), height: 1),
          ),
          _indexedItemRow(color),
        ],
      ),
    );
  }

  Widget _indexedItemRow(Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(radius: 20, backgroundColor: color),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(color, width: 150, height: 14),
              const SizedBox(height: 4),
              _bar(color, height: 10),
              const SizedBox(height: 8),
              _bar(color, height: 4),
              const SizedBox(height: 4),
              _bar(color, width: 72, height: 10),
            ],
          ),
        ),
        _bar(color, width: 20, height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.12 + (_controller.value * 0.08);
        final color = scheme.onSurface.withValues(alpha: alpha);
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_indexedCard(color)],
          ),
        );
      },
    );
  }
}
