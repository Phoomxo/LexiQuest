# LQ-02 Identity & Account checkpoint

- วันที่: 2026-10-20, Asia/Bangkok
- Chat / card: LQ-02 Identity & Account / Wave 1 bounded account slice
- ADLC: Ground → regression RED → Execute → Review → Attest → handoff to LQ-00
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Source state: uncommitted LQ-02 changes on the pre-existing dirty checkout; the 11 content hashes below identify the verified slice. This is not a repository-wide freeze or release attestation.
- Authority: exclusive account/identity/profile/register writer and serialized Flutter slot granted by LQ-00 after LQ-03 handoff. Shared main/routes/bootstrap/pubspec/lock/schema/deletion wiring remained outside this grant.
- Data classification: synthetic in-memory fixtures; no real credentials, participant data or production operations.
- Status: local slice verified; whole LQ-02 workstream remains incomplete pending shared contracts and runtime evidence.

## Outcome and user-visible behavior

1. Restoring or explicitly signing into/registering B while local registered owner A is active preserves A's vocabulary, answer evidence, Firebase binding, cloud revisions, acknowledgement fields, outbox and sync cursor. Account binding first creates an isolated local context through the existing owner authority, then activates an existing B or binds a new B.
2. A provider-confirmed anonymous session captured before sign-in may still transfer its matching Guest owner into the authenticated account. Guest evidence is retained and requeued once. Same-UID reconciliation remains a no-op. A restored mismatched session alone does not authorize merging the previous owner's data.
3. Injected binding failures preserve A and sign out the provider. A subsequent reconciliation can continue with a local Guest context. No new merge/reward/learning authority was introduced.
4. Authenticated users can edit the profile display name through `AccountUseCases` and Firebase user metadata. Names are trimmed, contain 1–50 Unicode code points, and reject control characters. Absent, anonymous and mismatched active-owner sessions cannot update a profile. UI cancellation writes nothing; pending save cannot submit twice; a failed save retains the draft and supports retry.
5. Registration now requires password confirmation before invoking the account provider. Both password fields share the existing show/hide control. Controllers are disposed with the screen.

The profile name uses Firebase identity metadata only. It is not a new offline profile/preferences entity. Existing learning exports continue to exclude direct identity metadata; this work does not claim a complete account-data export/deletion lifecycle.

## Changed files and actual diff

Production files (6):

- `lib/features/account/application/account_use_cases.dart`: snapshot the previous provider session; isolate unrelated bound owners before the existing upgrade call; validate and authorize profile-name updates.
- `lib/features/account/domain/account_contracts.dart`: optional `AccountSession.displayName`, `AccountGateway.updateDisplayName`, `AccountFailureCode.invalidDisplayName`.
- `lib/features/account/data/firebase_account_gateway.dart`: read/update Firebase display name; reject missing/anonymous users and map provider failures safely.
- `lib/screens/login_screen.dart`: one exhaustive-switch arm required by the new failure enum value; no login flow redesign.
- `lib/screens/profile_settings_screen.dart`: display/edit account name, acknowledged-save/error/retry/cancel states and controller lifecycle.
- `lib/screens/register_screen.dart`: confirm-password field and mismatch guard.

Tests (5):

- `test/features/account/account_owner_isolation_test.dart` (new): 11 real Drift-backed regression cases, including restore/sign-in/register against existing/new B, same UID, anonymous upgrade, binding failure and owner-scoped export reader.
- `test/features/account/firebase_account_gateway_test.dart` (new): 3 Firebase adapter contract tests with synthetic users and provider failures.
- `test/features/account/account_use_cases_test.dart`: name validation, owner/session authorization and updated gateway fixture.
- `test/screens/profile_settings_screen_test.dart`: edit/cancel/retry/pending-save behavior and compact 200% text with synthetic 300dp keyboard inset.
- `test/screens/registration_flow_test.dart`: confirmation field and mismatch rejection.

Tracked-file diff: 9 files, 539 insertions / 12 deletions. The two new test files add 344 lines; total code/test delta is 11 files, 883 insertions / 12 deletions. This checkpoint is an additional documentation file. No pre-existing dirty changes were overwritten, staged, reset or deleted.

## Contracts/schema/routes/features affected

