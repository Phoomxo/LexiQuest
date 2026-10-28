# Complete the remaining LexiQuest systems

Date 2026-10-28. User authorizes implementation of unfinished/unready systems. Branch `codex/remaining-system-readiness` in the existing `cycle12-release` worktree starts at `1aa189a3e76f078884ba3f71d4dde0b19a19c6bf`. The two pre-existing untracked critique documents remain unrelated WIP.

## Frame and acceptance

Use the approved 8-domain/44-capability catalog without changing its identity/hash. A catalog entry or a passing isolated test is not evidence of runtime readiness. Close concrete runtime gaps with behavior checks and record every capability's current state. Preserve the completed 20 audit fixes, current learning/reward authorities and ordinary offline learning.

Engineering completion means the implemented unit is wired through its actual caller, its data is owner-scoped, retries do not duplicate facts, existing data survives migration, and current-source tests/review pass. Research additionally requires signature rejection, withdrawal, owner isolation, before/after linkage, UI, sync/upload gating, export and deletion checks. Missing external authority denies research while ordinary learning continues.

Do not deploy, enable real enrollment/upload, provision signing authority, invent questionnaire validity, change guardrails or retry denied cleanup. Supplied protocol/instrument/issuer contracts and synthetic fixtures permit local development. Physical UAT, production infrastructure and rollout authorization remain separate.

## Grounding and recovery

- Current source has schema v10/29 tables. `schema_ledger.md` explicitly leaves v11+ unreserved.
- Archived approved Research source is `e3e46af3`, original branch `feature/adventure-research` at `b9184e8a`; its status cites verified implementation `ed89efaf`. It contains R1–R6 code, supplied instrument contracts and v24/48 tables. Historical results do not attest the current branch.
- A virtual merge against that history has 107 conflicts, including 82 Dart paths, guardrails, secret-scan policy and the schema ledger. No whole-tree merge is performed. Restore bounded components with current lineage/authority checks.
- `EvidenceContext` and eligibility policy are absent from the current source although their frozen definitions exist in the archive. Restore their existing shape and verify the current catalog digest before use.
- Quest/Streak V2 are not composed. Their existing event identity, replay, recurrence and freeze grant boundaries need correction before wiring; avoid a second streak/reward authority.
- The HF Space lacks the app's `/v1/content` contract, bounds only model tokens, loads at import and defaults to a mutable revision. Research JSON exports raw content/IDs. History has no dedicated runtime view.

## Workflow

1. Frame and inspect the current callers, contracts, plans and schema lineage.
2. Design bounded units and their write sets; capture focused RED before changing behavior.
3. Implement and verify each independent unit, then integrate current-source evidence.
4. Record decisions, source recovery references and review dispositions.
5. Run integration checks and update readiness without claiming external rollout.

The rigor is high for research privacy, migrations and owner boundaries. Read-only history is verified against existing learning facts. Root serializes Flutter/build/codegen and owns schema, bootstrap and integration. Workers own disjoint files. Reuse the worktree to limit disk use; write only logs/metadata under `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.

## Task board

| Unit | Scope and write owner | Acceptance | State |
| --- | --- | --- | --- |
| LM serving | Worker; HF app, serving tests/README, LM dev dependencies/lock | Authenticated app-compatible content and existing chat routes; import-safe fake-model CPU HTTP tests; actual body cap; pinned revision; busy/failure handling | CPU suite 140 passed; reviewed error-code issue fixed; commit 0704d632 |
| Research export | Worker; export use cases/contracts and scoped tests | Versioned allowlist, archive-local aliases and preserved linkage; no free text/provenance/raw IDs; personal formats unchanged; consent/owner/save guards pass | Scoped suite 52 passed; independent review accepted |
| Learning history | Worker; history query/model/screen, Mastery entry and scoped tests; root owns composition | Actual owner-scoped session/answer counts, empty/error/retry, owner-change hiding, accessible layout; no active-time or efficacy invention | Scoped suite 54 passed; page-query issue fixed and review accepted; commit 53dad6a5 |
| Research foundations | Root; exact frozen context/eligibility/digest and tests | Original keysets and current catalog identity match; no schema or rollout change | Scoped suite 68 passed; catalog revision 1.3.0 and digest unchanged |
| Supplied research instrument contracts | Root; archived instrument/protocol domain and synthetic tests | Immutable caller-supplied checksums, structured Thai/English forms, UTC precision, no invented instrument validity | Scoped suite 100 passed; no enrollment or database writes |
| Evidence metadata | Root schema/models/contract; workers own ordinary capture and sync contracts | Reserve v11 for two columns on existing attempts; exact frozen legacy sentinel; immutable captured content revision; ordinary v1/v2 wire compatibility; reject all research pins while collect/upload authority is absent | Grounded; storage and transport only, no score/reward policy activation |
| Participation authority | Worker; archived P256 domain/codec/validator/verifier and self-contained synthetic tests | Distinct participation interface; actual signature and pin rejection; no database/runtime enrollment composition | Grounded; tests-only stage next |
| Research schema and authorities | Root integration after metadata; adapt approved assignment/assessment/measurement/repositories/owner lifecycle | Reserve actual next versions before migration; migrate current lineage; versioned consent; distinct Ed25519 operation and P256 participation checks; synthetic rejection/recovery tests | Queued after v11 metadata |
| Research capture/UI/sync | Bounded restored source after schema/authority | Real capture and upload boundaries, zero research writes for nonparticipants, baseline/post linkage, withdrawal/revocation, owner/export/delete/emulator coverage; shipped default-off | Queued |
| Motivation integration | Existing event/quest/streak implementations after Research integration | Persisted event identity, replay-safe objectives/freeze, recurring periods with history, single UI authority and actual learning hooks | Queued |
| Remaining catalog integration | Reconcile archived approved components with current runtime for content, native modes, feedback, assessment, goals/preferences and offline content | Per-capability caller and behavior evidence; keep Pair Matching sequencing and research prerequisites | Queued |
| Integration and attestation | Root with independent review | Focused checks, full Flutter/backend/policy checks, analysis and bounded-memory Android build on frozen source; readiness matrix and external gates recorded | Wave 1: Flutter 2034, analysis 0, AI 186, Voice 64, LM 140, Firestore 39, Auth 3, Hosting 15 passed; build deferred to next integration checkpoint |

## Integration checks

Run the smallest relevant Flutter tests first, then touched subsystem tests. At the integration checkpoint pause writers and run `flutter analyze --no-pub`, the full Flutter suite, backend CPU suites and relevant policy/CLI contracts. Keep model downloads/GPU inference and live authority access out of CPU tests. Review the final diff and record current source hashes. New owner-scoped storage requires migration, merge, deletion, export and applicable sync/policy coverage.

The decision trail is [the remaining-system decision log](../../field/2026-10-28-remaining-system-decisions.tsv). Logs for this wave are in `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`. Earlier LM CPU logs are in the parent maintenance directory. Results on this board describe individual units until the integration suite attests the combined source.
