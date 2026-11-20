import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Pièces communes des formulaires d'édition de la bibliothèque : celui d'un
/// son ([SoundEditForm]) et celui d'un multipad enregistré
/// ([SavedMultipadEditForm]) ont la même mise en page — en-tête au titre
/// éditable, sections, barre d'actions en pied.

/// Colonne de contenu (bornée et centrée) au-dessus d'une barre d'actions
/// pleine largeur : les boutons collent aux bords du volet au lieu de flotter
/// au milieu de la colonne.
class EditFormShell extends StatelessWidget {
  final List<Widget> content;
  final List<Widget> footer;

  const EditFormShell({super.key, required this.content, required this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: BoxDecoration(
            border: Border(top: AppElevation.border(scheme)),
          ),
          child: Row(children: footer),
        ),
      ],
    );
  }
}

/// Une section = libellé en petites capitales + contenu, puis un séparateur
/// (direction « Console Linear » : pas de `Card` autour d'une section).
class EditFormSection extends StatelessWidget {
  final String label;
  final Widget child;
  final bool isLast;

  /// Action au bout de la ligne du libellé (« Ajouter »…).
  final Widget? trailing;

  const EditFormSection({
    super.key,
    required this.label,
    required this.child,
    this.isLast = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label.toUpperCase(),
      style: AppTextStyles.sectionLabel(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trailing == null)
          labelText
        else
          Row(
            children: [
              Expanded(child: labelText),
              trailing!,
            ],
          ),
        const SizedBox(height: 8),
        child,
        if (!isLast) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// Titre de l'en-tête : le nom, éditable en place, sans cadre. Une seule ligne :
/// l'en-tête garde la même hauteur quel que soit le titre, sinon tout le
/// formulaire se décale d'un élément à l'autre. Champ vidé : [hintText] (en
/// indice) est ce qui sera enregistré.
class EditFormTitleField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const EditFormTitleField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  State<EditFormTitleField> createState() => _EditFormTitleFieldState();
}

class _EditFormTitleFieldState extends State<EditFormTitleField> {
  // Ne sert qu'à afficher la croix « effacer » tant que le titre est focus.
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: AppTypography.titleLetterSpacing,
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            onChanged: widget.onChanged,
            maxLines: 1,
            style: titleStyle,
            // Aucun cadre, même au focus : le thème global donne aux champs un
            // fond et un contour, ici on veut un simple texte éditable.
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: widget.hintText,
              hintStyle: titleStyle.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        // Croix « tout effacer » tant que le titre est focus.
        // TextFieldTapRegion : sur desktop, un appui hors du champ lui retire le
        // focus dès le pointeur-bas, donc la croix disparaîtrait avant le
        // relâchement. ExcludeFocus : le clic ne doit pas non plus prendre le
        // focus au champ.
        if (_focus.hasFocus && widget.controller.text.isNotEmpty)
          TextFieldTapRegion(
            child: ExcludeFocus(
              child: IconButton(
                tooltip: 'Effacer le nom',
                icon: const StrokeIcon(AppIcons.close, size: AppIconSize.sm),
                color: scheme.onSurfaceVariant,
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged('');
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Contenu de la section « Suppression » : explication à gauche, bouton à
/// droite. La confirmation et l'effet restent à l'appelant.
class EditFormDelete extends StatelessWidget {
  final String message;
  final bool busy;
  final VoidCallback? onPressed;

  const EditFormDelete({
    super.key,
    required this.message,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const StrokeIcon(AppIcons.delete, size: AppIconSize.sm),
          label: const Text('Supprimer…'),
        ),
      ],
    );
  }
}
