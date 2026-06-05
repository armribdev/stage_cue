import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../../../../core/utils/layout_utils.dart';

/// Constantes partagées pour modales et petits dialogues.
abstract final class AppModalStyle {
  static const double radius = 16;
  static const double inset = 24;
  static const double padding = 16;
  static const double maxWidth = 520;
  static const double maxHeight = 720;
}

/// Ouvre une modale centrée (tablette / desktop) ou une page (téléphone).
Future<void> openAdaptiveScreen({
  required BuildContext context,
  required Widget Function({required bool isModal}) builder,
}) async {
  if (preferModalPresentation(context)) {
    await showAppModal<void>(
      context: context,
      child: builder(isModal: true),
    );
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (context) => builder(isModal: false)),
  );
}

Future<T?> showAppModal<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      return Dialog(
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.all(AppModalStyle.inset),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppModalStyle.radius),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(AppModalStyle.maxWidth, size.width - 48),
            maxHeight: min(AppModalStyle.maxHeight, size.height - 56),
          ),
          child: child,
        ),
      );
    },
  );
}

/// En-tête + corps pour une modale pleine (paramètres, bibliothèque Drive…).
class AppModalShell extends StatelessWidget {
  const AppModalShell({
    super.key,
    required this.title,
    required this.body,
    this.onClose,
  });

  final String title;
  final Widget body;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppModalStyle.padding,
            AppModalStyle.padding,
            8,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: onClose ?? () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(fit: FlexFit.loose, child: body),
      ],
    );
  }
}

/// Carte cliquable avec icône, titre, sous-titre et chevron.
class AppNavigationCard extends StatelessWidget {
  const AppNavigationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppModalStyle.padding,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Option de choix dans un dialogue (ex. dossier local / Drive).
class AppChoiceOption extends StatelessWidget {
  const AppChoiceOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppModalStyle.padding,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
