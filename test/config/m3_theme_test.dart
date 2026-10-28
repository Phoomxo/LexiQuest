import 'package:flutter/material.dart';
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

  test('display preference preserves platform reduced motion fail closed', () {
    const platformReduced = MediaQueryData(disableAnimations: true);
    const platformAnimated = MediaQueryData(disableAnimations: false);

    expect(
      M3Theme.applyReducedMotionPreference(
        platformReduced,
        reduceMotion: false,
      ).disableAnimations,
      isTrue,
    );
    expect(
      M3Theme.applyReducedMotionPreference(
        platformAnimated,
        reduceMotion: true,
      ).disableAnimations,
      isTrue,
    );
    expect(
      M3Theme.applyReducedMotionPreference(
        platformAnimated,
        reduceMotion: false,
      ).disableAnimations,
      isFalse,
    );
  });

  test('motion duration becomes static only for effective reduced motion', () {
    expect(
      M3Theme.motionDuration(
        const Duration(milliseconds: 300),
        mediaQuery: const MediaQueryData(disableAnimations: true),
      ),
      Duration.zero,
    );
    expect(
      M3Theme.motionDuration(
        const Duration(milliseconds: 300),
        mediaQuery: const MediaQueryData(disableAnimations: false),
      ),
      const Duration(milliseconds: 300),
    );
  });
}
