import 'package:flutter/material.dart';
import 'learning_feedback_theme.dart';

/// Centralized Material 3 Design System and Theme configuration for LexiQuest.
class M3Theme {
  const M3Theme._();

  static const Color primaryBlue = Color(0xFF1E88E5);
  static const Color accentIndigo = Color(0xFF3F51B5);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color cardSurface = Colors.white;
  static const pairFeedbackHold = Duration(milliseconds: 450);
  static const pairFeedbackFade = Duration(milliseconds: 150);

  /// Font family for proper Thai rendering across all screens.
  static const String thaiFontFamily = 'NotoSansThai';

  // Role sizes are shared by both themes. MediaQuery still owns text scaling.
  static TextTheme _learnerTextTheme(TextTheme base) => base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.4,
      letterSpacing: 0,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.5,
      letterSpacing: 0,
    ),
    titleSmall: base.titleSmall?.copyWith(fontSize: 14, height: 1.5),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.5,
      letterSpacing: 0,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 16,
      height: 1.5,
      letterSpacing: 0,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 14,
      height: 1.5,
      letterSpacing: 0,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
  );

  /// Applies the learner override without ever disabling a platform request
  /// for reduced motion.
  static MediaQueryData applyReducedMotionPreference(
    MediaQueryData platform, {
    required bool reduceMotion,
  }) => platform.copyWith(
    disableAnimations: platform.disableAnimations || reduceMotion,
  );

  static Duration motionDuration(
    Duration standard, {
    required MediaQueryData mediaQuery,
  }) => mediaQuery.disableAnimations ? Duration.zero : standard;

  /// Light Theme Data for Material 3
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundLight,
      extensions: const [LearningFeedbackTheme.light],
      visualDensity: VisualDensity.standard,
      fontFamily: thaiFontFamily,
    );

    return base.copyWith(
      textTheme: _learnerTextTheme(base.textTheme),
      dialogTheme: DialogThemeData(
        titleTextStyle: _learnerTextTheme(base.textTheme).titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: base.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        color: cardSurface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        titleTextStyle: _learnerTextTheme(base.textTheme).titleLarge,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  /// Dark Theme Data for Material 3
  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      extensions: const [LearningFeedbackTheme.dark],
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
      ),
      fontFamily: thaiFontFamily,
    );

    return base.copyWith(
      textTheme: _learnerTextTheme(base.textTheme),
      dialogTheme: DialogThemeData(
        titleTextStyle: _learnerTextTheme(base.textTheme).titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: base.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        titleTextStyle: _learnerTextTheme(base.textTheme).titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
