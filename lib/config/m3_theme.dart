import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized Material 3 Design System and Theme configuration for LexiQuest.
class M3Theme {
  const M3Theme._();

  static double appBarToolbarHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return scale >= 1.5 ? 96 : kToolbarHeight;
  }

  static Widget appBarTitle(BuildContext context, String label) {
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  static const Color primary = Color(0xFF5A4CF2);
  static const Color mastery = Color(0xFF0E8176);
  static const Color momentum = Color(0xFFD98213);
  static const Color momentumInk = Color(0xFF6B3E00);
  static const Color error = Color(0xFFB3261E);
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF171A2B);
  static const Color muted = Color(0xFF626A80);
  static const Color border = Color(0xFFDDE1EC);
  static const Color oceanLight = Color(0xFF075985);
  static const Color oceanDark = Color(0xFF7DD3FC);
  static const Color oceanDarkInk = Color(0xFF082F49);
  static const Color focusBackgroundLight = Color(0xFFEFF8FA);
  static const Color focusBackgroundDark = Color(0xFF0E2027);

  /// Light Theme Data for Material 3
  static ThemeData get lightTheme => lightThemeFor();

  static ThemeData lightThemeFor({String? themeId, String? wallpaperId}) {
    final selectedPrimary = themeId == 'theme_ocean' ? oceanLight : primary;
    final selectedBackground = wallpaperId == 'wallpaper_focus'
        ? focusBackgroundLight
        : background;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: selectedPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: selectedPrimary,
          onPrimary: Colors.white,
          secondary: mastery,
          onSecondary: Colors.white,
          tertiary: momentum,
          onTertiary: ink,
          tertiaryContainer: const Color(0xFFFFDDB8),
          onTertiaryContainer: momentumInk,
          error: error,
          onError: Colors.white,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: border,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'NotoSansThai',
      scaffoldBackgroundColor: selectedBackground,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        color: surface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: selectedBackground,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
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
  static ThemeData get darkTheme => darkThemeFor();

  static ThemeData darkThemeFor({String? themeId, String? wallpaperId}) {
    final isOcean = themeId == 'theme_ocean';
    final selectedPrimary = isOcean ? oceanDark : primary;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: selectedPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: selectedPrimary,
          onPrimary: isOcean ? oceanDarkInk : Colors.white,
          secondary: mastery,
          onSecondary: Colors.white,
          tertiary: momentum,
          onTertiary: ink,
          tertiaryContainer: const Color(0xFF513000),
          onTertiaryContainer: const Color(0xFFFFDDB8),
          error: error,
          onError: Colors.white,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'NotoSansThai',
      scaffoldBackgroundColor: wallpaperId == 'wallpaper_focus'
          ? focusBackgroundDark
          : null,
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: colorScheme.surface,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
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
