import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Thème de l'application — sombre, neutre, pensé "outil pro" (desktop-first).
///
/// La palette d'origine (violet saturé sur fond bleu nuit) évoquait une app
/// créative mobile. On bascule vers des surfaces plus neutres (charbon/ardoise)
/// et un accent indigo désaturé, plus proche des outils SaaS professionnels.
/// Tous les rayons et espacements proviennent de [AppRadius] / [AppSpacing]
/// pour garantir une échelle cohérente dans toute l'application.
class AppTheme {
  static const _seedColor = Color(0xFF5B6EF5);
  static const _surface = Color(0xFF15171D);
  static const _surfaceContainer = Color(0xFF1C1F27);
  static const _scaffoldBackground = Color(0xFF0E0F13);

  static const double _controlHeight = 42;

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      surface: _surface,
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: AppRadius.radiusSm,
      borderSide: AppElevation.border(scheme),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: _scaffoldBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _surfaceContainer.withValues(alpha: 0.92),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusMd,
          side: AppElevation.border(scheme),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusLg),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(AppRadius.lg),
          ),
          side: AppElevation.border(scheme),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: _surfaceContainer.withValues(alpha: 0.95),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceContainer.withValues(alpha: 0.7),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusSm,
          borderSide: AppElevation.emphasizedBorder(scheme),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(_controlHeight),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusSm),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(_controlHeight),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusSm),
          side: AppElevation.border(scheme),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surfaceContainer,
        contentTextStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusMd),
      ),
    );
  }
}
