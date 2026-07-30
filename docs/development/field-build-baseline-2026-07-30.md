# Field Build Baseline — 2026-07-30

- Commit: `d707dbf`
- Flutter: `3.44.7` stable, framework `84fc5cbb22`
- Dart: `3.12.2` stable
- Platform: Windows development host; Android debug APK target
- Working-tree exclusions: generated Linux/macOS/Windows plugin files and
  untracked `AGENTS.md`

| Check | Result | Classification | Planned gate |
|---|---|---|---|
| Flutter analyze | PASS — zero issues | baseline | P0-P1 |
| Focused runtime/progress/learning/navigation tests | PASS — 57 tests | baseline | P0-P1 |
| Android debug APK | PASS — `build/app/outputs/flutter-apk/app-debug.apk` | baseline | P0-P1 |
| Android Gradle Plugin support warning | AGP 8.9.1 will require upgrade to 8.11.1 or later | toolchain warning | P8 |
| Kotlin support warning | Kotlin 2.1.0 will require upgrade to 2.2.20 or later | toolchain warning | P8 |
| Android SDK XML warning | command-line tools and Android Studio SDK metadata versions differ | environment warning | P8 |
| Retracted transitive `jni` package | resolved `jni` 1.0.1 is retracted; 1.0.2 is available | dependency warning | P4 |

## Commands

```powershell
flutter analyze
flutter test test/runtime test/progress test/learning test/screens/main_navigation_screen_test.dart --reporter compact
flutter build apk --debug `
  --dart-define=LEXIQUEST_VERSION=1.0.0+1 `
  --dart-define=LEXIQUEST_BUILD_ID=p0-baseline `
  --dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001 `
  --dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000
```

The first analyzer, test, and build invocations were terminated by the CLI
execution timeout before the Flutter process could finish. Each command was run
once more with a bounded timeout appropriate to its observed duration. The
second invocation produced the results above; there was no code or dependency
change between timeout termination and the controlled rerun.

## Baseline Decision

P0-P1 starts from a passing analyzer, focused foundation suite, and Android
debug build. The recorded toolchain and dependency warnings are not caused by
the local-first package and do not interrupt it. They remain release-gate work
because the field-signed APK must not ship on a toolchain that Flutter reports
as approaching end of support.
