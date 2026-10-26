# LQ-07 E1 export owner/pre-write boundary checkpoint — 2026-10-21

## Execution identity and authority

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- Baseline HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Authority: the bounded E1 grant in `2026-10-20-lq-00-wave-0-checkpoint.md`; exactly eight existing source/test paths plus this checkpoint.
- Existing unrelated dirty files were preserved. No schema, generated source, dependency, lockfile, consent, identity, account, bootstrap, sync, upload, issuer, redaction-protocol, or screen-production file was changed by E1.

## Bounded engineering result

E1 is complete for the authorized local engineering boundary:

- Research export pins the owner from the accepted `ResearchConsentStatus` before any export read. Personal export pins the active owner without requiring research consent.
- Cancellation, owner continuity, and current-version research acceptance are checked around asynchronous reads/rendering and again through a required store callback at the final app-controlled pre-write gate.
- Storage and read uncertainty maps to typed fail-closed export errors. Existing CSV/PDF/Anki, reward opt-in, exclusions, and public prepared-artifact contract remain intact.
- Desktop ordering is destination dialog → validation → internal staging → validation → `XFile.saveTo`. Normal unwind removes the internal partial file when possible; no user-selected destination is guessed or deleted.
- Android selection receives only file name/MIME. It returns a one-shot `{destination, selectionToken}` capability; Dart validates both fields before sending bytes. Native write/discard accepts only an exact URI+token match, consumes a valid capability once, rejects reuse/mismatch, and does not let a stale request consume the latest selection. A fresh UUID token closes same-URI ABA at this native boundary.
- There is no post-write cancellation check that could report cancellation after a successful external write.

This capability token is only an ephemeral write-boundary binding. It does not add research authority, enrollment permission, persistence, or a new data contract.

## Test-first evidence

Initial focused export baseline was 17 passing tests. RED cases were observed before their fixes, including consent-owner A being reused for B, missing controllable reader/store boundary APIs, owner/cancellation changes during delayed consent/data/PDF work, raw storage failures escaping typed mapping, and Android selection returning a capability shape unsupported by the old URI-only caller. Focused GREEN checks were run after each correction.

Final current-source evidence, serialized in this worktree:

- `dart format` over the exact seven granted Dart paths: exit 0; 7 files processed, 2 changed.
- `flutter test --no-pub test/features/export/export_use_cases_test.dart test/features/export/file_selector_export_store_test.dart test/screens/export_center_screen_test.dart`: exit 0; 39 passed.
- The store suite includes a desktop test with mocked chooser/path lookup but real temporary-file staging and `XFile.saveTo`, proving both validations occur after the dialog and before the external copy. Android MethodChannel tests prove no bytes enter the picker call, capability forwarding, cancellation/discard, malformed capability rejection, failed validation with no write, and no false cancellation after write starts.
- `flutter analyze --no-pub` over the exact seven granted Dart paths: exit 0; no issues found.
- `flutter test --no-pub test/features/consent/research_consent_use_cases_test.dart test/features/account/account_owner_isolation_test.dart test/runtime/app_bootstrap_test.dart test/features/sync/cloud_sync_policy_test.dart test/features/sync/reward_transaction_sync_test.dart test/architecture/fitness_test.dart`: exit 0; 65 passed.
- `flutter build apk --debug --no-pub`: exit 0; built `build\app\outputs\flutter-apk\app-debug.apk`. Warnings were limited to the existing future Built-in Kotlin migration notice for plugins; no E1 Kotlin compile error occurred.
- Scoped `git diff --check`: exit 0, with only repository line-ending conversion warnings.
- Final workspace-owned Flutter/Dart/Java/Gradle process check: 0.

The first attempt to select two test names with a pipe in `--plain-name` selected no tests because Flutter treated it as a literal string. The corrected whole-file run passed; this was a command-selection error, not a source failure.

## Independent review disposition

The read-only E1 re-review reported Critical 0, Important 0, Minor 0 and approved this bounded engineering snapshot. It specifically confirmed that stale/mismatched native writes no longer consume the latest destination, the fresh token closes same-URI ABA, Dart fails closed on malformed capabilities, the desktop real-copy ordering is covered, and the personal pre-write owner-switch branch is covered.

The reviewer did not rerun the writer's tests/analyzer/build and did not attest device/provider or production readiness.

## Accepted residual limits and release boundary

E1 does **not** claim any of the following:

1. Owner/consent ABA completed entirely between checks; the current owner API exposes identity, not a monotonic owner epoch.
2. A transactionally consistent export snapshot; Drift export data is assembled by multiple queries.
3. Recovery of an Android pending picker/capability after Activity or process loss.
4. Prevention or safe deletion of an empty document created by a chooser/provider before a pre-write rejection.
5. Rollback of partial or complete external bytes after a provider write begins, crashes, or loses its acknowledgement.

No physical Android device or real document provider was exercised. MethodChannel tests plus a debug build are not native behavioral acceptance. No APK install, publish, deployment, real participant enrollment, real research export/upload, efficacy claim, redaction/permit approval, or destructive cleanup occurred. Real research export/upload remains default-off. LQ-07 cap 25 and program cap 250 are unchanged; actual spend is unavailable and was not inferred.

## Current-source SHA-256 manifest

```text
53EB9675271E571D2137E8DEB4C8B90F60F2EC3FED0004722C30F0FE7EB841D6  lib/features/export/application/export_use_cases.dart
7334145E2332E82DEDB20AAB96AC362A685EECE37B984EB513D87C7252A174EB  lib/features/export/data/drift_export_reader.dart
516BDDC5CEA7066D9133AFB6E3C7F8F82C371D30FB60A94DACDB7332BE96AF51  lib/features/export/domain/export_contracts.dart
E4C24CF1380F9472E52342213E019ADEF2E243B209F0B21E9C13A9D4F3E90E74  lib/features/export/data/file_selector_export_store.dart
9D4C406ED6E74BA9FA1478F63ADF0B4988C21C56EADB8B6EF53187A7F71D1E33  android/app/src/main/kotlin/com/lexiquest/app/MainActivity.kt
CA875FB5FCAD093622E23B525214EA5E19565CF57852EDED3566238DFBE7729E  test/features/export/export_use_cases_test.dart
81F1DEF32B839444BE8A2500F2DE7113AB370392CED1A3BAB25A5627E6C16CD8  test/features/export/file_selector_export_store_test.dart
4FA5CDBC08EC4D9839BCA33B900921DB30737B3278F7AB9588C5A86545E2649A  test/screens/export_center_screen_test.dart
```

E1 returns the sole production writer and serialized Flutter/build slot to root after this checkpoint. LQ-07 does not begin I4 implementation under this grant.
