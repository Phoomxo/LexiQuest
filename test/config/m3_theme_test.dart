import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';

Directory? _findRepoRoot(String start) {
  var directory = Directory(start);
  for (var depth = 0; depth < 16; depth++) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/lib').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
  return null;
}

Directory _repositoryRoot() {
  for (final start in <String>[
    File(Platform.script.toFilePath()).parent.path,
    Directory.current.path,
  ]) {
    final found = _findRepoRoot(start);
    if (found != null) return found;
  }
  return Directory.current;
}

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

  test('light theme uses the approved restrained component tokens', () {
    final theme = M3Theme.lightTheme;

    expect(theme.colorScheme.primary, const Color(0xFF2457A7));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
    expect(theme.cardTheme.elevation, 0);
    expect(theme.appBarTheme.centerTitle, isFalse);
    expect(theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height, 48);
  });

  test(
    'dark theme keeps accessible primary contrast and component geometry',
    () {
      final lightTheme = M3Theme.lightTheme;
      final darkTheme = M3Theme.darkTheme;
      final scheme = darkTheme.colorScheme;
      final primaryLuminance = scheme.primary.computeLuminance();
      final onPrimaryLuminance = scheme.onPrimary.computeLuminance();
      final brighterLuminance = primaryLuminance > onPrimaryLuminance
          ? primaryLuminance
          : onPrimaryLuminance;
      final darkerLuminance = primaryLuminance > onPrimaryLuminance
          ? onPrimaryLuminance
          : primaryLuminance;
      final contrastRatio = (brighterLuminance + .05) / (darkerLuminance + .05);

      expect(contrastRatio, greaterThanOrEqualTo(4.5));
      expect(darkTheme.cardTheme.elevation, lightTheme.cardTheme.elevation);
      expect(
        darkTheme.appBarTheme.centerTitle,
        lightTheme.appBarTheme.centerTitle,
      );
      expect(
        darkTheme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
        lightTheme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
      );
    },
  );

  test('application consumes M3Theme instead of declaring an inline seed', () {
    final source = File(
      '${_repositoryRoot().path}/lib/main.dart',
    ).readAsStringSync();

    expect(source, contains('theme: M3Theme.lightTheme'));
    expect(source, contains('darkTheme: M3Theme.darkTheme'));
    expect(source, isNot(contains('ColorScheme.fromSeed')));
    expect(source, isNot(contains('GoogleFonts.')));
  });
}
