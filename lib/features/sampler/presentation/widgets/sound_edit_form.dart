import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import 'sound_type_picker.dart';
import 'start_offset_editor.dart';
import 'tag_chips_editor.dart';

/// Formulaire d'édition d'un son de la bibliothèque (nom, type, couleur,
/// volume, point d'entrée, tags).
///
/// Partagé par la page mobile ([SoundDetailsScreen]) et le volet de droite de
/// l'écran de gestion en mode scindé : un seul jeu de règles de sauvegarde.
///
/// À rendre avec une `key` dérivée de l'id du son — l'état local (champs,
/// baseline de modifications) est propre à un son.
class SoundEditForm extends StatefulWidget {
  final Sound sound;
  final List<TagCategoryWithTags> tagCatalog;
  final SoundRepository repository;
  final SamplerNotifier? notifier;

  /// Appelé après une sauvegarde réussie.
  final VoidCallback? onSaved;

  /// Notifié à chaque bascule « modifications non enregistrées ».
  final ValueChanged<bool>? onDirtyChanged;

  const SoundEditForm({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.repository,
    this.notifier,
    this.onSaved,
    this.onDirtyChanged,
  });

  @override
  State<SoundEditForm> createState() => _SoundEditFormState();
}

class _SoundEditFormState extends State<SoundEditForm> {
  static const List<Color> _defaultColorChoices = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];

  // Valeurs courantes.
  late String _displayName;
  late int? _colorValue;
  late double _volume;
  late int _startOffsetMs;
  late SoundType? _type;
  late Uint8List? _waveform;
  Set<int> _tagIds = <int>{};

  // Baseline = dernier état enregistré (ou chargé) ; sert à calculer `dirty`.
  late String _baseDisplayName;
  late int? _baseColorValue;
  late double _baseVolume;
  late int _baseStartOffsetMs;
  late SoundType? _baseType;
  Set<int> _baseTagIds = <int>{};

  bool _tagsLoaded = false;
  bool _tagsFailed = false;
  bool _isSaving = false;
  bool _isRegeneratingWaveform = false;
  bool _wasDirty = false;

  @override
  void initState() {
    super.initState();
    final sound = widget.sound;
    _displayName = _baseDisplayName = sound.displayName ?? '';
    _colorValue = _baseColorValue = sound.colorValue;
    _volume = _baseVolume = sound.volume.clamp(0.0, 1.0);
    _startOffsetMs = _baseStartOffsetMs = sound.startOffsetMs;
    _type = _baseType = sound.type;
    _waveform = sound.waveform;
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.repository.getTagsForSound(widget.sound.id);
      if (!mounted) return;
      setState(() {
        _tagIds = tags.map((t) => t.id).toSet();
        _baseTagIds = {..._tagIds};
        _tagsLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      // Formulaire utilisable sans tags plutôt que bloqué : enregistrer ne
      // touche aux tags que si le chargement a abouti (voir `_save`).
      setState(() => _tagsFailed = true);
      showCopyableSnackBar(context, 'Impossible de charger les tags : $error');
    }
  }

  bool get _isDirty =>
      _displayName.trim() != _baseDisplayName.trim() ||
      _colorValue != _baseColorValue ||
      _volume != _baseVolume ||
      _startOffsetMs != _baseStartOffsetMs ||
      _type != _baseType ||
      _tagIds.length != _baseTagIds.length ||
      !_tagIds.containsAll(_baseTagIds);

  /// `setState` + notification du parent quand l'état « modifié » bascule.
  void _update(VoidCallback change) {
    setState(change);
    final dirty = _isDirty;
    if (dirty != _wasDirty) {
      _wasDirty = dirty;
      widget.onDirtyChanged?.call(dirty);
    }
  }

  String? _normalizedOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final repository = widget.repository;
      final id = widget.sound.id;
      await repository.updateSoundSettings(
        id: id,
        colorValue: _colorValue,
        updateColor: true,
        displayName: _normalizedOrNull(_displayName),
        updateDisplayName: true,
        volume: _volume,
        startOffsetMs: _startOffsetMs,
        isProcessed: true,
      );
      if (_tagsLoaded) {
        await repository.setTagsForSound(id, _tagIds.toList());
      }
      final type = _type;
      if (type != null && type != _baseType) {
        await repository.updateSoundType(id, type);
      }
      await widget.notifier?.refreshSoundMetadata(id);
      if (!mounted) return;
      setState(() {
        _baseDisplayName = _displayName;
        _baseColorValue = _colorValue;
        _baseVolume = _volume;
        _baseStartOffsetMs = _startOffsetMs;
        _baseType = _type;
        _baseTagIds = {..._tagIds};
        _isSaving = false;
      });
      if (_wasDirty) {
        _wasDirty = false;
        widget.onDirtyChanged?.call(false);
      }
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showCopyableSnackBar(context, 'Erreur de sauvegarde : $error');
    }
  }

  Future<void> _regenerateWaveform() async {
    if (_isRegeneratingWaveform) return;
    final notifier = widget.notifier;
    if (notifier == null) return;
    setState(() => _isRegeneratingWaveform = true);
    try {
      final status = await notifier.regenerateWaveform(widget.sound);
      final updated = await widget.repository.getSoundById(widget.sound.id);
      if (!mounted) return;
      switch (status) {
        case WaveformProbeStatus.success:
          setState(() => _waveform = updated?.waveform ?? _waveform);
          showCopyableSnackBar(context, 'Waveform régénérée.');
        case WaveformProbeStatus.unsupported:
          showCopyableSnackBar(
            context,
            'Format non pris en charge pour l\'extraction de waveform.',
          );
        case WaveformProbeStatus.transient:
          showCopyableSnackBar(
            context,
            'Moteur audio non prêt — réessayez dans un instant.',
          );
      }
    } catch (error) {
      if (!mounted) return;
      showCopyableSnackBar(context, 'Échec de la régénération : $error');
    } finally {
      if (mounted) setState(() => _isRegeneratingWaveform = false);
    }
  }

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
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _section('Nom affiché', _buildNameField()),
                    _section(
                      'Type de son',
                      SoundTypePicker(
                        selected: _type,
                        onChanged: (type) => _update(() => _type = type),
                      ),
                    ),
                    _section('Couleur par défaut', _buildColors()),
                    _section('Volume par défaut', _buildVolume()),
                    _section(
                      'Point d\'entrée',
                      _buildStartOffset(scheme),
                    ),
                    _section('Tags', _buildTags(), isLast: true),
                  ],
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
          // Même largeur max et même centrage que le contenu, pour que le
          // bouton reste aligné sur le bord droit du formulaire.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: _isSaving || !_isDirty ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Une section = libellé en petites capitales + contenu, puis un séparateur
  /// (direction « Console Linear » : pas de `Card` autour d'une section).
  Widget _section(String label, Widget child, {bool isLast = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.sectionLabel(context),
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

  Widget _buildHeader() {
    return Row(
      children: [
        SoundTypeAvatar(
          type: _type,
          colorValue: _colorValue,
          radius: 24,
          iconSize: 24,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            widget.sound.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      initialValue: _displayName,
      onChanged: (v) => _update(() => _displayName = v),
      decoration: InputDecoration(hintText: widget.sound.title),
    );
  }

  Widget _buildColors() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _colorSwatch(
          label: 'D',
          color: null,
          isSelected: _colorValue == null,
          onTap: () => _update(() => _colorValue = null),
        ),
        for (final color in _defaultColorChoices)
          _colorSwatch(
            color: color,
            isSelected: _colorValue == color.toARGB32(),
            onTap: () => _update(() => _colorValue = color.toARGB32()),
          ),
      ],
    );
  }

  Widget _buildVolume() {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: _volume,
            min: 0.0,
            max: 1.0,
            label: '${(_volume * 100).round()}%',
            onChanged: (v) => _update(() => _volume = v.clamp(0.0, 1.0)),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(_volume * 100).round()}%',
            textAlign: TextAlign.end,
            style: AppFonts.monoStyle(const TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildStartOffset(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'La lecture démarre à ce point au lieu du début du fichier.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (widget.notifier != null)
              TextButton.icon(
                onPressed:
                    _isRegeneratingWaveform ? null : _regenerateWaveform,
                icon: _isRegeneratingWaveform
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Régénérer la waveform'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StartOffsetEditor(
          filePath: widget.sound.filePath,
          waveform: _waveform,
          initialOffsetMs: _startOffsetMs,
          onChanged: (ms) => _update(() => _startOffsetMs = ms),
        ),
      ],
    );
  }

  Widget _buildTags() {
    if (_tagsFailed) {
      return Text(
        'Tags indisponibles — réessayez en rouvrant le son.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    if (!_tagsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return TagChipsEditor(
      tagCatalog: widget.tagCatalog,
      selectedTagIds: _tagIds,
      onTagAdded: (id) => _update(() => _tagIds.add(id)),
      onTagRemoved: (id) => _update(() => _tagIds.remove(id)),
    );
  }

  Widget _colorSwatch({
    Color? color,
    required bool isSelected,
    required VoidCallback onTap,
    String? label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.surfaceContainerHighest;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveColor,
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 18,
                color: color == null
                    ? scheme.onSurfaceVariant
                    : _checkmarkColor(effectiveColor),
              )
            : (label != null
                ? Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  )
                : null),
      ),
    );
  }

  Color _checkmarkColor(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}
