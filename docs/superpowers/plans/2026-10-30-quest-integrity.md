# Implement canonical Quest answer integrity

2026-10-30. Worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch `codex/remaining-system-readiness`. Verified Cloze baseline `55f9c407`, attested/pushed at `f9f83f2e`: Flutter3633, analysis0, CLI23, offline backend390/one opt-in skip and a normal debug APK. This executes the next card under the existing authorization.

## Execution board

The three units are now integrated locally. Domain replay/owner/terminal rules
reproduced19 real REDs plus2 controls, then33 domain checks passed. Four further
catalog-aliasing REDs proved caller filters/objectives/tags could mutate the
definition across startQuest's owner await. Both catalog constructors now copy
their collections; all actual const callers migrate without changing assertions.

The adapter first reproduced its missing API, then9 actual identity failures
with3 payload controls. Required attemptId and both actual command.id hook
callers now agree. The combined initial adapter/domain/learning/Assessment95
checks pass. The Assessment fixture assigns its quest before its existing
ordinary answers, preserving count1 and every isolation assertion.

The atomic repository's API RED preceded its real implementation. Canonical
attempt/session metadata and prior chains, matching catalog/window pins,
owner/deletion fencing, same-database construction, outer-transaction rejection
and terminal CAS are integrated; split public progress/completion ports are gone.
A real microsecond-clock RED additionally showed returned completion time
differed from persisted milliseconds. Only completedAt is quantized and shared
by event/state/SQL; validation clocks retain their full precision.

Current integration138 checks and wider learning/projection1121 checks pass;
analysis reports0 issues on the current integrated source.
Independent reviews accept adapter/core/storage after those corrections.
Source2702e008 now passes full Flutter3700, analysis0, CLI23, backend390/one
existing opt-in skip and a normal debug APK; all683 Dart plus54 CLI and92 backend
inputs remain unchanged. See [wave14](../../field/2026-10-30-remaining-systems-wave14.md).
No Quest activation or grant is enabled. Next is owned Word Scramble.
Evidence is under the existing remaining-systems D root: quest-domain-red.log,
quest-catalog-aliasing-red.log, quest-canonical-adapter-behavior-red.log,
quest-canonical-adapter-domain-final-green.log, quest-canonical-atomic-api-red.log,
quest-completion-precision-red.log, quest-integration-first-run.log and
quest-learning-projection-regression.log.

## Outcome and fixed scope

Each real persisted answer advances each matching objective at most once. Quest progress and first completion commit together for the current owner. Replayed, concurrent, missing, mismatched, ineligible, or out-of-window evidence cannot increase progress. Optional Quest failure leaves the already-committed learning answer and its ordinary effects intact.

Use existing Quest tables and `source_event_ids_json`. Reserve no migration or processed-event table. Do not activate bootstrap hooks, catalog seeding, recurrence, catch-up workers, grants, freezes, XP50/200 payouts, or production Research. Keep EventEnvelopeV2 and EvidenceContext fields unchanged. Do not insert nonparticipant `events_v2` rows or introduce a second learning/reward writer. f29 remains partial after this repair.

## Grounded change

`event_v1_to_v2_adapter.dart:124` accepts no attempt ID and generates IDs with a process counter; its idempotency key collides for answers in the same session/millisecond. `_afterRecordedAnswer` in `learning_use_cases.dart` is inserted-only and already uses the shared projection gate, but creates separate envelopes for shadow and Quest. `QuestInstance.advanceIfMatches` appends duplicate IDs. `QuestUseCases.processEvent` performs separate progress/completion awaits. `DriftQuestRepository` has no owner coordinator and accepts those split mutations. Quest bootstrap hooks are currently absent.

Add required `attemptId` to `adaptFromCommand`, set `eventId` to that persisted ID, and use `answer-attempt:$attemptId` as the idempotency key. Pass `command.id` at both hooks. Preserve legacy `adapt(LearningEvent)`, payload, and other envelope values. `QuizCompleted` still means one correct answer, not session completion. Retry identity must not depend on time, build, or process counter.

Keep `QuestUseCases.processEvent(event, catalog)` as the caller boundary. Replace public split progress/completion writes with one repository operation:

```dart
Future<List<QuestCompletedEvent>> applyCanonicalAnswer({
  required String ownerId,
  required EventEnvelopeV2 event,
  required List<QuestDefinition> catalog,
});
```

Inject the existing owner coordinator and a UTC clock into the Drift repository; reject a coordinator backed by another database. In one top-level owner transaction, load the attempt by `eventId` and its owned session. Reject missing rows or owner/actor/session/time/type/payload mismatches. Exclude Assessment and check stored metadata with the existing Quest projection gate. Match criteria against stored answer values. Every previously stored source ID must also resolve to an eligible owned attempt matching that objective/window. Legacy timestamp/counter IDs cannot be assumed canonical; fail closed without resetting or backfilling progress.

