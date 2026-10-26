# LQ-02 A2 Email Action checkpoint

- วันที่: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` unchanged; no commit/staging/reset/cleanup.
- Authority: source coordinator's exclusive LQ-02 production writer and serialized Flutter/test/analyze/format transfer after G1 acceptance/coordinator RETURN. Coordinator checkpoint observed SHA-256 `B4D75EA8D457E5831A3A5BA3A46E9BC7072ECF012D8D3FACE0BEF81D54E0CCC0`.
- Exact write set: `lib/screens/email_action_screen.dart`, new `test/screens/email_action_screen_test.dart`, this checkpoint. Other dirty/untracked work is preserved.
- ADLC: Intent / Ground / Plan / Execute / Review / Attest completed for bounded A2; integration acceptance remains LQ-00's decision.
- Disposition: local A2 accepted by independent current-source read-only review, no must-fix; RETURN production-writer/Flutter slot. Not whole-account completion, provider reset idempotency or release approval.
- Data: clearly synthetic codes/passwords/gateway only; no real credentials, network/provider calls, research data or production operations.

## Ground and outcome

Before A2 the screen used `_status` for both success and error and rendered the reset field only when `_status == null`. A real widget behavioral RED demonstrated that submitting a five-character password invoked the provider zero times but removed the TextField, preventing correction in place.

Pre-A2 screen SHA-256: `A8A6A333D38C6E07C9D0BE4FC60D5D4AC4F904962E581CCF5D142C405E5940A9` (matched grant; production file was clean against HEAD). Equivalent-file discovery found no dedicated email-action screen test or A2 checkpoint before creation.

The fix is contained in the existing screen:

- Acknowledged success is separate from error/status. Weak-password, network and unexpected errors retain the form and allow explicit user retry; no timer or automatic reset retry.
- Pending disables password editing and submit. Method-level guards reject double submission, obsolete button callbacks, terminal-code retries and post-success submission. Password is cleared after acknowledged success and terminal invalid/expired-code errors.
- Invalid/expired errors retain a disabled, cleared form with recovery guidance, rather than claiming success. Unknown actions never dispatch a supported action. Missing account authority displays unavailable guidance and a usable Login return.
- Generation fences discard obsolete success/error/finally updates after action/account replacement; mounted checks discard updates after disposal. New pending work cannot be ended by an old acknowledgement. Semantic action identity compares mode/code, not allocation identity.
- Existing verification action starts once for the displayed action. Same-action rebuilds/dependency changes do not repeat it, including after failure; account-authority replacement shows guidance instead of silently re-consuming the code.
- Network/unexpected outcomes remain explicitly uncertain, including after a subsequent invalid/expired-code error. The provider may have committed before acknowledgement failed; retry is not promised idempotent and Back/dispose is not claimed to roll back a dispatched write.
- The existing Material screen keeps its visual identity. SafeArea, scrollable content, expandable minimum-48dp controls, labelled password field/autofill and live status support compact layouts and large text. No framework, theme or navigation redesign.

Existing authorities/callers inspected: AccountUseCases, AccountGateway/EmailAction contracts, FirebaseAccountGateway, AppRouteFactory, AppNavigator, AppDependenciesScope, A1 startup tests and connected auth fixtures. Reset still delegates validation and code consumption to existing application/provider boundaries. The currently signed-in local account is not the reset target authority. Tests assert zero unrelated gateway methods, owner repository access or upgrade/deletion calls even with another synthetic account open. No local-owner/recent-login gate was added. Separate Settings `reauthenticateWithCredential` then `updatePassword` is untouched.

No writes to main/bootstrap/settings, account contracts/use cases/gateway, identity/consent/research/reward/learning, dependencies/schema/generated/native/backend/provider configuration or other checkpoints. No additional persisted entity, migration reservation or 8/44 contract change.

## Test evidence and bounded recovery

### RED, before production edits

```powershell
flutter test --no-pub test/screens/email_action_screen_test.dart --reporter expanded
```

Exit 1: **3 passed / 20 failed**. No compile failures. Assertions exposed missing recovery/status/pending/context behavior; unexpected synthetic provider exceptions escaped the old screen. Four layout cases failed because the expected error/form was absent, not because a new layout fix had already been proven necessary.

The validation assertion was reordered to observe the root symptom before checking copy, without removing any assertion:

```powershell
flutter test --no-pub test/screens/email_action_screen_test.dart --plain-name 'invalid length 5 stays editable before provider' --reporter expanded
```

Exit 1: **0 passed / 1 failed**, expected one TextField but found zero; provider invocation count was zero. This is behavioral RED, not a claim derived solely from source inspection.

### Focused GREEN and current-source connected verification

```powershell
flutter test --no-pub test/screens/email_action_screen_test.dart --reporter expanded
```

Exit 0: **23 passed** after production fix. Repeated on formatted source after strengthening obsolete-callback and actual viewport/IME assertions: exit 0, **23 passed**. Awaited final process exit before the next Flutter command.

```powershell
flutter analyze --no-pub lib/screens/email_action_screen.dart test/screens/email_action_screen_test.dart
dart format --output=none --set-exit-if-changed lib/screens/email_action_screen.dart test/screens/email_action_screen_test.dart
```

Final scoped analyzer: exit 0, **No issues found**. Final format check: exit 0, **2 files / 0 changed**. Earlier analyzer reported one braces-style info in a test; fixed without behavior changes. The first patch for that style correction did not match the formatted lines; inspected actual lines, corrected once successfully, then reran checks. No unrelated recovery/cleanup.

```powershell
flutter test --no-pub test/screens/email_action_screen_test.dart test/features/account test/features/identity test/screens/otp_screen_test.dart test/screens/registration_flow_test.dart test/screens/login_guest_mode_test.dart test/runtime/account_startup_restore_test.dart test/runtime/app_bootstrap_test.dart test/runtime/reward_appearance_restore_test.dart test/architecture --reporter compact
```

Exit 0: **151 tests passed** on the final code/test snapshot. Includes new action-screen tests, account/identity isolation and upgrades, auth entry/OTP/registration, bootstrap/A1 and real route-factory reset-link behavior, appearance navigation and architecture boundaries. These counts overlap the focused run; they are not additive. No implementation/test edits followed this connected run.

### UI evidence, not physical-device evidence

Four new rendered-widget cases exercise light/dark themes at **360x800** and **800x360**, DPR 1, text scale **200%**, synthetic IME **300dp portrait / 120dp landscape**, bottom safe inset 24dp and reduced-motion preference. They assert actual MediaQuery size/insets/scaled type, correction/retry/success/Login navigation, no layout exception, scroll-reachable readable error, hit-testable submit and minimum-48dp button height. They use existing M3Theme rather than a new design system.

These are Flutter test-rendered synthetic layouts, not screenshots from a native emulator/device, actual keyboard/TalkBack evidence, measured screen contrast or physical-device UAT. Impeccable/ui-ux guidance influenced the SafeArea, expandable controls, status/recovery and layout checks; native capture remains outside this bounded grant.

### Diff and independent review

```powershell
git diff --check -- lib/screens/email_action_screen.dart
git diff --no-index --check -- NUL test/screens/email_action_screen_test.dart
```

Tracked diff: exit 0, no whitespace errors; new-file no-index: exit 1 because contents differ, no whitespace errors. LF-to-CRLF working-copy warnings only; no normalization. Final production diff inspected in full; production delta 156 insertions / 45 deletions in one file.

Independent read-only reviewer `/root/a2_read_only_review`: **Critical 0 / Important 0 / Minor 0**, accepted bounded local A2/no must-fix. Reviewer read current diff, tests and connected authorities/routes and verified the two final hashes/whitespace. Reviewer did not edit or run competing Flutter/Dart commands; test/analyzer evidence is the implementer's execution, not a second independent run. Claude: not available from prior endpoint evidence; no fresh call or 401 retry.

## Verified final manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/screens/email_action_screen.dart` | `EF36D84B94B2B404196099F2EEF8ADDB540371B90F2E5B88ED11B3DDF7660A3F` |
| `test/screens/email_action_screen_test.dart` | `3A779B1C09E04D67D802F056D58FBC45F1A329BF8E7C7417865B03BEFDD4376A` |

