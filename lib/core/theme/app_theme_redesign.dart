import 'package:flutter/material.dart';
import 'app_colors_redesign.dart';
import 'app_typography_redesign.dart';
import 'app_spacing_redesign.dart';

/// Complete theme configuration for the 2026 redesign
///
/// Integrates all design tokens into a cohesive Material 3 theme
ThemeData getAppThemeRedesign({
  required Brightness brightness,
  required BuildContext context,
}) {
  final bool isDark = brightness == Brightness.dark;

  // Get appropriate colors for brightness
  final primaryColor = AppColorsRedesign.primary;
  final surfaceColor = AppColorsRedesign.getSurfaceColor(brightness, 0);
  final backgroundColor = AppColorsRedesign.getSurfaceColor(brightness, 1);
  final textPrimary = AppColorsRedesign.getTextColor(brightness);
  final textSecondary = AppColorsRedesign.getTextColor(brightness, secondary: true);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,

    // Color scheme
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: AppColorsRedesign.primaryLight,
      onPrimaryContainer: isDark ? Colors.white : AppColorsRedesign.textPrimary,

      secondary: AppColorsRedesign.info,
      onSecondary: Colors.white,
      secondaryContainer: AppColorsRedesign.info.withValues(alpha: 0.2),
      onSecondaryContainer: AppColorsRedesign.info,

      tertiary: AppColorsRedesign.streakGold,
      onTertiary: Colors.white,
      tertiaryContainer: AppColorsRedesign.streakGold.withValues(alpha: 0.2),
      onTertiaryContainer: AppColorsRedesign.streakGold,

      error: AppColorsRedesign.error,
      onError: Colors.white,
      errorContainer: AppColorsRedesign.error.withValues(alpha: 0.2),
      onErrorContainer: AppColorsRedesign.error,

      surface: surfaceColor,
      onSurface: textPrimary,
      surfaceContainerHighest: AppColorsRedesign.getSurfaceColor(brightness, 2),

      outline: isDark ? AppColorsRedesign.borderDark : AppColorsRedesign.borderLight,
      outlineVariant: isDark
          ? AppColorsRedesign.borderDark.withValues(alpha: 0.5)
          : AppColorsRedesign.borderLight.withValues(alpha: 0.5),

      shadow: Colors.black.withValues(alpha: 0.05),
      scrim: Colors.black.withValues(alpha: 0.5),
      inverseSurface: isDark ? Colors.white : Colors.black,
      onInverseSurface: isDark ? Colors.black : Colors.white,
      inversePrimary: isDark ? AppColorsRedesign.primaryLight : AppColorsRedesign.primary,

      surfaceTint: primaryColor.withValues(alpha: 0.05),
    ),

    // Scaffold background
    scaffoldBackgroundColor: backgroundColor,

    // App bar theme
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypographyRedesign.display3(context).copyWith(
        color: textPrimary,
      ),
    ),

    // Card theme
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      margin: EdgeInsets.all(AppSpacing.space3),
    ),

    // Elevated button theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.space6,
          vertical: AppSpacing.space3,
        ),
        minimumSize: Size(AppSpacing.buttonMd, AppSpacing.buttonMd),
        textStyle: AppTypographyRedesign.label(context),
      ),
    ),

    // Text button theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: AppTypographyRedesign.label(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
    ),

    // Outlined button theme
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: BorderSide(color: primaryColor, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.space6,
          vertical: AppSpacing.space3,
        ),
        minimumSize: Size(AppSpacing.buttonMd, AppSpacing.buttonMd),
        textStyle: AppTypographyRedesign.label(context),
      ),
    ),

    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorsRedesign.getSurfaceColor(brightness, 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(
          color: isDark ? AppColorsRedesign.borderDark : AppColorsRedesign.borderLight,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(
          color: isDark ? AppColorsRedesign.borderDark : AppColorsRedesign.borderLight,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(
          color: primaryColor,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(
          color: AppColorsRedesign.error,
        ),
      ),
      contentPadding: EdgeInsets.all(AppSpacing.space4),
      hintStyle: AppTypographyRedesign.bodyMedium(context).copyWith(
        color: textSecondary,
      ),
    ),

    // Chip theme
    chipTheme: ChipThemeData(
      backgroundColor: AppColorsRedesign.getSurfaceColor(brightness, 2),
      selectedColor: primaryColor.withValues(alpha: 0.2),
      disabledColor: AppColorsRedesign.getSurfaceColor(brightness, 1),
      labelStyle: AppTypographyRedesign.bodyMedium(context),
      secondaryLabelStyle: AppTypographyRedesign.bodySmall(context),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
    ),

    // Dialog theme
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      titleTextStyle: AppTypographyRedesign.display3(context).copyWith(
        color: textPrimary,
      ),
      contentTextStyle: AppTypographyRedesign.bodyMedium(context).copyWith(
        color: textSecondary,
      ),
    ),

    // Bottom navigation bar theme
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surfaceColor,
      selectedItemColor: primaryColor,
      unselectedItemColor: textSecondary,
      selectedLabelStyle: AppTypographyRedesign.caption(context).copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypographyRedesign.caption(context),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),

    // Progress indicator theme
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: AppColorsRedesign.progressIncomplete,
    ),

    // Floating action button theme
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
    ),

    // Text theme
    textTheme: TextTheme(
      displayLarge: AppTypographyRedesign.display1(context),
      displayMedium: AppTypographyRedesign.display2(context),
      displaySmall: AppTypographyRedesign.display3(context),
      bodyLarge: AppTypographyRedesign.bodyLarge(context),
      bodyMedium: AppTypographyRedesign.bodyMedium(context),
      bodySmall: AppTypographyRedesign.bodySmall(context),
      labelLarge: AppTypographyRedesign.label(context),
      labelMedium: AppTypographyRedesign.caption(context),
      labelSmall: AppTypographyRedesign.overline(context),
    ),

    // Icon theme
    iconTheme: IconThemeData(
      color: textPrimary,
      size: 24,
    ),
  );
}
