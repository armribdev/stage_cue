import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/layout_utils.dart';
import '../widgets/animated_pill_wrap.dart';
import '../widgets/app_form_dialog.dart';
import '../widgets/app_modal.dart';
import '../widgets/color_swatch_picker.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import '../widgets/pad_hotkey_field.dart';
import '../widgets/pad_play_mode_selector.dart';
import '../widgets/pad_sound_row.dart';
import '../widgets/sound_picker_overlay.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Écran de détails d'un pad — réglages, sons, mode de lecture.
class PadDetailsScreen extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;
  final AppPreferences appPreferences;
  final bool isModal;

  const PadDetailsScreen({
    super.key,
    required this.padItem,
    required this.notifier,
    required this.appPreferences,
    this.isModal = false,
  });

  /// Page plein écran sur téléphone, fenêtre modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required PadItem padItem,
    required SamplerNotifier notifier,
    required AppPreferences appPreferences,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => PadDetailsScreen(
        padItem: padItem,
        notifier: notifier,
        appPreferences: appPreferences,
        isModal: isModal,
      ),
    );
  }

  @override
  State<PadDetailsScreen> createState() => _PadDetailsScreenState();
}

class _PadDetailsScreenState extends State<PadDetailsScreen> {
  late int? _selectedColorValue;
  late PadPlayMode _playMode;
  late final TextEditingController _displayNameController;
  Timer? _displayNameDebounce;
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isTagsLoading = true;

  @override
  void initState() {
    super.initState();
    final pad = widget.padItem.pad;
    _selectedColorValue = pad.colorValue;
    _playMode = pad.playMode;
    _displayNameController = TextEditingController(text: pad.name ?? '');
    _loadTagCatalog();
  }

