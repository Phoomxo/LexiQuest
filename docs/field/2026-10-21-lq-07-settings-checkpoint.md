# LQ-07 S1 Settings / personal export checkpoint — 2026-10-21

## Disposition

**Ready for root acceptance as bounded S1 local engineering.** This handoff does
not claim release readiness, deployment approval, research enrollment authority,
real Cloud synchronization, or physical-device accessibility certification.

## Source and authority

- Existing checkout: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Authority: `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md`, section
  `LQ-07 S1 sole writer / Flutter grant`.
- The pre-existing dirty workspace was preserved. No commit, cleanup, reset,
  deployment, participant enrollment, provider request, or real-data upload was
  performed.

## Changed files

Only the granted five paths were written:

1. `lib/screens/setting_screen.dart`
2. `lib/screens/export_center_screen.dart`
3. `test/screens/setting_screen_test.dart` (new)
4. `test/screens/export_center_screen_test.dart` (new)
5. `docs/field/2026-10-21-lq-07-settings-checkpoint.md` (this file)

No sync engine/store, bootstrap, main, dependency composition, navigation,
schema/generated source, account/consent/export contract, reward authority,
rules, backend, or provider file changed. The existing feature-gated Export
route remains the only route; no duplicate link was added.

## Implemented behavior

- Account truthfulness distinguishes local Guest, Firebase anonymous Guest,
  registered-unverified, and registered-verified sessions without treating
  Firebase initialization as sync readiness.
- Research consent is read-only for every non-accepted state using the neutral
  text `ไม่ได้เข้าร่วม`; unavailable status fails closed. Only an accepted
  participant sees withdrawal, and withdrawal requires a scrollable
  confirmation dialog. Cancel writes nothing; confirm writes once.
- Manual Cloud uses the existing
  `SyncTrigger.request(SyncTriggerReason.manualRetry)`, disables concurrent
  submission, clears prior-run feedback when a new run starts, and reports only
  current-run completed / partial failure / cloud-disabled / unauthenticated /
  already-running / exception facts. It does not claim online state, queue
  count/emptiness, last-sync time, backoff bypass, or “sync all”.
- Personal rewards export is explicit opt-in and default-off, available only for
  CSV/PDF through the existing `includeRewards` authority, and resets false for
  Anki/Research. A personal reward-only CSV remains available after research
  withdrawal without mutating consent.
- Settings/export actions are full width where appropriate, have at least 48dp
  touch targets, remain scrollable at 360x800 with 200% text, and expose result
  feedback as a live region.

## TDD and review evidence

- Pre-edit connected baseline: **17 passed**.
- Initial RED established missing account/consent/manual-sync/reward-opt-in and
  accessibility behaviors before production edits.
- Reviewer returned `With fixes` for three source-backed issues: stale prior
  sync feedback, over-specific withdrawn wording, and unsupported remaining-
  queue claims. Added regression assertions first; the focused settings run
  failed in the expected four tests. Production was then corrected.
- Independent targeted re-review confirms all three findings resolved with
  **Verdict: Ready** and no remaining Critical/Important issue in S1 scope.

## Final verification on the current source

- `dart format --output=none --set-exit-if-changed` on the four source/test
  paths: **exit 0; 4 files, 0 changed**.
- `flutter analyze --no-pub` on the four source/test paths:
  **exit 0; No issues found**.
- Focused widget command for both new files: **exit 0; 12/12 passed**.
- Connected navigation, consent, export, cloud-policy, reward-transport, and
  architecture command: **exit 0; 49/49 passed**.
- Scoped tracked diff check and trailing-whitespace scan: no findings.
- Final task runtime inventory after tests: **0** matching Dart, Flutter,
  `flutter_tester`, or `gen_snapshot` processes.

Final focused command:

```text
flutter test --no-pub test/screens/setting_screen_test.dart test/screens/export_center_screen_test.dart
```

Final connected command:

```text
flutter test --no-pub test/screens/production_shell_navigation_test.dart test/features/consent/research_consent_use_cases_test.dart test/features/export/export_use_cases_test.dart test/features/sync/cloud_sync_policy_test.dart test/features/sync/reward_transaction_sync_test.dart test/architecture/fitness_test.dart
```

