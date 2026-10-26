# LQ-02 A1 Startup Restore checkpoint

- วันที่: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- ADLC: Intent / Ground / Plan / Execute / Review / Attest completed for bounded A1; integration disposition belongs to LQ-00.
- Authority: source coordinator's existing exclusive A1 production-writer and serialized Flutter-slot grant, reconciled by integration root. No second writer dispatch. Exact write set: the four code/test files below plus this checkpoint.
- Status: bounded local A1 engineering accepted by independent review; RETURN writer/Flutter slot to LQ-00. Not whole-account completion or release approval.
- Source state: pre-existing dirty checkout, including T1 appearance and I5a Gemini composition/tests. Their changes are retained; `git diff HEAD` is not the A1-only delta.
- Fixtures: synthetic sessions and in-memory Drift only. No live provider, credentials, participant data or production operation.

## Outcome and scope

Normal platform `/` launch after bootstrap now selects:

| Published runtime/session | Initial destination |
| --- | --- |
| Firebase ready, registered verified | Home, without Login underneath |
| Firebase ready, anonymous | Home, without Login underneath |
| Firebase ready, registered unverified | Existing verification screen with `EmailVerificationArgs`; Back reaches Login |
| Session absent, Firebase unavailable, or session getter fails | Existing Login/local Guest entry |

- Startup selection is cached once per app state, so appearance/theme or root rebuild does not replace current navigation or reread the startup session.
- Explicit nondefault routes and password-reset deep links retain existing route-factory behavior. This does not introduce an auth guard for explicit `/home`.
- Route selection reads only; it does not sign in, reconcile, rebind, merge or upgrade. Bootstrap still uses the existing `AccountUseCases.reconcileLocalOwner()` authority.
- Account gateway construction moved inside the existing bootstrap try. Factory/session-reconciliation failure disables published account/sync while retaining local learning and explicit Guest entry.
- A/B owner isolation, same-UID idempotency and provider-confirmed anonymous upgrade are reused, not rewritten.

Actual A1 writes:

1. `lib/main.dart`: startup status import, cached platform/route selection, typed initial verification stack, restored-session destination selection. Existing appearance stream/theme/lifecycle wiring retained.
2. `lib/runtime/app_bootstrap.dart`: move candidate construction inside its existing try; no other A1 production changes.
3. `test/runtime/account_startup_restore_test.dart` (new): 13 widget cases for verified/anonymous/unverified restore, typed arguments/Back, absent/unavailable/error fallback, explicit routes, reset deep link and navigation-preserving rebuild.
4. `test/runtime/app_bootstrap_test.dart`: seven synthetic bootstrap cases plus minimal fixtures for factory/read failure, unavailable Firebase, registered/anonymous reconciliation and restoring existing/new B while A remains intact. Existing I5a `GeminiTutorMode` fake signature retained.
5. This dated checkpoint.

No account/identity implementation, route registry/factory, Google sign-in, deletion flow, consent, schema/migration, dependency/lockfile, feature catalog, learning/reward authority, production Firebase/App Check configuration, deployment or real research upload changes.

## Attribution baseline before A1

| Path | Pre-A1 SHA-256 |
| --- | --- |
| `lib/main.dart` | `943B03ABC9931DDF03C37A2DF7831F7629A66E6511D2161ED4CE453530235F6B` |
| `lib/runtime/app_bootstrap.dart` | `8D52606C2494335A0F988C04637280F9D39BECF8F745F62624C2701DEE187923` |
| `test/runtime/app_bootstrap_test.dart` | `729824394323661C0CCBC6966B9AFE56049E82E954913E07E901EC0E826BED94` |

No equivalent startup-restore test/checkpoint existed in the discovered `test/runtime` / `docs/field` paths before creation. Baseline bootstrap-test hash includes the preceding I5a fake-signature update.

## Test and review evidence

### Behavioral RED then GREEN

```powershell
flutter test --no-pub test/runtime/account_startup_restore_test.dart test/runtime/app_bootstrap_test.dart
```

- Before production edits: exit 1, **33 passed / 4 failed**. Verified and anonymous restores did not reach Home, unverified restore did not reach verification, and synthetic account-factory exception escaped bootstrap. No compilation failures.
- After the minimal production correction: exit 0, **37 passed**.