First protect `upsertDefinition`: an exact same-version definition is a no-op, changed same-version content and downgrades are rejected. Current INSERT OR REPLACE can otherwise overwrite criteria/expiry before `startQuest` checks for an active instance; later supplied/stored/version comparisons cannot recover the original definition. A newer stored definition must not retarget an older active instance. No schema snapshot is added.

For each active instance, require the supplied catalog, stored definition, and instance version to agree. Verify objectives/criteria/target counts/expiry and reject malformed progress. Do not invent missing historical catalog proof. Reject evidence before assignment or in the future. Keep the current expiry convention: exact deadline is allowed, later evidence or processing is denied. Recheck the clock before commit. Terminal replay returns no new completion and preserves its first timestamp.

Deduplicate per objective; one answer may satisfy different objectives once each. Enforce active state/owner in the pure helper. Commit progress and first completion together, then recheck answer/catalog/owner/fence facts. Reject ambient transactions. Emit completion only after commit; shadow remains optional and cannot grant production rewards. Scope `markExpired`/`markAbandoned` to owner/fence and active-state CAS, so a stale expiry read cannot overwrite terminal facts. Remove public `saveProgress`/`markCompleted` after caller migration.

## Units and disjoint writers

| Order | Owned production files | Tests and acceptance |
| --- | --- | --- |
| A, freeze the small contract first | `lib/features/quest/domain/quest_models.dart`, `quest_repository.dart` | `test/features/quest/quest_models_test.dart`: duplicate source, terminal/foreign-owner event, two objectives, and defensive immutable progress/catalog inputs. Define the atomic port above. |
| B, after A | `lib/features/quest/data/drift_quest_repository.dart`, `lib/features/quest/application/quest_use_cases.dart` | `drift_quest_repository_test.dart`, `quest_use_cases_test.dart`: real owner/attempt/session fixtures, atomic operation, final checks, and post-commit notification. Migrate existing split-write assertions to the canonical operation without dropping their persistence checks. |
| C, may run beside B after A | `lib/features/events/application/event_v1_to_v2_adapter.dart`, `lib/features/learning/application/learning_use_cases.dart` | `test/features/events/event_v1_to_v2_adapter_test.dart`, `test/features/quest/quest_learning_integration_test.dart`, and one distinct identity regression file. Pass the real command ID, retain inserted-only/eligibility/error isolation, and prove the actual committed answer feeds Quest. |

Keep one writer per file. Root serializes executable checks against consistent snapshots. Use real active-owner/deletion-fence fixtures; synthetic standalone envelopes are insufficient for repository admission tests.

## RED checks and completion evidence

- Replay the same stored attempt through another adapter/use-case instance and after a file-backed database reopen. Count it once; preserve completion time/source IDs and emit no second completion. Two attempts at the same millisecond remain distinct.
- Run concurrent duplicate and distinct callbacks. Inject a failure between progress and completed-state writes. Roll back every Quest change and emit no completion on failure; keep canonical answer/SRS/XP/coins unchanged.
- Reject foreign owner, owner change during await, fence, ambient transaction, unknown event, absent attempt, or forged fields. Test clock/deadline crossing, mismatched coordinator/database, and stale expiry/abandonment racing a completed instance.
- Prove exact same-version upsert is a no-op and changed criteria/expiry is rejected before `startQuest` can overwrite an active instance's definition. Deny stale version, downgrade, corrupt source JSON, duplicate objective IDs, and missing rows without backfill. Preserve ordinary inferred compatibility; malformed/Assessment and current declared assisted Dictation/Cloze gain no eligibility.
- Drive a real LearningUseCases answer through the optional sink. Retried ACKs do not redispatch; a throwing Quest sink cannot roll back learning. Compare Research rows/outbox/events and ordinary projection snapshots before/after. Test null sink and current default-off bootstrap unchanged.

Run the focused checks first: `flutter test test/features/events/event_v1_to_v2_adapter_test.dart test/features/quest/ test/features/learning/learning_use_cases_test.dart test/features/assessment/assessment_projection_isolation_test.dart`. Then root runs relevant ordinary/native projection checks, analysis, and full regression/build at the integration checkpoint. Review the final diff and current source hashes before recording the result.

Existing `unique(owner_id, quest_id)` cannot preserve repeated daily/weekly periods. Leave that schema and history intact. Period identity, recurrence, delivery recovery, payout authority, and runtime/UI activation are separate queued units; this implementation requires none of them to prove canonical answer integrity.
