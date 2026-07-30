# P1 Local-First Gate — 2026-07-30

- Gate: `tool/cli/verify-local-first.ps1`
- Result: PASS, 6/6 phases
- Duration: 01:41
- Flutter: 3.44.7 stable
- Dart: 3.12.2
- Android artifact: `build/app/outputs/flutter-apk/app-debug.apk`
- APK size: 227,537,093 bytes
- APK SHA-256: `914BDB2B1D71D0E4B97E99D16B18AC6AA5C2F2B29D31194D44A761260D1F07F6`

| Phase | Result |
|---|---|
| Scoped formatting | PASS — 43 files, no changes |
| Scoped static analysis | PASS — 0 issues |
| Focused local-first tests | PASS — 51 tests |
| Screen infrastructure boundary | PASS — no direct Firebase, HTTP, or Drift imports |
| Android debug APK | PASS |
| Working-tree whitespace check | PASS |

## Verified behavior

- Drift schema version 1 contains the field data spine.
- The app creates one stable local owner before optional cloud startup.
- Firebase or Supabase startup failure does not block local vocabulary.
- Category, word, and import mutations are owner-scoped and append their outbox
  operation atomically.
- Import is bounded, cancellable, replay-safe, and enforces the 50-word limit.
- Category and vocabulary screens read and write through local application use
  cases.
- A guest can create a category and word, reconstruct the widget tree without
  cloud, and read the same local data.
- Application lifecycle disposal closes the local database exactly once.
- Field defaults hide participant-visible features that do not yet have real
  evidence-backed behavior.

## Deferred hardware evidence

No Android device was connected; `flutter devices` exposed only Windows,
Chrome, and Edge. The real-device force-stop/restart persistence journey remains
pending and must be executed when an Android test device is attached. This does
not invalidate the automated Drift reconstruction and APK build evidence.

## Non-blocking build warnings

Flutter reported future support floors for Android Gradle Plugin 8.9.1 and
Kotlin 2.1.0. Upgrade AGP to at least 8.11.1 and Kotlin to at least 2.2.20 in a
dedicated toolchain package; do not mix that upgrade into sync behavior.
