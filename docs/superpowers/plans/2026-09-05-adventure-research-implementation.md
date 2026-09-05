# Adventure Research and Motivation Measurement Implementation Plan

> Execute with `subagent-driven-development` for bounded independent tasks and `executing-plans` for the shared persistence/runtime integration. Use TDD and review each deliverable.

**Goal:** Complete research Tasks 5.1–5.4 and their user-facing/runtime integration, then create a separate user-visible task to implement Pair Matching PM0–PM8 from the completed source.

**Authorization:** On 2026-09-05 the user explicitly requested research implementation now and Pair implementation in a new chat after research is finished. This supersedes the prior implementation hold. Enrollment, institutional approvals, actual participant results and production rollout remain distinct external inputs; no approval or validated questionnaire is fabricated.

**Architecture:** A versioned instrument/form catalog supplies bounded Thai/English prompts and response codes. A paired form includes explicitly tagged baseline and post items with globally unique IDs; both timepoints remain pinned in one measurement run. Existing consent, stable assignment, signed permit, owner gate, canonical session and EventsV2 authorities govern every mutation. Four owner-scoped tables provide runs, responses, permits and opportunities. Product Entry consumes only an active permit projection; research capture cannot select presentation.

**Tech Stack:** Existing Flutter/Dart, Drift/SQLite, crypto, Firestore rules and local test tooling. No external service deployment or new paid dependency.

## Global constraints

- Preserve exact 8/44 feature catalog and learning EvidenceContext/EventEnvelopeV2 keysets.
- Standard/Adventure use the same four neutral events. Nonparticipant creates zero research row/event/outbox/upload.
- Baseline completes after issuance and at most 24 hours before first treatment exposure; post follows the first canonical accepted session completion by at most 30 minutes.
- Validate owner, consent withdrawal, permit signature/revision/expiry, assignment and every version immediately before writes and upload claims.
- Switch ordinals are transactional 1–10; excess changes increment only the suppression count. Retries reuse identity and denominator.
- No raw answer, free-text response, DOB, guardian PII or parallel learning/reward authority.
- Reserve actual next schema version (current source v23; reserve v24) and add exactly four tables. Preserve all existing rows.
- Runtime requires a supplied versioned instrument/protocol/issuer catalog; synthetic test forms never imply approved production instruments.
- Worktree `C:/Users/Phet/Documents/LexiQuest/.worktrees/research` starts at `6968ce97`. Original worktree's two dirty files are untouched.
- No Codex Security workflow. Do not run multi-agent implementation with repository-wide analysis/security. Stop a stalled tool at 10 minutes without measurable progress.

## R1 — Instrument catalog and scoring

**Files:** `lib/features/research/domain/motivation_instrument.dart`, `test/features/research/motivation_instrument_test.dart`.

**Interfaces:** `MotivationTimepoint { baseline, post }`; immutable `MotivationResponseOption`, `MotivationItem`, `MotivationInstrument`; canonical JSON/checksum validation, exact response lookup and `normalizedScore(timepoint, responseCodes)`.

- [x] RED: reject duplicate IDs/codes, unbounded/noncanonical values, mutable caller collections, unknown responses, partial forms and invalid checksum.
- [x] GREEN: version-pinned paired instrument with 1–32 items per timepoint, each 2–10 ordered response options, Thai/English labels, deterministic canonical SHA-256 and 0–100 scoring. Optional ordinal-only absence of score must not become zero.
- [x] Verify `flutter test --no-pub test/features/research/motivation_instrument_test.dart`; focused analyzer; review exact contract and report changed files.

## R2 — Research schema and durable models

**Files:** `lib/data/local/tables/research_tables.dart`, `lib/data/local/app_database.dart`, generated `app_database.g.dart`, `docs/database/schema_ledger.md`, `test/support/current_database_contract.dart`, `test/database/migration_v23_to_v24_test.dart`; research domain `motivation_measurement.dart`, `measurement_opportunity.dart`.

