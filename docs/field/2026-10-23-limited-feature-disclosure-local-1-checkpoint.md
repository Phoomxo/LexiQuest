# LIMITED-FEATURE-DISCLOSURE-LOCAL-1 checkpoint

## Status and authority

- Date: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Authority: bounded UI/catalog card with one production writer and serialized Flutter checks.
- ADLC: Intent, Ground, Plan, Execute, Review and Attest completed.
- Status: local engineering complete; return the writer and Flutter slot to LQ-00. This is not release, deployment or production approval.
- Source state: pre-existing dirty shared checkout. Unrelated user and agent changes were preserved; `git diff HEAD` is not a card-only delta.

## Grounded behavior

- `BuildFieldFeatureRegistry.fieldDefaults()` remains the sole availability authority.
- `objectScanner`, `speechPractice` and `aiTutor` are `limited`; hidden features remain absent and enabled features do not receive limited-state copy.
- The drawer previously asked only `isVisible()`, so limited entries looked identical to enabled entries.
- Existing destinations already provide the required recovery/setup flows: camera permission and verified model download, microphone permission and device speech recognition, and Gemini BYOK key plus consent.

## Bounded change

Actual write set:

1. `lib/screens/main_navigation_screen.dart`
   - Reads `stateOf()` from the existing registry for the three already-visible limited features.
   - Shows plain Thai status and a concrete reason for each feature.
   - Adds a visible setup action that reuses the existing scanner, speaking practice and Gemini settings routes.
   - Keeps each normal tile action intact and adds no flag, authority, dependency or new route.
   - Places the setup action under the explanation so the drawer remains operable at 200% text scale.
2. `test/screens/main_navigation_screen_test.dart`
   - Proves limited status/reasons/actions, Gemini settings navigation, enabled-state omission and 200% text reflow.
   - Updates the existing field-composition assertion to scroll the now-taller drawer before checking later entries.
3. This checkpoint.

No registry defaults, settings implementation, source practice, schema, generated source, backend, native code or research contract changed.

## TDD and recovery evidence

The first focused RED run exited 1 because zero `ทดลองใช้` disclosures existed. After the initial implementation, the 200% text test exposed a real `ListTile` assertion because a trailing button consumed the remaining drawer width. Moving the CTA below the description corrected the root layout constraint; the same test then passed without exceptions.

## Final verification on current source

```powershell
flutter test --no-pub test/screens/main_navigation_screen_test.dart --reporter expanded
```

Result: exit 0, **13/13 passed**.

```powershell
flutter test --no-pub test/runtime/field_feature_registry_test.dart --reporter expanded
```

Result: exit 0, **4/4 passed**.

```powershell
flutter analyze --no-pub lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart
dart format --output=none --set-exit-if-changed lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart
git diff --check -- lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart
```

- Scoped analyzer: exit 0, no issues.
- Formatter: exit 0, 2 files / 0 changed.
- Scoped diff check: exit 0; Git emitted LF-to-CRLF warnings only. No line-ending normalization was performed.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/screens/main_navigation_screen.dart` | `FB85B6112FF7EC1BD3536BCC2ACB1CE8C55F1C7F5834E1995CAD76A456B5AA6E` |
| `test/screens/main_navigation_screen_test.dart` | `4CFED644E9DB451796FCAD26183B75A2FE38A7C527D4714C59D7A25CAF68746E` |

## Review disposition and remaining integration work

- Accepted: feature state comes from the existing registry, Thai copy identifies the restriction, setup actions are explicit and reuse existing flows, hidden behavior is unchanged, and large text does not overflow.
- Not verified in this card: repository-wide regression, APK build and physical-device drawer traversal. LQ-00 owns those integration checks on a consistent source snapshot.
- Risk: reasons are presentation copy tied to the existing limited states. If the underlying permission/model/BYOK requirements change, this copy must change with the affected flow; it does not decide availability.