Unchanged connected boundaries inspected/rechecked:

| Path | SHA-256 |
| --- | --- |
| `lib/features/account/application/account_use_cases.dart` | `CB992098C171352ED58B4C892E6056733B6A6D2D473C8BE9085CF95A0C4F29D9` |
| `lib/features/account/data/firebase_account_gateway.dart` | `65181C55DB3F485388A4FE28B68F10E4AB71C0293B3F48BDC6B6A9771EEFDF63` |
| `lib/navigation/app_route_factory.dart` | `897C3E06C897C80EF164D0442498518F619AB948A9F848F272C0D63A2EDB71D3` |
| `lib/navigation/app_routes.dart` | `C703305B2AFE6EA062B76A23CB83394C02BF9B34C83C2B1D72DC74DC6FAA96F0` |
| `lib/main.dart` | `9747EAD8BCB702934723531C19EF52A96BE207856A2282CA7D9A230CBC7ABE31` |
| `lib/runtime/app_bootstrap.dart` | `FA7FDDCE3D74C6709954D69E9B344F65485CEEE001B4567DA812629C3FEC3A0D` |
| `test/runtime/app_bootstrap_test.dart` | `A1A4A6BF84CE4DD59C656D8AF26EDBDA7ADED71CAA9CECD4605558B324D69E5B` |
| `lib/screens/setting_screen.dart` | `A1DEE530176CE2BCF56214E00412C8DA7D88232CC978988E51C070538B3BE7E7` |

Bootstrap/test hashes reflect accepted S2 changes after A1, not a promise that the historical A1 manifest remains byte-identical. Existing A1 routing and account catch/reconcile logic remain in current source.

## RETURN and remaining boundaries

- At handoff, runtime worker check includes `dart.exe`, `dartvm.exe`, `dartaotruntime.exe`, `flutter_tester.exe`, `flutter.exe`: **0**; no task-owned test/build session remains. No processes killed or files deleted.
- RETURN exclusive LQ-02 production-writer and Flutter slot to LQ-00 after final manifest/checkpoint verification. No further code/test writes or Flutter/Dart commands after RETURN. LQ-00 owns acceptance and the next dispatch; this checkpoint dispatches nothing.
- Held external work: Google OAuth/client/provider enablement; trusted full account-deletion backend and owner/local/cloud/outbox/export/retention lifecycle; actual Firebase action-link/persistence/device/UAT evidence. S3a/v11 stays held/unreserved.
- Not run: full repository suite/APK/build, native emulator/device capture, actual accessibility services or live Firebase code consumption. No provider-level exactly-once/idempotency, durable retry/crash-resume, rollback of dispatched writes, whole-account completion, research efficacy or release-readiness claim.
- No deployment/publish/enrollment/real research upload/production configuration change or destructive cleanup. Existing LQ-02 cap 28 / program cap 250 unchanged; actual spend unavailable.
