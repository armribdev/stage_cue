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

  /// File de traitement active (filtre « À traiter ») : le bouton d'un son non
  /// traité devient « Valider et suivant » et l'appelant enchaîne sur le son
  /// suivant dans [onSaved].
  final bool isQueueMode;

  /// Sons restant à traiter, affiché en pied de formulaire en file de
  /// traitement. `null` = pas de compteur.
  final int? queueRemaining;

  /// « Passer » : laisse ce son à traiter et ouvre le suivant. `null` = pas de
  /// bouton (pas de file, ou plus de son suivant).
  final VoidCallback? onSkip;

  const SoundEditForm({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.repository,
    this.notifier,
    this.onSaved,
    this.onDirtyChanged,
    this.isQueueMode = false,
    this.queueRemaining,
    this.onSkip,
    this.controller,
  });

  /// Permet à un raccourci clavier extérieur (Ctrl+Entrée) de déclencher
  /// l'enregistrement. Un `GlobalKey` ne conviendrait pas : le formulaire est
  /// recréé par son (clé de valeur) et un GlobalKey ferait réutiliser l'état.
  final SoundEditFormController? controller;

  @override
  State<SoundEditForm> createState() => _SoundEditFormState();
}

/// Poignée vers l'action « enregistrer » du [SoundEditForm] actuellement monté.
class SoundEditFormController {
  Future<void> Function()? _save;

  /// Enregistre le son affiché ; sans effet si aucun formulaire n'est monté ou
  /// s'il n'y a rien à enregistrer.
  Future<void> save() => _save?.call() ?? Future<void>.value();
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
  late final TextEditingController _nameController;
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
  bool _isMeasuringVolume = false;
  bool _wasDirty = false;

  /// Reflète `Sound.isProcessed`, passé à `true` dès le premier enregistrement
  /// (l'entité reçue en `widget.sound` n'est pas rafraîchie après coup).
  late bool _isProcessed;

  @override
  void initState() {
    super.initState();
    final sound = widget.sound;
    _isProcessed = sound.isProcessed;
    widget.controller?._save = save;
    _displayName = _baseDisplayName = sound.displayName;
    _nameController = TextEditingController(text: _displayName);
    _colorValue = _baseColorValue = sound.colorValue;
    _volume = _baseVolume = sound.volume.clamp(0.0, 1.0);
    _startOffsetMs = _baseStartOffsetMs = sound.startOffsetMs;
    _type = _baseType = sound.type;
    _waveform = sound.waveform;
    _loadTags();
  }

  @override
  void dispose() {
    // Le nouvel état (autre son) s'attache avant que celui-ci soit démonté :
    // ne détacher que si la poignée pointe encore sur nous.
    final controller = widget.controller;
    if (controller != null && controller._save == save) {
      controller._save = null;
    }
    _nameController.dispose();
    super.dispose();
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

  /// Nom à enregistrer : le champ vidé retombe sur le titre du fichier.
  String get _resolvedName {
    final trimmed = _displayName.trim();
    return trimmed.isEmpty ? widget.sound.title : trimmed;
  }

  /// Un son non traité s'enregistre même sans modification : « c'est bon tel
  /// quel » est une décision de traitement à part entière.
  bool get _canSave => !_isSaving && (_isDirty || !_isProcessed);

  /// Enregistre (et marque le son comme traité). Sans effet si rien à faire :
  /// appelable depuis un raccourci clavier extérieur.
  Future<void> save() async {
    if (!_canSave) return;
    await _save();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final repository = widget.repository;
      final id = widget.sound.id;
      final name = _resolvedName;
      await repository.updateSoundSettings(
        id: id,
        colorValue: _colorValue,
        updateColor: true,
        displayName: name,
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
        // Le champ affiche désormais le nom effectivement enregistré (le titre
        // du fichier s'il était vide).
        _displayName = name;
        if (_nameController.text != name) _nameController.text = name;
        _baseDisplayName = name;
        _baseColorValue = _colorValue;
        _baseVolume = _volume;
        _baseStartOffsetMs = _startOffsetMs;
        _baseType = _type;
        _baseTagIds = {..._tagIds};
        _isProcessed = true;
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

  /// Volume « auto » : mesure la sonie du fichier et règle le curseur pour la
  /// ramener à la sonie cible. N'enregistre rien — passe par `_update`, donc le
  /// formulaire devient « modifié » et l'opérateur peut ajuster avant de valider.
  Future<void> _applyAutoVolume() async {
    if (_isMeasuringVolume) return;
    final notifier = widget.notifier;
    if (notifier == null) return;
    setState(() => _isMeasuringVolume = true);
    try {
      final volume = await notifier.computeAutoVolume(widget.sound);
      if (!mounted) return;
      if (volume == null) {
        showCopyableSnackBar(
          context,
          'Mesure impossible (audio silencieux, format non pris en charge ou '
          'moteur audio non prêt).',
        );
        return;
      }
      _update(() => _volume = volume);
    } catch (error) {
      if (!mounted) return;
      showCopyableSnackBar(context, 'Échec de la mesure : $error');
    } finally {
      if (mounted) setState(() => _isMeasuringVolume = false);
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
                    _section('Point d\'entrée', _buildStartOffset(scheme)),
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
                children: [
                  if (widget.isQueueMode && widget.queueRemaining != null)
                    Text(
                      '${widget.queueRemaining} à traiter',
                      style: AppFonts.monoStyle(
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  const Spacer(),
                  if (widget.onSkip != null) ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: _isSaving ? null : widget.onSkip,
                      child: const Text('Passer'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: _canSave ? _save : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_saveLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _saveLabel {
    if (_isProcessed) return 'Enregistrer';
    return widget.isQueueMode ? 'Valider et suivant' : 'Valider';
  }

  /// Une section = libellé en petites capitales + contenu, puis un séparateur
  /// (direction « Console Linear » : pas de `Card` autour d'une section).
  Widget _section(String label, Widget child, {bool isLast = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.sectionLabel(context)),
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
        if (!_isProcessed) ...[
          const SizedBox(width: 12),
          _buildToProcessBadge(),
        ],
      ],
    );
  }

  /// Pastille « À traiter » : même repère que l'accent de la ligne dans la
  /// liste, pour relier visuellement les deux.
  Widget _buildToProcessBadge() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: AppRadius.radiusMd,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        'À TRAITER',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.primary,
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
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
        if (widget.notifier != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message:
                'Mesure la sonie du fichier et règle le volume pour '
                'normaliser',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _isMeasuringVolume ? null : _applyAutoVolume,
              child: _isMeasuringVolume
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Auto'),
            ),
          ),
        ],
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (widget.notifier != null)
              TextButton.icon(
                onPressed: _isRegeneratingWaveform ? null : _regenerateWaveform,
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null),
      ),
    );
  }

  Color _checkmarkColor(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}
