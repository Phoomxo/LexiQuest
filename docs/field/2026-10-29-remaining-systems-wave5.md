# Remaining systems: durable signed participation

Date 2026-10-29. Application commit `6a49e8e7` and CLI fix `6f88bdc5` are pushed
on `codex/remaining-system-readiness` in
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
The application inputs are identical across those commits; the two unrelated
untracked critique files remain untouched.

## Implemented and reviewed

Schema v13 adds one 20-field signed participation cache, bringing the schema to
31 tables. It copies the original signed revisions and payload without unsigned
transport timestamps. Stored documents never act as current issuer authority.
Import and participant reads use independent current-document authority, actual
P256/Ed25519 verification, accepted consent, trusted time and the same concrete
owner/deletion transaction boundary. Failed imports roll back newly admitted
assignments. Revoked/deleted documents cannot be resurrected. Authentic narrowing
updates can preserve existing history after expiry or withdrawal without enrolling
a new participant or creating collect effects.

Owner-changing merges reject any source-owned signed permit before business
writes; target-owned and same-owner signed facts remain unchanged. Export,
deletion and purge-proof fixtures include signed facts for separate owners.
Populated-v12 migration preserves every old row and the pending deletion fence.

Two behavior regressions caught an Ed25519 permit expiring during post-authority
cache reads while P256 remained valid. R1 now carries its actual final receipt;
R2 checks that receipt against its last trusted clock after local reads. Both
regressions pass. Independent repository and storage reviewers accepted the final
change. A helper-path collision during drafting was reconciled into separate
seed fixture and test harness files before verification; both originals and
hashes are retained in the maintenance evidence.

## Evidence on the frozen source

| Check | Result |
| --- | --- |
| Participation repository | 47 passed |
| Assignment admission | 55 passed |
| Combined storage/research/consent/owner/export/deletion integration | 715 passed |
| Full Flutter suite | 2445 passed |
| Flutter analysis | No issues |
| CLI contract scripts | 23/23 passed after the focused Windows PowerShell fix |
| Normal Android debug APK | Passed, `lib/main.dart`, build ID `6f88bdc5` |

The first CLI run passed 22/23 scripts. Windows PowerShell 5.1 converted expected
child-process rejection stderr into a terminating harness error before its
assertion. Commit `6f88bdc5` captures the exit code with a scoped preference and
restores the preference in `finally`. The actual verifier and trust rules are
unchanged. All ten public-release assertions pass under both PowerShell 5.1 and
7; independent review accepted the fix. Initial failure logs remain retained.

Logs and `participation-normal-debug-apk-manifest.json` are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
The manifest pins source/lib/test/Android trees. The normal debug `1.0.0+1` APK
at `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`
is 251307870 bytes, SHA-256
`f6cdc6afb8473cc2bbca94d763f2f6995c8a34de0687f5db3c55677bd44af09f`.
It was not installed or published. Later builds replace that path; this hash
identifies this artifact. The build retains the existing future-KGP warning.
Normal Drift export captures the current v13 DDL before the next migration.

## Remaining engineering work

Research is still default-off. Current production document/state/time/receipt
adapters, measurement storage, canonical first-exposure/index-session linkage,
capture UI and upload gates remain separate implementation work. The matrix
stays 10 connected, 19 partial and 15 missing runtime capabilities; it is not a
production-readiness score. No ethics, instrument validity, live authority,
physical UAT, model quality or rollout approval is inferred.

The ledger reserves v14 for two local-only supplied-instrument measurement
tables. Root owns schema, migration and the seed fixture; the measurement worker
owns separate domain/repository/tests and its distinctly named harness. R3A
must preserve actual final receipts, full pins and immutable replay. R3B must
link explicit visible exposure to the first actually accepted learning session;
it cannot select arbitrary owner/time rows or substitute a later completed
session for an abandoned index session. Ordinary learning must survive research
sidecar denial. No UI composition is claimed by storage alone.

The emulator/preview cleanup rejection remains as recorded in wave 3: automatic
approval rejected the owned stop/delete command with `blocked by policy`.
No retry or cleanup occurred. Native dark/200% checks, hardware gestures and the
fixture status-bar contrast cause remain unverified.