- Account API extension is contained in account modules; all current `AccountGateway` implementations/fixtures were inspected. The login failure switch was the only connected exhaustive enum caller needing an additional arm.
- Existing callers retain source compatibility because `AccountSession.displayName` is optional and screen constructor injection is optional.
- No route, shared dependency/composition-root, schema, migration, feature registry or 8/44 catalog mutation.
- No production Firebase/App Check enforcement/configuration change. No deploy, publish, enrollment or research upload.
- Existing owner repository/upgrade contracts, schema v10 and learning/reward authorities are reused without modification.

## Focused checks with exact results

### RED and bounded recovery

- Before the exclusive slot, `flutter test --no-pub test/features/account/account_use_cases_test.dart` failed twice before compilation due to shared `build/native_assets/windows/sqlite3.dll` contention. These attempts were not product RED evidence. No process was killed and no build output was deleted. The operation stopped until LQ-00 granted the slot.
- First isolated-regression run hit an `isNull` import ambiguity; corrected the test import to `package:drift/drift.dart hide isNull` before evaluating behavior.
- `flutter test --no-pub test/features/account/account_owner_isolation_test.dart` on the original production code then returned exit 1: **5 passed / 6 failed**. The six restore/sign-in/register cases demonstrated A→B binding/row migration or A's cloud revision/outbox reset. This was behavioral RED with the current API, independent of unfinished profile drafts.
- After the owner-boundary correction, `flutter test --no-pub test/features/account/account_owner_isolation_test.dart test/features/identity` returned exit 0: **34 passed**.
- Profile/register draft check `flutter test --no-pub test/features/account/account_use_cases_test.dart test/screens/registration_flow_test.dart test/screens/profile_settings_screen_test.dart` returned exit 1: missing proposed profile APIs plus registration's absent confirmation field/mismatch message (**1 passed / 4 failed**, including two file-loading failures). These are distinguished from the behavioral owner-isolation RED.
- Initial focused analysis reported one `curly_braces_in_flow_control_structures` info in the new profile dialog; the braces were corrected before final verification.

### Final source verification

```powershell
dart format --output=none --set-exit-if-changed lib/features/account/application/account_use_cases.dart lib/features/account/domain/account_contracts.dart lib/features/account/data/firebase_account_gateway.dart lib/screens/login_screen.dart lib/screens/register_screen.dart lib/screens/profile_settings_screen.dart test/features/account/account_use_cases_test.dart test/features/account/account_owner_isolation_test.dart test/features/account/firebase_account_gateway_test.dart test/screens/profile_settings_screen_test.dart test/screens/registration_flow_test.dart
```

Result: exit 0; **11 files, 0 changed**.

```powershell
flutter analyze --no-pub lib/features/account lib/features/identity lib/screens/login_screen.dart lib/screens/register_screen.dart lib/screens/profile_settings_screen.dart test/features/account test/screens/profile_settings_screen_test.dart test/screens/registration_flow_test.dart
```

Result: exit 0; **No issues found**.

```powershell
flutter test --no-pub test/features/account test/features/identity test/features/export/export_use_cases_test.dart test/services/guest_session_service_test.dart test/runtime/app_bootstrap_test.dart test/screens/registration_flow_test.dart test/screens/profile_settings_screen_test.dart test/screens/login_guest_mode_test.dart test/screens/otp_screen_test.dart test/screens/accessibility_smoke_test.dart
```

Result: exit 0; **105 tests passed** on the final formatted source, including Guest binding, owner-upgrade inventory, export, bootstrap, login/verification and compact auth accessibility regression checks. Firebase profile adapter tests use synthetic fake SDK objects; they are not live-provider evidence.

```powershell
git diff --check -- lib/features/account lib/screens/login_screen.dart lib/screens/register_screen.dart lib/screens/profile_settings_screen.dart test/features/account test/screens/registration_flow_test.dart test/screens/profile_settings_screen_test.dart
```

Result: exit 0; no whitespace errors. Git emitted existing LF→CRLF working-copy warnings; no line-ending normalization was performed. Both new test files were also inspected in full.

