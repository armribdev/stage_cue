import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/settings/app_preferences.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stroke_icon.dart';
import '../providers/sampler_provider.dart';
import 'dashed_slot_frame.dart';

/// Case de saisie du raccourci clavier d'un pad (desktop) : capture la
/// prochaine touche, signale en continu une collision avec un autre pad du
/// même board et permet de retirer le raccourci.
class PadHotkeyField extends StatefulWidget {
  final AppPreferences appPreferences;
  final SamplerNotifier notifier;
  final int padId;

  const PadHotkeyField({
    super.key,
    required this.appPreferences,
    required this.notifier,
    required this.padId,
  });

  @override
  State<PadHotkeyField> createState() => _PadHotkeyFieldState();
}

class _PadHotkeyFieldState extends State<PadHotkeyField> {
  bool _isCapturingHotkey = false;
  bool _isHotkeyHovered = false;
  late final FocusNode _hotkeyCaptureFocusNode = FocusNode(
    debugLabel: 'pad-hotkey-capture',
  );

  @override
  void dispose() {
    _hotkeyCaptureFocusNode.dispose();
    super.dispose();
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
    await widget.appPreferences.setPadHotkey(widget.padId, null);
    if (!mounted) return;
    setState(() {});
  }

  /// Pad du même board qui détient déjà [keyId], le cas échéant (exclut le
  /// pad courant). La portée par board seule est correcte : un raccourci n'est
  /// jamais actif que pour le board affiché.
  PadItem? _padHoldingHotkey(int keyId) {
    for (final item in widget.notifier.state.pads) {
      if (item.pad.id == widget.padId) continue;
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
    // est signalée en permanence dans `build` (touche en rouge
    // + « déjà utilisée par… ») plutôt que par une notification ponctuelle.
    final keyId = event.logicalKey.keyId;
    unawaited(widget.appPreferences.setPadHotkey(widget.padId, keyId));
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
          ? StrokeIcon(
              AppIcons.keyboard,
              size: AppIconSize.sm,
              color: scheme.primary,
            )
          : (label != null
                ? Padding(
                    padding: const EdgeInsets.all(4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style:
                            AppFonts.monoStyle(
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
          child: StrokeIcon(
            AppIcons.close,
            size: 10,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static const _hotkeyKeycapSize = 36.0;
  static const _hotkeyBadgeSize = 18.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyId = widget.appPreferences.hotkeyForPad(widget.padId);
    final label = keyId != null
        ? _keycapLabel(LogicalKeyboardKey(keyId))
        : null;
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
      // `Focus` et non `KeyboardListener` : ce dernier ignore le résultat du
      // handler, l'événement remonterait alors jusqu'aux raccourcis de la
      // route — Échap déclencherait `DismissIntent` et fermerait la modale.
      keycap = Focus(
        focusNode: _hotkeyCaptureFocusNode,
        autofocus: true,
        onKeyEvent: _handleHotkeyCaptureKey,
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
}
