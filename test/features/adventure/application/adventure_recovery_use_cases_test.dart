import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  late CurrentActivityEvidenceAdapter evidence;
  late AdventureRecoveryUseCases recovery;
  late String ownerId;
  late AdventureSessionPlanV1 plan;
  var enabled = true;
  var nextId = 0;
  var now = DateTime.utc(2026, 9, 4, 9);

  setUp(() async {
    enabled = true;
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'adventure-owner',
      nowUtc: () => now,
    );
    ownerId = (await owners.getOrCreateActiveOwner()).id;
    final content = await _seedVocabulary(database, ownerId);
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'adventure-${++nextId}',
      nowUtc: () {
        final value = now;
        now = now.add(const Duration(seconds: 1));
        return value;
      },
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'adventure-test'),
    );
    evidence = CurrentActivityEvidenceAdapter(learning: learning);
    recovery = _recovery(
      learning: learning,
      evidence: evidence,
      canStart: () => enabled,
    );
    plan = _plan(ownerId: ownerId, content: content);
  });

  tearDown(() => database.close());

  test(
    'starts one Learning-owned checkpointed session without persisted origin',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );

      expect(run.recovered, isFalse);
      expect(run.presentation, AdventureLearningPresentation.adventure);
      expect(run.session.ownerId, ownerId);
      expect(run.session.questions, hasLength(4));
      final stored = await database.select(database.learningSessions).get();
      expect(stored, hasLength(1));
      expect(stored.single.activityType, mixedReviewActivityType);
      final exact = await learning.loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: run.session.id,
        activityType: mixedReviewActivityType,
      );
      final state = exact!.checkpoint!.state;
      expect(
        AdventureLearningCheckpointState.fromJson(state).sessionId,
        run.session.id,
      );
      final encoded = state.toString();
      expect(encoded, isNot(contains('planId')));
      expect(encoded, isNot(contains('catalog')));
      expect(encoded, isNot(contains('presentation')));
      expect(encoded, isNot(contains(plan.planId)));
    },
  );

  test(
    'accepted Learning session resumes before flag and new plan checks',
    () async {
      final first = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      enabled = false;
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => enabled,
      );

      final resumed = await restarted.startOrResume(
        plan: _plan(ownerId: ownerId, content: plan.content.reversed.toList()),
        activeOwnerId: ownerId,
      );

      expect(resumed.recovered, isTrue);
      expect(resumed.session.id, first.session.id);
      expect(resumed.presentation, AdventureLearningPresentation.standard);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
    },
  );

  test(
    'completed Learning session with closing checkpoint resumes before feature gate',
    () async {
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final first = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: oneItemPlan,
        index: 0,
        isCorrect: true,
      );
      final close = learning.captureSessionClose(
        sessionId: first.session.id,
        ownerId: ownerId,
      );
      await recovery.checkpointSessionClose(close);
      final committed = await close.finish();
      enabled = false;
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => enabled,
      );

      final resumed = await restarted.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );

      expect(resumed.session.id, first.session.id);
      expect(resumed.recovered, isTrue);
      expect(resumed.presentation, AdventureLearningPresentation.standard);
      expect(resumed.state.phase, AdventureLearningCheckpointPhase.closing);
      expect(resumed.pendingClose, isNotNull);
      final replay = await resumed.pendingClose!.finish();
      await restarted.acknowledgeSessionClosed(
        close: resumed.pendingClose!,
        summary: replay,
      );
      expect(replay.endedAtUtc, committed.endedAtUtc);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
    },
  );

  test(
    'terminal recovery is not displaced by newer unrelated history',
    () async {
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final first = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: oneItemPlan,
        index: 0,
        isCorrect: true,
      );
      final close = learning.captureSessionClose(
        sessionId: first.session.id,
        ownerId: ownerId,
      );
      await recovery.checkpointSessionClose(close);
      await close.finish();

      for (var index = 0; index < 101; index += 1) {
        final startedAt = now.add(Duration(minutes: index + 1));
        await database
            .into(database.learningSessions)
            .insert(
              LearningSessionsCompanion.insert(
                id: 'unrelated-history-$index',
                ownerId: ownerId,
                activityType: 'quiz',
                state: 'completed',
                startedAtUtcMs: startedAt.millisecondsSinceEpoch,
                endedAtUtcMs: Value(
                  startedAt
                      .add(const Duration(seconds: 1))
                      .millisecondsSinceEpoch,
                ),
                appVersion: 'test',
                buildId: 'history-test',
              ),
            );
      }
      enabled = false;
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => enabled,
      );

      final resumed = await restarted.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );

      expect(resumed.session.id, first.session.id);
      expect(resumed.state.phase, AdventureLearningCheckpointPhase.closing);
      expect(resumed.presentation, AdventureLearningPresentation.standard);
    },
  );

  test('completed unpresented session resumes before a new mission', () async {
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final first = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    await _recordOriginal(
      recovery: recovery,
      evidence: evidence,
      plan: oneItemPlan,
      index: 0,
      isCorrect: true,
    );
    await recovery.completeSession(
      learning.captureSessionClose(
        sessionId: first.session.id,
        ownerId: ownerId,
      ),
    );
    final restarted = _recovery(
      learning: learning,
      evidence: evidence,
      canStart: () => true,
    );

    final resumed = await restarted.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );

    expect(resumed.session.id, first.session.id);
    expect(resumed.recovered, isTrue);
    expect(resumed.state.phase, AdventureLearningCheckpointPhase.completed);
    expect(resumed.state.summaryPresented, isFalse);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
  });

  test('presented completion does not block a new mission', () async {
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final first = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    await _recordOriginal(
      recovery: recovery,
      evidence: evidence,
      plan: oneItemPlan,
      index: 0,
      isCorrect: true,
    );
    await recovery.completeSession(
      learning.captureSessionClose(
        sessionId: first.session.id,
        ownerId: ownerId,
      ),
    );
    await recovery.acknowledgeSummaryPresented();
    final restarted = _recovery(
      learning: learning,
      evidence: evidence,
      canStart: () => true,
    );

    final next = await restarted.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );

    expect(next.session.id, isNot(first.session.id));
    expect(next.recovered, isFalse);
    expect(next.presentation, AdventureLearningPresentation.adventure);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(2),
    );
  });

  test(
    'exact recovery uses Standard presentation without transient plan provenance',
    () async {
      final first = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
      );

      final restored = await restarted.recoverExact(
        ownerId: ownerId,
        sessionId: first.session.id,
      );

      expect(restored, isNotNull);
      expect(restored!.recovered, isTrue);
      expect(restored.presentation, AdventureLearningPresentation.standard);
    },
  );

  test(
    'emergency off blocks a new start without a Learning mutation',
    () async {
      enabled = false;

      await expectLater(
        recovery.startOrResume(plan: plan, activeOwnerId: ownerId),
        throwsStateError,
      );

      expect(await database.select(database.learningSessions).get(), isEmpty);
    },
  );

  test('owner drift rejects before session or checkpoint mutation', () async {
    final otherPlan = _plan(ownerId: 'owner:other', content: plan.content);

    await expectLater(
      recovery.startOrResume(plan: otherPlan, activeOwnerId: 'owner:other'),
      throwsStateError,
    );

    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test('owner switch rejects a new occurrence checkpoint', () async {
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: ownerId,
    );
    final before = await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );
    await _switchActiveOwner(database, ownerId);

    await expectLater(
      recovery.checkpointSkippedOccurrence(
        identity: plan.content.first,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
        promptVariant: 'typedRecall',
      ),
      throwsStateError,
    );

    final after = await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );
    expect(after!.checkpoint!.revision, before!.checkpoint!.revision);
    expect(after.checkpoint!.state, before.checkpoint!.state);
    expect(
      recovery.currentRun!.state.phase,
      AdventureLearningCheckpointPhase.active,
    );
  });

  test('owner switch rejects close before terminal mutation', () async {
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    await _recordOriginal(
      recovery: recovery,
      evidence: evidence,
      plan: oneItemPlan,
      index: 0,
      isCorrect: true,
    );
    final before = await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );
    final close = learning.captureSessionClose(
      sessionId: run.session.id,
      ownerId: ownerId,
    );
    await _switchActiveOwner(database, ownerId);

    await expectLater(recovery.checkpointSessionClose(close), throwsStateError);

    final after = await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );
    expect(after!.checkpoint!.revision, before!.checkpoint!.revision);
    expect(after.checkpoint!.state, before.checkpoint!.state);
    expect(after.session.state, 'active');
    expect(
      recovery.currentRun!.state.phase,
      AdventureLearningCheckpointPhase.active,
    );
  });

  test(
    'guest binding preserves same-owner exact recovery and mutation',
    () async {
      final first = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final bound = await owners.bindFirebaseUid(ownerId, 'firebase-user-1');
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
      );

      final restored = await restarted.recoverExact(
        ownerId: ownerId,
        sessionId: first.session.id,
      );
      await restarted.checkpointSkippedOccurrence(
        identity: plan.content.first,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
        promptVariant: 'typedRecall',
      );

      expect(bound.id, ownerId);
      expect(bound.firebaseUid, 'firebase-user-1');
      expect(restored!.session.ownerId, ownerId);
      expect(restored.recovered, isTrue);
      expect(
        restarted.currentRun!.state.phase,
        AdventureLearningCheckpointPhase.pendingOccurrence,
      );
    },
  );

  test(
    'pending evidence is frozen durably and restores as explicit retry',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final pending = evidence.capture(
        ownerId: ownerId,
        input: CurrentActivityInput.typedRecall,
        sessionId: run.session.id,
        wordId: plan.content.first.id,
        isCorrect: false,
        responseTimeMs: 812,
        attemptNumber: 1,
      );

      await recovery.checkpointPendingEvidence(
        pending: pending,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
      );
      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
      );
      final restored = await restarted.recoverExact(
        ownerId: ownerId,
        sessionId: run.session.id,
      );

      expect(restored!.pendingEvidence, isNotNull);
      expect(restored.pendingEvidence!.requiresRetry, isTrue);
      expect(
        restored.pendingEvidence!.sourceEvidenceId,
        pending.sourceEvidenceId,
      );
      await expectLater(restored.pendingEvidence!.record(), throwsStateError);
      final result = await restored.pendingEvidence!.retry();
      expect(result.inserted, isTrue);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  test(
    'lost checkpoint acknowledgement retries the exact checkpoint',
    () async {
      final observed = <LearningActivityCheckpoint>[];
      var loseAcknowledgement = true;
      final exactRecovery = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
        appendCheckpoint: (checkpoint, {required ownerId}) async {
          observed.add(checkpoint);
          await learning.appendActivityCheckpoint(checkpoint, ownerId: ownerId);
          if (loseAcknowledgement) {
            loseAcknowledgement = false;
            throw StateError('simulated checkpoint acknowledgement loss');
          }
        },
      );
      final run = await exactRecovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final pending = evidence.capture(
        ownerId: ownerId,
        input: CurrentActivityInput.typedRecall,
        sessionId: run.session.id,
        wordId: plan.content.first.id,
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
      );

      Future<void> checkpoint() => exactRecovery.checkpointPendingEvidence(
        pending: pending,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
      );
      await expectLater(checkpoint(), throwsStateError);
      await checkpoint();

      expect(observed, hasLength(2));
      expect(observed[1].revision, observed[0].revision);
      expect(observed[1].occurredAtUtc, observed[0].occurredAtUtc);
      expect(observed[1].state, observed[0].state);
      expect(exactRecovery.currentRun!.checkpointRevision, 2);
    },
  );

  test(
    'repair ledger and cursor coalesce into the next pre-write checkpoint',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final wrong = await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: plan,
        index: 0,
        isCorrect: false,
      );
      final nextPending = evidence.capture(
        ownerId: ownerId,
        input: CurrentActivityInput.typedRecall,
        sessionId: run.session.id,
        wordId: plan.content[1].id,
        isCorrect: true,
        responseTimeMs: 500,
        attemptNumber: 2,
      );
      await recovery.checkpointPendingEvidence(
        pending: nextPending,
        originalIndex: 1,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
      );

      final restored = await _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
      ).recoverExact(ownerId: ownerId, sessionId: run.session.id);

      expect(restored!.repairPolicy.tickets, hasLength(1));
      expect(
        restored.repairPolicy.tickets.single.originalEvidenceId,
        wrong.sourceEvidenceId,
      );
      expect(restored.state.currentOriginalIndex, 1);
      expect(restored.state.nextOccurrenceOrdinal, 2);
      expect(restored.checkpointRevision, 3);
      expect(
        restored.pendingEvidence!.sourceEvidenceId,
        nextPending.sourceEvidenceId,
      );
    },
  );

  test('flashcard repair recovers without creating answer evidence', () async {
    recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (_, mode, prompt) =>
          mode == LessonMode.flashcard && prompt == 'flashcardExposure',
      spacingForIdentity: (_) => 3,
    );
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: ownerId,
    );
    for (var index = 0; index < plan.content.length; index += 1) {
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: plan,
        index: index,
        isCorrect: index != 0,
      );
    }
    expect(recovery.currentRun!.repairPolicy.dueRepairs, hasLength(1));
    await recovery.checkpointFlashcardRepair(
      identity: plan.content.first,
      originalIndex: plan.content.length,
    );

    final restarted = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => false,
      isRepairModeEligible: (_, mode, prompt) =>
          mode == LessonMode.flashcard && prompt == 'flashcardExposure',
      spacingForIdentity: (_) => 3,
    );
    final restored = await restarted.recoverExact(
      ownerId: ownerId,
      sessionId: run.session.id,
    );

    expect(restored!.pendingEvidence, isNull);
    expect(
      restored.state.pendingOccurrence!.role,
      AdventureLearningItemRole.repair,
    );
    expect(restored.presentation, AdventureLearningPresentation.standard);
    final decision = restarted.acceptPendingOccurrence(
      AdventureRepairAttempt(
        identity: plan.content.first,
        mode: LessonMode.flashcard,
        promptVariant: 'flashcardExposure',
        outcome: AdventureAttemptOutcome.exposure,
        evidenceClass: null,
        canonicalEvidenceCommitted: false,
        sourceEvidenceId: null,
        isRepair: true,
      ),
      nextOriginalIndex: plan.content.length,
      remainingOriginalItems: 0,
    );

    expect(decision.disposition, AdventureRepairDisposition.completed);
    expect(await database.select(database.answerAttempts).get(), hasLength(4));
  });

  test(
    'skipped occurrence is checkpointed without evidence and advances only after acceptance',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );

      await recovery.checkpointSkippedOccurrence(
        identity: plan.content.first,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
        promptVariant: 'typedRecall',
      );

      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => true,
      );
      final restored = await restarted.recoverExact(
        ownerId: ownerId,
        sessionId: run.session.id,
      );

      expect(restored!.pendingEvidence, isNull);
      expect(restored.state.currentOriginalIndex, 0);
      expect(
        restored.state.pendingOccurrence!.role,
        AdventureLearningItemRole.original,
      );
      restarted.acceptPendingOccurrence(
        AdventureRepairAttempt(
          identity: plan.content.first,
          mode: LessonMode.typedRecall,
          promptVariant: 'typedRecall',
          outcome: AdventureAttemptOutcome.skipped,
          evidenceClass: null,
          canonicalEvidenceCommitted: false,
          sourceEvidenceId: null,
        ),
        nextOriginalIndex: 1,
        remainingOriginalItems: plan.content.length - 1,
      );

      expect(restarted.currentRun!.state.currentOriginalIndex, 1);
      expect(restarted.currentRun!.state.nextOccurrenceOrdinal, 2);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    },
  );

  test('occurrence checkpoint cannot move the original cursor ahead', () async {
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: ownerId,
    );
    final pending = evidence.capture(
      ownerId: ownerId,
      input: CurrentActivityInput.typedRecall,
      sessionId: run.session.id,
      wordId: plan.content[1].id,
      isCorrect: true,
      responseTimeMs: 200,
      attemptNumber: 1,
    );

    await expectLater(
      recovery.checkpointPendingEvidence(
        pending: pending,
        originalIndex: 1,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
      ),
      throwsStateError,
    );

    expect(recovery.currentRun!.state.currentOriginalIndex, 0);
    expect(recovery.currentRun!.checkpointRevision, 1);
  });

  test(
    'completion checkpoints the exact close before and after Learning close',
    () async {
      final run = await recovery.startOrResume(
        plan: _plan(ownerId: ownerId, content: plan.content.take(1).toList()),
        activeOwnerId: ownerId,
      );
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: _plan(ownerId: ownerId, content: plan.content.take(1).toList()),
        index: 0,
        isCorrect: true,
      );
      final close = learning.captureSessionClose(
        sessionId: run.session.id,
        ownerId: ownerId,
      );

      final summary = await recovery.completeSession(close);
      final replay = await recovery.completeSession(close);
      final exact = await learning.loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: run.session.id,
        activityType: mixedReviewActivityType,
      );

      expect(summary.state, 'completed');
      expect(replay.endedAtUtc, summary.endedAtUtc);
      expect(exact!.checkpoint!.terminalAcknowledged, isTrue);
      expect(exact.checkpoint!.terminalAtUtc, close.completedAtUtc);
      expect(
        AdventureLearningCheckpointState.fromJson(
          exact.checkpoint!.state,
        ).phase,
        AdventureLearningCheckpointPhase.completed,
      );
      expect(exact.checkpoint!.revision, 4);

      await recovery.acknowledgeSummaryPresented();
      final acknowledged = await learning.loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: run.session.id,
        activityType: mixedReviewActivityType,
      );
      expect(acknowledged!.checkpoint!.revision, 5);
      expect(
        AdventureLearningCheckpointState.fromJson(
          acknowledged.checkpoint!.state,
        ).summaryPresented,
        isTrue,
      );
    },
  );

  test(
    'split shell close resumes after Learning commit before terminal acknowledgement',
    () async {
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final run = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: oneItemPlan,
        index: 0,
        isCorrect: true,
      );
      final close = learning.captureSessionClose(
        sessionId: run.session.id,
        ownerId: ownerId,
      );

      await recovery.checkpointSessionClose(close);
      final summary = await close.finish();

      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => false,
      );
      final restored = await restarted.recoverExact(
        ownerId: ownerId,
        sessionId: run.session.id,
      );
      expect(restored!.state.phase, AdventureLearningCheckpointPhase.closing);
      expect(restored.pendingClose, isNotNull);
      final replay = await restored.pendingClose!.finish();
      await restarted.acknowledgeSessionClosed(
        close: restored.pendingClose!,
        summary: replay,
      );

      expect(replay.endedAtUtc, summary.endedAtUtc);
      expect(
        restarted.currentRun!.state.phase,
        AdventureLearningCheckpointPhase.completed,
      );
      expect(restarted.currentRun!.checkpointRevision, 4);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
    },
  );

  test('completed acknowledgement rejects a fabricated summary', () async {
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    await _recordOriginal(
      recovery: recovery,
      evidence: evidence,
      plan: oneItemPlan,
      index: 0,
      isCorrect: true,
    );
    final close = learning.captureSessionClose(
      sessionId: run.session.id,
      ownerId: ownerId,
    );
    final summary = await recovery.completeSession(close);
    final fabricated = LearningSessionSummary(
      id: summary.id,
      ownerId: summary.ownerId,
      activityType: summary.activityType,
      state: summary.state,
      startedAtUtc: summary.startedAtUtc,
      endedAtUtc: summary.endedAtUtc,
      correctCount: summary.correctCount + 1,
      wrongCount: summary.wrongCount,
      score: summary.score,
      sessionConfiguration: summary.sessionConfiguration,
    );

    await expectLater(
      recovery.acknowledgeSessionClosed(close: close, summary: fabricated),
      throwsStateError,
    );
  });

  test(
    'completed summary is restored from canonical Learning authority',
    () async {
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final run = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      await _recordOriginal(
        recovery: recovery,
        evidence: evidence,
        plan: oneItemPlan,
        index: 0,
        isCorrect: true,
      );
      final summary = await recovery.completeSession(
        learning.captureSessionClose(
          sessionId: run.session.id,
          ownerId: ownerId,
        ),
      );

      final restarted = _recovery(
        learning: learning,
        evidence: evidence,
        canStart: () => false,
      );
      await restarted.recoverExact(ownerId: ownerId, sessionId: run.session.id);

      final restored = await restarted.loadCompletedSummary();

      expect(restored.id, summary.id);
      expect(restored.endedAtUtc, summary.endedAtUtc);
      expect(restored.correctCount, summary.correctCount);
      expect(restored.wrongCount, summary.wrongCount);
      expect(restored.score, summary.score);
    },
  );

  test('recovered completed summary rejects a mismatched terminal', () async {
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    await _recordOriginal(
      recovery: recovery,
      evidence: evidence,
      plan: oneItemPlan,
      index: 0,
      isCorrect: true,
    );
    await recovery.completeSession(
      learning.captureSessionClose(sessionId: run.session.id, ownerId: ownerId),
    );
    final exact = (await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    ))!;
    final canonical = exact.session;
    final mismatched = LearningSessionSummary(
      id: canonical.id,
      ownerId: canonical.ownerId,
      activityType: canonical.activityType,
      state: canonical.state,
      startedAtUtc: canonical.startedAtUtc,
      endedAtUtc: canonical.endedAtUtc!.add(const Duration(seconds: 1)),
      correctCount: canonical.correctCount,
      wrongCount: canonical.wrongCount,
      score: canonical.score,
      appVersion: canonical.appVersion,
      buildId: canonical.buildId,
      sessionConfiguration: canonical.sessionConfiguration,
      configurationActiveEffort: canonical.configurationActiveEffort,
    );
    final mismatchedRepository = _ExactRecoveryLearningRepository(
      pinnedContent: learning.repository as PinnedLearningContentRepository,
      recovery: LearningActivityRecovery(
        session: mismatched,
        checkpoint: exact.checkpoint,
        attempts: exact.attempts,
      ),
    );
    final mismatchedLearning = LearningUseCases(
      owners: owners,
      repository: mismatchedRepository,
      generateId: () => 'unused-recovery-id',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'adventure-test'),
    );
    final restarted = _recovery(
      learning: mismatchedLearning,
      evidence: CurrentActivityEvidenceAdapter(learning: mismatchedLearning),
      canStart: () => false,
    );

    final restored = await restarted.recoverExact(
      ownerId: ownerId,
      sessionId: run.session.id,
    );

    expect(restored, isNotNull);
    await expectLater(restarted.loadCompletedSummary(), throwsStateError);
  });

  test(
    'checkpoint codec rejects unknown and inconsistent pending state',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      final json = Map<String, Object?>.of(run.state.toJson())
        ..['unknown'] = true;
      expect(
        () => AdventureLearningCheckpointState.fromJson(json),
        throwsFormatException,
      );

      final inconsistent = Map<String, Object?>.of(run.state.toJson())
        ..['phase'] = AdventureLearningCheckpointPhase.pendingOccurrence.name;
      expect(
        () => AdventureLearningCheckpointState.fromJson(inconsistent),
        throwsFormatException,
      );
      final nonIntegerSchema = Map<String, Object?>.of(run.state.toJson())
        ..['schemaVersion'] = 1.0;
      expect(
        () => AdventureLearningCheckpointState.fromJson(nonIntegerSchema),
        throwsFormatException,
      );
    },
  );

  test(
    'checkpoint codec reads v1, writes v2, and rejects corrupt catalog snapshot',
    () async {
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
        buildPromptCatalogSnapshot: (session) async =>
            AdventureMixedReviewCatalogSnapshot.fromLexicalWords(
              session: session,
              lexicalWords: const [],
            ),
      );

      expect(
        run.state.schemaVersion,
        AdventureLearningCheckpointState.currentSchemaVersion,
      );
      expect(run.state.promptCatalogSnapshot, isNotNull);
      final exact = await learning.loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: run.session.id,
        activityType: mixedReviewActivityType,
      );
      final persistedV2 = exact!.checkpoint!.state;
      expect(persistedV2, contains('promptCatalog'));
      expect(
        AdventureLearningCheckpointState.fromJson(
          persistedV2,
        ).promptCatalogSnapshot,
        isNotNull,
      );

      final legacyV1 = Map<String, Object?>.of(persistedV2)
        ..['schemaVersion'] = 1
        ..remove('promptCatalog');
      final decodedLegacy = AdventureLearningCheckpointState.fromJson(legacyV1);
      expect(decodedLegacy.schemaVersion, 1);
      expect(decodedLegacy.promptCatalogSnapshot, isNull);
      expect(decodedLegacy.toJson(), legacyV1);

      final corruptCatalog = Map<String, Object?>.of(
        (persistedV2['promptCatalog']! as Map).cast<String, Object?>(),
      )..['schemaVersion'] = 999;
      final corruptV2 = Map<String, Object?>.of(persistedV2)
        ..['promptCatalog'] = corruptCatalog;
      expect(
        () => AdventureLearningCheckpointState.fromJson(corruptV2),
        throwsFormatException,
      );
    },
  );

  test('checkpoint budget reserves three terminal revisions', () {
    expect(AdventureRecoveryUseCases.maximumOriginalItems, 30);
    expect(AdventureRecoveryUseCases.maximumOccurrences, 60);
    expect(
      1 +
          AdventureRecoveryUseCases.maximumOccurrences +
          AdventureRecoveryUseCases.terminalCheckpointReserve,
      AdventureRecoveryUseCases.maximumRecoveryCheckpoints,
    );
  });
}

