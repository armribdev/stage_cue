import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/layout_utils.dart';
import '../widgets/app_modal.dart';
import '../widgets/dashed_slot_frame.dart';
import '../../domain/entities/pad.dart';
import '../../domain/entities/sound.dart';
import '../../domain/entities/tag_category_with_tags.dart';
import '../models/pad_sound_slot.dart';
import '../providers/sampler_provider.dart';
import '../utils/sound_type_ui.dart';
import '../../domain/entities/tag_item.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/sound_picker_overlay.dart';

/// Écran de détails d'un pad — réglages, sons, mode de lecture.
class PadDetailsScreen extends StatefulWidget {
  final PadItem padItem;
  final SamplerNotifier notifier;
  final AppPreferences appPreferences;
  final bool isModal;
  final bool openPickerOnStart;

  const PadDetailsScreen({
    super.key,
    required this.padItem,
    required this.notifier,
    required this.appPreferences,
    this.isModal = false,
    this.openPickerOnStart = false,
  });

  /// Page plein écran sur téléphone, fenêtre modale sur tablette et desktop.
  static Future<void> open(
    BuildContext context, {
    required PadItem padItem,
    required SamplerNotifier notifier,
    required AppPreferences appPreferences,
    bool openPickerOnStart = false,
  }) {
    return openAdaptiveScreen(
      context: context,
      builder: ({required isModal}) => PadDetailsScreen(
        padItem: padItem,
        notifier: notifier,
        appPreferences: appPreferences,
        isModal: isModal,
        openPickerOnStart: openPickerOnStart,
      ),
    );
  }

  @override
  State<PadDetailsScreen> createState() => _PadDetailsScreenState();
}

class _PadDetailsScreenState extends State<PadDetailsScreen> {
  static const List<Color> _colorChoices = <Color>[
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.brown,
    Colors.grey,
  ];

  late int? _selectedColorValue;
  late PadPlayMode _playMode;
  late final TextEditingController _displayNameController;
  Timer? _displayNameDebounce;
  List<TagCategoryWithTags> _tagCatalog = [];
  bool _isTagsLoading = true;
  bool _volumeControlsVisible = true;
  bool _isCapturingHotkey = false;
  bool _isHotkeyHovered = false;
  late final FocusNode _hotkeyCaptureFocusNode;