### Final formatted-source connected regression

```powershell
flutter test --no-pub test/runtime/account_startup_restore_test.dart test/runtime/app_bootstrap_test.dart test/features/account test/features/identity test/services/guest_session_service_test.dart test/screens/login_guest_mode_test.dart test/screens/registration_flow_test.dart test/screens/otp_screen_test.dart test/runtime/reward_appearance_restore_test.dart test/runtime/app_build_info_test.dart test/screens/production_shell_navigation_test.dart test/screens/main_navigation_screen_test.dart
```

Result: exit 0, **145 tests passed**. Includes existing account A/B evidence/outbox/ack preservation, anonymous upgrade, identity inventory, Guest rollback, auth screens, appearance navigation and shell checks. Flutter commands were serialized; no implementation edits followed this test run.

```powershell
flutter analyze --no-pub lib/main.dart lib/runtime/app_bootstrap.dart test/runtime/app_bootstrap_test.dart test/runtime/account_startup_restore_test.dart
dart format --output=none --set-exit-if-changed lib/main.dart lib/runtime/app_bootstrap.dart test/runtime/app_bootstrap_test.dart test/runtime/account_startup_restore_test.dart
git diff --check -- lib/main.dart lib/runtime/app_bootstrap.dart test/runtime/app_bootstrap_test.dart
git diff --no-index --check -- NUL test/runtime/account_startup_restore_test.dart
```

- Scoped analysis: exit 0, **No issues found**.
- Final format verification: exit 0, **4 files / 0 changed**.
- Tracked diff check: exit 0; no whitespace errors. New test no-index check: exit 1 for differing content, no whitespace errors. Git emitted LF-to-CRLF warnings; no line-ending normalization or cleanup was performed.
- Final production diff and new widget test inspected; predecessor T1/I5a/source-picker changes left intact.
- Independent read-only reviewer `/root/a1_read_only_review`: **Critical 0 / Important 0 / Minor 0**, accepted for bounded local A1, no must-fix. Reviewed current source, connected callers/tests and whitespace; did not write or run competing Flutter commands.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/main.dart` | `9747EAD8BCB702934723531C19EF52A96BE207856A2282CA7D9A230CBC7ABE31` |
| `lib/runtime/app_bootstrap.dart` | `D5573B4D30C17C0A8D4E8E0A76F3FF3958A0122CBDE53657B3C2DFDFF2254F91` |
| `test/runtime/app_bootstrap_test.dart` | `CECAAE80250168C91C1972E439546F533EF2D4AAE3C546367389F6153E63C69B` |
| `test/runtime/account_startup_restore_test.dart` | `76FD1511C08CCA9AF289CB2821128AC592FE34469D427CC9E064052B073DFA40` |

Untouched account authorities rechecked:

| Path | SHA-256 |
| --- | --- |
| `lib/features/account/application/account_use_cases.dart` | `CB992098C171352ED58B4C892E6056733B6A6D2D473C8BE9085CF95A0C4F29D9` |
| `lib/features/account/data/firebase_account_gateway.dart` | `65181C55DB3F485388A4FE28B68F10E4AB71C0293B3F48BDC6B6A9771EEFDF63` |

## RETURN, limits and next executable step

- Process check at handoff: zero `dart.exe`, `dartaotruntime.exe`, `flutter_tester.exe` or `flutter.exe` workers; no task-owned test/build session remains. No process killed and no files cleaned up.
- RETURN: release A1 production-writer/Flutter slot to LQ-00 after manifest reconciliation. No further A1 source edits or Flutter commands after RETURN.
- Next: LQ-00 accepts this bounded snapshot and controls dispatch of LQ-07 S2; this checkpoint does not dispatch another card.
- Not run: full repository suite/build, physical device/native restart, real Firebase persistence/provider/deep-link tests. Synthetic widget route behavior is not device evidence. Whole account, Google sign-in, deletion/export lifecycle and research/release readiness are not claimed.
- No deployment, publishing, enrollment, real upload or production configuration change authorized/performed. Card cap 28 / program cap 250 unchanged; actual spend unavailable, not represented as measured cost.
