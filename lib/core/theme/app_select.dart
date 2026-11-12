import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'app_tokens.dart';
import './stroke_icon.dart';

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

  final StrokeIconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => o.value == value).firstOrNull;
    final label = selected?.label ?? fallbackLabel ?? '';

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.hasBoundedWidth ? box.maxWidth : null;
        // Le survol global (blanc à 4 %) disparaît sur le fond `surface2` du
        // menu : on le renforce ici, le menu héritant du thème du bouton.
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(hoverColor: Colors.white.withValues(alpha: 0.08)),
          // Enregistrement `({T value})` : un `null` nu comme valeur d'item
          // serait pris pour une annulation du menu et n'appellerait pas
          // `onSelected`.
          child: PopupMenuButton<({T value})>(
            tooltip: '',
            // L'`InkWell` du bouton peint son survol en rectangle : sans rayon,
            // ses coins carrés dépassent derrière le champ arrondi.
            borderRadius: AppRadius.radiusMd,
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
                        const StrokeIcon(
                          AppIcons.check,
                          size: 16,
                          color: AppColors.accent,
                        ),
                    ],
                  ),
                ),
            ],
            child: _SelectField(label: label, leadingIcon: leadingIcon),
          ),
        );
      },
    );
  }
}

/// Champ fermé d'un [AppSelect]. Le survol est peint ici, pas par l'`InkWell`
/// du `PopupMenuButton` : le fond opaque du champ recouvrirait son encre.
class _SelectField extends StatefulWidget {
  const _SelectField({required this.label, required this.leadingIcon});

  final String label;
  final StrokeIconData? leadingIcon;

  @override
  State<_SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<_SelectField> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          // `surface` et non `bg` : sur l'écran Paramètres (fond `bg`) un champ
          // en `bg` se confondait avec la page ; dans un dialogue (`surface2`)
          // `surface` reste en retrait.
          color: _hovered ? AppColors.surface2 : AppColors.surface,
          borderRadius: AppRadius.radiusMd,
          border: Border.fromBorderSide(
            _hovered
                ? AppElevation.borderStrong(scheme)
                : AppElevation.border(scheme),
          ),
        ),
        child: Row(
          children: [
            if (widget.leadingIcon case final leadingIcon?) ...[
              StrokeIcon(leadingIcon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const StrokeIcon(
              AppIcons.chevronDown,
              size: 16,
              color: AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}