## Four-path SHA-256 manifest

```text
7D7B78D49E17917B667EAC6A1AD2382238E59466AB5A88E91336275D1C8C67A4  lib/screens/setting_screen.dart
ADE7B4E4693C5C21BA6E980756E1FA81AB7B2D0A5AB2781BC157AF7E88DF69CB  lib/screens/export_center_screen.dart
89F5C7FBB3D08581CCE1C449336822D8617D188B6FFA07C6253452A01BC90A2A  test/screens/setting_screen_test.dart
0156D3C09538863B7ECA777698FEB3061FA5D8F85E4CB22E527F4D4F25071760  test/screens/export_center_screen_test.dart
```

The checkpoint's own SHA-256 is reported out-of-band at handoff because a file
cannot contain a stable hash of itself.

## Remaining boundaries

- Not run: whole-repository regression, platform builds, golden tests,
  physical-device/TalkBack checks, live Cloud/auth/provider calls, or rendered
  PDF inspection.
- Durable queue/conflict/last-sync API, user Cloud toggle, enrollment and
  registration-decline lifecycle, delete-account/data, persisted preferences,
  and broader sync lifecycle remain separate cards.
- LQ-07 cap 25 and program cap 250 remain unchanged; actual spend telemetry is
  unavailable, so no usage amount is asserted.

## Handoff

Return the sole writer / serialized Flutter slot to root after root matches this
manifest and checkpoint hash. Do not infer permission for deployment, cleanup,
real research activity, or another implementation card from this handoff.

## S1b consent owner / initial-decline boundary addendum — 2026-10-21

### Disposition and source

**Ready for root acceptance as bounded S1b local engineering.** This addendum
supersedes the original S1 consent-lifecycle follow-up, but does not claim
research-release readiness or permission to enroll, upload, deploy, or publish.

- Checkout: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Authority: `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md`, sections
  `S1 verification / concrete consent boundary follow-up` and
  `S1b caller-test grant / I3b ready card`.
- The dirty workspace and all unrelated user work were preserved. No schema,
  generated source, account/identity implementation, sync/export/reward
  authority, deployment, real enrollment, real-data upload, reset, or cleanup
  was performed.
- Independent review exposed that the shared research dialog collapsed system
  Back into an explicit decline. The minimum additional path
  `lib/widgets/research_consent_dialog.dart` was changed to return a tri-state;
  its callers and regression test were updated without changing dialog content.

### Implemented boundary

- `ResearchConsentStatus` carries the owner that was actually loaded. A delayed
  load rechecks the active owner before returning, and UI writes pass that
  captured owner explicitly instead of resolving a new implicit target.
- The Drift decision transaction requires exactly one active owner matching the
  target. Withdrawal conditionally updates only an existing `accepted` row.
  Initial decline/direct withdrawal and repeated withdrawal return no-op without
  creating or changing consent rows, events, or outbox operations.
- Settings refreshes after cancel, no-op, or failure. A dialog opened for A
  cannot create or withdraw consent for B, whether B is accepted or has never
  participated.
- Registration always obtains a fresh post-registration owner context. Initial
  decline writes nothing; declining an already accepted current consent performs
  a real owner-pinned withdrawal; pre-registration acceptance is never rebound
  to another owner. System Back is cancellation, not withdrawal.
- Login records acceptance only for the displayed owner. Consent read/write
  failure is reported with safe text and fails research closed while verified
  sign-in or offline Guest learning continues.

### TDD and independent review

- Behavioral RED was observed before production changes for never-participant
  rows, repeated withdrawal timestamps, inactive-owner writes, delayed owner
  loads, Settings A-to-B retargeting, registration decline/rebinding, and Login
  decline/retargeting.
- Review follow-up RED additionally reproduced accepted-consent decline being
  ignored, consent read errors blocking navigation, stale acceptance lacking
  feedback, and system Back being interpreted as withdrawal.
- Independent final review inspected the updated tree and reported no Critical,
  Important, or Minor finding; verdict: ready for the bounded S1b scope.

### Final verification on the frozen source

- Format check over the eleven production/test paths: **exit 0; 11 files,
  0 changed**.
