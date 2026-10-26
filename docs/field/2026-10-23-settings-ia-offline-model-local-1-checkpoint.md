# SETTINGS-IA-OFFLINE-MODEL-LOCAL-1 checkpoint

## Status and authority

- Date: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Authority: bounded local Settings A1+A2 implementation in the shared dirty checkout.
- ADLC: Intent, Ground, Plan, Execute, Review and Attest completed.
- Status: local engineering complete. This checkpoint is not deployment or release approval.

## Grounded behavior

- `AppDependenciesScope.deviceModels` remains the production model lifecycle authority.
- `FieldFeatureRegistry` remains the visibility and enabled/limited/hidden authority.
- Existing Export, Gemini settings, Shadowing and Object Scanner screens remain the real destinations; no duplicate flow or route was added.
- Opening Settings reads local model status only. It does not request camera or microphone permission, open a provider, or start a download.

## Bounded change

Actual write set:

1. `lib/screens/setting_screen.dart`
   - Organizes plain-Thai rows for export, AI, voice, scanner and offline device content.
   - Hides hidden features and explains limited features before navigation.
   - Shows the device-model manifest version, exact expected bytes and local absent/downloading/verifying/ready/active/failed/cancelled state.
   - Starts `DeviceModelUseCases.downloadAndActivate()` only from the explicit button, blocks repeated taps, refreshes status, and reports success or a privacy-safe Thai failure.
   - Ignores delayed status/download completions after disposal or dependency replacement.
   - Preserves account, research consent, Cloud status, password and logout behavior.
2. `test/screens/setting_screen_test.dart`
   - Proves enabled/limited/hidden disclosure, Export/Gemini navigation and no download/media side effect on open.
   - Covers absent/downloading/active/failed model states, success, retry, one-flight behavior and delayed old-dependency completion.
   - Covers light 360x800 and dark 800x360 at 200% text with a 48dp model action.
3. This checkpoint.

No main navigation, composition root, schema/generated source, media gateway, research contract, Source Practice or Tutor file changed in this card.

## TDD and recovery evidence

- The first focused RED run failed because Settings had no feature rows or offline-model action/status UI.
- The first GREEN compile exposed the omitted private status enum; it was added without expanding scope.
- Placing the new cards before the existing research/Cloud cards made lazy-list tests unable to find existing controls. Moving the new cards after the established account/Cloud controls preserved prior behavior.
- The first download widget harness stalled on a real file lock before reaching its byte source. A narrow test-only download callback replaced filesystem orchestration in the widget test; production still calls `downloadAndActivate()` directly. Device-model lifecycle/file behavior remains covered by its existing focused unit tests.

## Final verification on current source

```powershell
flutter test --no-pub test/screens/setting_screen_test.dart --reporter expanded
```

Result: exit 0, **24/24 passed**.

```powershell
flutter analyze --no-pub lib/screens/setting_screen.dart test/screens/setting_screen_test.dart
dart format --output=none --set-exit-if-changed lib/screens/setting_screen.dart test/screens/setting_screen_test.dart
git diff --check -- lib/screens/setting_screen.dart
```

- Scoped analyzer: exit 0, no issues.
- Formatter: exit 0, 2 files / 0 changed in the final verification run.
- Tracked scoped diff check: exit 0; Git emitted the existing LF-to-CRLF notice only.
- `test/screens/setting_screen_test.dart` was already untracked in the shared checkout, so Git has no index baseline for a normal diff check; Dart format and analyzer covered its final source.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/screens/setting_screen.dart` | `A9142F334BE6CCA408924DBFBD887E2B9E15AB1AAB1F6B187A5CE92641499D82` |
| `test/screens/setting_screen_test.dart` | `6CA146C18590D8E02B8FF518BC8DA617DFA19C7FD14EACBF7ABBD58BCC00D89F` |

## Review disposition and remaining integration work

- Accepted: local Settings A1+A2 behavior and focused regression evidence.
- Not run in this card: repository-wide regression, APK build, emulator matrix or physical-device traversal. LQ-00 owns those serialized integration checks on a consistent source snapshot.
- Risk: limited-state explanations mirror the current feature defaults. If permission, provider or model requirements change, the copy must change with the affected flow.
