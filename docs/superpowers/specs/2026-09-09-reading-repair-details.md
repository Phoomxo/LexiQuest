# Reading resume repair decisions — R06

Approved remediation Task3. Source discovery found canonical activity recovery already implemented: atomic session+checkpoint start, exact pinned start, latest/exact recovery and source-authenticated attempts. No migration is needed. Do not overload SessionConfiguration or infer document/session linkage from timestamps or matching word sets.

## Canonical checkpoint reuse

After checking equivalents, add a strict reading-specific nested checkpoint codec, expected `lib/features/learning/domain/associative_reading_checkpoint.dart`. Use nested schemaVersion1/kind associativeReading, document ID/revision, stage, ordered word/content pins including normalization/accepted-variant identity, and bounded frozen passage identity/content needed for reconstruction. Retain the existing64KiB checkpoint limit and frozen outer EvidenceContext/EventEnvelopeV2. Cached booleans must never authorize scores.

Extend `startAssociativeReadingSessionHandle` with initial checkpoint and reuse atomic exact-pinned start. Do not fall back to an uncheckpointed session when recovery capability is unavailable. Launcher checks matching recovery before creating a new session: exact owner/document/revision/ordered pins and revalidated original configuration. Attach the recovered session ID/start/config, not the latest preferences.

Stage comes from the linked canonical checkpoint. Derive recall results from authenticated recovery attempts with exact session, word, attempt number, associativeRecall prompt type and content identity. Reject duplicates/unexpected occurrences and corrupt/missing canonical source. Do not combine historical answers with a newly created session.

Partial-batch recovery at stage3 shows committed results and disables only those occurrences; submit only missing responses. Persist sequential idempotent stage checkpoints before displaying the next stage. Document reading_progress can remain a browsing aggregate but cannot advance a different session past recall.

## Terminal and route semantics

Close the session-completion/terminal-checkpoint/reading-progress crash gap through a reading-specific atomic finish/checkpoint seam or secure reconciliation of the authenticated existing terminal timestamp. Existing exact recovery requires checkpoint terminalAtUtc == session endedAtUtc; merely appending after completion without recovery is insufficient. Preserve completion event identity on retry.

Keep explicit Back/stop abandonment semantics; do not add a new suspend feature during this repair. Active sessions interrupted by process death can recover under the same identity. Abandoned sessions may display their linked historical summary read-only with stopped status; a deliberately new round starts at stage1. Never reactivate abandoned sessions. Completed reopen displays terminal summary without starting a new session.

Legacy document-only progress has no provable score linkage. Explain in Thai that previous recall results cannot be linked, preserve historical progress, and explicitly start a new round from stage1 (or clearly labeled fresh recall if existing compatibility demands stage3). Never show unknown as0/N or attach old answers to the new run. This compatibility fallback alone does not close R06; same-session active recovery must work.

## Scope and acceptance

Files: reading launcher/screen, learning use cases/repository contract/Drift implementation, new strict codec, existing reading/recovery/restart tests. Existing events_v2 lifecycle supplies owner/export/delete coverage; verify recovery after owner merge. No cross-device checkpoint transport is added by this repair; a fresh device with only document progress gets the honest legacy path.

Required tests: correct+wrong → stage4 → DB close/reopen → same session/evidence and1/2 summary; no answer/SRS/reward effects from restore; partial commit before checkpoint; terminal boundary crashes/retries; document/content/config drift; foreign owner; duplicate/corrupt/missing source; explicit abandon cannot resume; completed reopen no new session; legacy unknown copy; owner upgrade/export/delete. Read-only planning is complete; root serializes all Flutter/codegen commands.

## Implementation preflight refinement

Latest generic recovery is only candidate discovery; authenticate via exact recovery before attaching. Do not silently abandon an active mismatched document/configuration to start a different run. A bounded reading-specific lookup may be added to the optional recovery seam to find the latest matching document when a later session belongs to another document, rather than widening generic recovery or scanning/truncating all history in UI.

The reading completion seam validates the strict latest checkpoint, stage6, complete authenticated recall occurrences and owner/configuration pins, then invokes existing canonical finish plus terminal checkpoint plus reading progress in one database transaction. Capture terminal time, checkpoint revision and reading progress event identity once for retry. Do not replace canonical finish with separate reward logic. Existing explicitly no-session compatibility fixtures can preserve association persistence and document browsing, but their summary must show unknown rather than0/N when no linked recall exists.