  @override
  void dispose() {
    _displayNameDebounce?.cancel();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadTagCatalog() async {
    final catalog = await widget.notifier.loadTagCatalog();
    if (!mounted) return;
    setState(() {
      _tagCatalog = catalog;
      _isTagsLoading = false;
    });
  }

  void _updateColor(int? colorValue) {
    setState(() => _selectedColorValue = colorValue);
    widget.notifier.updatePadItemSettings(
      widget.padItem,
      buttonColor: colorValue != null ? Color(colorValue) : null,
      updateColor: true,
    );
  }

  void _updatePlayMode(PadPlayMode mode) {
    setState(() => _playMode = mode);
    widget.notifier.updatePadItemSettings(widget.padItem, playMode: mode);
  }

  Future<void> _updateDisplayName() async {
    if (!mounted) return;
    final trimmed = _displayNameController.text.trim();
    await widget.notifier.updatePadItemSettings(
      widget.padItem,
      displayName: trimmed.isEmpty ? null : trimmed,
      updateDisplayName: true,
    );
  }

  void _scheduleDisplayNameUpdate(String _) {
    _displayNameDebounce?.cancel();
    _displayNameDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _updateDisplayName();
    });
  }

  Future<void> _addSound(BuildContext ctx) async {
    await SoundPickerOverlay.showForPad(
      ctx,
      notifier: widget.notifier,
      padId: widget.padItem.pad.id,
      onPadUpdated: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  /// Enregistre une copie du multipad dans la bibliothèque (décision 0051) :
  /// nom, couleur, mode de lecture et sons, sans lien avec ce pad ensuite.
  Future<void> _saveToLibrary() async {
    // Couleur et mode de lecture s'écrivent sur le pad dès qu'on les change :
    // `pad` est à jour. Le nom, lui, est débouncé — on part du champ affiché.
    final pad = widget.padItem.pad;
    final shownName = _displayNameController.text.trim();
    final name = await AppTextInputDialog.show(
      context,
      title: 'Enregistrer dans la bibliothèque',
      confirmLabel: 'Enregistrer',
      initialValue: shownName.isEmpty ? null : shownName,
      hint: widget.padItem.displayName,
      icon: AppIcons.text,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    try {
      await widget.notifier.saveMultipadToLibrary(pad, name: trimmed);
    } catch (error) {
      if (mounted) {
        showCopyableSnackBar(context, 'Enregistrement impossible : $error');
      }
      return;
    }
    if (!mounted) return;
    AppSnackBar.show(
      context,
      'Multipad « $trimmed » enregistré dans la bibliothèque.',
      severity: AppToastSeverity.success,
    );
  }

  Future<void> _removeSound(int soundId) async {
    await widget.notifier.removeSoundFromPad(widget.padItem.pad.id, soundId);
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildBody(BuildContext context) {
    final pad = widget.padItem.pad;
    final sounds = pad.sounds;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Réglages du pad ──────────────────────────────────────────
          // Pas de Card : la maquette pose la section à plat (label +
          // champs), une carte ici lirait comme un "Card-in-dialog" M3.
          Text('RÉGLAGES', style: AppTextStyles.sectionLabel(context)),
          const SizedBox(height: 16),
          Text('Nom affiché', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _displayNameController,
            decoration: InputDecoration(
              hintText: widget.padItem.displayName,
              suffixIcon: _displayNameController.text.isNotEmpty
                  ? IconButton(
                      icon: const StrokeIcon(AppIcons.close),
                      onPressed: () {
                        setState(() => _displayNameController.clear());
                        _updateDisplayName();
                      },
                    )
                  : null,
            ),
            textInputAction: TextInputAction.done,
            onChanged: (v) {
              setState(() {});
              _scheduleDisplayNameUpdate(v);
            },
            onSubmitted: (_) => _updateDisplayName(),
          ),
          const SizedBox(height: 16),
          Text(
            'Couleur du bouton',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          ColorSwatchPicker(
            value: _selectedColorValue,
            onChanged: _updateColor,
          ),
          if (sounds.length > 1) ...[
            const SizedBox(height: 16),
            Text(
              'Mode de lecture',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            PadPlayModeSelector(value: _playMode, onChanged: _updatePlayMode),
          ],

          if (isNativeDesktopPlatform()) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(height: 1),
            ),

            // ── Raccourci clavier ──────────────────────────────────────
            Text(
              'RACCOURCI CLAVIER',
              style: AppTextStyles.sectionLabel(context),
            ),
            const SizedBox(height: 16),
            PadHotkeyField(
              appPreferences: widget.appPreferences,
              notifier: widget.notifier,
              padId: widget.padItem.pad.id,
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1),
          ),

          // ── Sons du pad ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'SONS DU PAD',
                  style: AppTextStyles.sectionLabel(context),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addSound(context),
                icon: const StrokeIcon(AppIcons.add, size: AppIconSize.sm),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sounds.isEmpty)
            Text('Aucun son', style: Theme.of(context).textTheme.bodyMedium),
          // Toujours montée, même vide : le premier son ajouté s'ouvre comme
          // les suivants au lieu de remplacer le texte d'un coup.
          ListenableBuilder(
            listenable: widget.notifier,
            builder: (context, _) {
              // Relue ici : un réordonnancement remplace la liste du pad sans
              // reconstruire l'écran.
              final sounds = widget.padItem.pad.sounds;
              return AnimatedRevealColumn(
                // Souris : clic maintenu puis glisser ; tactile : appui long,
                // pour ne pas détourner le défilement de l'écran.
                delayedDrag: !context.prefersDesktopUi,
                onReorder: (oldIndex, newIndex) => unawaited(
                  widget.notifier.reorderPadSounds(
                    widget.padItem.pad.id,
                    oldIndex,
                    newIndex,
                  ),
                ),
                entries: [
                  for (var i = 0; i < sounds.length; i++)
                    PillEntry(
                      ValueKey(sounds[i].id),
                      PadSoundRow(
                        padItem: widget.padItem,
                        slotIndex: i,
                        sound: sounds[i],
                        canRemove: sounds.length > 1,
                        tagCatalog: _tagCatalog,
                        isTagsLoading: _isTagsLoading,
                        notifier: widget.notifier,
                        onRemove: () => _removeSound(sounds[i].id),
                      ),
                    ),
                ],
              );
            },
          ),

          // Un seul son : un pad ordinaire, rien à enregistrer comme modèle.
          if (sounds.length > 1) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(_saveToLibrary()),
                icon: const StrokeIcon(AppIcons.library, size: AppIconSize.sm),
                label: const Text('Enregistrer dans la bibliothèque'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    if (widget.isModal) {
      return AppModalShell(
        title: 'Détails du pad',
        body: body,
        footer: _buildFooterActions(context),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du pad')),
      body: body,
      bottomNavigationBar: _buildFooterActions(context),
    );
  }

  // Chaque champ s'enregistre déjà tout seul à la volée (debounce sur le nom,
  // effet immédiat sur couleur/mode/volume) : "Annuler" et "Enregistrer" ne
  // font donc que fermer l'écran — pas d'état "brouillon" à annuler ou à
  // committer séparément. Ajouté uniquement pour l'affordance visuelle
  // attendue (cf. maquette) ; zéro changement de logique d'enregistrement.
  Widget _buildFooterActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: AppElevation.border(scheme)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Annuler'),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
