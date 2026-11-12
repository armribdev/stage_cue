import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'compact_switch.dart';

/// Briques communes de l'écran Paramètres : toutes les sections partagent le
/// même squelette (libellé en capitales, contenu, séparateur) et les mêmes
/// lignes de réglage, au lieu de recomposer titres, espacements et boutons
/// section par section. Direction « Console Linear » : pas de `Card`.

/// En-tête de section : icône + libellé en petites capitales, actions à droite.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing = const [],
  });

  final IconData icon;
  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Text(title.toUpperCase(), style: AppTextStyles.sectionLabel(context)),
        if (trailing.isNotEmpty) ...[const Spacer(), ...trailing],
      ],
    );
  }
}

/// Section à plat : [SettingsSectionHeader] puis son contenu.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    this.trailing = const [],
    required this.child,
  });

  final IconData icon;
  final String title;
  final List<Widget> trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(icon: icon, title: title, trailing: trailing),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

/// Intercale un séparateur entre les [sections] d'un écran.
List<Widget> separatedSettingsSections(List<Widget> sections) {
  return [
    for (var i = 0; i < sections.length; i++) ...[
      if (i > 0)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Divider(height: 1),
        ),
      sections[i],
    ],
  ];
}

/// Texte d'aide discret : explication ou état sous un réglage.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.color});

  final String text;

  /// Teinte de remplacement (erreur…) ; discrète par défaut.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: color ?? scheme.onSurfaceVariant),
    );
  }
}

/// Ligne de réglage : titre et explication à gauche, contrôle à droite
/// (interrupteur ou bouton). Le contenu éventuel de [below] se range sous le
/// texte, pleine largeur (barre de progression…).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.description,
    this.descriptionColor,
    this.trailing,
    this.below,
  });

  /// Ligne dont le contrôle est un interrupteur.
  SettingsRow.toggle({
    Key? key,
    required String title,
    String? description,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) : this(
         key: key,
         title: title,
         description: description,
         trailing: CompactSwitch(value: value, onChanged: onChanged),
       );

  final String title;
  final String? description;
  final Color? descriptionColor;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      SettingsNote(description!, color: descriptionColor),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                trailing!,
              ],
            ],
          ),
          if (below != null) ...[const SizedBox(height: AppSpacing.sm), below!],
        ],
      ),
    );
  }
}

/// Bouton d'action compact des Paramètres. Le thème global donne 42 px de haut
/// (et une largeur infinie à `Size.fromHeight`) : ici, un gabarit de ligne.
/// [busy] remplace l'icône par un indicateur et désactive le bouton.
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 34)),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