## Admission discriminator refinement

Source review found that checking latest checkpoint.kind alone allows a newly checkpointed reading session with all checkpoints deleted/downgraded to fall through legacy generic completion. Reserve `reading:` session IDs for new atomic exact-pinned reading admission, following the existing reserved Pair identity principle. Generic startSession cannot admit this prefix; finish and exact recovery require authenticated reading start/checkpoint authority for every reserved identity regardless of latest checkpoint presence/kind. No migration or historical relabeling; legacy `session:` rows remain explicit compatibility and cannot supply invented recall results. Preserve the reserved ID through resume and owner/export/delete paths. The actual launcher never falls back to uncheckpointed admission.

Candidate recovery must precede randomized vocabulary selection or preference-based count changes, otherwise the launcher can fail to discover its original session. Reuse the existing active-owner-safe ordered pinned-word read for the frozen candidate and revalidate exact core/variant/configuration identities. Completed reopen is read-only under the original terminal identity; provide a deliberate new-round path using existing UI patterns so a completed candidate does not permanently trap the learner. Never abandon a recovered completed session merely because launcher navigation was retired.

## Owner upgrade collision acceptance

Independent review identified that existing word merge protects pinned Pair identities but deletes/tombstones colliding guest words needed by reading checkpoints. Task3a includes the existing identity upgrade repository and maintained tests as needed to preserve/reconcile authenticated frozen reading pins through collision. Use the existing immutable pin protection model; do not relabel checkpoint history or weaken exact live content validation. Test both stage1 with no attempts and stage4 with authenticated recall, upgrading into an account with the same normalized spelling/meaning/category, then actual reading recovery under the upgraded owner. A no-collision owner test alone is insufficient. No new schema or parallel learning authority.

Chosen bounded repair after reviewer/source checks: preserve original categories containing authenticated reserved reading pins when category names collide. Category display name is outside the lexical checksum; categoryId is inside it, so retaining categoryId/word IDs and lexical fields preserves frozen authority. Assign a deterministic human-readable original-name plus `(บทเรียนเดิม)` suffix with further collision resolution, normalized using existing rules. Names must be unique across both owners, including deleted categories and earlier retained renames. Bump category localRevision/update time only; skip normal merge/delete/remap/import-ref rewrite for that preserved category. Keep all work in the existing transaction, authenticate active/completed reading histories before mutation and recheck target-owner recovery before commit. Existing move/requeue/export/delete paths remain authoritative; do not add word revision/hash churn for the display rename. Test rollback/retry and suffix collisions.

Current vocabulary may legitimately be edited or deleted after a reading history was recorded. Authenticate canonical history independently; only currently exact and available word/category sets enter the protection set. Later current-content drift prevents restoring that reading but must not permanently block ordinary account binding or merging. Never catch all authentication errors to achieve this distinction. Test source and existing target histories, edited/deleted words and deleted categories, preserving original evidence/checkpoint bytes and requiring current reading recovery to reject unavailable content.

## Explicit stop retry and fresh-round acceptance

Manual retry uses an opt-in seam on the existing route lifecycle: clear only a settled failed terminal Future, retain original cutoff, accepted operations/configuration closure, and keep admission closed. Concurrent/in-flight calls join; successful terminal work remains idempotent. Do not replace this with direct repository compensation. Postcommit acknowledgment loss retries the identical timestamp and produces one durable transition; two prewrite failures require two explicit retries. Mark reading launcher terminal authority after a non-null canonical abandon succeeds and before Navigator.pop, since the push Future can finish before outgoing route disposal.

Pointer interaction and app lifecycle reconciliation must respect closed route admission at event time, including auto-reentry; no second Back may restart idle work after failed retirement. The first Back pointer event may validly precede the cutoff. Fire all captured stale idle callbacks and verify unchanged session/time/event rows, rather than assuming a single lifetime timer schedule.

An authenticated completed candidate with subsequently unavailable content must still offer a deliberate new round. Fetch current owner-scoped vocabulary and current configuration, derive all new document/passage/revision/answer pins from that fresh set, and preserve the old history. Do not reuse the old passage just because a candidate existed, and do not implicitly abandon an active session to implement this path. Current owner and original configuration must be revalidated on recovered attachment. These are local acceptance requirements; they do not claim native UAT.
