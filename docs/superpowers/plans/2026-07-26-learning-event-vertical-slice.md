# Learning Event Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one real quiz answer flow through a privacy-safe learning-event store and SRS, then render measured mastery and weakness data instead of built-in samples.

**Architecture:** A provider-neutral immutable `LearningEvent` is written through a small `LearningEventStore` port. The first adapter is a bounded, idempotent SharedPreferences store; Firestore synchronization is a later slice behind the same port. `RecordQuizAnswer` coordinates event persistence and SRS without putting Firebase or persistence logic in the widget. Analytics projectors derive only measured values, and UI surfaces explicitly mark unavailable dimensions.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, SharedPreferences, existing `SrsService`, Flutter unit/widget tests.

## Global Constraints

- Apply RED-GREEN-REFACTOR for every behavior change.
- Give Cointh/GLM one bounded contract or one file per request.
- Do not persist prompt text, selected answer text, email, tokens, raw audio, images, or server credentials.
- Store UTC timestamps and schema/app/build identity on every event.
- Keep at most 500 local learning events and deduplicate by `eventId`.
- A missing provider must render an explicit unavailable/empty state, never fabricated scores or words.
- No GPU consumer or backend process is needed for this slice.

---

## Task 1: Privacy-Safe Learning Event Contract

**Files:**

- Create: `lib/learning/learning_event.dart`
- Create: `test/learning/learning_event_test.dart`

**Interfaces:**

- Produces: `LearningActivity`, `LearningSkill`, and immutable `LearningEvent`.
- `LearningEvent.toMap()` and `LearningEvent.fromMap()` use stable wire names.

- [ ] **Step 1: Ask GLM for the single-file RED test**

Require constructor validation, UTC normalization, stable round-trip, score bounds, positive attempt/response time, event-id validation, and a strict privacy denylist.

- [ ] **Step 2: Add the failing unit test**

The wished-for contract is:

```dart
const event = LearningEvent(
  eventId: 'quiz-session-1:0',
  schemaVersion: 1,
  pseudonymousUserId: 'firebase-uid-1',
  occurredAtUtc: DateTime.utc(2026, 7, 26, 1),
  activity: LearningActivity.multipleChoiceQuiz,
  contentId: 'word:apple',
  categoryId: 'fruit',
  cefrLevel: 'A1',
  skill: LearningSkill.meaningRecall,
  correct: true,
  score: 100,
  responseTimeMs: 1200,
  attemptNumber: 1,
  appVersion: '1.0.0+1',
  buildId: '214b2b6',
);
```

`toMap()` must contain only the declared wire fields and must not contain any key matching `email`, `token`, `password`, `prompt`, `answerText`, `audio`, or `image`.

- [ ] **Step 3: Run RED**

```powershell
flutter test test/learning/learning_event_test.dart
```

Expected: compile failure because `lib/learning/learning_event.dart` does not exist.

- [ ] **Step 4: Ask GLM for the single-file GREEN implementation**

The model validates non-empty bounded identifiers, `schemaVersion == 1`,
`score` in `0..100`, `attemptNumber >= 1`, optional `responseTimeMs >= 0`,
normalizes timestamps to UTC, and rejects unknown wire enum values.

- [ ] **Step 5: Implement and run GREEN**

```powershell
dart format lib/learning/learning_event.dart test/learning/learning_event_test.dart
flutter test test/learning/learning_event_test.dart
```

- [ ] **Step 6: Commit**

```powershell
git add lib/learning/learning_event.dart test/learning/learning_event_test.dart
git commit -m "feat(learning): define privacy-safe learning events"
```

---

## Task 2: Bounded Idempotent Local Event Store

**Files:**

- Create: `lib/learning/learning_event_store.dart`
- Create: `lib/learning/shared_preferences_learning_event_store.dart`
- Create: `test/learning/shared_preferences_learning_event_store_test.dart`

**Interfaces:**

- Consumes: `LearningEvent`.
- Produces:

```dart
abstract interface class LearningEventStore {
  Future<void> append(LearningEvent event);
  Future<List<LearningEvent>> readRecent({int limit = 500});
}
```

- [ ] **Step 1: Ask GLM for RED tests for only the store adapter**

Cover empty state, append/read order, event-id replacement, 500-event bound,
corrupt payload recovery, and returned-list isolation.

- [ ] **Step 2: Add tests and run RED**

```powershell
flutter test test/learning/shared_preferences_learning_event_store_test.dart
```

