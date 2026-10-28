import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lightTheme has Material 3 enabled and correct brightness', () {
    final theme = M3Theme.lightTheme;
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.light);
  });

  test('darkTheme has Material 3 enabled and dark brightness', () {
    final theme = M3Theme.darkTheme;
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  test('action text remains readable against each theme surface', () {
    for (final theme in [
      M3Theme.lightTheme,
      M3Theme.darkTheme,
      M3Theme.lightThemeFor(themeId: 'theme_ocean'),
      M3Theme.darkThemeFor(themeId: 'theme_ocean'),
      M3Theme.lightThemeFor(wallpaperId: 'wallpaper_focus'),
      M3Theme.darkThemeFor(wallpaperId: 'wallpaper_focus'),
    ]) {
      expect(
        _contrast(theme.colorScheme.primary, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(theme.colorScheme.primary, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('dark error text remains readable on surfaces', () {
    for (final theme in [
      M3Theme.darkTheme,
      M3Theme.darkThemeFor(themeId: 'theme_ocean'),
      M3Theme.darkThemeFor(wallpaperId: 'wallpaper_focus'),
    ]) {
      expect(
        _contrast(theme.colorScheme.error, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(theme.colorScheme.error, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('themes expose readable system-bar icon brightness', () {
    final lightOverlay = M3Theme.lightTheme.appBarTheme.systemOverlayStyle;
    final darkOverlay = M3Theme.darkTheme.appBarTheme.systemOverlayStyle;

    expect(lightOverlay?.statusBarIconBrightness, Brightness.dark);
    expect(lightOverlay?.systemNavigationBarIconBrightness, Brightness.dark);
    expect(darkOverlay?.statusBarIconBrightness, Brightness.light);
    expect(darkOverlay?.systemNavigationBarIconBrightness, Brightness.light);
  });

  test('lightTheme exposes the R11 semantic color roles', () {
    final theme = M3Theme.lightTheme;

    expect(theme.colorScheme.primary, const Color(0xFF5A4CF2));
    expect(theme.colorScheme.secondary, const Color(0xFF0E8176));
    expect(theme.colorScheme.tertiary, const Color(0xFFD98213));
    expect(theme.colorScheme.onTertiaryContainer, const Color(0xFF6B3E00));
    expect(theme.colorScheme.error, const Color(0xFFB3261E));
    expect(theme.colorScheme.surface, Colors.white);
    expect(theme.colorScheme.onSurface, const Color(0xFF171A2B));
    expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF626A80));
    expect(theme.colorScheme.outline, const Color(0xFFDDE1EC));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F6FA));
  });

  test('semantic foreground pairs meet text contrast in light and dark', () {
    for (final scheme in <ColorScheme>[
      M3Theme.lightTheme.colorScheme,
      M3Theme.darkTheme.colorScheme,
    ]) {
      expect(
        _contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.secondary, scheme.onSecondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.tertiary, scheme.onTertiary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.error, scheme.onError),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('themes use the R11 Thai typography and low-elevation cards', () {
    for (final theme in <ThemeData>[M3Theme.lightTheme, M3Theme.darkTheme]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'NotoSansThai');
      expect(theme.cardTheme.elevation, 0);

      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
    }
  });

  test('interactive button themes retain a 48dp minimum touch target', () {
    for (final style in <ButtonStyle?>[
      M3Theme.lightTheme.filledButtonTheme.style,
      M3Theme.lightTheme.outlinedButtonTheme.style,
      M3Theme.lightTheme.textButtonTheme.style,
      M3Theme.darkTheme.filledButtonTheme.style,
      M3Theme.darkTheme.outlinedButtonTheme.style,
      M3Theme.darkTheme.textButtonTheme.style,
    ]) {
      final size = style?.minimumSize?.resolve(<WidgetState>{});
      expect(size, isNotNull);
      expect(size!.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('adaptive app bar title stays readable at 200 percent text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              toolbarHeight: M3Theme.appBarToolbarHeight(context),
              title: M3Theme.appBarTitle(context, 'คลังคำศัพท์'),
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('คลังคำศัพท์'),
    );
    final title = tester.widget<Text>(find.text('คลังคำศัพท์'));
    expect(title.style?.fontSize, inInclusiveRange(20, 24));
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      M3Theme.appBarToolbarHeight(tester.element(find.byType(AppBar))),
      96,
    );
    expect(tester.takeException(), isNull);
  });

  test('reward appearance composes ocean colors and focus wallpaper', () {
    final light = M3Theme.lightThemeFor(
      themeId: 'theme_ocean',
      wallpaperId: 'wallpaper_focus',
    );
    final dark = M3Theme.darkThemeFor(
      themeId: 'theme_ocean',
      wallpaperId: 'wallpaper_focus',
    );

    expect(light.colorScheme.primary, const Color(0xFF075985));
    expect(light.scaffoldBackgroundColor, const Color(0xFFEFF8FA));
    expect(dark.colorScheme.primary, const Color(0xFF7DD3FC));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0E2027));
    expect(
      _contrast(light.colorScheme.primary, light.colorScheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(dark.colorScheme.primary, dark.colorScheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('unknown reward appearance falls back to the default themes', () {
    final light = M3Theme.lightThemeFor(
      themeId: 'unknown',
      wallpaperId: 'unknown',
    );
    final dark = M3Theme.darkThemeFor(
      themeId: 'unknown',
      wallpaperId: 'unknown',
    );

    expect(light.colorScheme.primary, M3Theme.lightTheme.colorScheme.primary);
    expect(light.scaffoldBackgroundColor, M3Theme.background);
    expect(dark.colorScheme.primary, M3Theme.darkTheme.colorScheme.primary);
  });
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