  @override
  void initState() {
    super.initState();
    final pad = widget.padItem.pad;
    _selectedColorValue = pad.colorValue;
    _playMode = pad.playMode;
    _displayNameController = TextEditingController(text: pad.name ?? '');
    _hotkeyCaptureFocusNode = FocusNode(debugLabel: 'pad-hotkey-capture');
    _loadTagCatalog();
    if (widget.openPickerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addSound(context);
      });
    }
  }

  @override
  void dispose() {
    _displayNameDebounce?.cancel();
    _displayNameController.dispose();
    _hotkeyCaptureFocusNode.dispose();
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

  Future<void> _removeSound(int soundId) async {
    await widget.notifier.removeSoundFromPad(
      widget.padItem.pad.id,
      soundId,
    );
    if (!mounted) return;
    setState(() {});
  }

  static final _hotkeyModifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  void _startHotkeyCapture() {
    setState(() => _isCapturingHotkey = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hotkeyCaptureFocusNode.requestFocus();
    });
  }

  void _cancelHotkeyCapture() {
    if (!mounted) return;
    setState(() => _isCapturingHotkey = false);
  }

  Future<void> _clearHotkey() async {
    await widget.appPreferences.setPadHotkey(widget.padItem.pad.id, null);
    if (!mounted) return;
    setState(() {});
  }

  /// Pad du même board qui détient déjà [keyId], le cas échéant (exclut le
  /// pad courant). La portée par board seule est correcte : un raccourci n'est
  /// jamais actif que pour le board affiché.
  PadItem? _padHoldingHotkey(int keyId) {
    for (final item in widget.notifier.state.pads) {
      if (item.pad.id == widget.padItem.pad.id) continue;
      if (widget.appPreferences.hotkeyForPad(item.pad.id) == keyId) {
        return item;
      }
    }
    return null;
  }

  KeyEventResult _handleHotkeyCaptureKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelHotkeyCapture();
      return KeyEventResult.handled;
    }
    if (_hotkeyModifiers.contains(event.logicalKey)) {
      return KeyEventResult.handled; // reste en capture
    }

    // Pas de blocage : une collision reste possible (utile pour « déplacer »
    // une touche d'un pad à l'autre sans devoir d'abord la libérer) — elle
    // est signalée en permanence dans `_buildHotkeySection` (touche en rouge
    // + « déjà utilisée par… ») plutôt que par une notification ponctuelle.
    final keyId = event.logicalKey.keyId;
    unawaited(
      widget.appPreferences.setPadHotkey(widget.padItem.pad.id, keyId),
    );
    setState(() => _isCapturingHotkey = false);
    return KeyEventResult.handled;
  }

  /// Étiquette courte affichée sur la touche (symbole pour les non-imprimables
  /// les plus courants, sinon `keyLabel` — `FittedBox` en aval absorbe le
  /// reste, ex. "Page Up").
  static String _keycapLabel(LogicalKeyboardKey key) {
    final symbols = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.space: '␣',
      LogicalKeyboardKey.tab: '⇥',
      LogicalKeyboardKey.enter: '⏎',
      LogicalKeyboardKey.numpadEnter: '⏎',
      LogicalKeyboardKey.backspace: '⌫',
      LogicalKeyboardKey.delete: 'Del',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
    };
    final symbol = symbols[key];
    if (symbol != null) return symbol;
    final raw = key.keyLabel;
    return raw.length <= 3 ? raw.toUpperCase() : raw;
  }

  Widget _buildHotkeyKeycap(
    BuildContext context, {
    String? label,
    bool isConflicting = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const size = 36.0;

    final border = _isCapturingHotkey
        ? AppElevation.emphasizedBorder(scheme)
        : (_isHotkeyHovered
            ? AppElevation.borderStrong(scheme)
            : AppElevation.border(scheme));

    final content = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _isCapturingHotkey
            ? scheme.primary.withValues(alpha: 0.12)
            : (label != null
                ? scheme.surfaceContainer
                : (_isHotkeyHovered
                    ? scheme.surfaceContainer.withValues(alpha: 0.5)
                    : Colors.transparent)),
        borderRadius: AppRadius.radiusSm,
        border: Border.fromBorderSide(border),
      ),
      child: _isCapturingHotkey
          ? Icon(
              Icons.keyboard_alt_outlined,
              size: 18,
              color: scheme.primary,
            )
          : (label != null
              ? Padding(
                  padding: const EdgeInsets.all(4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: AppFonts.monoStyle(
                        Theme.of(context).textTheme.bodyMedium!,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isConflicting ? scheme.error : null,
                      ),
                    ),
                  ),
                )
              : null),
    );

    // Sans touche assignée : cadre pointillé (même langage visuel que les
    // emplacements vides ailleurs dans l'app, cf. DashedSlotFrame) — accentué
    // au survol pour signaler que la case est cliquable.
    final framed = (label == null && !_isCapturingHotkey)
        ? CustomPaint(
            foregroundPainter: DashedRoundedRectPainter(
              color: _isHotkeyHovered
                  ? scheme.primary.withValues(alpha: 0.6)
                  : AppElevation.borderStrong(scheme).color,
              radius: AppRadius.sm,
            ),
            child: content,
          )
        : content;

    if (_isCapturingHotkey) return framed;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHotkeyHovered = true),
      onExit: (_) => setState(() => _isHotkeyHovered = false),
      child: InkWell(
        onTap: _startHotkeyCapture,
        borderRadius: AppRadius.radiusSm,
        child: framed,
      ),
    );
  }

  Widget _buildHotkeyClearBadge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Retirer le raccourci',
      child: InkWell(
        onTap: _clearHotkey,
        customBorder: const CircleBorder(),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: Border.fromBorderSide(AppElevation.border(scheme)),
          ),
          child: Icon(Icons.close, size: 10, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  static const _hotkeyKeycapSize = 36.0;
  static const _hotkeyBadgeSize = 18.0;

  Widget _buildHotkeySection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyId = widget.appPreferences.hotkeyForPad(widget.padItem.pad.id);
    final label =
        keyId != null ? _keycapLabel(LogicalKeyboardKey(keyId)) : null;
    final showClearBadge = label != null && !_isCapturingHotkey;
    // Une collision reste permise à l'assignation (voir
    // `_handleHotkeyCaptureKey`) — signalée ici en continu plutôt qu'une
    // seule fois au moment du tap.
    final conflictingPad = (keyId != null && !_isCapturingHotkey)
        ? _padHoldingHotkey(keyId)
        : null;

    Widget keycap = _buildHotkeyKeycap(
      context,
      label: label,
      isConflicting: conflictingPad != null,
    );
    if (_isCapturingHotkey) {
      keycap = KeyboardListener(
        focusNode: _hotkeyCaptureFocusNode,
        autofocus: true,
        onKeyEvent: (event) =>
            _handleHotkeyCaptureKey(_hotkeyCaptureFocusNode, event),
        child: keycap,
      );
    }

    // Zone réservée pour le carré + la pastille de suppression, SANS
    // dépassement négatif (pas de `Positioned` hors des bornes de la boîte) :
    // un `Positioned` à coordonnée négative peut se faire rogner la zone
    // tactile par un ancêtre qui clippe (ex. le défilement de l'écran), ce
    // qui ne coupe alors qu'une fraction du disque au clic — la pastille
    // reste ici entièrement DANS la boîte, juste chevauchant le coin du carré.
    return Row(
      children: [
        SizedBox(
          width: _hotkeyKeycapSize + _hotkeyBadgeSize / 2,
          height: _hotkeyKeycapSize + _hotkeyBadgeSize / 2,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: _hotkeyBadgeSize / 2,
                width: _hotkeyKeycapSize,
                height: _hotkeyKeycapSize,
                child: keycap,
              ),
              if (showClearBadge)
                Positioned(
                  right: 0,
                  top: 0,
                  width: _hotkeyBadgeSize,
                  height: _hotkeyBadgeSize,
                  child: _buildHotkeyClearBadge(context),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _isCapturingHotkey
                ? 'Appuyez sur une touche… (Échap pour annuler)'
                : (conflictingPad != null
                    ? 'Déjà utilisée par « ${conflictingPad.displayName} ».'
                    : (label != null
                        ? 'Déclenche ce pad au clavier.'
                        : 'Aucune touche assignée — touchez la case.')),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: conflictingPad != null ? scheme.error : null,
            ),
          ),
        ),
      ],
    );
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
            Text(
              'RÉGLAGES',
              style: AppTextStyles.sectionLabel(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nom affiché',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                hintText: widget.padItem.displayName,
                suffixIcon: _displayNameController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(
                            () => _displayNameController.clear(),
                          );
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDefaultColorOption(context),
                for (final c in _colorChoices)
                  _buildColorDot(context, c),
              ],
            ),
            if (sounds.length > 1) ...[
              const SizedBox(height: 16),
              Text(
                'Mode de lecture',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              _PlayModeSelector(
                value: _playMode,
                onChanged: _updatePlayMode,
              ),
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
              _buildHotkeySection(context),
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
                if (sounds.isNotEmpty)
                  Tooltip(
                    message: _volumeControlsVisible ? 'Masquer les volumes' : 'Afficher les volumes',
                    child: IconButton(
                      icon: Icon(
                        _volumeControlsVisible
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _volumeControlsVisible = !_volumeControlsVisible);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _addSound(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sounds.isEmpty)
              Text(
                'Aucun son',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ListenableBuilder(
                listenable: widget.notifier,
                builder: (context, _) {
                  final offlineMode = widget.notifier.offlineMode;
                  final visibleIndices = <int>[
                    for (var i = 0; i < sounds.length; i++)
                      if (!offlineMode ||
                          widget.notifier.isSlotLocallyAvailable(
                            widget.padItem,
                            i,
                          ))
                        i,
                  ];
                  if (visibleIndices.isEmpty) {
                    return Text(
                      offlineMode
                          ? 'Aucun son disponible hors-ligne'
                          : 'Aucun son',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  }
                  return Column(
                    children: [
                      for (final i in visibleIndices)
                        _SoundRow(
                          padItem: widget.padItem,
                          slotIndex: i,
                          sound: sounds[i],
                          canRemove: sounds.length > 1,
                          tagCatalog: _tagCatalog,
                          isTagsLoading: _isTagsLoading,
                          notifier: widget.notifier,
                          onRemove: () => _removeSound(sounds[i].id),
                        ),
                    ],
                  );
                },
              ),
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
            // Le thème global met `minimumSize` à largeur infinie (pensé pour
            // un bouton seul en pleine largeur) — invisible dans un Row à
            // plusieurs boutons sans cette borne locale.
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 42)),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Annuler'),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(64, 42)),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultColorOption(BuildContext context) {
    final isSelected = _selectedColorValue == null;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    final onSurface = scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _updateColor(null),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: isSelected
              ? Icon(Icons.check, color: onSurface, size: 20)
              : Text(
                  'D',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
        ),
    );
  }

  Widget _buildColorDot(BuildContext context, Color color) {
    final isSelected = _selectedColorValue == color.toARGB32();
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isSelected ? scheme.primary : scheme.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _updateColor(color.toARGB32()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? Icon(Icons.check, color: _checkColor(color), size: 20)
            : null,
      ),
    );
  }

  Color _checkColor(Color color) =>
      color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
}

