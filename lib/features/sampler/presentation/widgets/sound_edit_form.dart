import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/audio/gain.dart';
import '../../../../core/autotag/auto_tag_analysis.dart';
import '../../../../core/autotag/auto_tag_status.dart';
import '../../../../core/logging/app_log.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/title_tag_matcher.dart';
import '../../data/repositories/sound_repository.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/sound_auto_tag.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../providers/sampler_provider.dart';
import 'app_form_dialog.dart';
import 'color_swatch_picker.dart';
import 'sound_edit_preload.dart';
import 'sound_tags_section.dart';
import 'sound_type_selector.dart';
import 'sound_gain_field.dart';
import 'start_offset_editor.dart';
import '../../../../core/theme/stroke_icon.dart';

/// Formulaire d'édition d'un son de la bibliothèque (nom, type, couleur,
/// gain, point d'entrée, tags).
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

  /// Notifié quand le son a été supprimé (corbeille Drive, base et cache) : le
  /// formulaire n'a plus d'objet, l'appelant le ferme et rafraîchit sa liste.
  final VoidCallback? onDeleted;

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

  /// Ce que la section « Tags » affiche, déjà lu par l'appelant
  /// ([SoundEditPane]) : le formulaire est complet dès sa première image. `null`
  /// = le lire ici, la section se remplit à l'arrivée des données.
  final SoundEditPreload? preload;

  /// Hauteur de la section « Tags » du formulaire précédent, pour qu'elle
  /// s'anime d'un son à l'autre (voir [SoundEditPane]). `null` = pas de suite.
  final SoundFormMemory? sectionMemory;

  const SoundEditForm({
    super.key,
    required this.sound,
    required this.tagCatalog,
    required this.repository,
    this.notifier,
    this.autoTag,
    this.preload,
    this.sectionMemory,
    this.onSaved,
    this.onDirtyChanged,
    this.onMarkedUnprocessed,
    this.onFavoriteChanged,
    this.onDeleted,
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

class _SoundEditFormState extends State<SoundEditForm>
    with SingleTickerProviderStateMixin {
  late String _displayName;
  late final TextEditingController _nameController;
  // Ne sert qu'à afficher la croix « effacer » tant que le titre est focus.
  late final FocusNode _nameFocus = FocusNode()..addListener(_onNameFocus);
  late int? _colorValue;

  /// Gain du formulaire (facteur linéaire, décision 0045) : le curseur et
  /// « Auto » le fixent, « Enregistrer » l'écrit.
  late double _gain;

  /// Gain, en dB, montré par le curseur et la waveform de l'éditeur (voir
  /// [GainGlide]) ; `_gain` reste la valeur du formulaire.
  late final GainGlide _gainGlide;
  late int _startOffsetMs;
  late SoundType? _type;
  late Uint8List? _waveform;

  /// Extraction de l'enveloppe en cours (son sans waveform à l'ouverture).
  late bool _waveformPending;
  Set<int> _tagIds = <int>{};

  // Baseline = dernier état enregistré (ou chargé) ; sert à calculer `dirty`.
  late String _baseDisplayName;
  late int? _baseColorValue;
  late double _baseGain;
  late int _baseStartOffsetMs;
  late SoundType? _baseType;
  Set<int> _baseTagIds = <int>{};

  /// Suggestions de l’IA (décision 0031) : lecture seule. En accepter une
  /// l’ajoute à [_tagIds], donc à la baseline `dirty` comme tout autre tag.
  List<SoundAutoTag> _autoTags = const [];

  /// Tags que le titre du son désigne (décision 0041), calculés à l'ouverture :
  /// rien n'est stocké, la fiche suit le catalogue du moment.
  List<TitleTagMatch> _titleMatches = const [];

  /// Où en est l'analyse IA de ce son (`null` = inconnu ou fonction absente).
  SoundAnalysisStatus? _analysisStatus;

  int _analysisRefreshSeq = 0;
  bool _suggestionsReloadPending = false;

  /// L'utilisateur a cliqué « Analyser » et le passage n'est pas fini : le son
  /// s'affiche « en attente » même si le passage n'a pas encore bâti sa file.
  bool _analysisRequested = false;
  SoundAnalysisStatus? _lastLiveStatus;
  bool _lastRunning = false;

  bool _tagsLoaded = false;
  bool _tagsFailed = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isMeasuringGain = false;

  /// `_gain` vient de « Auto » et n'a pas été retouché au curseur : à
  /// l'enregistrement, le son est marqué « gain mesuré » (`gainMeasureGeneration`).
  bool _gainMeasured = false;
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
    _gain = _baseGain = sound.gain;
    final gainDb = gainToDb(_gain);
    final gainDbFrom = widget.sectionMemory?.gainDb;
    widget.sectionMemory?.gainDb = gainDb;
    // Le curseur et la waveform partent du gain du formulaire précédent et
    // glissent vers celui de ce son.
    _gainGlide = GainGlide(vsync: this, initialDb: gainDbFrom ?? gainDb);
    if (gainDbFrom != null && gainDbFrom != gainDb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _gainGlide.glideTo(
          gainDb,
          instant: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
        );
      });
    }
    _startOffsetMs = _baseStartOffsetMs = sound.startOffsetMs;
    _type = _baseType = sound.type;
    _waveform = sound.waveform;
    _waveformPending = _waveform == null && widget.notifier != null;
    if (_waveform == null) unawaited(_loadMissingWaveform());
    final preload = widget.preload;
    if (preload != null) {
      _tagIds = {...preload.tagIds};
      _baseTagIds = {...preload.tagIds};
      _autoTags = preload.autoTags;
      _titleMatches = preload.titleMatches;
      _analysisStatus = preload.analysisStatus;
      _tagsLoaded = true;
    } else {
      unawaited(_loadTags());
    }
    final autoTag = widget.autoTag;
    if (autoTag != null) {
      final activity = autoTag.activity.value;
      _lastRunning = activity.running;
      _lastLiveStatus = activity.liveStatusOf(sound.id);
      autoTag.activity.addListener(_onAnalysisActivity);
      if (preload == null) unawaited(_refreshAnalysis());
    }
  }

  /// Un son sans enveloppe (indexé avant que la waveform couvre tous les types)
  /// la reçoit à l'ouverture de sa fiche, sans attendre qu'on le pose sur un
  /// plateau. Silencieux : sans waveform, l'éditeur reste utilisable.
  Future<void> _loadMissingWaveform() async {
    final waveform = await widget.notifier?.ensureWaveform(widget.sound.id);
    if (!mounted) return;
    setState(() {
      _waveformPending = false;
      if (waveform != null) _waveform = waveform;
    });
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
    // Seule la dernière lecture compte : `statusOf` peut rendre tout de suite
    // (passage en cours) ou après une lecture en base, et une réponse plus
    // ancienne qui arriverait après ferait osciller la rangée d'état. La
    // relecture des suggestions demandée par une lecture écartée est reportée.
    final seq = ++_analysisRefreshSeq;
    if (reloadSuggestions) _suggestionsReloadPending = true;
    try {
      final status = await autoTag.statusOf(widget.sound.id);
      final suggestions = _suggestionsReloadPending
          ? await widget.repository.getAutoTagsForSound(widget.sound.id)
          : null;
      if (!mounted || seq != _analysisRefreshSeq) return;
      _suggestionsReloadPending = false;
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
    _gainGlide.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onNameFocus() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTags() async {
    try {
      final data = await SoundEditPreload.load(
        sound: widget.sound,
        repository: widget.repository,
      );
      if (!mounted) return;
      setState(() {
        _tagIds = {...data.tagIds};
        _baseTagIds = {...data.tagIds};
        _autoTags = data.autoTags;
        _titleMatches = data.titleMatches;
        _tagsLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      // Formulaire utilisable sans tags plutôt que bloqué : enregistrer ne
      // touche aux tags que si le chargement a abouti (voir `_save`).
      setState(() {
        _tagsFailed = true;
        _tagsLoaded = false;
      });
      showCopyableSnackBar(context, 'Impossible de charger les tags : $error');
    }
  }

  bool get _isDirty =>
      _displayName.trim() != _baseDisplayName.trim() ||
      _colorValue != _baseColorValue ||
      _gain != _baseGain ||
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
        gain: _gain,
        gainMeasured: _gainMeasured,
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
        _baseGain = _gain;
        _gainMeasured = false;
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

  /// Un son de bibliothèque Drive (identité Drive connue) peut être supprimé ;
  /// un son local ne le peut pas (un rescan le ré-indexerait).
  bool get _canDelete =>
      widget.notifier != null && widget.sound.driveFileId != null;

  /// Supprime le son après confirmation. Le notifier met le fichier à la
  /// corbeille Drive puis nettoie la base et le cache ; sur échec Drive rien n'a
  /// changé en local et le formulaire reste ouvert.
  Future<void> _delete() async {
    final notifier = widget.notifier;
    if (notifier == null || _isDeleting || _isSaving) return;
    final id = widget.sound.id;

    final blocked = notifier.soundDeletionBlockedReason(id);
    if (blocked != null) {
      showCopyableSnackBar(context, blocked);
      return;
    }

    // Le nombre de pads est une information d'aide à la décision : s'il est
    // illisible, la confirmation reste valable sans lui.
    var padCount = 0;
    try {
      padCount = await widget.repository.countPadsUsingSound(id);
    } catch (error) {
      AppLog.warn('Nombre de pads du son $id illisible : $error');
    }
    if (!mounted) return;

    final name = _resolvedName;
    final usage = switch (padCount) {
      0 => '',
      1 => ' Il sera aussi retiré de 1 pad.',
      _ => ' Il sera aussi retiré de $padCount pads.',
    };
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Supprimer ce son',
      message:
          '« $name » sera mis à la corbeille Google Drive (récupérable '
          'pendant 30 jours) et disparaîtra de tous vos appareils.$usage '
          'Dans un dossier partagé, il disparaît aussi pour les autres '
          'utilisateurs.',
      confirmLabel: 'Supprimer',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    // L'état de lecture a pu changer pendant la confirmation.
    final blockedNow = notifier.soundDeletionBlockedReason(id);
    if (blockedNow != null) {
      showCopyableSnackBar(context, blockedNow);
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await notifier.deleteLibrarySound(id);
    } catch (error, stack) {
      AppLog.warn('Suppression du son $id échouée : $error\n$stack');
      if (!mounted) return;
      setState(() => _isDeleting = false);
      showCopyableSnackBar(context, 'Suppression impossible : $error');
      return;
    }
    // Toast global : il survit au démontage de ce formulaire.
    if (mounted) {
      AppSnackBar.show(
        context,
        '« $name » supprimé — récupérable 30 jours dans la corbeille Drive.',
        severity: AppToastSeverity.success,
      );
    }
    if (_wasDirty) {
      _wasDirty = false;
      widget.onDirtyChanged?.call(false);
    }
    widget.onDeleted?.call();
  }

  Widget _buildDelete(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Met le fichier à la corbeille Google Drive et le retire de tous '
            'vos appareils et de vos pads.',
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
          onPressed: _isDeleting || _isSaving ? null : _delete,
          icon: _isDeleting
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

  /// Change le gain du formulaire et le répercute en direct sur l'aperçu
  /// bibliothèque en cours : celui du lecteur unique, que l'éditeur de point
  /// d'entrée partage avec le bouton de ligne.
  ///
  /// [glide] : valeur posée d'un coup (« Auto »), que le curseur et la waveform
  /// atteignent en glissant ; sinon c'est un geste sur le curseur (en dB), suivi
  /// sans retard.
  void _setGain(double gain, {bool glide = false}) {
    final gainDb = gainToDb(gain);
    _update(() => _gain = gain);
    if (glide) {
      _gainGlide.glideTo(
        gainDb,
        instant: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
      );
    } else {
      _gainGlide.jumpTo(gainDb);
    }
    widget.sectionMemory?.gainDb = gainDb;
    widget.notifier?.setLibraryPreviewGain(widget.sound.id, gain);
  }

  /// Geste sur le curseur : [db] est l'échelle du curseur, `_gain` le facteur.
  void _onGainSlider(double db) {
    _gainMeasured = false;
    _setGain(dbToGain(db));
  }

  /// Gain « auto » : mesure la sonie et le pic du fichier, et fixe le gain qui la
  /// ramène à la cible (relevé ou atténué, décision 0044). N'enregistre rien —
  /// passe par `_update`, donc le formulaire devient « modifié » et l'opérateur
  /// peut ajuster avant de valider.
  Future<void> _applyAutoGain() async {
    if (_isMeasuringGain) return;
    final notifier = widget.notifier;
    if (notifier == null) return;
    setState(() => _isMeasuringGain = true);
    try {
      final gain = await notifier.computeAutoGain(widget.sound);
      if (!mounted) return;
      if (gain == null) {
        showCopyableSnackBar(
          context,
          'Mesure impossible (audio silencieux ou format non pris en charge).',
        );
        return;
      }
      _gainMeasured = true;
      _setGain(gain, glide: true);
    } catch (error) {
      if (!mounted) return;
      showCopyableSnackBar(context, 'Échec de la mesure : $error');
    } finally {
      if (mounted) setState(() => _isMeasuringGain = false);
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
                    _section(
                      'Couleur par défaut',
                      ColorSwatchPicker(
                        value: _colorValue,
                        onChanged: (v) => _update(() => _colorValue = v),
                      ),
                    ),
                    _section(
                      'Gain',
                      SoundGainField(
                        gainDb: _gainGlide,
                        onChanged: _onGainSlider,
                        isMeasuring: _isMeasuringGain,
                        onAuto: widget.notifier != null ? _applyAutoGain : null,
                      ),
                    ),
                    _section('Point d\'entrée', _buildStartOffset()),
                    _section(
                      'Tags',
                      SoundTagsSection(
                        tagCatalog: widget.tagCatalog,
                        selectedTagIds: _tagIds,
                        autoTags: _autoTags,
                        titleMatches: _titleMatches,
                        tagsLoaded: _tagsLoaded,
                        memory: widget.sectionMemory,
                        tagsFailed: _tagsFailed,
                        hasAnalysis: widget.autoTag != null,
                        analysisStatus: _analysisStatus,
                        analysisRequested: _analysisRequested,
                        onTagAdded: (id) => _update(() => _tagIds.add(id)),
                        onTagRemoved: (id) => _update(() => _tagIds.remove(id)),
                        onStartAnalysis: _startAnalysis,
                      ),
                      isLast: !_canDelete,
                    ),
                    if (_canDelete)
                      _section(
                        'Suppression',
                        _buildDelete(scheme),
                        isLast: true,
                      ),
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
    const titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: AppTypography.titleLetterSpacing,
    );
    return Row(
      children: [
        // L'avatar est le sélecteur du type de son.
        SoundTypeSelector(
          type: _type,
          colorValue: _colorValue,
          onChanged: (type) => _update(() => _type = type),
        ),
        const SizedBox(width: 6),
        Expanded(
          // Le titre est le nom affiché, éditable en place. Une seule ligne :
          // l'en-tête garde la même hauteur quel que soit le titre, sinon tout
          // le formulaire se décale d'un son à l'autre. Champ vidé : le titre
          // du fichier (en indice) est ce qui sera enregistré, voir
          // `_resolvedName`.
          child: TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            onChanged: (v) => _update(() => _displayName = v),
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
              hintText: widget.sound.title,
              hintStyle: titleStyle.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        // Croix « tout effacer » tant que le titre est focus : le champ vidé
        // retombe sur le titre du fichier à l'enregistrement (`_resolvedName`).
        // TextFieldTapRegion : sur desktop, un appui hors du champ lui retire le
        // focus dès le pointeur-bas, donc la croix disparaîtrait avant le
        // relâchement. ExcludeFocus : le clic ne doit pas non plus prendre le
        // focus au champ.
        if (_nameFocus.hasFocus && _nameController.text.isNotEmpty)
          TextFieldTapRegion(
            child: ExcludeFocus(
              child: IconButton(
                tooltip: 'Effacer le nom',
                icon: const StrokeIcon(AppIcons.close, size: AppIconSize.sm),
                color: scheme.onSurfaceVariant,
                onPressed: () {
                  _nameController.clear();
                  _update(() => _displayName = '');
                },
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
            icon: StrokeIcon(AppIcons.favorite, size: 24, filled: _isFavorite),
            color: _isFavorite ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }

  Widget _buildStartOffset() {
    return StartOffsetEditor(
      soundId: widget.sound.id,
      notifier: widget.notifier,
      waveform: _waveform,
      waveformPending: _waveformPending,
      memory: widget.sectionMemory,
      initialOffsetMs: _startOffsetMs,
      gain: _gain,
      displayGainDb: _gainGlide,
      autoPlay: widget.autoPlayEntryPoint,
      onChanged: (ms) => _update(() => _startOffsetMs = ms),
    );
  }
}
