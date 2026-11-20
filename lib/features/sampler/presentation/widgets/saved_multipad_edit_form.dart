import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/logging/app_log.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/layout_utils.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/saved_multipad.dart';
import '../../domain/entities/sound.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import 'app_form_dialog.dart';
import 'color_swatch_picker.dart';
import 'animated_pill_wrap.dart';
import 'edit_form_parts.dart';
import 'pad_play_mode_selector.dart';
import 'sound_picker_overlay.dart';

/// Formulaire d'édition d'un multipad enregistré dans la bibliothèque (décision
/// 0051) : nom, couleur, mode de lecture, sons et leur ordre.
///
/// Même mise en page que [SoundEditForm] (mêmes pièces : en-tête, sections,
/// barre d'actions), sans waveform ni gain — un multipad n'a pas de niveau
/// propre, seulement la liste de ses sons. Partagé par la page mobile
/// ([SavedMultipadDetailsScreen]) et le volet de droite de la gestion de la
/// bibliothèque.
///
/// Rien ne s'écrit à la volée : « Enregistrer » valide. Aucun pad posé sur un
/// plateau n'est touché (c'est une copie).
///
/// À rendre avec une `key` dérivée de l'id du modèle — l'état local (champs,
/// baseline de modifications) est propre à un modèle.
class SavedMultipadEditForm extends StatefulWidget {
  final SamplerNotifier notifier;
  final SavedMultipad saved;

  final VoidCallback? onSaved;

  /// Notifié à chaque bascule « modifications non enregistrées ».
  final ValueChanged<bool>? onDirtyChanged;

  /// Notifié quand le modèle a été supprimé : le formulaire n'a plus d'objet,
  /// l'appelant le ferme et rafraîchit sa liste.
  final VoidCallback? onDeleted;

  const SavedMultipadEditForm({
    super.key,
    required this.notifier,
    required this.saved,
    this.onSaved,
    this.onDirtyChanged,
    this.onDeleted,
  });

  @override
  State<SavedMultipadEditForm> createState() => _SavedMultipadEditFormState();
}

class _SavedMultipadEditFormState extends State<SavedMultipadEditForm> {
  late final TextEditingController _nameController;
  late int? _colorValue;
  late PadPlayMode _playMode;

  /// Ids des sons dans l'ordre ; le sélecteur la modifie en place.
  late final List<int> _soundIds;

  /// Sons connus par id : ceux du modèle, puis ceux que le sélecteur ajoute
  /// (lus dans l'index de recherche).
  late final Map<int, Sound> _soundsById;

  // Baseline = dernier état enregistré (ou chargé) ; sert à calculer `dirty`.
  late String _baseName;
  late int? _baseColorValue;
  late PadPlayMode _basePlayMode;
  late List<int> _baseSoundIds;

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _wasDirty = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.saved;
    _baseName = saved.name;
    _nameController = TextEditingController(text: saved.name);
    _colorValue = _baseColorValue = saved.colorValue;
    _playMode = _basePlayMode = saved.playMode;
    _soundIds = [for (final sound in saved.sounds) sound.id];
    _baseSoundIds = List<int>.of(_soundIds);
    _soundsById = {for (final sound in saved.sounds) sound.id: sound};
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _nameController.text.trim() != _baseName.trim() ||
      _colorValue != _baseColorValue ||
      _playMode != _basePlayMode ||
      !_sameIds(_soundIds, _baseSoundIds);

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Un modèle sans nom ou sans son ne se retrouverait ni ne se poserait.
  bool get _canSave =>
      !_isSaving &&
      _isDirty &&
      _nameController.text.trim().isNotEmpty &&
      _soundIds.isNotEmpty;

  /// `setState` + notification du parent quand l'état « modifié » bascule.
  void _update(VoidCallback change) {
    setState(change);
    final dirty = _isDirty;
    if (dirty != _wasDirty) {
      _wasDirty = dirty;
      widget.onDirtyChanged?.call(dirty);
    }
  }

