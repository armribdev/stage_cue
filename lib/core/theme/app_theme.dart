import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Thème de l'application — direction "Console Linear" (voir
/// `docs/decisions/` si une entrée existe) : surfaces quasi noires, un seul
/// accent violet, hiérarchie portée par le poids typographique et le mono
/// plutôt que par la couleur, aucune élévation Material ni effet ripple.
/// Tous les rayons/espacements/couleurs proviennent de [AppRadius] /
/// [AppSpacing] / [AppColors] pour garantir une échelle cohérente.
class AppTheme {
  static const double _controlHeight = 42;

  static const ColorScheme _scheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.text,
    secondary: Color(0xFF8891B0),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF23242E),
    onSecondaryContainer: AppColors.text,
    tertiary: AppColors.warn,
    onTertiary: AppColors.bg,
    tertiaryContainer: Color(0x29E8A23B),
    onTertiaryContainer: AppColors.warn,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: Color(0x29E5484D),
    onErrorContainer: AppColors.danger,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textDim,
    // Gris neutre clair plutôt que blanc pur : les ~25 sites qui appliquent
    // leur propre alpha sur `outlineVariant` (hors du helper [AppElevation])
    // restent proches de leur calibrage d'origine — seul [AppElevation.border]
    // (alpha .09) doit rendre le hairline exact de la maquette, et à alpha si
    // faible la teinte RGB exacte ne change quasiment rien à l'œil.
    outline: Color(0xFFA8AAB5),
    outlineVariant: Color(0xFFA8AAB5),
    surfaceTint: Colors.transparent,
    scrim: Colors.black,
    surfaceContainerLowest: AppColors.bg,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface2,
    surfaceContainerHigh: Color(0xFF232430),
    surfaceContainerHighest: AppColors.surface2,
    inverseSurface: AppColors.text,
    onInverseSurface: AppColors.bg,
    inversePrimary: AppColors.accent,
  );

  static ThemeData get darkTheme {
    final scheme = _scheme;

    final outlineBorder = OutlineInputBorder(
      borderRadius: AppRadius.radiusMd,
      borderSide: AppElevation.border(scheme),
    );

    final solidButtonShape = RoundedRectangleBorder(
      borderRadius: AppRadius.radiusMd,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: AppFonts.ui,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: 0.04),
      focusColor: AppColors.accentSoft,
      iconTheme: const IconThemeData(color: AppColors.textDim, size: 20),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accentSoft,
        selectionHandleColor: AppColors.accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusLg,
          side: AppElevation.border(scheme),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusLg,
          side: AppElevation.border(scheme),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 14,
          color: AppColors.textDim,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: AppElevation.border(scheme),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          side: AppElevation.border(scheme),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const AutomaticNotchedShape(RoundedRectangleBorder()),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        disabledBorder: outlineBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusMd,
          borderSide: AppElevation.emphasizedBorder(scheme),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.radiusMd,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.textFaint,
          minimumSize: const Size.fromHeight(_controlHeight),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: solidButtonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(_controlHeight),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: solidButtonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(_controlHeight),
          shape: solidButtonShape,
          side: AppElevation.border(scheme),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusSm),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textDim,
          highlightColor: Colors.transparent,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textDim,
        textColor: AppColors.text,
        tileColor: Colors.transparent,
        selectedColor: AppColors.accent,
        selectedTileColor: AppColors.accentSoft,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusSm),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        elevation: 0,
        contentTextStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.text,
          fontSize: 14,
        ),
        actionTextColor: AppColors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusMd,
          side: AppElevation.border(scheme),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textDim,
          selectedBackgroundColor: AppColors.accent,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.radiusSm),
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.text,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.radiusMd,
          side: AppElevation.border(scheme),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        disabledColor: AppColors.surface2,
        selectedColor: AppColors.accentSoft,
        secondarySelectedColor: AppColors.accentSoft,
        side: AppElevation.border(scheme),
        labelStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.textDim,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        deleteIconColor: AppColors.textFaint,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: AppRadius.radiusSm,
          border: Border.fromBorderSide(AppElevation.border(scheme)),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.text,
          fontSize: 12,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surface2,
        circularTrackColor: AppColors.surface2,
        linearMinHeight: 3,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surface2,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accentSoft,
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.textFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accentSoft
              : AppColors.surface2,
        ),
        trackOutlineColor: WidgetStateProperty.all(AppColors.border),
      ),
    );
  }
}
