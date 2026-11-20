import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/saved_multipad.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import '../widgets/app_modal.dart';
import '../widgets/color_swatch_picker.dart';
import '../widgets/pad_play_mode_selector.dart';
import '../widgets/sound_picker_overlay.dart';

/// Édition d'un multipad enregistré (décision 0051) : nom, couleur, mode de
/// lecture, sons et leur ordre. Contrairement aux détails d'un pad, rien ne
/// s'écrit à la volée : « Enregistrer » valide, « Annuler » abandonne. Aucun pad
/// posé sur un plateau n'est touché.
class SavedMultipadEditScreen extends StatefulWidget {
  final SamplerNotifier notifier;
  final SavedMultipad saved;
  final bool isModal;

  const SavedMultipadEditScreen({
    super.key,
    required this.notifier,
    required this.saved,
    this.isModal = false,
  });

  static Future<void> open(
    BuildContext context, {
    required SamplerNotifier notifier,
    required SavedMultipad saved,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => SavedMultipadEditScreen(
        notifier: notifier,
        saved: saved,
        isModal: isModal,
      ),
    );
  }

  @override
  State<SavedMultipadEditScreen> createState() =>
      _SavedMultipadEditScreenState();
}

class _SavedMultipadEditScreenState extends State<SavedMultipadEditScreen> {
  late final TextEditingController _nameController;
  late int? _colorValue;
  late PadPlayMode _playMode;

  /// Ids des sons dans l'ordre ; le sélecteur la modifie en place.
  late final List<int> _soundIds;

  /// Sons connus par id : ceux du modèle, puis ceux que le sélecteur ajoute
  /// (lus dans l'index de recherche).
  late final Map<int, Sound> _soundsById;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.saved;
    _nameController = TextEditingController(text: saved.name);
    _colorValue = saved.colorValue;
    _playMode = saved.playMode;
    _soundIds = [for (final sound in saved.sounds) sound.id];
    _soundsById = {for (final sound in saved.sounds) sound.id: sound};
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _nameController.text.trim().isNotEmpty &&
      _soundIds.isNotEmpty;

  Future<void> _addSounds() async {
    await SoundPickerOverlay.showForSelection(
      context,
      notifier: widget.notifier,
      selectedIds: _soundIds,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    // Les sons ajoutés viennent de l'index de recherche : on les y retrouve
    // pour les afficher.
    final snapshot = await widget.notifier.ensureSearchIndex();
    if (!mounted) return;
    setState(() {
      for (final sound in snapshot.sounds) {
        if (_soundIds.contains(sound.id)) _soundsById[sound.id] = sound;
      }
    });
  }

  void _removeSound(int soundId) {
    // Le dernier son reste : un modèle sans son ne se poserait nulle part.
    if (_soundIds.length <= 1) return;
    setState(() => _soundIds.remove(soundId));
  }

  void _reorder(int oldIndex, int newIndex) {
    // `onReorderItem` fournit déjà l'indice d'arrivée corrigé du retrait.
    setState(() => _soundIds.insert(newIndex, _soundIds.removeAt(oldIndex)));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await widget.notifier.updateSavedMultipad(
        widget.saved.id,
        name: _nameController.text.trim(),
        colorValue: _colorValue,
        clearColor: _colorValue == null,
        playMode: _playMode,
        soundIds: List<int>.of(_soundIds),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCopyableSnackBar(context, 'Enregistrement impossible : $error');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyMedium = Theme.of(context).textTheme.bodyMedium;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RÉGLAGES', style: AppTextStyles.sectionLabel(context)),
          const SizedBox(height: 16),
          Text('Nom', style: bodyMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Porte qui grince'),
          ),
          const SizedBox(height: 16),
          Text('Couleur du bouton', style: bodyMedium),
          const SizedBox(height: 8),
          ColorSwatchPicker(
            value: _colorValue,
            onChanged: (value) => setState(() => _colorValue = value),
          ),
          if (_soundIds.length > 1) ...[
            const SizedBox(height: 16),
            Text('Mode de lecture', style: bodyMedium),
            const SizedBox(height: 8),
            PadPlayModeSelector(
              value: _playMode,
              onChanged: (mode) => setState(() => _playMode = mode),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: Text('SONS', style: AppTextStyles.sectionLabel(context)),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_addSounds()),
                icon: const StrokeIcon(AppIcons.add, size: AppIconSize.sm),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            itemCount: _soundIds.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final id = _soundIds[index];
              final sound = _soundsById[id];
              return Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SoundTypeAvatar(
                      type: sound?.type,
                      colorValue: sound?.colorValue,
                      radius: 14,
                      iconSize: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sound?.displayName ?? 'Son #$id',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Retirer un son d'une liste n'est pas critique : croix
                    // discrète, pas de rouge (voir `ui.md`).
                    if (_soundIds.length > 1)
                      IconButton(
                        tooltip: 'Retirer',
                        onPressed: () => _removeSound(id),
                        icon: StrokeIcon(
                          AppIcons.close,
                          size: AppIconSize.sm,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    // Marge pour la poignée de glissement que la liste ajoute.
                    const SizedBox(width: 28),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
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
          // Boutons côte à côte : largeur minimale locale (voir `ui.md`).
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Annuler'),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(64, 42)),
            onPressed: _canSave ? () => unawaited(_save()) : null,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Multipad enregistré';
    final body = _buildBody(context);
    if (widget.isModal) {
      return AppModalShell(
        title: title,
        body: body,
        footer: _buildFooter(context),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: body,
      bottomNavigationBar: _buildFooter(context),
    );
  }
}
