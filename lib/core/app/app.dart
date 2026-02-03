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
      home: SamplerScreen(services: widget.services),
    );
  }
}

