# P3 Core Learning Evidence Implementation Plan

> Status: ACTIVE
>
> Dependency: P0, P1, and P2 automated gates are complete. Device-only
> WorkManager validation remains part of P8 field certification.

**Goal:** Make Quiz, SRS, reading, weakness, mastery, streaks, achievements,
recommendations, and game progression derive deterministically from durable
local evidence, with no participant-facing sample data.

**Architecture:** Drift is the only source of truth. Application use cases own
transactions; screens receive use cases through `AppDependenciesScope` and do
not call Firebase, HTTP, or persistence plugins. Answer and reading events are
immutable. SRS and progress are rebuildable projections. A completed answer is
persisted atomically with its SRS and points projections.

**Algorithm decision:** P3 uses a documented, versioned SM-2-compatible binary
review policy. Correct answers advance 1, 3, 7, 14, then doubling-day
intervals; incorrect answers reset the interval to one day and increment
lapses. This is deterministic for the available binary correctness evidence
and can be replaced later by replaying attempts under a new algorithm version.

---

## Package A — Durable learning repository

**Files**

- Modify: `lib/data/local/tables/learning_tables.dart`
- Modify: `lib/data/local/app_database.dart`
- Create: `lib/features/learning/domain/learning_models.dart`
- Create: `lib/features/learning/domain/learning_repository.dart`
- Create: `lib/features/learning/data/drift_learning_repository.dart`
- Test: `test/features/learning/drift_learning_repository_test.dart`
- Test: `test/data/local/app_database_migration_test.dart`

**Tasks**

1. Add deterministic constraints and indexes needed for owner/session/word and
   due-date queries without changing immutable attempt semantics.
2. Add schema-v3 migration and migration coverage.
3. Write failing repository tests for session start, atomic answer recording,
   duplicate attempt replay, session completion, and reading progress/events.
4. Implement the Drift repository transaction boundaries.
5. Verify focused tests and generated Drift code.

**Exit**

- A process restart preserves every session, answer, response time, reading
  position, and completion event.
- Replaying an attempt ID changes no counts, points, or SRS state.

## Package B — Quiz and SRS application core

**Files**

- Create: `lib/features/learning/application/learning_use_cases.dart`
- Create: `lib/features/learning/domain/srs_policy.dart`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Replace: `lib/services/quiz_service.dart`
- Replace: `lib/services/srs_service.dart`
- Test: `test/features/learning/learning_use_cases_test.dart`
- Test: `test/features/learning/srs_policy_test.dart`

**Tasks**

1. Write failing tests proving quiz words come only from active local
   vocabulary owned by the active owner.
2. Write failing tests for deterministic option selection and the documented
   SRS intervals, due dates, repetitions, and lapses.
3. Implement start-session, record-answer, finish-session, and due-review use
   cases with injected clock and ID sources.
4. Award idempotent points from answer event IDs and unlock evidence-backed
   achievements in the same transaction.
5. Expose the learning API through bootstrap; keep compatibility facades free
   of Firebase and SharedPreferences.

**Exit**

- One completed quiz creates one completed session, N attempts, N SRS updates,
  and idempotent ledger entries.
- Quiz and SRS work with Firebase unavailable.

## Package C — Quiz and SRS screens

**Files**

- Modify: `lib/screens/quiz_screen.dart`
- Modify: `lib/screens/choose_mode_screen.dart`
- Modify: `lib/screens/select_category_for_quiz.dart`
- Modify: `lib/screens/srs_flashcards_screen.dart`
- Modify: affected widget tests under `test/screens/`
- Add: `test/architecture/learning_screen_boundary_test.dart`

**Tasks**

1. Add a static architecture test that rejects Firebase, HTTP, and direct
   plugin imports from the four screens.
2. Replace passed map/sample lists with local query state and explicit empty,
   loading, and failure states.
3. Persist each answer before advancing and complete the session before showing
   the score.
4. Load the due SRS deck from Drift and record every review through the same
   answer pipeline.

**Exit**

- No learning screen directly imports Firebase, HTTP, SharedPreferences, or
  Drift.
- Empty local vocabulary shows a real empty state rather than sample words.

## Package D — Reading evidence

**Files**

- Create: `lib/features/learning/application/reading_use_cases.dart`
- Modify: `lib/screens/associative_reading_session_screen.dart`
- Modify: the active article/reading screen selected by route audit
- Test: `test/features/learning/reading_use_cases_test.dart`
- Test: `test/screens/associative_reading_session_screen_test.dart`

**Tasks**

1. Test save/resume, monotonic position, document revision isolation, complete,
   and idempotent reading-event behavior.
2. Implement throttled checkpoint and explicit completion use cases.
3. Restore stored position on screen entry and persist on lifecycle exit.
4. Remove claims that memory state was updated unless an actual attempt was
   recorded.

**Exit**

- Reading resumes after app restart and completion is backed by an event.

## Package E — Evidence-derived projections and participant screens

**Files**

- Create: `lib/features/progress/domain/progress_models.dart`
- Create: `lib/features/progress/application/progress_projector.dart`
- Create: `lib/features/progress/data/drift_progress_queries.dart`
- Modify: `lib/screens/mastery_dashboard_screen.dart`
- Modify: `lib/screens/weakness_clinic_screen.dart`
- Modify: Ghost Shadow Duel, Weakness SRS, AI Tutor, and Shadowing Challenge
  entry screens found by the scoped audit
- Test: `test/features/progress/progress_projector_test.dart`
- Test: corresponding screen tests

**Tasks**

1. Define sample-size-bearing mastery, weakness, streak, recommendation,
   achievement, and game-progression view models.
2. Test empty evidence, mixed outcomes, UTC day boundaries, and deterministic
   rebuild.
3. Implement read-only projections from sessions, attempts, SRS, ledger, and
   unlock tables.
4. Replace defaults and hard-coded participant records with dependency-backed
   projections or honest unavailable/empty states.

**Exit**

- A new account shows sample size zero.
- Deleting and rebuilding derived rows yields the same visible projections.

## Package F — Learning-event synchronization

**Files**

- Modify: sync domain/store/gateway files under `lib/features/sync/`
- Modify: `firestore.rules`
- Modify: `test/security/firestore-rules.test.cjs`
- Add: focused learning-sync tests under `test/features/sync/`

**Tasks**

1. Add immutable event collections keyed by stable event IDs.
2. Push events with create-or-identical replay semantics and pull as set union.
3. Rebuild SRS/progress locally after newly pulled evidence; never merge
   derived totals.
4. Add owner isolation, schema, replay, and malicious-payload emulator tests.

**Exit**

- Repeated offline/online replay cannot duplicate attempts, reading events, or
  points.
- Conflicting immutable event payloads are quarantined and never overwrite.

## Package G — P3 bounded gate

**Files**

- Create: `tool/cli/verify-learning-core.ps1`
- Create: `docs/development/p3-learning-core-gate-2026-07-30.md`
- Modify: this plan status

**Commands**

1. `dart format --output=none --set-exit-if-changed <P3 files>`
2. `flutter analyze`
3. `flutter test`
4. `firebase emulators:exec --only firestore "node --test test/security/firestore-rules.test.cjs"`
5. `flutter build apk --debug`
6. scoped diff and screen-boundary checks

**Exit**

- Automated gate is green and recorded once.
- Hardware-only force-stop/restart, background execution, thermal, camera,
  speech, and GPU checks remain explicitly queued for P8 and do not cause
  repeated P3 test loops.

