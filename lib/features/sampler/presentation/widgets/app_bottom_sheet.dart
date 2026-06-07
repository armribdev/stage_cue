import 'package:flutter/material.dart';

/// Constantes partagées pour les tiroirs du bas (sélection de sons, régie…).
abstract final class AppBottomSheetStyle {
  static const double initialChildSize = 0.75;
  static const double minChildSize = 0.45;
  static const double maxChildSize = 0.92;
  static const EdgeInsets titlePadding = EdgeInsets.fromLTRB(20, 0, 20, 4);
}

/// Ouvre un tiroir du bas avec le style unifié de l'app.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: scheme.surfaceContainerLow,
    builder: (context) => child,
  );
}

/// Structure commune : titre, zone fixe optionnelle, contenu scrollable.
class AppBottomSheetShell extends StatelessWidget {
  const AppBottomSheetShell({
    super.key,
    required this.title,
    required this.bodyBuilder,
    this.leadingIcon,
    this.header,
    this.initialChildSize = AppBottomSheetStyle.initialChildSize,
    this.minChildSize = AppBottomSheetStyle.minChildSize,
    this.maxChildSize = AppBottomSheetStyle.maxChildSize,
  });

  final String title;
  final IconData? leadingIcon;
  final Widget? header;
  final Widget Function(BuildContext context, ScrollController scrollController)
      bodyBuilder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppBottomSheetTitle(
                title: title,
                leadingIcon: leadingIcon,
              ),
              ?header,
              Expanded(
                child: bodyBuilder(context, scrollController),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppBottomSheetTitle extends StatelessWidget {
  const _AppBottomSheetTitle({
    required this.title,
    this.leadingIcon,
  });

  final String title;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );

    if (leadingIcon == null) {
      return Padding(
        padding: AppBottomSheetStyle.titlePadding,
        child: Text(title, style: style),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: AppBottomSheetStyle.titlePadding,
      child: Row(
        children: [
          Icon(leadingIcon, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: style)),
        ],
      ),
    );
  }
}