- [x] RED: real v23→current fixture preserves preference, owner and assignment rows; inventory is exactly 48. Foreign keys, owner boundaries, minor receipt pair, state/presentation enums, UTC/revision bounds, unique response/opportunity identity and 0–10 ordinal constraints reject malformed rows.
- [x] Reserve v24; add exact four SDS §4.2 tables and forward migration. New installs and all historical upgrade fixtures yield the same schema.
- [x] Generate Drift once; run migration matrix and update only current-inventory assertions, retaining historical checks.

## R3 — Signed permits, capture gate, responses and opportunities

**Files:** research application `adventure_research_capture_gate.dart`, `motivation_measurement_use_cases.dart`, `measurement_opportunity_use_cases.dart`, `adventure_behavior_event_recorder.dart`; research data `drift_motivation_measurement_repository.dart`, `drift_research_participation_repository.dart`; events `today_experience_event_payload_policy.dart`; corresponding focused tests.

- [x] RED: real-database start/record/close with stable IDs; signed adult/minor permits, expiry/revocation/withdrawal races and owner switches; zero writes on denial.
- [x] Implement version-bound runs and validated responses through owner-locked transactions. Derive baseline completeness from baseline item identities; keep study run active until post completion/skip/withdrawal. Classify out-of-window responses as ineligible for primary analysis.
- [x] Open opportunity before Presented; preserve it if event delivery fails. Retry deterministic event identity, accepted session links and atomic switch reservation; no denominator duplication or learning mutation.
- [x] Reconstruct first exposure/index session/completion from committed records for baseline/post eligibility and restart; tests exercise lost acknowledgements and concurrent operations.

## R4 — Owner lifecycle, sync, rules and export

**Files:** existing identity manifest/upgrade, sync entity/store, export reader/archive, consent withdrawal and `firestore.rules`; matching identity/sync/export/rules tests.

- [x] RED: each new table appears once; owner upgrade/conflict/replay and deletion order are correct; export keeps the five measurement axes separate.
- [x] Add versioned bounded payloads and rollout gates requiring exact deployed rules revision. Preserve immutable signed payload identity on owner upgrade; re-enrollment is required if a cryptographic owner pin cannot transfer.
- [x] Check consent and permit at upload claim; deny unknown keys, unauthorized owners, immutable-pin replacement and invalid references in Firestore emulator tests.
- [x] Verify retention/withdrawal suppress new collection/upload while explicit deletion and personal export stay operable.

## R5 — Runtime and accessible participation/measurement UI

**Files:** `lib/config/adventure_research_runtime_config.dart`, bootstrap/runtime services, Today experience host, research presentation and corresponding widget/integration tests.

- [x] RED: no configured protocol leaves existing learning behavior and research cardinality unchanged; a configured active participant receives baseline/post prompts at the defined boundaries.
- [x] Wire production database-backed permit projection, enrollment validation, optional prompt/Skip/withdrawal, guardian permission and independent assent states. Opaque externally signed receipt import never creates authority from a local checkbox.
- [x] Share research hooks across Standard and Adventure; repeat validation at Host/start/event/enqueue while preserving the one-UUID/one-Today-load invariant.
- [x] Test Thai/English, 200% text, narrow view, semantics/focus, offline/revoked/expired states and safe product continuation.

## R6 — Verification, evidence and Pair handoff

- [x] Run touched research/domain/widget/integration/migration/lifecycle suites, analyzer, Firestore/Auth tests, exact feature map, generated plan check, full default/serial inventory and bounded Gitleaks/OSV after agents stop.
- [x] Build/hash Android APK; document research implementation, configurable external artifacts and local versus physical/UAT evidence. Do not claim actual efficacy or external acceptance.
- [x] Review the research diff and address blocking findings; retain precise source and verification evidence.
- [ ] Only after research engineering completion: call `list_projects`, then `create_thread` for the existing LexiQuest project from the research branch. Prompt the new task to implement Pair PM0–PM8 with the user's explicit authorization, existing UX contracts and inherited verification guardrails. Report its created-thread directive.