final class _ExactRecoveryLearningRepository
    implements
        LearningRepository,
        LearningActivityRecoveryRepository,
        PinnedLearningContentRepository {
  const _ExactRecoveryLearningRepository({
    required this.pinnedContent,
    required this.recovery,
  });

  final PinnedLearningContentRepository pinnedContent;
  final LearningActivityRecovery recovery;

  @override
  Future<LearningActivityRecovery?> loadExactActivityRecovery({
    required String ownerId,
    required String sessionId,
    required String activityType,
  }) async => recovery;

  @override
  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  }) => pinnedContent.listExactPinnedQuizWords(
    ownerId: ownerId,
    content: content,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _switchActiveOwner(AppDatabase database, String previousOwnerId) =>
    database.transaction(() async {
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(previousOwnerId)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'local:replacement-owner',
              createdAtUtcMs: DateTime.utc(
                2026,
                9,
                4,
                12,
              ).millisecondsSinceEpoch,
              isActive: const Value(true),
            ),
          );
    });

Future<PendingCurrentActivityEvidence> _recordOriginal({
  required AdventureRecoveryUseCases recovery,
  required CurrentActivityEvidenceAdapter evidence,
  required AdventureSessionPlanV1 plan,
  required int index,
  required bool isCorrect,
}) async {
  final run = recovery.currentRun!;
  final pending = evidence.capture(
    ownerId: run.state.ownerId,
    input: CurrentActivityInput.typedRecall,
    sessionId: run.session.id,
    wordId: plan.content[index].id,
    isCorrect: isCorrect,
    responseTimeMs: 600,
    attemptNumber: run.state.nextOccurrenceOrdinal,
  );
  await recovery.checkpointPendingEvidence(
    pending: pending,
    originalIndex: index,
    role: AdventureLearningItemRole.original,
    mode: LessonMode.typedRecall,
  );
  await pending.record();
  recovery.acceptPendingOccurrence(
    AdventureRepairAttempt(
      identity: plan.content[index],
      mode: LessonMode.typedRecall,
      promptVariant: 'typedRecall',
      outcome: isCorrect
          ? AdventureAttemptOutcome.correct
          : AdventureAttemptOutcome.incorrect,
      evidenceClass: EvidenceClass.independentRecall,
      canonicalEvidenceCommitted: true,
      sourceEvidenceId: pending.sourceEvidenceId,
    ),
    nextOriginalIndex: index + 1,
    remainingOriginalItems: plan.content.length - index - 1,
  );
  return pending;
}

