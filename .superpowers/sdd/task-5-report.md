# Task 5 — Unified Material 3 theme report

## Scope

- Centralized application light and dark Material 3 tokens in `M3Theme`.
- Replaced the inline `main.dart` theme with the centralized light/dark themes
  and system theme mode.
- Preserved the default Flutter system text theme, which provides appropriate
  Thai and Latin font fallback. The `google_fonts` package remains unchanged.

## RED evidence

Command:

```powershell
flutter test test/config/m3_theme_test.dart
```

Result: failed as expected before the implementation. The new light token
contract observed the prior primary color, and the source-wiring contract
observed the inline `ThemeData`, `ColorScheme.fromSeed`, and `GoogleFonts`
usage in `main.dart`.

## GREEN evidence

Command:

```powershell
flutter test test/config/m3_theme_test.dart test/widget_test.dart test/screens/production_shell_navigation_test.dart
```

Result: passed, 12 tests.

The seeded color scheme required an explicit `primary: primaryBlue` override
to make the approved `#2457A7` token deterministic under the installed Flutter
version's seed-color derivation.

## Full verification

```powershell
dart format lib/config/m3_theme.dart lib/main.dart test/config/m3_theme_test.dart
flutter test
```

Result: formatting completed for all three files; the full Flutter suite
passed, 698 tests.

## Files changed

- `lib/config/m3_theme.dart`
- `lib/main.dart`
- `test/config/m3_theme_test.dart`

## Self-review

- `git diff --check` completed with no whitespace errors.
- An independent scoped diff review found no Critical, Important, or Minor
  issues.
- Confirmed `main.dart` has no inline `ColorScheme.fromSeed` or runtime
  `GoogleFonts` reference, retains all routes, and uses
  `M3Theme.lightTheme`, `M3Theme.darkTheme`, and `ThemeMode.system`.

## Follow-up: dark theme contrast correction

### RED evidence

```powershell
flutter test test/config/m3_theme_test.dart
```

Result: failed as expected after adding the dark primary/onPrimary WCAG
contract. The measured contrast was `1.8755643609552393:1`, below the required
minimum `4.5:1`. The cause was an explicit dark `primary` override paired with
an `onPrimary` value derived for the original seeded dark primary.

### GREEN evidence

The dark scheme now retains its seed-derived primary/onPrimary pair; the
explicit approved `#2457A7` primary remains limited to the light scheme.

```powershell
flutter test test/config/m3_theme_test.dart
dart format lib/config/m3_theme.dart test/config/m3_theme_test.dart
flutter test test/config/m3_theme_test.dart test/widget_test.dart test/screens/production_shell_navigation_test.dart
```

Result: the theme contract passed 5 tests; formatting completed; the requested
combined theme, widget, and shell suite passed 13 tests. The new contract also
asserts matching dark/light card elevation, app-bar alignment, and filled-button
minimum height.