  Future<void> _addSounds() async {
    await SoundPickerOverlay.showForSelection(
      context,
      notifier: widget.notifier,
      selectedIds: _soundIds,
      onChanged: () {
        if (mounted) _update(() {});
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
    _update(() => _soundIds.remove(soundId));
  }

  void _reorder(int oldIndex, int newIndex) {
    // `onReorderItem` fournit déjà l'indice d'arrivée corrigé du retrait.
    _update(() => _soundIds.insert(newIndex, _soundIds.removeAt(oldIndex)));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    final name = _nameController.text.trim();
    try {
      await widget.notifier.updateSavedMultipad(
        widget.saved.id,
        name: name,
        colorValue: _colorValue,
        clearColor: _colorValue == null,
        playMode: _playMode,
        soundIds: List<int>.of(_soundIds),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showCopyableSnackBar(context, 'Enregistrement impossible : $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _baseName = name;
      _baseColorValue = _colorValue;
      _basePlayMode = _playMode;
      _baseSoundIds = List<int>.of(_soundIds);
      _isSaving = false;
    });
    if (_wasDirty) {
      _wasDirty = false;
      widget.onDirtyChanged?.call(false);
    }
    widget.onSaved?.call();
  }

  /// Supprime le modèle après confirmation. Les pads déjà posés sur les
  /// plateaux n'en dépendent pas.
  Future<void> _delete() async {
    if (_isDeleting || _isSaving) return;
    final name = _nameController.text.trim().isEmpty
        ? _baseName
        : _nameController.text.trim();
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer le multipad enregistré',
      message:
          '« $name » sera retiré de la bibliothèque. Les pads déjà posés sur '
          'vos plateaux ne changent pas.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      await widget.notifier.deleteSavedMultipad(widget.saved.id);
    } catch (error, stack) {
      AppLog.warn(
        'Suppression du multipad ${widget.saved.id} échouée : $error\n$stack',
      );
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showCopyableSnackBar(context, 'Suppression impossible : $error');
      return;
    }
    if (!mounted) return;
    if (_wasDirty) {
      _wasDirty = false;
      widget.onDirtyChanged?.call(false);
    }
    widget.onDeleted?.call();
  }

  /// Type commun des sons actuels (avatar de l'en-tête) ; `null` si mixte.
  SoundType? get _commonType {
    final types = {for (final id in _soundIds) _soundsById[id]?.type};
    return types.length == 1 ? types.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return EditFormShell(
      content: [
        _buildHeader(),
        const SizedBox(height: 20),
        EditFormSection(
          label: 'Couleur du bouton',
          child: ColorSwatchPicker(
            value: _colorValue,
            onChanged: (value) => _update(() => _colorValue = value),
          ),
        ),
        // Clés : la section « Mode de lecture » apparaît et disparaît avec le
        // nombre de sons. Sans elles, « Sons » changerait de rang et perdrait
        // son état (donc l'animation en cours de ses lignes).
        if (_soundIds.length > 1)
          EditFormSection(
            key: const ValueKey('play-mode'),
            label: 'Mode de lecture',
            child: PadPlayModeSelector(
              value: _playMode,
              onChanged: (mode) => _update(() => _playMode = mode),
            ),
          ),
        EditFormSection(
          key: const ValueKey('sounds'),
          label: 'Sons',
          trailing: TextButton.icon(
            onPressed: () => unawaited(_addSounds()),
            icon: const StrokeIcon(AppIcons.add, size: AppIconSize.sm),
            label: const Text('Ajouter'),
          ),
          child: _buildSounds(),
        ),
        EditFormSection(
          label: 'Suppression',
          isLast: true,
          child: EditFormDelete(
            message:
                'Retire ce multipad de la bibliothèque. Les pads déjà posés '
                'sur vos plateaux ne changent pas.',
            busy: _isDeleting || _isSaving,
            onPressed: () => unawaited(_delete()),
          ),
        ),
      ],
      footer: [
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(64, 42),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          onPressed: _canSave ? () => unawaited(_save()) : null,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        SoundTypeAvatar(
          type: _commonType,
          colorValue: _colorValue,
          radius: 24,
          iconSize: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: EditFormTitleField(
            controller: _nameController,
            hintText: 'Nom du multipad',
            onChanged: (_) => _update(() {}),
          ),
        ),
      ],
    );
  }

  /// Les sons dans l'ordre. Un son ajouté s'ouvre, un son retiré se referme
  /// avant de quitter la liste ([AnimatedRevealColumn], comme les sons d'un
  /// pad) ; la ligne entière se glisse (immédiat à la souris, après un appui
  /// long au doigt).
  Widget _buildSounds() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedRevealColumn(
      delayedDrag: !context.prefersDesktopUi,
      onReorder: _reorder,
      entries: [
        for (final id in _soundIds)
          PillEntry(
            ValueKey(id),
            Padding(
              // Marge à gauche seulement : à droite, la croix a déjà la sienne.
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 6, 0, 6),
              child: Row(
                children: [
                  SoundTypeAvatar(
                    type: _soundsById[id]?.type,
                    colorValue: _soundsById[id]?.colorValue,
                    radius: 14,
                    iconSize: 16,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _soundsById[id]?.displayName ?? 'Son #$id',
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
                ],
              ),
            ),
          ),
      ],
    );
  }
}
