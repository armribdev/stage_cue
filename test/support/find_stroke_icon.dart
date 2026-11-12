import 'package:flutter_test/flutter_test.dart';
import 'package:stage_cue/core/theme/stroke_icon.dart';

/// Équivalent de `find.byIcon` pour les icônes de l'app, qui sont des
/// [StrokeIcon] et non des glyphes `Icon` : repère le widget qui dessine ces
/// données (typiquement un `AppIcons.xxx`).
Finder findStrokeIcon(StrokeIconData data) => find.byWidgetPredicate(
  (widget) => widget is StrokeIcon && widget.data == data,
  description: 'StrokeIcon($data)',
);