Expected: compile failure because the store files do not exist.

- [ ] **Step 3: Ask GLM for the port file, then the adapter file separately**

Use injected `SharedPreferences`; persist a versioned JSON array under
`lexiquest_learning_events_v1`; sort newest first; replace an existing
`eventId`; retain the newest 500.

- [ ] **Step 4: Implement and run GREEN**

```powershell
dart format lib/learning test/learning/shared_preferences_learning_event_store_test.dart
flutter test test/learning/shared_preferences_learning_event_store_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/learning test/learning/shared_preferences_learning_event_store_test.dart
git commit -m "feat(learning): persist bounded offline events"
```

---

## Task 3: Quiz Answer Recording Use Case

**Files:**

- Create: `lib/learning/record_quiz_answer.dart`
- Create: `test/learning/record_quiz_answer_test.dart`

**Interfaces:**

- Consumes: `LearningEventStore`, `SrsService`, `AppBuildInfo`.
- Produces:

```dart
final class QuizAnswerInput {
  const QuizAnswerInput({
    required this.eventId,
    required this.pseudonymousUserId,
    required this.occurredAtUtc,
    required this.contentId,
    required this.categoryId,
    required this.cefrLevel,
    required this.correct,
    required this.responseTimeMs,
    required this.attemptNumber,
  });
}

final class RecordQuizAnswer {
  Future<void> call(QuizAnswerInput input);
}
```

- [ ] **Step 1: Ask GLM for the RED test**

Verify one call appends one `meaningRecall` event and calls `SrsService.recordReview`
with the same content identifier/correctness. Verify event-store failure does
not skip the SRS update and reports a typed partial failure without leaking input.

- [ ] **Step 2: Add the failing test and run RED**

```powershell
flutter test test/learning/record_quiz_answer_test.dart
```

- [ ] **Step 3: Ask GLM for one-file GREEN and implement**

Use an injected SRS port if direct `SrsService` testing becomes coupled:

```dart
abstract interface class QuizSrsRecorder {
  Future<void> recordReview(String contentId, bool correct, {DateTime? now});
}
```

- [ ] **Step 4: Run GREEN and regressions**

```powershell
dart format lib/learning/record_quiz_answer.dart test/learning/record_quiz_answer_test.dart
flutter test test/learning/record_quiz_answer_test.dart test/services/srs_service_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/learning/record_quiz_answer.dart test/learning/record_quiz_answer_test.dart
git commit -m "feat(learning): record quiz outcomes through one use case"
```

---

## Task 4: Quiz Screen Emits Real Outcomes Safely

**Files:**

- Modify: `lib/screens/quiz_screen.dart`
- Create: `test/screens/quiz_learning_event_test.dart`

**Interfaces:**

- Consumes: injected `RecordQuizAnswer`, points writer, pseudonymous identity,
  clock, event-id/session source.
- Produces: exactly one recorded answer per question tap.

- [ ] **Step 1: Ask GLM for RED widget tests for `QuizScreen` only**

Cover correct/wrong event, category propagation, response-time measurement,
double-tap idempotency, empty vocabulary, missing Firebase, and navigation
after a points-write failure.

- [ ] **Step 2: Add tests and run RED**

```powershell
flutter test test/screens/quiz_learning_event_test.dart
```

- [ ] **Step 3: Ask GLM for one-file GREEN and implement**

Constructor defaults may preserve old callers, but direct Firebase access must
move behind injected ports. Record only IDs and measured values; do not record
answer/prompt strings. Start the monotonic stopwatch when a question appears.

- [ ] **Step 4: Run GREEN and quiz regressions**

```powershell
dart format lib/screens/quiz_screen.dart test/screens/quiz_learning_event_test.dart
flutter test test/screens/quiz_learning_event_test.dart test/screens/quiz_screen_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/screens/quiz_screen.dart test/screens/quiz_learning_event_test.dart
git commit -m "feat(quiz): emit measured learning outcomes"
```

---

## Task 5: Measured Analytics Projection

**Files:**

- Create: `lib/learning/learning_analytics_snapshot.dart`
- Create: `test/learning/learning_analytics_snapshot_test.dart`

**Interfaces:**

- Consumes: `List<LearningEvent>` and `List<SrsItem>`.
- Produces measured counts, correctness/score by skill, streak days, and
  weakness content IDs. Missing dimensions are `null`, never default scores.

