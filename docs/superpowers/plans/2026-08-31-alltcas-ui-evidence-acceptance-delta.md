# AllTCAS UI Evidence Acceptance Delta

> **For agentic workers:** Apply this companion only while executing the
> existing f44 → f43 → f42 dependency order in
> `2026-08-14-alltcas-8-44-capability-implementation-master-plan.md`. It adds
> acceptance evidence, not product scope or a new capability.

**Goal:** Convert the approved Android UI research evidence into bounded,
original LexiQuest acceptance contracts for the remaining f44, f43, and f42
packages.

**Architecture:** Existing canonical authorities remain the only writers. The
delta strengthens presentation and read-model acceptance at existing delivery
boundaries; it does not add data models, runtime activation, or research
assignment behavior.

**Tech Stack:** Flutter/Dart widget and integration tests over the existing
Unified Lesson Shell, Content Manifest, LearningSessions, AnswerAttempts,
EventsV2, Review Center, History, Recommendation, and Today Hub authorities.

## Evidence and intellectual-property boundary

- The source consists of 66 temporary Android screenshots reviewed for flow
  structure only: content catalog/set progress, rich lexical detail, unified
  lesson shell, session settings, report sheet, correct/incorrect feedback,
  and review queue.
- The screenshots are research evidence, not shippable assets. Do not copy or
  trace their images, colors, branding, layout artwork, icons, typography, or
  other visual assets into LexiQuest.
- Product copy, visual styling, components, and assets must remain original and
  follow the existing LexiQuest Material 3 and accessibility contracts.
- No screenshot or derivative binary is added to the repository, bundle,
  generated artifacts, tests, or release packaging.

## Locked scope and authority invariants

- Schema, table inventory, migrations, owner lifecycle, sync schema, and rules
  revisions do not change.
- No new repository, writer, projection, aggregate, cache authority, or source
  table is introduced.
- Product-contract capability count remains 44 and runtime-feature count
  remains unchanged. No feature flag, delivery entry, route identity, cohort,
  or research rollout is added or enabled.
- f01–f41 remain closed. This delta must not reopen, redesign, or mutate their
  accepted domain behavior.
- Today Hub and Learning History remain read models. Replay creates new
  canonical session/evidence identity and never edits historical evidence.
- f44 behavior and scope remain exactly as approved; only its current bounded
  debugging and acceptance work continues before f43 starts.

## Ordered execution delta

### 1. Close f44 without scope change

**Files:** Use only the currently approved f44 production/test paths from the
master plan and the focused runtime test under diagnosis.

- Resume systematic debugging of the hanging widget test only after a source
  fingerprint change.
- Run one bounded diagnostic attempt that identifies the exact pending phase;
  do not repeat an unchanged hanging command.
- Preserve verified manifest identity, local-first recovery, pin/removal
  safety, fresh production voice catalog, bounded download cancellation, and
  resource-disposal ordering.
- f44 exit remains the master-plan contract; this companion adds no UI surface
  or activation requirement to f44.

### 2. Add f43 Learning History UI acceptance before GREEN

**Tests:**

- `test/screens/learning_history_screen_test.dart`
- `test/features/history/learning_history_reader_test.dart`
- `test/features/history/learning_history_replay_test.dart`

Acceptance must prove:

- Each real history session card/timeline entry renders its canonical pack,
  lesson mode, active-learning duration, and terminal state (`completed` or
  `abandoned`) with accessible, non-color-only status.
- Ordering is deterministic and derived from immutable canonical session and
  evidence timestamps.
- Replay starts a new LearningSession with new evidence identifiers through the
  existing lesson-start authority.
- The source session, AnswerAttempts, EventsV2, outcomes, and research context
  remain byte-equivalent before and after replay.
- Missing/deleted display content uses the existing safe fallback and never
  invents pack, mode, time, or completion metadata.

### 3. Add f42 Today Hub priority UI acceptance before GREEN

**Tests:**

- `test/screens/today_hub_screen_test.dart`
- `test/features/today_hub/today_hub_reader_test.dart`

Acceptance must prove:

- Priority cards cover a resumable session, due/incorrect review work, and the
  next recommended activity.
- Every recommendation card exposes its canonical reason; duplicate work is
  merged deterministically without losing reasons.
- Hub composition is read-only and leaves all source tables byte-equivalent.
- Copy contains no leaderboard, public rank, social comparison, competitive
  pressure, or other social-graph implication.
- Hub actions only navigate/invoke existing typed use cases and do not write
  progress, assignment, recommendation, review, or history state.

### 4. Add final cross-surface UX acceptance

**Tests:**

- `test/features/learning/unified_lesson_controller_test.dart`
- `test/features/learning/session_configuration_sheet_test.dart`
- `test/features/learning/answer_feedback_panel_test.dart`
- `test/features/review/content_report_sheet_test.dart`
- `test/widgets/rich_lexical_card_test.dart`

Acceptance must prove:

- The production lesson shell consistently exposes progress, active-learning
  time when authorized, bookmark, report, session preferences, non-color-only
  correct/incorrect feedback, and an explicit next action.
- Feedback is shown only after canonical commit and remains owned by the shell;
  no mode creates a parallel result or evidence authority.
- Session preferences remain bounded by the accepted protocol and do not alter
  committed evidence retroactively.
- `RichLexicalCard` renders image, audio, IPA, part of speech, level,
  definitions, and examples only when each field is available from the exact
  approved/published manifest-backed lexical artifact.
- Missing media or lexical fields degrade independently and accessibly; the UI
  never fabricates content or bypasses checksum/revision validation.

## Gate discipline and rollback

- Run only focused gates whose source fingerprint changed. A repeated hang or
  identical filesystem/runtime failure stops the package immediately.
- No full suite, backend suite, deployment, push, or merge is implied by this
  delta.
- Rollback removes only the new presentation/read-model behavior or keeps the
  corresponding existing delivery disabled. It does not delete or rewrite
  manifests, sessions, evidence, review state, assignments, or downloads.
- Package order remains f44 → f43 → f42. f42 stays the final learner-facing
  composite and cannot start until its typed dependencies, including f43, are
  complete.

## Self-review record

- Placeholder scan: no TBD/TODO or deferred acceptance remains.
- Scope check: acceptance-only; no schema, authority, feature, route, or
  capability expansion.
- Evidence check: all screenshot-derived observations are expressed as
  original functional contracts; no screenshot asset or brand treatment is
  imported.
- Order check: f44 remains current, f43 precedes f42, and f01–f41 stay closed.