## Verified content hashes (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/features/account/application/account_use_cases.dart` | `CB992098C171352ED58B4C892E6056733B6A6D2D473C8BE9085CF95A0C4F29D9` |
| `lib/features/account/domain/account_contracts.dart` | `4734BC8DF45AC12F7D1E6704270A223B8817E9833304313164FCF46F64135E43` |
| `lib/features/account/data/firebase_account_gateway.dart` | `65181C55DB3F485388A4FE28B68F10E4AB71C0293B3F48BDC6B6A9771EEFDF63` |
| `lib/screens/login_screen.dart` | `BC3BE912919DBB7A231EB989FEDBDBCB532E22D89606720610A6C6FC85EFC4F2` |
| `lib/screens/register_screen.dart` | `BF2E3B64268694EEE128E3A4B8E46D513D278A9544254040B9B1611C9B5BD6A1` |
| `lib/screens/profile_settings_screen.dart` | `A5CB550C3414BEB92538A4BAD5E8612FC169653F4514AFC5AA38771E98CAEC6B` |
| `test/features/account/account_use_cases_test.dart` | `FCE4DA288F93F737487A9DD8391A209B7383486F40C2DA71668F5162C4750748` |
| `test/features/account/account_owner_isolation_test.dart` | `363068CDB90099F9662D246DAA5610E0770D87A6E12D4EBD864E8F633B43D249` |
| `test/features/account/firebase_account_gateway_test.dart` | `D18E13B0D9555C06BECEF736FD87F8D80B8E689DEA6889E7078779E6EE64489B` |
| `test/screens/profile_settings_screen_test.dart` | `3ABCD1C8F809195B2EAF48C20F6CED2A1D93FF9499256C81BF9AA82EC207CFDE` |
| `test/screens/registration_flow_test.dart` | `EB425FC3C53E5FD05388227C9B28525790C091B4807C9CBF426F23FA6C3E359E` |

## Claude review and local disposition

`Claude review: not available`.

Pre-implementation architecture critique used sanitized context and disabled tools. Initial CLI request returned `401 Invalid API key`; status identified environment-key authentication without printing the credential. One corrected process-local retry also returned 401. The retry budget was then closed. No fresh Claude result is claimed. Per LQ-00 direction, post-diff review used local source/tests rather than another unchanged authentication attempt.

Local review inspected connected account/identity/Firebase/Profile/Register/Login paths, all new tests and the actual diff. Dispositions:

- **accepted with local evidence**: registered A/B separation through the account boundary, preservation of tested A data/namespace fields, anonymous upgrade, same UID, injected binding failure, owner-scoped export reader, name validation/authorization and profile save/cancel/retry lifecycle.
- **accepted with local evidence**: confirmation mismatch prevents provider invocation; existing auth/Guest/bootstrap/export checks remain green.
- **not verified**: native Firebase/Google UI, real account linking, remote profile persistence after restart, physical Android/TalkBack, actual IME and foldable behavior. Widget inset simulation does not substitute for device evidence.
- **follow-up / pending shared contract**: Google dependency/provider wiring; authenticated startup route/deep-link handling in main/routes; complete account export/deletion with reauthentication, local/cloud/outbox coverage and partial-failure/retry semantics.
- **outside this slice**: research consent-row semantics and research authority gaps already held by LQ-00/LQ-08. Passing legacy consent/export tests does not establish research readiness.

No unresolved must-fix was found in the reviewed bounded diff. The entire Identity & Account workstream is not marked engineering-complete or release-ready.

## Device/external/release dependencies

Google auth remains unwired. Shared dependency/bootstrap/main/delete-account work requires a separate writer grant. No live provider, Firebase Auth emulator, Firestore policy suite, full Flutter regression, APK/device build or physical-device test was run in this slice. Provider displayName relies on Firebase identity metadata, and account deletion is still unavailable; the UI does not claim that deletion is implemented.

The 28-credit operating cap of this chat is unchanged. Actual provider billing is unavailable; no new budget was created or inferred.

## Processes and next executable step

The final Flutter test exited 0. A subsequent `Get-CimInstance Win32_Process` check filtered Dart/DartVM/Flutter tester commands for `flutter_tools.snapshot` and `flutter_test_listener` and returned **0** build/test processes. No task-owned process, background helper or code generator is retained; no process was killed.

LQ-02 releases its exclusive production/Flutter slot to LQ-00 after this handoff. LQ-00 should inspect the connected diff and verify the 11 hashes, then authorize LQ-04 as the next queue owner. LQ-02 will not start additional implementation/build work after release. Remaining shared account work can resume only under a later bounded contract and file-specific writer grant.
