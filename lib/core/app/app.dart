import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../features/sampler/presentation/screens/sampler_screen.dart';
import 'app_services.dart';

/// Widget racine de l'application
class SoundboardApp extends StatefulWidget {
  final AppServices services;

  const SoundboardApp({
    super.key,
    required this.services,
  });

  @override
  State<SoundboardApp> createState() => _SoundboardAppState();
}

/// Largeur max des snackbars — au-delà, elles paraissent démesurées sur un
/// écran de bureau large ; en dessous, on laisse la largeur s'adapter pour
/// ne pas déborder sur un écran de téléphone étroit.
const double _maxSnackBarWidth = 420;

class _SoundboardAppState extends State<SoundboardApp> {
  @override
  void dispose() {
    widget.services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stage Cue - Soundboard',
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        final theme = Theme.of(context);
        final availableWidth = MediaQuery.sizeOf(context).width - 48;
        final snackBarWidth = availableWidth.clamp(0, _maxSnackBarWidth).toDouble();
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(width: snackBarWidth),
          ),
          child: child!,
        );
      },
      home: SamplerScreen(services: widget.services),
    );
  }
}

