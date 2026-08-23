# Shared Compatibility Foundation Verification Record

Verification date: 2026-08-24

## Verified baseline

- Pre-document HEAD: `b486544fed57cc373a7d0a59511bb137d26d9c44`
- Reviewed baseline: `c4ec20d2d7fd04e5b6a860fed5d17de9eb0ca612..b486544fed57cc373a7d0a59511bb137d26d9c44`
- Database: `AppDatabase` schema v15 with exactly 33 current tables. The forward-only v14→v15 migration adds only `assessment_runs` (32→33).
- Product contract: revision `1.0.0`, semantic SHA-256 `f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0`, 44 product contracts, and 15 runtime features.

## Production handoff state

The foundation is `implementedOff`:

- Evidence policy defaults to Legacy and AnswerAttempt writes default to payload v1.
- Research collection sync is Off: both experiment-assignment and assessment-run claims are false.
- The assessment application dependency is nullable and is not supplied by production composition.
- No learner-facing 8/44 capability is enabled merely because the foundation is present.

The verified foundation retains the established isolation boundaries: assessment is invocation-off and isolated from learning/motivation projections, and recreational evidence remains excluded from Active Effort.

## Verification commands

| # | Command | Exit | Recorded result |
|---:|---|---:|---|
| 1 | `flutter test --no-pub test/architecture/fitness_test.dart` | 0 | passed |
| 2 | `dart format --output=none --set-exit-if-changed lib test tool` | 0 | 314 files checked, 0 changed |
| 3 | `flutter analyze` | 0 | no issues |
| 4 | `dart run tool/feature_contract/generate_feature_map.dart --check` | 0 | passed |
| 5 | `flutter test --no-pub test/architecture` | 0 | 150 passed |
| 6 | `flutter test --no-pub test/features/learning` | 0 | 136 passed |
| 7 | `flutter test --no-pub test/features/progress` | 0 | 7 passed |
| 8 | `flutter test --no-pub test/features/rewards` | 0 | 58 passed |
| 9 | `flutter test --no-pub test/features/research` | 0 | 8 passed |
| 10 | `flutter test --no-pub test/features/assessment` | 0 | 41 passed |
| 11 | `flutter test --no-pub test/features/sync` | 0 | 196 passed |
| 12 | `flutter test --no-pub test/features/export` | 0 | 16 passed |
| 13 | `flutter test --no-pub test/features/identity` | 0 | 51 passed |
| 14 | `flutter test --no-pub test/database` | 0 | 29 passed |
| 15 | `flutter test --no-pub test/data/local` | 0 | 9 passed |
| 16 | `flutter test --no-pub test/scenarios/complete_owner_export_delete_test.dart` | 0 | 6 passed |
| 17 | `npm run test:rules` | 0 | 60/60 against the local emulator |
| 18 | `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1` | 0 | PASS: CLI/release-packaging/format/analyze/feature-contracts/generated-artifacts/product-completion/integration-journeys/Auth-emulator/Rules/APK/model-integrity/diff; product completion 1087; three integration journeys 1/1 each; Auth 3/3; Rules 60/60 |
| 19 | `flutter build apk --debug` | 0 | debug candidate built |
| 20 | `Get-FileHash -Algorithm SHA256 build/app/outputs/flutter-apk/app-debug.apk` | 0 | `DE7F3F0C11AD7E940C2EBA231BAB85BD7D621CAC6A755565C131E46A4363FE06` |
| 21 | `git diff c4ec20d...HEAD --stat` | 0 | reviewed |
| 22 | `git diff c4ec20d...HEAD -- lib test tool firestore.rules docs` | 0 | reviewed |
| 23 | `git status --short` | 0 | only the seven known generated plugin registrants carried EOL metadata; no substantive or untracked product changes |
| 24 | `git diff --ignore-space-at-eol --exit-code -- linux/flutter/generated_plugin_registrant.cc linux/flutter/generated_plugin_registrant.h linux/flutter/generated_plugins.cmake macos/Flutter/GeneratedPluginRegistrant.swift windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugin_registrant.h windows/flutter/generated_plugins.cmake` | 0 | content diff zero |

## Debug APK

- Path: `C:\Users\Phet\.codex\worktrees\e559\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`
- Bytes: `253636933`
- SHA-256: `DE7F3F0C11AD7E940C2EBA231BAB85BD7D621CAC6A755565C131E46A4363FE06`

This is a debug-signed candidate, not release-signed. It does not replace the frozen field-release candidate.

## Late journey TDD evidence

- Default-timezone RED: exit 1; expected `Asia/Bangkok`, received `SE Asia Standard Time`.
- After the minimal canonical-IANA fix: targeted GREEN 1/1, full `app_bootstrap_test` 39/39, and the core field-trial journey 1/1.
- Independent final review: Critical 0, Important 0, READY.
- The product-completion verifier finished PASS.

## Explicitly skipped external actions

No Firestore Rules deployment, production cloud deployment, release signing or release packaging, frozen field-release replacement, push, or merge was performed. The local emulator Rules result is verification evidence only; it is not deployment evidence.
