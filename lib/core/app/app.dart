import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../features/sampler/presentation/screens/sampler_screen.dart';

/// Widget racine de l'application
class SoundboardApp extends StatelessWidget {
  const SoundboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stage Cue - Soundboard',
      theme: AppTheme.darkTheme,
      home: const SamplerScreen(),
    );
  }
}