AdventureRecoveryUseCases _recovery({
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  required bool Function() canStart,
  AdventureCheckpointAppender? appendCheckpoint,
}) => AdventureRecoveryUseCases(
  learning: learning,
  evidence: evidence,
  canStartNewMission: canStart,
  isRepairModeEligible: (_, mode, _) =>
      mode == LessonMode.flashcard || mode == LessonMode.meaningQuiz,
  spacingForIdentity: (_) => 3,
  appendCheckpoint: appendCheckpoint,
);

Future<List<ContentIdentity>> _seedVocabulary(
  AppDatabase database,
  String ownerId,
) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:adventure',
          ownerId: ownerId,
          name: 'Adventure',
          normalizedName: 'adventure',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final identities = <ContentIdentity>[];
  for (final entry in const <(String, String, String)>[
    ('word:station', 'station', 'สถานี'),
    ('word:ticket', 'ticket', 'ตั๋ว'),
    ('word:platform', 'platform', 'ชานชาลา'),
    ('word:journey', 'journey', 'การเดินทาง'),
  ]) {
    final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:adventure',
      spelling: entry.$2,
      normalizedSpelling: entry.$2,
      meaning: entry.$3,
      normalizedMeaning: entry.$3,
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
      isGlobal: false,
    );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: entry.$1,
            ownerId: ownerId,
            categoryId: 'category:adventure',
            spelling: entry.$2,
            normalizedSpelling: entry.$2,
            meaning: entry.$3,
            normalizedMeaning: entry.$3,
            partOfSpeech: 'noun',
            source: const Value('manual'),
            isGlobal: const Value(false),
            contentRevision: const Value(1),
            contentChecksumSha256: Value(checksum),
            contentProvenance: Value(ContentProvenance.userAuthored.name),
            contentReviewState: Value(ContentReviewState.unreviewed.name),
            contentPublicationState: Value(
              ContentPublicationState.private.name,
            ),
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    identities.add(
      ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: entry.$1,
        revision: 1,
      ),
    );
  }
  return identities;
}