// ── Sélecteur de mode de lecture ──────────────────────────────────────────

class _PlayModeSelector extends StatelessWidget {
  final PadPlayMode value;
  final ValueChanged<PadPlayMode> onChanged;

  const _PlayModeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PadPlayMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: PadPlayMode.random,
          icon: Icon(Icons.shuffle_rounded, size: 16),
          label: Text('Aléatoire'),
        ),
        ButtonSegment(
          value: PadPlayMode.sequential,
          icon: Icon(Icons.repeat_one_rounded, size: 16),
          label: Text('Séquentiel'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── Ligne d'un son ────────────────────────────────────────────────────────

class _SoundRow extends StatefulWidget {
  final PadItem padItem;
  final int slotIndex;
  final Sound sound;
  final bool canRemove;
  final List<TagCategoryWithTags> tagCatalog;
  final bool isTagsLoading;
  final SamplerNotifier notifier;
  final VoidCallback onRemove;

  const _SoundRow({
    required this.padItem,
    required this.slotIndex,
    required this.sound,
    required this.canRemove,
    required this.tagCatalog,
    required this.isTagsLoading,
    required this.notifier,
    required this.onRemove,
  });

  @override
  State<_SoundRow> createState() => _SoundRowState();
}

class _SoundRowState extends State<_SoundRow> {
  static const _maxVisibleTags = 3;

  Set<int> _tagIds = {};
  bool _loaded = false;
  late double _volume;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _volume = _resolvedPadItem().pad.effectiveVolume(widget.slotIndex);
    _loadTags();
  }

  void _updateVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    widget.notifier.updatePadSoundVolume(
      _resolvedPadItem(),
      widget.sound.id,
      clamped,
    );
  }

  Future<void> _loadTags() async {
    final tags = await widget.notifier.getTagsForSound(widget.sound.id);
    if (!mounted) return;
    setState(() {
      _tagIds = tags.map((t) => t.id).toSet();
      _loaded = true;
    });
  }

  PadItem _resolvedPadItem() =>
      widget.notifier.findPadItemById(widget.padItem.pad.id) ?? widget.padItem;

  PadSoundAvailability _availability(PadItem padItem) =>
      widget.slotIndex < padItem.slots.length
          ? padItem.slots[widget.slotIndex].availability
          : PadSoundAvailability.needsDownload;

  bool _isLocal(PadSoundAvailability availability) =>
      availability == PadSoundAvailability.ready ||
      availability == PadSoundAvailability.cached;

  bool _canDownload(PadSoundAvailability availability) =>
      availability == PadSoundAvailability.needsDownload ||
      availability == PadSoundAvailability.offline ||
      availability == PadSoundAvailability.missingFile;

  Future<void> _downloadSound() async {
    final padItem = _resolvedPadItem();
    final availability = _availability(padItem);
    if (!_canDownload(availability)) return;
    if (padItem.downloadingSlotIndex == widget.slotIndex) return;

    await widget.notifier.downloadPadSoundAtIndex(padItem, widget.slotIndex);
  }

  List<TagItem> _resolvedTags() {
    final tags = <TagItem>[];
    for (final cat in widget.tagCatalog) {
      for (final tag in cat.tags) {
        if (_tagIds.contains(tag.id)) tags.add(tag);
      }
    }
    return tags;
  }

  Color? _categoryColor(int categoryId) {
    for (final group in widget.tagCatalog) {
      if (group.category.id == categoryId) return Color(group.category.color);
    }
    return null;
  }

  Widget _buildTagRow(ColorScheme scheme, List<TagItem> tags) {
    final visible = tags.take(_maxVisibleTags).toList();
    final overflow = tags.length - visible.length;
    return Row(
      children: [
        for (final tag in visible) ...[
          _buildTagChip(scheme, tag),
          const SizedBox(width: 4),
        ],
        if (overflow > 0)
          Text(
            '+$overflow',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(ColorScheme scheme, TagItem tag) {
    final color = _categoryColor(tag.categoryId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color?.withAlpha(24),
        borderRadius: BorderRadius.circular(4),
        border: color == null ? null : Border.all(color: color),
      ),
      child: Text(
        tag.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color ?? scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSubtitle(
    ColorScheme scheme, {
    required bool isLocal,
    required bool isDownloading,
  }) {
    if (isDownloading) {
      return Text(
        'Téléchargement…',
        style: TextStyle(
          fontSize: 12,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      children: [
        Text(
          widget.sound.typeDisplayLabel,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (!isLocal) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.cloud_outlined,
            size: 13,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sound = widget.sound;

    return ListenableBuilder(
      listenable: widget.padItem.revision,
      builder: (context, _) {
        final padItem = _resolvedPadItem();
        final availability = _availability(padItem);
        final isLocal = _isLocal(availability);
        final isDownloading = padItem.downloadingSlotIndex == widget.slotIndex;
        final canDownload = _canDownload(availability) && !isDownloading;

        final tags = _loaded ? _resolvedTags() : const <TagItem>[];

        final soundContent = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SoundTypeAvatar(
              type: sound.type,
              colorValue: sound.colorValue,
              radius: 12,
              iconSize: 14,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ScrollingTextSpan(
                      animate: _hovered,
                      span: TextSpan(text: sound.displayName ?? sound.title),
                    ),
                    _buildSubtitle(
                      scheme,
                      isLocal: isLocal,
                      isDownloading: isDownloading,
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _buildTagRow(scheme, tags),
                    ],
                  ],
                ),
              ),
            ),
            // Volume propre à ce son dans ce pad — barre compacte inline
            // (plutôt qu'une rangée pleine largeur séparée) ; visible
            // seulement quand le son est jouable localement.
            if (isLocal) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: Slider(
                  value: _volume.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  label: '${(_volume * 100).round()}%',
                  onChanged: _updateVolume,
                ),
              ),
            ],
            if (widget.canRemove) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: widget.onRemove,
                color: scheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: canDownload
                    ? IconButton.styleFrom(hoverColor: Colors.transparent)
                    : null,
              ),
            ],
          ],
        );

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: AppRadius.radiusMd,
            border: Border.fromBorderSide(AppElevation.border(scheme)),
          ),
          child: canDownload
              ? Material(
                  color: Colors.transparent,
                  borderRadius: AppRadius.radiusSm,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => unawaited(_downloadSound()),
                    borderRadius: AppRadius.radiusSm,
                    hoverColor: scheme.onSurface.withValues(alpha: 0.08),
                    splashColor: scheme.onSurface.withValues(alpha: 0.12),
                    child: soundContent,
                  ),
                )
              : soundContent,
        );
      },
    );
  }
}

