import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Distance (en pixels logiques) que le pointeur doit parcourir avant que le
/// drag ne s'accroche. Par défaut, un [Draggable] avec une souris s'accroche
/// dès ~1 px (`kPrecisePointerHitSlop`), ce qui transforme le moindre clic en
/// drag et rend le clic simple désagréable.
const double kPadDragSlop = 16.0;

/// [Draggable] qui n'accroche le geste qu'après un déplacement d'au moins
/// [dragSlop] pixels, quel que soit le type de pointeur (souris incluse).
///
/// Contrairement au [Draggable] standard qui utilise un slop d'1 px pour la
/// souris, on force un seuil unique pour éviter que « rester cliqué » sans
/// bouger — ou avec un micro-mouvement — ne déclenche le drag.
class ThresholdDraggable<T extends Object> extends Draggable<T> {
  const ThresholdDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.axis,
    super.childWhenDragging,
    super.feedbackOffset,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    super.ignoringFeedbackSemantics,
    super.ignoringFeedbackPointer,
    super.allowedButtonsFilter,
    super.hitTestBehavior,
    super.rootOverlay,
    this.dragSlop = kPadDragSlop,
  });

  /// Seuil de déplacement avant l'accrochage du drag.
  final double dragSlop;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _ThresholdMultiDragGestureRecognizer(
      dragSlop: dragSlop,
      allowedButtonsFilter: allowedButtonsFilter,
    )..onStart = onStart;
  }
}

/// Variante de [ImmediateMultiDragGestureRecognizer] avec un seuil de distance
/// explicite plutôt que le hit slop dépendant du pointeur.
class _ThresholdMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _ThresholdMultiDragGestureRecognizer({
    required this.dragSlop,
    super.debugOwner,
    super.allowedButtonsFilter,
  });

  final double dragSlop;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _ThresholdPointerState(
      event.position,
      event.kind,
      gestureSettings,
      dragSlop,
    );
  }

  @override
  String get debugDescription => 'threshold multidrag';
}

class _ThresholdPointerState extends MultiDragPointerState {
  _ThresholdPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
    this.dragSlop,
  );

  final double dragSlop;

  @override
  void checkForResolutionAfterMove() {
    assert(pendingDelta != null);
    if (pendingDelta!.distance > dragSlop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}
