# Remaining systems: authorized local assignments

Date 2026-10-29. Application source `8504a202` on
`codex/remaining-system-readiness` is pushed to GitHub from
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
The two unrelated untracked critique documents remain untouched.

## Implemented and reviewed

Schema v12 adds one seven-field `experiment_assignments` table, with owner FK
and unique owner/experiment/version. Current schema has 30 tables. The original
8-domain/44-capability catalog and its digest are unchanged.

The repository exposes only signed admission. It checks independent current
P256 participation state, real P256/Ed25519 signatures, explicit integer revision
pins, the supplied study's string versions, accepted consent and trusted time.
It rechecks authority after SQLite writer acquisition and time after the last
local read. Only P256 evaluation/storage project time to milliseconds; expiry
decisions retain full precision. Missing authority denies admission.

The stored timestamp is first successful local admission, not permit issuance.
Valid retry retains it, including with newer permits. A stored future or
pre-consent timestamp causes an immutable conflict. Owner merge validates and
rekeys canonical IDs, deduplicates exact cohort/protocol/time matches and rolls
back every owner table on conflict or collision. No assignment event, outbox
mutation or enrollment composition was added.

Independent review caught a coordinator/database mismatch: checking one DB and
writing another bypassed the shared owner boundary. A two-DB RED reproduced it;
constructor identity checks now reject it. Independent admission and storage
reviews accepted the final source. Export/deletion/purge-proof fixtures contain
real populated synthetic assignments for separate owners.

## Evidence on the frozen source

| Check | Result |
| --- | --- |
| Signed admission | 54 passed, including real synthetic signatures and two-connection races |
| Storage/owner lifecycle | 238 passed |
| Combined research/consent/export/account integration | 655 passed |
| Full Flutter suite | 2385 passed |
| Flutter analysis | No issues |
| CLI contract scripts | 23/23 passed |
| Normal Android debug APK | Passed, target `lib/main.dart`, build ID `8504a202` |

The populated-v11 migration compares every old table before/after, including
answer metadata, consent and outbox. The historical v10 fixture still has 29
tables and its original blob. A normal Drift export captured the v11 DDL before
changes. Generated source adds 983 lines without deleting old lines under
histogram diff; generated output was not edited manually.

Logs and `assignment-normal-debug-apk-manifest.json` are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
The manifest pins lib/test/Android Git trees and the APK hash. The APK is
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`,
251255688 bytes, SHA-256
`6051bb02ab3e12afabb8cb06d71ae3fc2176e60449c07a690215964e286c3415`.
It is debug `1.0.0+1`, not installed or published. Later builds replace that
path; this record and hash identify this specific artifact.

## Remaining boundaries and next unit

This completes the local assignment unit, not research engineering as a whole.
Production current-document/state/time/receipt adapters remain unavailable;
enrollment, collection and upload remain default-off. Cross-authority revocation
is not claimed atomic with SQLite commit. Backend/policy inputs are unchanged;
their earlier results are retained separately in the wave 3 checkpoint.

The [matrix](2026-10-28-feature-readiness-matrix.md) remains 10 connected, 19
partial and 15 missing capabilities, with all applicable release checks still
required. Physical UAT, dark/200% native motion checks and the fixture status-bar
contrast issue remain unverified. The owned emulator/preview cleanup rejection
and retained paths remain recorded in [wave 3](2026-10-29-remaining-systems-wave3.md).

The [ledger](../database/schema_ledger.md) reserves v13 for cached signed
participation. The verified application above remains v12/30 tables. Next use
v12 admission inside the same transaction to import/read cached documents,
never treat that cache as current issuer authority, and block owner-changing
merges that would rewrite signed source pins. Draft workers remain outside the
repository until the root releases this snapshot. No new cloud collection is authorized.