- [ ] **Step 1: Ask GLM for the RED test**

Cover empty projection, multi-day UTC streak, per-skill averages, SRS weakness
ordering, duplicate event-id handling, and no invented pronunciation/listening.

- [ ] **Step 2: Add tests and run RED**

```powershell
flutter test test/learning/learning_analytics_snapshot_test.dart
```

- [ ] **Step 3: Ask GLM for one-file GREEN and implement**

Correctness uses answered-event count as denominator; a score is present only
when at least one event exists for that skill. Streak counts consecutive UTC
calendar days ending on the most recent event day.

- [ ] **Step 4: Run GREEN**

```powershell
dart format lib/learning/learning_analytics_snapshot.dart test/learning/learning_analytics_snapshot_test.dart
flutter test test/learning/learning_analytics_snapshot_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/learning/learning_analytics_snapshot.dart test/learning/learning_analytics_snapshot_test.dart
git commit -m "feat(analytics): project measured learning outcomes"
```

---

## Task 6: Live Mastery and Weakness Screens

**Files:**

- Modify: `lib/screens/mastery_dashboard_screen.dart`
- Modify: `lib/screens/weakness_clinic_screen.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Create: `test/screens/live_learning_analytics_test.dart`

**Interfaces:**

- Consumes: async analytics loader injected through screen constructors.
- Produces: loading, measured, empty, and privacy-safe failure states.

- [ ] **Step 1: Ask GLM for each screen's RED tests separately**

Mastery must show only measured dimensions and label unavailable dimensions.
Weakness must use stored SRS data and show no sample `ephemeral/meticulous/challenge`
deck when empty.

- [ ] **Step 2: Add tests and run RED**

```powershell
flutter test test/screens/live_learning_analytics_test.dart
```

- [ ] **Step 3: Ask GLM for each production file separately and implement**

Keep the five-tab navigation. Use injected loaders for tests and composition;
provider failures render retryable status rather than throwing.

- [ ] **Step 4: Run GREEN and navigation regressions**

```powershell
dart format lib/screens/mastery_dashboard_screen.dart lib/screens/weakness_clinic_screen.dart lib/screens/main_navigation_screen.dart test/screens/live_learning_analytics_test.dart
flutter test test/screens/live_learning_analytics_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/main_navigation_screen_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add lib/screens test/screens/live_learning_analytics_test.dart
git commit -m "feat(analytics): render real mastery and weakness data"
```

---

## Task 7: Runtime Composition and Slice Verification

**Files:**

- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/main.dart`
- Modify: `tool/cli/verify.ps1`
- Modify: `docs/runbooks/android-lan-development.md`
- Modify: `docs/superpowers/plans/2026-07-26-learning-event-vertical-slice.md`

**Interfaces:**

- Production composition creates the local store, SRS adapter, quiz recorder,
  and analytics loader once and exposes them through `AppDependencies`.

- [ ] **Step 1: Add failing composition tests**

Extend `test/runtime/app_bootstrap_test.dart` to assert stable identity of
injected learning dependencies and safe degraded operation without Firebase.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/runtime/app_bootstrap_test.dart
```

- [ ] **Step 3: Ask GLM for each composition file separately and implement**

Do not introduce Firebase event synchronization in this slice. Document local
storage as the offline source pending the next Firestore-sync slice.

- [ ] **Step 4: Run full verification**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
git diff --check
```

- [ ] **Step 5: Review privacy boundary**

```powershell
rg -n -i "(email|token|password|prompt|answerText|audio|image)" lib/learning test/learning
```

Every match must be a denylist assertion, interface comment, or deliberate
non-sensitive identifier; no persisted event contains forbidden content.

- [ ] **Step 6: Commit and push**

```powershell
git add lib test tool/cli/verify.ps1 docs
git commit -m "feat(learning): connect quiz outcomes to live analytics"
git push
```

---

## Completion Gate

- [ ] One answer tap creates exactly one event and one SRS update.
- [ ] Event payload is versioned, UTC, bounded, idempotent, and privacy-safe.
- [ ] Quiz finishes and navigates when Firebase/points persistence is unavailable.
- [ ] Empty quiz input renders a stable state.
- [ ] Mastery scores are calculated from real events or shown unavailable.
- [ ] Weakness clinic uses stored SRS items and contains no built-in sample deck.
- [ ] Full CPU-safe verification and Android debug build pass.
- [ ] PR #3 is updated with the new commits and verification evidence.
