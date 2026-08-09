# LexiQuest P0-P10 Verification and Correction Plan

**Date:** 2026-08-09  
**Authority:** `2026-08-08-lexiquest-complete-field-trial-convergence-design.md` and `2026-08-08-lexiquest-complete-field-trial-release-execution.md`  
**Canonical worktree:** `.worktrees/p0-integration` on `integration/p0-baseline`

## Verification rules

- A phase is complete only when its behavior is integrated, reachable,
  persisted where required, and covered by the phase's bounded gate.
- Commit messages and historical APK evidence are not substitutes for files,
  current test output, or evidence tied to the current source and APK hash.
- Physical-device, provider, App Check, and owner-approval results stay
  `BLOCKED` or `PENDING` until real evidence exists. They are never synthesized.
- Corrections are applied as small rollback-safe slices. Each code defect gets
  a failing focused test before its implementation and one focused green run.
- The normal dirty checkout remains untouched. Only this worktree is writable.

## Evidence ledger at audit start

| Phase | Status | Verified evidence | Gap to exit gate |
|---|---|---|---|
| P0 Baseline/Convergence | PARTIAL | Isolated worktree; branch history inspected; approved convergence design and execution plan committed; root user changes preserved | Required baseline `7b8ac6c` is not an ancestor of this integration branch; reconcile provenance without a wholesale merge before accepting P0 |
| P1 Platform/Data | PARTIAL | Bounded local-first/data gate passed 81 tests; schema v12 owner isolation and erasure corrections passed their focused gate; `flutter analyze` passes | P0 ancestry/provenance remains unresolved and no release artifact is frozen |
| P2 Sync/Learning | PARTIAL | Bounded sync/learning gate passed 110 tests; Firestore emulator policy gate passed 31 tests | Release-artifact and device journey evidence remain pending |
| P3 Device/Media | PARTIAL | Device/media gate passed 57 tests; the pinned model fixture SHA was verified and the 3 affected LiteRT tests then passed | Current checkpoint must not be treated as physical-device evidence |
| P4 AI/Voice | PARTIAL | AI/BYOK gate passed 27 tests and the remaining Voice gate passed 260 tests; provider-neutral owner-scoped accounting is production-wired | Real provider and physical-device evidence remain required |
| P5 Production Backend | PARTIAL | Frozen CPU-only dev environments passed Voice API 55, AI API 76, and Local LM 75 tests | Supabase policy gate and deployed-provider evidence remain unavailable in the current environment |
| P6 Internal APK | BLOCKED | Historical/debug APK references exist | No signed APK manifest/hash/certificate tied to current source SHA |
| P7 Device Checkpoint | BLOCKED | Historical mid/high device records are documented | No complete low/mid/high evidence tied to the current APK hash |
| P8 Beta/Field Journeys | PARTIAL | Local reliability/cost defects are corrected; persisted runtime feature controls are production-reachable and update mounted navigation | Real device/provider journeys and exact-hash evidence remain pending |
| P9 Release Readiness | BLOCKED | One local scenario test file was added in `93fc50c` | App Check, policy snapshots, asset links, budget controls, support/research references, owner approval, and release verifier are not evidenced for current SHA |
| P10 Final Acceptance | BLOCKED | Version changed to `1.0.0+13` in `63ff15b` | The commit changed no manifest/evidence/gate files; final acceptance cannot be claimed |

Baseline commands recorded before corrections:

- `flutter analyze` — PASS, no issues.
- `flutter test test/features/sync/sync_engine_test.dart test/scenarios/device_certification_journey_test.dart test/runtime/registries_test.dart` — PASS, 19 tests.

## Corrective slices

### Slice 1: P8 reliability and cost observability

1. Replace the current breaker with an explicit closed/open/half-open state
   machine that admits exactly one probe and counts only configured transient
   failures.
2. Add focused breaker tests, then wire it to Gemini retry, VoxCPM, and the
   OmniVoice rollback provider with their existing typed failure mappings.
3. Apply the same dynamic request/character/concurrency quota to both remote
   voice providers and ensure AI Tutor's Gemini adapter uses the retry gateway.
4. Make sync request timeout injectable for tests, convert timeout into a
   retryable provider-unavailable failure, and retain partial-run semantics.
5. Replace the boolean-presence download counter with durable event counting;
   record only successful new downloads and wire it in production bootstrap.

Targeted gate:

