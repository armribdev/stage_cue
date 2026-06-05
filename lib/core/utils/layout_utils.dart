import 'package:flutter/widgets.dart';

/// Tablette, desktop et fenêtres larges : préférer une modale à une page plein écran.
bool preferModalPresentation(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide >= 600;
}
