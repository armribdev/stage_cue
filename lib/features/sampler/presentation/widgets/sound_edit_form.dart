import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/autotag/auto_tag_analysis.dart';
import '../../../../core/autotag/auto_tag_status.dart';
import '../../../../core/logging/app_log.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_auto_tag.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import 'auto_tag_chips.dart';
import 'auto_tag_status_row.dart';
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

  final VoidCallback? onSaved;

  /// Notifié à chaque bascule « modifications non enregistrées ».
  final ValueChanged<bool>? onDirtyChanged;

  /// Notifié quand « Marquer non traité » a été écrit en base — l'appelant
  /// rafraîchit sa liste. Distinct de [onSaved] : pas d'enchaînement sur le
  /// son suivant.
  final VoidCallback? onMarkedUnprocessed;

  /// Notifié après la bascule du favori (écrit en base immédiatement, hors du
  /// cycle « modifier puis enregistrer ») — l'appelant rafraîchit sa liste.
  final ValueChanged<bool>? onFavoriteChanged;

  /// File de traitement active : « Passer » apparaît en pied de formulaire, et
  /// l'appelant enchaîne sur le son suivant dans [onSaved].
  final bool isQueueMode;

  /// « Passer » : laisse ce son à traiter et ouvre le suivant. `null` = pas de
  /// bouton (pas de file, ou plus de son suivant).
  final VoidCallback? onSkip;

  /// Fait jouer l'éditeur de point d'entrée dès l'ouverture du son (lecture auto
  /// de la file de traitement).
  final bool autoPlayEntryPoint;

  /// État et déclenchement de l'analyse IA des tags ; `null` = fonction absente
  /// (mobile) : la zone d'état n'est pas affichée.
  final AutoTagAnalysis? autoTag;

  const SoundEditForm({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.repository,
    this.notifier,
    this.autoTag,
    this.onSaved,
    this.onDirtyChanged,
    this.onMarkedUnprocessed,
    this.onFavoriteChanged,
    this.isQueueMode = false,
    this.onSkip,
    this.autoPlayEntryPoint = false,
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

  /// Suggestions de l’IA (décision 0031) : lecture seule. En accepter une
  /// l’ajoute à [_tagIds], donc à la baseline `dirty` comme tout autre tag.
  List<SoundAutoTag> _autoTags = const [];

  /// Où en est l'analyse IA de ce son (`null` = inconnu ou fonction absente).
  SoundAnalysisStatus? _analysisStatus;

  /// L'utilisateur a cliqué « Analyser » et le passage n'est pas fini : le son
  /// s'affiche « en attente » même si le passage n'a pas encore bâti sa file.
  bool _analysisRequested = false;
  SoundAnalysisStatus? _lastLiveStatus;
  bool _lastRunning = false;

  bool _tagsLoaded = false;
  bool _tagsFailed = false;
  bool _isSaving = false;
  bool _isRegeneratingWaveform = false;

  /// Vrai brièvement après une régénération réussie : le bouton affiche une
  /// coche + « Waveform régénérée » avant de reprendre son libellé normal.
  bool _waveformRegenerated = false;
  Timer? _regeneratedResetTimer;
  static const _regeneratedFeedbackDuration = Duration(seconds: 2);
  bool _isMeasuringVolume = false;
  bool _wasDirty = false;

  /// Reflète `Sound.isProcessed`, passé à `true` dès le premier enregistrement
  /// (l'entité reçue en `widget.sound` n'est pas rafraîchie après coup).
  late bool _isProcessed;

  /// Favori : écrit en base dès le tap, donc hors baseline `dirty`.
  late bool _isFavorite;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    final sound = widget.sound;
    _isProcessed = sound.isProcessed;
    _isFavorite = sound.isFavorite;
    widget.controller?._save = save;
    _displayName = _baseDisplayName = sound.displayName;
    _nameController = TextEditingController(text: _displayName);
    _colorValue = _baseColorValue = sound.colorValue;
    _volume = _baseVolume = sound.volume.clamp(0.0, 1.0);
    _startOffsetMs = _baseStartOffsetMs = sound.startOffsetMs;
    _type = _baseType = sound.type;
    _waveform = sound.waveform;
    _loadTags();
    final autoTag = widget.autoTag;
    if (autoTag != null) {
      final activity = autoTag.activity.value;
      _lastRunning = activity.running;
      _lastLiveStatus = activity.liveStatusOf(sound.id);
      autoTag.activity.addListener(_onAnalysisActivity);
      unawaited(_refreshAnalysis());
    }
  }

  /// Le passage d'analyse a bougé : on ne relit l'état que si cela concerne ce
  /// son (son tour, sa file) ou si le passage vient de se terminer — il vient
  /// alors d'écrire ses empreintes et ses suggestions.
  void _onAnalysisActivity() {
    final activity = widget.autoTag?.activity.value;
    if (activity == null) return;
    final live = activity.liveStatusOf(widget.sound.id);
    final changed = live != _lastLiveStatus || activity.running != _lastRunning;
    final finished = _lastRunning && !activity.running;
    _lastLiveStatus = live;
    _lastRunning = activity.running;
    if (changed) unawaited(_refreshAnalysis(reloadSuggestions: finished));
  }

  Future<void> _refreshAnalysis({bool reloadSuggestions = false}) async {
    final autoTag = widget.autoTag;
    if (autoTag == null) return;
    try {
      final status = await autoTag.statusOf(widget.sound.id);
      final suggestions = reloadSuggestions
          ? await widget.repository.getAutoTagsForSound(widget.sound.id)
          : null;
      if (!mounted) return;
      final finishedRequest =
          _analysisRequested && !autoTag.activity.value.running;
      setState(() {
        _analysisStatus = status;
        if (suggestions != null) _autoTags = suggestions;
        if (finishedRequest) _analysisRequested = false;
      });
      // Le passage est fini et le son n'a pas été pris : ne pas laisser le clic
      // sans réponse.
      if (finishedRequest && status == SoundAnalysisStatus.pending) {
        showCopyableSnackBar(
          context,
          'Analyse non faite pour ce son : son fichier n’est sans doute pas '
          'encore téléchargé sur cet appareil, ou l’analyse a été interrompue.',
        );
      }
    } catch (error) {
      AppLog.warn(
        'État de l’analyse IA illisible (son ${widget.sound.id}) : $error',
      );
    }
  }

  void _startAnalysis() {
    final autoTag = widget.autoTag;
    if (autoTag == null || _analysisRequested) return;
    final refusal = autoTag.start(widget.sound.id);
    if (refusal != null) {
      showCopyableSnackBar(
        context,
        'Analyse impossible pour l’instant : $refusal.',
      );
      return;
    }
    setState(() => _analysisRequested = true);
  }

  @override
  void dispose() {
    widget.autoTag?.activity.removeListener(_onAnalysisActivity);
    // Le nouvel état (autre son) s'attache avant que celui-ci soit démonté :
    // ne détacher que si la poignée pointe encore sur nous.
    final controller = widget.controller;
    if (controller != null && controller._save == save) {
      controller._save = null;
    }
    _regeneratedResetTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await widget.repository.getTagsForSound(widget.sound.id);
      if (!mounted) return;
      // Les tags de l’IA sont facultatifs : un échec de lecture ne bloque rien.
      var auto = const <SoundAutoTag>[];
      try {
        auto = await widget.repository.getAutoTagsForSound(widget.sound.id);
      } catch (error) {
        AppLog.warn(
          'Tags de l’IA illisibles (son ${widget.sound.id}) : $error',
        );
      }
      if (!mounted) return;
      setState(() {
        _tagIds = tags.map((t) => t.id).toSet();
        _baseTagIds = {..._tagIds};
        _autoTags = auto;
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
      // Type ou « traité » ont pu changer : l'éligibilité à l'analyse aussi.
      unawaited(_refreshAnalysis());
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showCopyableSnackBar(context, 'Erreur de sauvegarde : $error');
    }
  }

  /// Remet le son dans la file « à traiter ». N'écrit que ce drapeau : les
  /// modifications en cours dans le formulaire restent à enregistrer.
  Future<void> _markUnprocessed() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.repository.updateSoundSettings(
        id: widget.sound.id,
        isProcessed: false,
      );
      if (!mounted) return;
      setState(() {
        _isProcessed = false;
        _isSaving = false;
      });
      unawaited(_refreshAnalysis());
      widget.onMarkedUnprocessed?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showCopyableSnackBar(context, 'Erreur : $error');
    }
  }

  /// Bascule le favori et l'écrit tout de suite : un tap sur l'étoile n'est pas
  /// une « modification » à valider avec le reste du formulaire.
  Future<void> _toggleFavorite() async {
    final notifier = widget.notifier;
    if (notifier == null || _isTogglingFavorite) return;
    setState(() => _isTogglingFavorite = true);
    try {
      final next = await notifier.toggleSoundFavorite(widget.sound.id);
      if (!mounted) return;
      setState(() => _isFavorite = next);
      widget.onFavoriteChanged?.call(next);
    } catch (error) {
      AppLog.warn(
        'Bascule du favori échouée (son ${widget.sound.id}) : $error',
      );
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        'Impossible de modifier le favori : $error',
      );
    } finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  /// Change le volume du formulaire et le répercute en direct sur l'aperçu
  /// bibliothèque en cours (l'éditeur de point d'entrée suit via son `volume`).
  void _setVolume(double value) {
    final volume = value.clamp(0.0, 1.0);
    _update(() => _volume = volume);
    widget.notifier?.setLibraryPreviewVolume(widget.sound.id, volume);
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
      _setVolume(volume);
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
          // Confirmation sur le bouton lui-même (coche) plutôt qu'en snackbar.
          setState(() {
            _waveform = updated?.waveform ?? _waveform;
            _waveformRegenerated = true;
          });
          _regeneratedResetTimer?.cancel();
          _regeneratedResetTimer = Timer(_regeneratedFeedbackDuration, () {
            if (mounted) setState(() => _waveformRegenerated = false);
          });
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
          // Barre pleine largeur du volet (comme son filet) : les boutons
          // collent aux bords au lieu de flotter au milieu de la colonne.
          child: Row(
            children: [
              if (_isProcessed)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  onPressed: _isSaving ? null : _markUnprocessed,
                  child: const Text('Marquer non traité'),
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
      ],
    );
  }

  String get _saveLabel => _isProcessed ? 'Enregistrer' : 'Valider';

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
    final scheme = Theme.of(context).colorScheme;
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
          // Une seule ligne : l'en-tête garde la même hauteur quel que soit le
          // titre, sinon tout le formulaire se décale d'un son à l'autre. Le
          // titre complet reste lisible au survol.
          child: Tooltip(
            message: widget.sound.title,
            child: Text(
              widget.sound.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (widget.notifier != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: _isFavorite
                ? 'Retirer des favoris'
                : 'Ajouter aux favoris',
            onPressed: _isTogglingFavorite ? null : _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 24,
            ),
            color: _isFavorite ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      onChanged: (v) => _update(() => _displayName = v),
      decoration: InputDecoration(
        hintText: widget.sound.title,
        // Croix « tout effacer » : le champ vidé retombe sur le titre du
        // fichier à l'enregistrement (voir `_resolvedName`).
        suffixIcon: _nameController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Effacer le nom',
                onPressed: () {
                  _nameController.clear();
                  _update(() => _displayName = '');
                },
              ),
      ),
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
            onChanged: _setVolume,
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
            // Outil de développement : en production l'enveloppe est
            // rafraîchie automatiquement au bump de `kWaveformProbeGeneration`.
            if (kDebugMode && widget.notifier != null)
              TextButton.icon(
                onPressed: _isRegeneratingWaveform || _waveformRegenerated
                    ? null
                    : _regenerateWaveform,
                icon: _isRegeneratingWaveform
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _waveformRegenerated ? Icons.check : Icons.refresh,
                        size: 18,
                      ),
                label: Text(
                  _waveformRegenerated
                      ? 'Waveform régénérée'
                      : 'Régénérer la waveform',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StartOffsetEditor(
          filePath: widget.sound.filePath,
          waveform: _waveform,
          initialOffsetMs: _startOffsetMs,
          volume: _volume,
          autoPlay: widget.autoPlayEntryPoint,
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
    final editor = TagChipsEditor(
      tagCatalog: widget.tagCatalog,
      selectedTagIds: _tagIds,
      onTagAdded: (id) => _update(() => _tagIds.add(id)),
      onTagRemoved: (id) => _update(() => _tagIds.remove(id)),
    );
    final status = _analysisStatus;
    // Analysé : rien à dire, les suggestions parlent d'elles-mêmes. Sinon : le
    // bouton « Analyser », ou la raison pour laquelle le son ne peut pas l'être.
    final showStatus =
        widget.autoTag != null &&
        status != null &&
        status != SoundAnalysisStatus.analyzed;
    final hasPending = _autoTags.any((s) => !_tagIds.contains(s.tag.id));
    if (!hasPending && !showStatus) return editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        editor,
        if (hasPending) ...[
          const SizedBox(height: 14),
          AutoTagChips(
            suggestions: _autoTags,
            colors: _categoryColorsByTagId(),
            acceptedTagIds: _tagIds,
            // Accepter = ajouter aux tags du son, enregistré avec le formulaire.
            onAdd: (s) => _update(() => _tagIds.add(s.tag.id)),
          ),
        ],
        if (showStatus) ...[
          const SizedBox(height: 10),
          AutoTagStatusRow(
            // Demandée, pas encore dans la file du passage : déjà « en attente ».
            status: _analysisRequested && status == SoundAnalysisStatus.pending
                ? SoundAnalysisStatus.queued
                : status,
            onStart: _startAnalysis,
          ),
        ],
      ],
    );
  }

  Map<int, Color> _categoryColorsByTagId() => {
    for (final cat in widget.tagCatalog)
      for (final tag in cat.tags) tag.id: Color(cat.category.color),
  };

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