AdventureSessionPlanV1 _plan({
  required String ownerId,
  required List<ContentIdentity> content,
}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: ownerId,
    mode: LessonMode.typedRecall,
    itemCount: content.length,
    direction: SessionDirection.reverse,
    difficulty: SessionDifficulty.standard,
    hintBudget: 1,
    timing: const SessionTiming.timed(Duration(minutes: 5)),
    packIdentity: null,
    protocolId: 'protocol:local',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:one',
  );
  const planId = 'adventure-plan:recovery';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: ownerId,
    createdAtUtc: DateTime.utc(2026, 9, 4, 9),
    sourceEvaluatedAtUtc: DateTime.utc(2026, 9, 4, 9),
    content: content,
    contentChecksumsSha256: <String, String>{
      for (final item in content) item.id: _checksumForContent(item.id),
    },
    mode: LessonMode.typedRecall,
    configuration: configuration,
    recommendationPolicyVersion: 'recommendation-v1',
    sourceReasonCode: 'due',
    learnerOverrideApplied: false,
    origin: const AdventureOriginContextV1(
      planId: planId,
      nodeId: 'today-mission',
      catalogId: 'catalog:one',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      presentation: TodayExperiencePresentation.adventure,
    ),
  );
}

String _checksumForContent(String id) {
  final values = <String, (String, String)>{
    'word:station': ('station', 'สถานี'),
    'word:ticket': ('ticket', 'ตั๋ว'),
    'word:platform': ('platform', 'ชานชาลา'),
    'word:journey': ('journey', 'การเดินทาง'),
  };
  final value = values[id]!;
  return ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:adventure',
    spelling: value.$1,
    normalizedSpelling: value.$1,
    meaning: value.$2,
    normalizedMeaning: value.$2,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
  );
}
