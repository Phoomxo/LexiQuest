# R2 schema review fixes — verified focused patch

Status: both findings fixed within the authorized trigger/test scope. The complete
`migration_v23_to_v24_test.dart` passed **102 tests**, exit 0, on the source hashes
below. The focused slot has been returned to MAIN for the waiting UI worker.
No worker-owned Flutter/Dart process remains and no further such command is planned.

## Source and exclusive write scope

- Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
- Branch: `feature/adventure-research`
- HEAD: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`
- Allowed: `lib/data/local/research_schema_guards.dart`,
  `test/database/migration_v23_to_v24_test.dart`, and this report only.
- Changed across this task: the three allowed files only. Production guards were
  patched only after the new tests produced observed RED for both findings.
- No table definition, migration version, generated source, other worker file,
  dependency, commit, task creation, scan, or cleanup was changed/performed.

## Review inputs and implemented behavior

The original eight SQL guards validate the row being written, but do not protect
existing child rows against parent identity changes. Minor receipt checks require
non-null values only; generated Drift text-length validation does not constrain
raw SQL writes. The user independently confirmed both findings against actual SQL.

Six uniquely named forward guards were added to the existing installer, which
already runs from `AppDatabase.migration.beforeOpen`. The eight original guard
definitions are preserved. The installation test exercises an already-v24 database
with those old triggers present and calls beforeOpen twice. No schema bump or
generation was performed.

- `research_participation_permits_strict_receipts_v24_insert` and `_update` enforce
  nonempty canonical ASCII references of at most 128 characters, reject embedded
  NUL explicitly, and require both guardian/assent references for minors. Adult
  optional references may remain null; supplied optional references are validated.
- `<table>_referenced_pins_v24_update` is installed for runs, permits, assignments,
  and learning sessions. It checks the existing research children before allowing
  changes to the relevant parent identity. Tombstoned children still pin parents.
- Null-safe `IS NOT` comparisons accept repeated identical pins in full-row
  updates. Unreferenced ordinary assignment/session rekeys remain allowed.

The lifecycle repository's `_sameImmutablePins` was inspected read-only: permit
revision, expiry, issuer-key rotation, signature/hash, revocation, acknowledgement
metadata, and tombstone changes remain allowed at the storage layer when enrollment
pins are unchanged. SQL fixtures are explicitly synthetic and do not assert valid
cryptographic signatures or authorize enrollment.

## Test patch

The existing six tests and their existing helpers are preserved verbatim apart
from the added `OpeningDetails` import. A nested `research SQL constraints review
fixes` group adds 96 parameterized/individual cases:

- 30 strict receipt INSERT/UPDATE cases: consent, guardian and assent references;
  empty, blank, embedded space, over-128 length, and embedded NUL values. UPDATE
  fixtures are unreferenced so parent immutability cannot mask missing validation.
- 1 acceptance case for canonical 1–128 character references and adult null refs.
- 34 run-pin cases, separately referenced by a response or an opportunity. Owner,
  assignment, protocol and treatment mutations use matching replacement assignment
  rows so existing forward guards cannot hide the missing reverse protection.
  Consent, instrument/form, application/build/schema/content/evidence pins and
  start time are covered as well.
- 11 permit-pin cases, including null-to-value receipt changes and issued identity.
- 12 assignment cases, separately referenced by a run or a permit; owner, protocol,
  treatment, experiment identity/version and assigned time are covered.
- 1 referenced-session owner case and 4 tombstoned-child parent cases.
- 1 same-owner lifecycle acceptance case including full-row permit/run updates,
  signed-revision storage fields, withdrawal, response/opportunity tombstones,
  opportunity progress, session completion and no-op assignment pins.
- 1 ordinary assignment/session rekey acceptance case with unrelated research
  preserved.
- 1 v24 installation case: preserve the eight legacy triggers, remove only added
  guards on the six relevant tables inside an in-memory fixture, invoke the real
  beforeOpen callback twice with `OpeningDetails(24, 24)`, then require rejection
  of parent rekey and empty minor receipts. Data and exact 48-table inventory must
  remain unchanged.

Each rejected write must throw a native `SqliteException` with primary result
code 19 (`SQLITE_CONSTRAINT`), preserve a complete snapshot of the seven relevant
tables, and leave `PRAGMA foreign_key_check` empty. A syntax error or fixture
setup failure is not accepted as the expected rejection. No skips or weakening
of existing assertions were introduced.

## Verification and current-source evidence

- Read-only Git checks confirm the worktree, branch and HEAD above.
- Text comparison against the captured pre-edit test source confirms all original
  tests/helpers are preserved; 528 lines were added, including the import.
- `git diff --no-index --check -- NUL test/database/migration_v23_to_v24_test.dart`
  returned exit 1 for the added-file comparison and emitted only an LF/CRLF notice;
  no whitespace error was reported. This is not a Dart format/analyzer result.
- Final scoped source/diff inspection covered the new guard predicates, reference
  edges, unchanged legacy definitions, and test preservation. The same no-index
  whitespace check on the guard file reported only the LF/CRLF notice.
- Tested production guard SHA-256:
  `0383195AB5D429A157638A595EEE0FAA46D8BDC908AEF0C88B167CB106DC70FC`.
- Tested test SHA-256 (unchanged from RED preparation):
  `5102CF74D0BCE74F871B30737281D0E10CF59D5793B80B46B2A318DEAD65F673`.
- Post-test hashes of `research_tables.dart`, `app_database.dart`, and
  `app_database.g.dart` match their pre-fix review hashes; their contents and the
  48-table schema were not changed by this patch.

All three Flutter commands ran sequentially only after MAIN explicitly confirmed
session 13372 had ended and handed over the slot. No schema edits occurred while
any command ran. The earlier premature grant was held without starting Flutter.

1. RED: `flutter test --no-pub test/database/migration_v23_to_v24_test.dart --plain-name "review fixes" --reporter expanded`
   — **3 passed / 93 failed**, exit 1 (tool chunk `e9ac4f`, no running session).
   The broad output was truncated; the three positive compatibility cases passed.
2. Bounded exact RED confirmation, to retain untruncated evidence of both original
   findings: `flutter test --no-pub test/database/migration_v23_to_v24_test.dart --name '(insert rejects empty guardian_permission_receipt_ref in SQL|response pins run owner and matching assignment)$' --reporter expanded`
   — **0 passed / 2 failed**, exit 1 (chunk `ebd97e`, no running session). Both
   expected a native SQLite constraint exception but the write future completed
   successfully (`emitted <null>`). These are behavioral failures, not compiler,
   fixture, lock or runtime-host failures. Production remained unpatched until
   these results were observed.
3. GREEN after the guard-only production patch:
   `flutter test --no-pub test/database/migration_v23_to_v24_test.dart --reporter expanded`
   — **102 passed**, exit 0 (chunk `196b1e`, no running session). This includes the
   six original migration/constraint/deletion tests and all 96 new cases.

No analyzer, formatter, generator, dependency resolution, scanner, repository-wide
analysis, or other Flutter/Dart test file ran in this narrowly granted slot.
The focused SQL lifecycle acceptance cases passed; the separate full owner-upgrade,
export and lifecycle repository suites have not been rerun by this worker.

## Slot release and integration handoff

The slot was explicitly returned to MAIN immediately after the GREEN command
completed. The latest user instruction supersedes the earlier Sync-next queue:
MAIN can now grant the waiting UI worker its slot. No process from this worker is
pending, and the worker will not issue further Flutter/Dart commands without a
new handoff. Only read-only diff/hash inspection and this report update followed
the slot release; no tested Dart source changed afterward.

Next executable work belongs to MAIN's integration checkpoint: run the relevant
owner-upgrade/export/research lifecycle regressions when their shared inputs and
test slot are available. This report establishes bounded R2 SQL correctness for
the tested paths, not complete Research or production enrollment readiness.
