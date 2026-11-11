import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_tokens.dart';

/// Une entrée d'un [AppSelect].
class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Sélecteur à choix unique de la direction "Console Linear".
///
/// Remplace `DropdownButtonFormField`, dont le champ et la liste (ombre,
/// ouverture en fondu/échelle, items de 48 px) lisent comme du Material par
/// défaut. Ici : un champ en retrait (fond `bg`, hairline, radius `md`, comme
/// un `TextField`) qui ouvre un menu `popupMenuTheme` de même largeur, aux items
/// denses ([AppMenu]), sans animation, avec l'option courante marquée d'une coche.
///
/// [T] peut être nullable (`String?`) : `null` est alors une valeur comme une
/// autre (ex. « Désactivé »). [value] absent des [options] affiche [fallbackLabel]
/// (ou rien).
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.fallbackLabel,
    this.leadingIcon,
  });

  final T value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// Libellé affiché quand [value] ne correspond à aucune option.
  final String? fallbackLabel;

  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = options.where((o) => o.value == value).firstOrNull;
    final label = selected?.label ?? fallbackLabel ?? '';

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.hasBoundedWidth ? box.maxWidth : null;
        // Enregistrement `({T value})` : un `null` nu comme valeur d'item serait
        // pris pour une annulation du menu et n'appellerait pas `onSelected`.
        return PopupMenuButton<({T value})>(
          tooltip: '',
          position: PopupMenuPosition.under,
          offset: const Offset(0, AppSpacing.xs),
          padding: EdgeInsets.zero,
          popUpAnimationStyle: AnimationStyle.noAnimation,
          constraints: width == null
              ? null
              : BoxConstraints.tightFor(width: width),
          onSelected: (choice) => onChanged(choice.value),
          itemBuilder: (_) => [
            for (final option in options)
              PopupMenuItem<({T value})>(
                value: (value: option.value),
                height: AppMenu.itemHeight,
                padding: AppMenu.itemPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: option.value == value
                              ? AppColors.accent
                              : null,
                          fontWeight: option.value == value
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                    ),
                    if (option.value == value)
                      const Icon(
                        AppIcons.check,
                        size: 16,
                        color: AppColors.accent,
                      ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: AppRadius.radiusMd,
              border: Border.fromBorderSide(AppElevation.border(scheme)),
            ),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  AppIcons.chevronDown,
                  size: 16,
                  color: AppColors.textDim,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
