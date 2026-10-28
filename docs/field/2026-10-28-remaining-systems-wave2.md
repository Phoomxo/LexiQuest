# Evidence metadata and participation authority checkpoint

On 2026-10-28, `codex/remaining-system-readiness` integrates ordinary answer
metadata at `efff26a6d6f46d3ee2bf42d480d49c27d7b7f955`, following participation
authority commit `2cbd2420`. The existing `cycle12-release` checkout remains the
active source. The two pre-existing untracked critique documents are preserved.
The overall remaining-system task continues.

## Integrated behavior

Schema v11 adds only `answer_attempts.evidence_class` and
`evidence_context_json`; the database still has 29 tables. A generated snapshot
of the actual v10 schema is retained in `test/fixtures/schema_v10.sql`. Migration
tests populate that schema, compare all pre-existing table facts and confirm the
exact archived legacy sentinel on existing answers. Legacy evidence does not
become research-eligible.

The six current learning modes capture class, hint use and the vocabulary
revision shown to the learner. Hiding a used hint does not erase its receipt.
Quiz, SRS, Ghost, Shadowing, Source Voice and associative reading preserve their
captured metadata through retry. The canonical repository rejects conflicting
metadata on an existing answer ID and compares JSON without depending on key
order. Score, SRS and reward projection policy remains unchanged in this unit.

Attempts use wire v2 for declared ordinary metadata and retain v1 for the exact
legacy sentinel. Other collections remain v1. Push, pull, replay, receipts and
Firestore rules preserve metadata and version linkage. Unsupported queued
versions are rejected without changing the queue row or lease. All 14 research
pins are refused at ordinary write/sync boundaries. These local rules have not
been deployed; rolling out the new client requires the reviewed server contract.

The P256 participation document, codec, validator and verifier use the approved
archive contract. Their interface is distinct from the current Ed25519
operation-permit verifier. Tests include real public-key vectors, a separately
signed synthetic canonical document, tampering and minor-receipt rejection.
The ephemeral test signing key was never exported. No production issuer or
participant permission was created.

## Verification

All source writers were frozen for the combined analysis, full Flutter suite
and Android build. Independent reviews accepted participation, capture and
transport/migration. The transport reviewer found an unsupported-version
downgrade; RED tests reproduced versions 3 and 99 being sent, and the fix now
preserves their complete queue rows after rollback.

| Check | Current evidence |
| --- | --- |
| Full Flutter suite | 2,191 passed in 9 minutes 2 seconds |
| Flutter analysis | No issues |
| Capture, database, migration and participation checks | 391 passed before the final transport integration |
| Sync, owner, account lifecycle, export, progress and related screens | 333 passed |
| Final unsupported-version and repository boundary checks | 25 passed; also covered by the full suite |
| Firestore emulator | 45 passed, including the 39 retained cases |
| CLI contract scripts | 23 passed |
| Android debug | Build passed in 156.8 seconds; actual Gradle daemon heap 1536 MiB, one worker configured |
| Dependency resolution | Offline; existing pointycastle 4.0.0 changed from transitive to direct, no package upgrade |
| Generated source | Normal Drift build runner; scoped output only |

The unchanged backend source retains the verified LM 140, AI API 186 and Voice
API 64 results from this run. Voice live E2E remains opt-in and skipped. Auth 3
and Hosting 15 checks passed earlier in the run and their inputs are unchanged.
Android retains the existing Kotlin-plugin and SDK XML compatibility warnings.

The debug artifact is
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`.
It embeds build ID `efff26a6`, version `1.0.0+1`, and has SHA-256
`da612c06f12798093899180ecf4da9fed270da57a79c5f38bd4e5ecc260b20e2`.
It was not installed, published or distributed. Signed baseline +18 is retained.

Logs, source manifests and the APK manifest are in
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
`wave2-source-manifest.json` describes the frozen source before the commit; the
ledger's completion wording was updated afterward without changing app inputs.

## Remaining work and next action

The [44-capability matrix](2026-10-28-feature-readiness-matrix.md) records 9
connected, 20 partial and 15 missing runtime capabilities. Those counts do not
mean nine production-certified features. Foundations alone do not complete
assessment, research capture or motivation.

The next unit reads versioned consent snapshots from existing storage. Then
reserve v12 for canonical assignments only after admission, owner merge and
deletion coverage are concrete. Candidate assignment pins must match both the
P256 participation document and the explicit Ed25519 operation requirements.
Their string versions and integer revisions must not be converted by inference.

Research enrollment/upload stays disabled. Assignment, baseline/post collection,
UI, withdrawal/revocation, upload gating and owner lifecycle remain engineering
work. Real instrument/protocol/issuer/ethics artifacts, live model behavior,
physical-device UAT and rollout authority remain separate requirements.

## Subsequent consent unit

Commit `a06c1a4c` replaces the unused synchronous consent check with versioned
six-field snapshots. The adapter delegates to the existing consent repository;
it introduces no SQL or writes. Bootstrap shares that same repository instance.
An integration test proves accepted consent is visible while the default
operation authorizer still rejects research export.

Runtime and consent checks pass 117 tests, analysis reports no issues and
independent review accepted the unit. The full-suite and APK results above
remain evidence for source `efff26a6`; they are not relabelled as a new full
regression or APK for the later consent commit.

Before assignment writes, the next design examines actual owner/deletion
coordination. The current sync lease and instance-local write queues are not a
shared deletion fence. No v12 schema or assignment write path is reserved or
implemented at this checkpoint.
