# R4a personal export/lifecycle — resume report

สถานะ: ส่งมอบ patch R4a พร้อม focused tests 31 ผ่าน และ T25 1 ผ่าน;
analyzer ไม่มีปัญหา คืน exclusive Flutter/Dart slot ให้ main แล้ว
regression เดิมพบ 2 จุดล้มเหลว: ปรับ assertion ของ ordinary inventory แล้วตาม
scope extension ล่าสุด (ยังไม่ทดสอบซ้ำ); sync schema v24 รอ main/R4 sync worker

## Source and scope

- Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
- Branch: `feature/adventure-research`
- HEAD: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`
- Requirements: `.superpowers/sdd/research-export-resume-brief.md`, updated `AGENTS.md`,
  active implementation plan and historical 2026-09-05 checkpoint.
- Read and applied TDD, systematic-debugging and verification-before-completion.
  Brief explicitly permits preparing the patch from known RED evidence while crypto
  owns the test slot: export 5 passed/3 failed; owner-upgrade 12 passed (historical).

## Files edited by this resumed worker

1. `lib/features/export/application/owner_lifecycle_archive.dart`
2. `lib/features/export/data/research_lifecycle_export_reader.dart` (new)
3. `test/features/export/research_lifecycle_export_test.dart` (pre-existing RED file, extended)
4. `test/features/identity/drift_owner_upgrade_repository_test.dart` (only the ordinary
   migration test's research inventory distinction, authorized after slot release)
5. `.superpowers/sdd/research-export-resume-report.md` (this report)

Existing research lifecycle manifest/deletion order, typed research owner-upgrade
conflict, identity fixtures/tests, and T25 inventory updates were present on entry;
this worker has preserved them and other agents' changes.

## Behavior

- Four explicit owner-filtered SQL projections now feed the existing personal archive
  inside its pinned-owner transaction and manifest field validation.
- Stable archive-local run/permit aliases retain exact links without emitting raw
  IDs, signatures, hashes of permit payloads, issuer keys or receipt references.
- All four tables include tombstones; withdrawn runs/revoked permits remain readable.
- Canonical 1–128 ASCII identifier codes only; malformed codes fail with typed
  `ExportException(unavailable)` and never appear in diagnostic text.
- Motivation responses retain coded value, raw nullable ordinal and answer time.
  Opportunities retain assigned/effective presentation, event/session-presence flags,
  switch/suppression counts and stored times. No primary score, exposure/index-session
  derivation, combined outcome or conversion of missing ordinals to zero.
- 11 additional edge cases cover malformed response/metadata codes, cross-owner
  malformed evidence, absent ordinal/events and multiple run/permit linkage.

## Verification

Main explicitly granted the exclusive slot after crypto released every Flutter/Dart
process. All commands below ran sequentially in the shared research worktree;
incomplete opportunity tests were excluded. The three export source/test files
are unchanged after these checks. The separately authorized ordinary inventory
assertion correction below was made after slot release and has NOT been rerun.

1. `dart format lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/research_lifecycle_export_reader.dart test/features/export/research_lifecycle_export_test.dart`
   — exit 0, 3 files formatted.
2. `flutter test --no-pub test/features/export/research_lifecycle_export_test.dart test/features/identity/research_owner_upgrade_test.dart --reporter expanded`
   — exit 0, **31 passed** (19 export/lifecycle, 12 owner-upgrade). This verifies
   formerly missing projections, all allowlisted fields, exact coded responses,
   malformed-code rejection, withdrawals/revocation/tombstones, owner isolation,
   aliases, deterministic archive hashes, nonparticipant zero rows, child-first
   deletion/rollback/replay, and atomic typed upgrade rejection before credentials.
3. `flutter test --no-pub test/features/export/export_use_cases_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart test/features/account/local_data_deletion_test.dart --reporter expanded`
   — exit 1, **81 passed / 2 failed**. Both failures are in the pre-existing
   `drift_owner_upgrade_repository_test.dart`; export facade and deletion tests
   passed. Existing restart fixtures also emit Drift multiple-database warnings.
4. `flutter test --no-pub test/architecture/fitness_test.dart --plain-name 'T25' --reporter expanded`
   — exit 0, **1 passed**, exact 48-table lifecycle inventory.
5. `dart analyze lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/research_lifecycle_export_reader.dart lib/features/identity/domain/owner_lifecycle_manifest.dart lib/features/identity/data/drift_owner_upgrade_repository.dart test/features/export/research_lifecycle_export_test.dart test/features/identity/research_owner_upgrade_test.dart test/features/identity/research_lifecycle_fixtures.dart`
   — exit 0, **No issues found** in seven scoped files.
6. `dart format --output=none --set-exit-if-changed lib/features/export/application/owner_lifecycle_archive.dart lib/features/export/data/research_lifecycle_export_reader.dart test/features/export/research_lifecycle_export_test.dart`
   — exit 0, **3 files / 0 changes**.
7. `git diff --check -- lib/features/export/application/owner_lifecycle_archive.dart`
   and final focused diff/source review — exit 0. Initial broader allowlist diff
   check also exited 0 with only LF/CRLF notices. New reader and extended test were
   inspected directly because they are untracked and absent from normal Git diff.

Historical RED evidence (5 pass/3 fail) is from the brief/checkpoint, not a new run.
No failing assertions were removed or weakened to obtain the 31 focused passes.

### Diagnosed integration failures and follow-up scope extension

- `test/features/identity/drift_owner_upgrade_repository_test.dart:2030`,
  **moves every owner-scoped row and replays as a no-op**: assertion at line 2052
  expected target-owner count >= 1, actual 0 for `motivation_measurement_runs`.
  `_seedEveryOwnerScopedTable` predates the four research tables but the assertion
  iterates the expanded lifecycle-derived `ownerUpgradeInventory`. Distinguish
  transferable fixture rows from research requiring explicit removal/re-enrollment;
  the separate research-conflict suite already proves signed rows must not move.
  **Patch applied after explicit scope extension:** name exactly the four research
  tables, assert all remain in inventory, assert zero on source and target before
  ordinary migration, and assert target zero after upgrade/replay. Source zero and
  target >= 1 remain required for every ordinary inventory table. No test was
  skipped and no research pin protection changed. Main explicitly owns the slot
  and requested no further Flutter/Dart command; main will verify this correction.
- Same test file at line 3561, **equivalent terminal run merge retires source
  revisions and keeps target sync claimable**: `SyncFailure(invalidPayload)` at
  `AssessmentRunSyncPayloadContract.requireCanonical`,
  `lib/features/sync/domain/sync_entity.dart:1352`. The schema allowlist immediately
  above permits only 15..23, whereas the assessment fixtures at test lines 4350/4898
  pin `AppDatabase.currentSchemaVersion`, now 24. Align the existing assessment
  contract/rules and relevant tests with v24 under main's integration authority.
  Export code is absent from both failing execution paths.

Main received both exact failures before slot release, then extended the write
allowlist only for the ordinary inventory assertion in the first test file.
`sync_entity.dart` was not edited. No unchanged retry or validator bypass occurred.
The additional assertion diff and `git diff --check -- test/features/identity/drift_owner_upgrade_repository_test.dart`
were inspected after the correction (exit 0; only LF/CRLF notice). No Flutter/Dart
command ran after release. Original failing-test line numbers above refer to the
pre-correction source captured by the regression run.

### Verified edited-source SHA-256

- `lib/features/export/application/owner_lifecycle_archive.dart`:
  `E853E192B274BA0E679327053F2B154B4613C5E3D55524AF204BEE3EDCDC1165`
- `lib/features/export/data/research_lifecycle_export_reader.dart`:
  `023EDC9FCDC4B1B96ADACCAC7F1AC8C7B5877A005EBCFC13E44C38A21EF4385B`
- `test/features/export/research_lifecycle_export_test.dart`:
  `4BC11281BD01F6CB1A2CFA1198303FB7DC02DF9724DBEAE7AA89A64B8C1E8321`
- Follow-up **not yet test-verified** `test/features/identity/drift_owner_upgrade_repository_test.dart`:
  `4364F4E177DE628060321D6D00512C48CA068B74A92ABB9971EE7DB7C356AA7E`

## Handoff dependencies

- Exclusive test slot released explicitly to main after analyzer and format check.
  All worker-owned sessions completed, including regression session 61190 (exit 1).
  No running worker-owned process and no further Flutter/Dart checks planned here.
- No commit, new user task, dependency resolution, generation, full suite, scan,
  deployment, enrollment, upload or cleanup performed.
- This is bounded R4a engineering work; wider research timing/repository/sync/UI and
  release verification remain with main. External research approvals are not asserted.
- Next executable step for main: verify the corrected ordinary owner-upgrade
  inventory test, repair the sync v24 limit with applicable sync/rules tests, then
  rerun the ordinary owner-upgrade regression under main's slot. Do not treat this
  report as full research or end-to-end production readiness.