- Targeted `flutter analyze --no-pub` over the same paths: **exit 0; no issues**.
- Focused consent, Settings, registration, Login, and personal-export widgets:
  **exit 0; 38 tests passed**.
- Connected account, owner isolation, identity upgrade, navigation, consent,
  export, cloud policy, reward transport, and architecture fitness:
  **exit 0; 103 tests passed**.
- Scoped `git diff --check`: no whitespace error; only the existing Git
  LF-to-CRLF working-copy warnings were emitted.
- Final task runtime inventory: **0** matching workspace Dart, Flutter,
  `flutter_tester`, or `gen_snapshot` processes.

Final focused command:

```text
flutter test --no-pub test/features/consent/research_consent_use_cases_test.dart test/screens/setting_screen_test.dart test/screens/registration_flow_test.dart test/screens/login_guest_mode_test.dart test/screens/export_center_screen_test.dart
```

Final connected command:

```text
flutter test --no-pub test/features/account/account_use_cases_test.dart test/features/account/account_owner_isolation_test.dart test/features/account/firebase_account_gateway_test.dart test/features/identity/drift_local_owner_repository_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/identity/identity_mapping_test.dart test/features/identity/upgrade_guest_owner_test.dart test/screens/production_shell_navigation_test.dart test/features/consent/research_consent_use_cases_test.dart test/features/export/export_use_cases_test.dart test/features/sync/cloud_sync_policy_test.dart test/features/sync/reward_transaction_sync_test.dart test/architecture/fitness_test.dart
```

### Eleven-path SHA-256 manifest

```text
5739ADD521FA1540A21193C879498D868D74D788A960D5DC17BB2AA74E80C5C7  lib/features/consent/application/research_consent_use_cases.dart
9F3F44CFCC91EAE9280A9B0666CBEC58165ED776FEAD1DACA29EE1B2110ED531  lib/features/consent/domain/research_consent.dart
E34810300576D8C44BC120945DFB3E5E344F856FC236C458ADE8AEB47EB00230  lib/features/consent/data/drift_research_consent_repository.dart
1502A09278551DE7547216E1A36E2051EE090F42C00E89EE7A160AE6B89E3EB2  lib/screens/setting_screen.dart
7B4AEA349D4F18A5E7188238D318E515E8D19DC4258A442BF56759EE96171C5D  lib/screens/register_screen.dart
7EE23D35BFC0F1EF7E216C0A0F14C07437A92FE5900CD4E9CBA13EA6CB9740CB  lib/screens/login_screen.dart
B4FA7F1F8B081309354B61BC7691E9F79352B538A4C9F4F5FD056372B05B0712  lib/widgets/research_consent_dialog.dart
108738BFCDF507794745A938657EF0BDB96A945B301AF5A3503E3214D73D47A4  test/features/consent/research_consent_use_cases_test.dart
64DE8E6209DA1FC5208C0CB39B1A121FD57C20EB4DA43EAD289E55D073977DD7  test/screens/setting_screen_test.dart
D8671A09E31BB5D2A2AA86884FF619BA3742DE175916DF29B669362B1961EEF6  test/screens/registration_flow_test.dart
A6729B425F3F27BC78D4BEEF2786DF174EBE152A5B77B8CBEFD0B25739AB1F31  test/screens/login_guest_mode_test.dart
```

The checkpoint's own hash is reported out-of-band because it cannot contain a
stable hash of itself.

### Remaining boundaries and handoff

- Whole-repository regression, platform builds, physical-device/TalkBack,
  live Cloud/auth/provider calls, and real research workflows were not run.
- `ExportUseCases.prepare` still checks research consent and resolves the export
  owner across separate awaits. This card does not claim to close the broader
  research export/save/upload owner-recheck boundary; real research export and
  upload remain disabled pending that lifecycle work and its authority tests.
- LQ-07 cap 25 and program cap 250 remain unchanged; no actual-spend telemetry
  is available or asserted.
- Return the sole writer / serialized Flutter slot to root after matching this
  manifest and the out-of-band checkpoint hash. The next card requires an
  explicit transfer; this handoff grants no deployment, enrollment, upload, or
  destructive-cleanup permission.