`flutter test test/runtime/circuit_breaker_test.dart test/features/gemini/retry_gemini_gateway_test.dart test/features/gemini/ai_tutor_gateway_factory_test.dart test/voice/vox_cpm_standard_provider_test.dart test/voice/omni_voice_provider_test.dart test/voice/voice_service_factory_test.dart test/features/sync/sync_engine_test.dart test/features/device_model/model_download_manager_test.dart test/runtime/download_counter_test.dart`

Status: implemented. The final bounded Slice 1 run, including production
bootstrap coverage, passed 81 tests; the shared-breaker regression passed 4
focused Gemini tests; `flutter analyze` reported no issues. Read-only review
returned `SPEC COMPLIANCE: APPROVED` and `CODE QUALITY: APPROVED`.

### Slice 2: Runtime feature controls

1. Define the persisted runtime-flag key/value contract and expiry behavior.
2. Load persisted overrides before constructing `AppDependencies`.
3. Add focused registry/bootstrap tests proving restart persistence and
   emergency-off precedence.

This slice must not claim remote kill-switch support unless a real remote
source, refresh policy, and test are integrated.

Status: implemented as a local persisted emergency control. TTL writes are
rejected until a live expiry scheduler exists, and externally written TTL rows
are ignored. The bounded Slice 2 gate passed 27 tests; `flutter analyze`
reported no issues. Read-only review returned `SPEC COMPLIANCE: APPROVED` and
`CODE QUALITY: APPROVED` with no remaining Critical or Important findings.

### Slice 3: P1-P7 bounded reconciliation

Run each existing targeted phase gate once, record the command and source SHA,
and correct only reproducible failures. Historical device evidence remains
historical. Do not rerun passing suites without a code change in their scope.

The bounded reconciliation exposed an owner-isolation gap in the selected
provider-neutral AI usage slice. Correct it as a forward-only schema v12:

1. Add `owner_id` to `ai_usage_events`; bind repository reads, writes, exports,
   retention, and clearing to the current active owner.
2. Drop unattributable legacy v11 AI usage rows during migration rather than
   assigning them to whichever owner happens to be active at upgrade time.
3. Include AI usage in owner upgrade and make full local erasure transactional.
4. Namespace the secure AI profile by active owner and discard unattributable
   device-global legacy profiles.
5. Keep Gemini/provider billing explicitly BYOK and non-authoritative. The
   approved 0-100 THB target applies to shared infrastructure, so this slice
   does not invent a client-side monetary or call quota.

Migration trade-off: only legacy AI usage metadata and the unattributable
device-global AI profile are discarded. Learning, vocabulary, progress,
rewards, consent, and other owner data are preserved. Downgrade to a v11 APK is
unsupported after the v12 database has opened. When two owners merge, the
source owner's BYOK profile is erased rather than implicitly transferred to a
different identity; the user can explicitly configure a provider again.

Status: implemented and approved by read-only Principal Engineer review
(`SPEC COMPLIANCE: APPROVED`, `CODE QUALITY: APPROVED`). The schema/identity/
AI/bootstrap corrective gate passed 73 tests. Follow-up gates proved pinned
owner identity across provider calls, complete secure-key deletion, reachable
provider-neutral UI and right-to-erasure composition, full vocabulary/reward
FK graphs, and privacy-first cross-store rollback behavior. The final changed
scope passed 4 deletion, 35 UI/deletion/identity/bootstrap, 4 navigation, and
23 architecture/shell tests. Fresh `flutter analyze` and `git diff --check`
pass.

### Slice 4: P9/P10 honest release state

1. Add a current release-readiness record that reports local PASS/PARTIAL and
   external PENDING/BLOCKED separately.
2. Run the repository release verifier against current source without
   weakening it and record every failed prerequisite.
3. Build an internal APK checkpoint only when signing prerequisites are
   available; record source SHA and APK SHA-256.
4. P10 remains blocked until signed-APK, device matrix, App Check/provider,
   field evidence, and owner approval all reconcile to the same artifact.

Status: current readiness is recorded in
`docs/field/2026-08-09-current-release-readiness.md`. Release evidence,
signing configuration, packaged manifest/APK, physical-device matrix, App
Check acceptance, private references, and owner approval are absent. The
release verifier remains intentionally blocked at the missing evidence file;
its missing-path diagnostic is covered by a corrected contract test.

## Rollback points

- Pre-authority integration: `63ff15b`
- Approved-plan integration: `fd73f60`
- Each corrective slice receives its own commit and can be reverted without
  reverting user-authored P0-P10 commits wholesale.
