import 'dart:async';
import 'dart:convert';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_controller.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late LearningUseCases learning;
  late CurrentActivityEvidenceAdapter evidence;
  late LessonModeRegistry registry;
  late String ownerId;
  late AdventureSessionPlanV1 plan;
  late List<VocabularyWord> lexicalWords;
  var nextId = 0;
  var now = DateTime.utc(2026, 9, 5, 9);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner:mixed-review',
      nowUtc: () => now,
    );
    ownerId = (await owners.getOrCreateActiveOwner()).id;
    final seeded = await _seedWords(database, ownerId);
    plan = _plan(ownerId: ownerId, content: seeded.$1);
    lexicalWords = seeded.$2;
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'mixed-review-${++nextId}',
      nowUtc: () {
        final value = now;
        now = now.add(const Duration(seconds: 1));
        return value;
      },
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'mixed-review-test',
      ),
    );
    evidence = CurrentActivityEvidenceAdapter(learning: learning);
    registry = buildLessonModeRegistry();
  });

  tearDown(() => database.close());

  Future<void> expectIntegratedChoiceParity({
    required LessonMode mode,
    required SessionDirection direction,
    required String expectedPromptVariant,
  }) async {
    final occurrenceAtUtc = DateTime.utc(2026, 9, 5, 10);
    final equivalentEvidence = CurrentActivityEvidenceAdapter(
      learning: learning,
      generateId: () => 'mixed-review-equivalence',
      nowUtc: () => occurrenceAtUtc,
    );
    late AdventureMixedReviewPromptCatalog catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: equivalentEvidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (identity, repairMode, variant) =>
          catalog.supports(identity, repairMode, variant),
    );
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
      mode: mode,
      direction: direction,
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: lexicalWords.take(1),
      registry: registry,
      direction: direction,
    );
    final controller = AdventureMixedReviewController(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: _FakeLessonHost(recordFailures: 1),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final prompt = controller.prompt!;
    expect(prompt.mode, mode);
    expect(prompt.promptVariant, expectedPromptVariant);
    final option = prompt.answer!;
    final standard = switch (mode) {
      LessonMode.meaningQuiz => _captureStandardMeaningQuiz(
        evidence: equivalentEvidence,
        ownerId: ownerId,
        sessionId: run.session.id,
        prompt: prompt,
        option: option,
        responseTimeMs: 420,
      ),
      LessonMode.cloze => _captureStandardCloze(
        evidence: equivalentEvidence,
        ownerId: ownerId,
        sessionId: run.session.id,
        prompt: prompt,
        option: option,
        responseTimeMs: 420,
      ),
      LessonMode.definitionQuiz => _captureStandardDefinitionQuiz(
        evidence: equivalentEvidence,
        ownerId: ownerId,
        sessionId: run.session.id,
        prompt: prompt,
        option: option,
        responseTimeMs: 420,
      ),
      _ => throw ArgumentError.value(mode, 'mode', 'must use choice input'),
    };
    final standardFrozen = await standard.freezeForRecovery();

    await expectLater(
      controller.submitChoice(option: option, responseTimeMs: 420),
      throwsStateError,
    );
    final adventureFrozen =
        recovery.currentRun!.state.pendingOccurrence!.evidence!;

    _expectFrozenEvidenceParity(
      adventure: adventureFrozen,
      standard: standardFrozen,
    );
  }

  test(
    'incorrect typed answer returns as cloze after three independent items',
    () async {
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
        spacingForIdentity: (_) => 3,
      );
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: lexicalWords,
        registry: registry,
        direction: plan.configuration.direction,
      );
      final host = _FakeLessonHost();
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: host,
      );

      await controller.initialize();
      expect(controller.phase, AdventureMixedReviewPhase.awaitingAnswer);
      expect(controller.prompt!.mode, LessonMode.typedRecall);
      expect(controller.role, AdventureLearningItemRole.original);

      await controller.submitTyped(
        response: 'not-the-word',
        responseTimeMs: 50,
      );
      expect(controller.feedback!.isCorrect, isFalse);
      expect(controller.supportMessage, contains('จะกลับมาอีกครั้ง'));

      for (var index = 1; index <= 3; index += 1) {
        await controller.next();
        expect(controller.prompt!.identity, plan.content[index]);
        await controller.submitTyped(
          response: controller.prompt!.answer!,
          responseTimeMs: 50 + index,
        );
      }

      await controller.next();
      expect(controller.isRepair, isTrue);
      expect(controller.prompt!.identity, plan.content.first);
      expect(controller.prompt!.mode, LessonMode.cloze);
      expect(controller.prompt!.promptVariant, 'clozeSelected');
      await controller.submitChoice(
        option: controller.prompt!.answer!,
        responseTimeMs: 80,
      );

      await controller.next();
      expect(controller.isRepair, isFalse);
      expect(controller.prompt!.identity, plan.content[4]);
      await controller.submitTyped(
        response: controller.prompt!.answer!,
        responseTimeMs: 90,
      );
      await controller.next();

      expect(controller.phase, AdventureMixedReviewPhase.completed);
      expect(controller.summary!.state, 'completed');
      expect(host.occurrenceModes, <LessonMode>[
        LessonMode.typedRecall,
        LessonMode.typedRecall,
        LessonMode.typedRecall,
        LessonMode.typedRecall,
        LessonMode.cloze,
        LessonMode.typedRecall,
      ]);
      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(6));
      expect(attempts.map((attempt) => attempt.attemptNumber), <int>[
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      controller.dispose();
    },
  );

  test('evidence retry reuses the exact captured occurrence', () async {
    late AdventureMixedReviewPromptCatalog catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (identity, mode, variant) =>
          catalog.supports(identity, mode, variant),
      spacingForIdentity: (_) => 3,
    );
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: lexicalWords.take(1),
      registry: registry,
      direction: oneItemPlan.configuration.direction,
    );
    final host = _FakeLessonHost(recordFailures: 1);
    final controller = AdventureMixedReviewController(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: host,
    );
    await controller.initialize();

    await expectLater(
      controller.submitTyped(
        response: controller.prompt!.answer!,
        responseTimeMs: 70,
      ),
      throwsStateError,
    );
    final evidenceId = recovery
        .currentRun!
        .state
        .pendingOccurrence!
        .evidence!
        .sourceEvidenceId;
    expect(controller.phase, AdventureMixedReviewPhase.evidenceRetryRequired);

    await controller.retryEvidence();

    expect(controller.phase, AdventureMixedReviewPhase.answered);
    expect(host.evidenceIds, <String>[evidenceId, evidenceId]);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    controller.dispose();
  });

  test(
    'integrated Adventure answer and evidence JSON equal Standard bytes',
    () async {
      final occurrenceAtUtc = DateTime.utc(2026, 9, 5, 10);
      final equivalentEvidence = CurrentActivityEvidenceAdapter(
        learning: learning,
        generateId: () => 'mixed-review-equivalence',
        nowUtc: () => occurrenceAtUtc,
      );
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: equivalentEvidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
      );
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final run = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: lexicalWords.take(1),
        registry: registry,
        direction: oneItemPlan.configuration.direction,
      );
      final host = _FakeLessonHost(recordFailures: 1);
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: host,
      );
      await controller.initialize();
      final prompt = controller.prompt!.typedRecallPrompt!;
      final standard = const TypedRecallModeAdapter().capture(
        evidence: CurrentActivityEvidenceAdapter(
          learning: learning,
          generateId: () => 'mixed-review-equivalence',
          nowUtc: () => occurrenceAtUtc,
        ),
        ownerId: ownerId,
        sessionId: run.session.id,
        prompt: prompt,
        response: prompt.canonicalAnswer,
        responseTimeMs: 420,
        attemptNumber: 1,
        support: const TypedRecallSupport.unassisted(),
      );
      final standardFrozen = await standard.pending.freezeForRecovery();

      await expectLater(
        controller.submitTyped(
          response: prompt.canonicalAnswer,
          responseTimeMs: 420,
        ),
        throwsStateError,
      );
      final adventureFrozen =
          recovery.currentRun!.state.pendingOccurrence!.evidence!;

      expect(
        jsonEncode(_answerPayload(adventureFrozen)),
        jsonEncode(_answerPayload(standardFrozen)),
      );
      expect(
        jsonEncode(adventureFrozen.evidenceContext.toJson()),
        jsonEncode(standardFrozen.evidenceContext.toJson()),
      );
      expect(
        jsonEncode(adventureFrozen.toJson()),
        jsonEncode(standardFrozen.toJson()),
      );
      expect(
        adventureFrozen.evidenceContext.toJson().keys,
        isNot(contains('adventure')),
      );
      controller.dispose();
    },
  );

  test(
    'integrated Adventure meaning quiz evidence equals Standard bytes',
    () => expectIntegratedChoiceParity(
      mode: LessonMode.meaningQuiz,
      direction: SessionDirection.reverse,
      expectedPromptVariant: 'wordChoice',
    ),
  );

  test(
    'integrated Adventure cloze evidence equals Standard bytes',
    () => expectIntegratedChoiceParity(
      mode: LessonMode.cloze,
      direction: SessionDirection.forward,
      expectedPromptVariant: 'clozeSelected',
    ),
  );

  test(
    'integrated Adventure definition quiz evidence equals Standard bytes',
    () => expectIntegratedChoiceParity(
      mode: LessonMode.definitionQuiz,
      direction: SessionDirection.forward,
      expectedPromptVariant: 'definitionChoice',
    ),
  );

  test(
    'checkpoint evidence and completion stay inside one route recovery lease',
    () async {
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
      );
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final run = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: lexicalWords.take(1),
        registry: registry,
        direction: oneItemPlan.configuration.direction,
      );
      final host = _FakeLessonHost(requireRecoveryLease: true);
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: host,
      );
      await controller.initialize();

      await controller.submitTyped(
        response: controller.prompt!.answer!,
        responseTimeMs: 40,
      );
      await controller.next();

      expect(controller.phase, AdventureMixedReviewPhase.completed);
      expect(host.recoveryLeaseCalls, 2);
      expect(host.maximumRecoveryLeaseDepth, 1);
      controller.dispose();
    },
  );

  test(
    'flashcard repair checkpoints only inside accepted continuation',
    () async {
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
        spacingForIdentity: (_) => 3,
      );
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: const <VocabularyWord>[],
        registry: registry,
        direction: plan.configuration.direction,
      );
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: _FakeLessonHost(),
      );
      await controller.initialize();
      await controller.submitTyped(response: 'wrong', responseTimeMs: 20);
      for (var index = 1; index <= 3; index += 1) {
        await controller.next();
        await controller.submitTyped(
          response: controller.prompt!.answer!,
          responseTimeMs: 20,
        );
      }

      await controller.next();

      expect(controller.prompt!.mode, LessonMode.flashcard);
      expect(
        controller.phase,
        AdventureMixedReviewPhase.awaitingFlashcardReveal,
      );
      expect(
        recovery.currentRun!.state.phase,
        AdventureLearningCheckpointPhase.active,
      );
      expect(recovery.currentRun!.state.pendingOccurrence, isNull);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(4),
      );

      controller.revealFlashcard();
      expect(controller.phase, AdventureMixedReviewPhase.flashcardRevealed);
      await controller.continueAfterFlashcard();
      expect(controller.phase, AdventureMixedReviewPhase.answered);
      expect(
        recovery.currentRun!.state.phase,
        AdventureLearningCheckpointPhase.active,
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(4),
      );
      controller.dispose();
    },
  );

  test(
    'flashcard continuation rejects reentrancy and restores retry state',
    () async {
      final checkpointEntered = Completer<void>();
      final checkpointGate = Completer<void>();
      var blockFlashcardCheckpoint = false;
      var flashcardCheckpointOperations = 0;
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
        spacingForIdentity: (_) => 3,
        appendCheckpoint: (checkpoint, {required ownerId}) async {
          if (blockFlashcardCheckpoint) {
            flashcardCheckpointOperations += 1;
            if (!checkpointEntered.isCompleted) checkpointEntered.complete();
            await checkpointGate.future;
          }
          await learning.appendActivityCheckpoint(checkpoint, ownerId: ownerId);
        },
      );
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: const <VocabularyWord>[],
        registry: registry,
        direction: plan.configuration.direction,
      );
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: _FakeLessonHost(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.submitTyped(response: 'wrong', responseTimeMs: 20);
      for (var index = 1; index <= 3; index += 1) {
        await controller.next();
        await controller.submitTyped(
          response: controller.prompt!.answer!,
          responseTimeMs: 20,
        );
      }
      await controller.next();
      controller.revealFlashcard();
      blockFlashcardCheckpoint = true;

      final firstCall = controller.continueAfterFlashcard();
      final phaseAfterFirstCall = controller.phase;
      final busyAfterFirstCall = controller.isBusy;
      final firstFailure = expectLater(
        firstCall,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'injected flashcard checkpoint failure',
          ),
        ),
      );
      final secondRejection = expectLater(
        controller.continueAfterFlashcard(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Flashcard exposure cannot continue now.',
          ),
        ),
      );
      await checkpointEntered.future;
      checkpointGate.completeError(
        StateError('injected flashcard checkpoint failure'),
      );

      await firstFailure;
      await secondRejection;
      expect(
        phaseAfterFirstCall,
        isNot(AdventureMixedReviewPhase.flashcardRevealed),
      );
      expect(busyAfterFirstCall, isTrue);
      expect(flashcardCheckpointOperations, 1);
      expect(controller.phase, AdventureMixedReviewPhase.flashcardRevealed);
      expect(
        controller.failure,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'injected flashcard checkpoint failure',
        ),
      );
    },
  );

  test('recovered flashcard skip returns to the exact skip retry', () async {
    late AdventureMixedReviewPromptCatalog catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (identity, mode, variant) =>
          catalog.supports(identity, mode, variant),
      spacingForIdentity: (_) => 3,
    );
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: ownerId,
    );
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: const <VocabularyWord>[],
      registry: registry,
      direction: plan.configuration.direction,
    );
    final controller = AdventureMixedReviewController(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: _FakeLessonHost(),
    );
    await controller.initialize();
    await controller.submitTyped(response: 'wrong', responseTimeMs: 20);
    for (var index = 1; index <= 3; index += 1) {
      await controller.next();
      await controller.submitTyped(
        response: controller.prompt!.answer!,
        responseTimeMs: 20,
      );
    }
    await controller.next();
    final repairPrompt = controller.prompt!;
    expect(repairPrompt.mode, LessonMode.flashcard);
    await recovery.checkpointSkippedOccurrence(
      identity: repairPrompt.identity,
      originalIndex: recovery.currentRun!.state.currentOriginalIndex,
      role: AdventureLearningItemRole.repair,
      mode: repairPrompt.mode,
      promptVariant: repairPrompt.promptVariant,
    );
    controller.dispose();

    final restarted = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => false,
      isRepairModeEligible: (identity, mode, variant) =>
          catalog.supports(identity, mode, variant),
      spacingForIdentity: (_) => 3,
    );
    final restored = await restarted.recoverExact(
      ownerId: ownerId,
      sessionId: run.session.id,
    );
    expect(restored, isNotNull);
    final resumed = AdventureMixedReviewController(
      recovery: restarted,
      catalog: catalog,
      registry: registry,
      host: _FakeLessonHost(),
    );
    addTearDown(resumed.dispose);

    await resumed.initialize();
    expect(resumed.phase, AdventureMixedReviewPhase.skipRetryRequired);
    await resumed.retrySkip();

    expect(resumed.phase, AdventureMixedReviewPhase.answered);
    expect(
      restarted.currentRun!.repairPolicy.tickets.single.state,
      AdventureRepairTicketState.deferred,
    );
    expect(await database.select(database.answerAttempts).get(), hasLength(4));
  });

  test(
    'skip checkpoint and completion stay inside route recovery leases',
    () async {
      late AdventureMixedReviewPromptCatalog catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (identity, mode, variant) =>
            catalog.supports(identity, mode, variant),
      );
      final oneItemPlan = _plan(
        ownerId: ownerId,
        content: plan.content.take(1).toList(),
      );
      final run = await recovery.startOrResume(
        plan: oneItemPlan,
        activeOwnerId: ownerId,
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: lexicalWords.take(1),
        registry: registry,
        direction: oneItemPlan.configuration.direction,
      );
      final host = _FakeLessonHost(requireRecoveryLease: true);
      final controller = AdventureMixedReviewController(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        host: host,
      );
      await controller.initialize();

      final review = DriftReviewCenterReader(database);
      final filter = ReviewQueueFilter(
        ownerId: ownerId,
        evaluatedAtUtc: DateTime.utc(2026, 9, 5),
        timezoneId: 'UTC',
      );
      expect(await review.compose(filter), isEmpty);
      await controller.skip();
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(await database.select(database.savedLearningItems).get(), isEmpty);
      expect(await review.compose(filter), isEmpty);
      await controller.next();

      expect(controller.phase, AdventureMixedReviewPhase.completed);
      expect(host.recoveryLeaseCalls, 2);
      expect(host.maximumRecoveryLeaseDepth, 1);
      controller.dispose();
    },
  );

  test('failed skip retries the exact checkpoint before advancing', () async {
    var failNextCheckpoint = true;
    late AdventureMixedReviewPromptCatalog catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (identity, mode, variant) =>
          catalog.supports(identity, mode, variant),
      appendCheckpoint: (checkpoint, {required ownerId}) async {
        if (failNextCheckpoint) {
          failNextCheckpoint = false;
          throw StateError('injected checkpoint failure');
        }
        await learning.appendActivityCheckpoint(checkpoint, ownerId: ownerId);
      },
    );
    final oneItemPlan = _plan(
      ownerId: ownerId,
      content: plan.content.take(1).toList(),
    );
    final run = await recovery.startOrResume(
      plan: oneItemPlan,
      activeOwnerId: ownerId,
    );
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: lexicalWords.take(1),
      registry: registry,
      direction: oneItemPlan.configuration.direction,
    );
    final controller = AdventureMixedReviewController(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: _FakeLessonHost(),
    );
    await controller.initialize();

    await expectLater(controller.skip(), throwsStateError);
    expect(controller.phase, AdventureMixedReviewPhase.skipRetryRequired);
    expect(controller.completedOriginalItems, 0);

    await controller.retrySkip();

    expect(controller.phase, AdventureMixedReviewPhase.answered);
    expect(controller.completedOriginalItems, 1);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    controller.dispose();
  });
}

PendingCurrentActivityEvidence _captureStandardMeaningQuiz({
  required CurrentActivityEvidenceAdapter evidence,
  required String ownerId,
  required String sessionId,
  required AdventureMixedReviewPrompt prompt,
  required String option,
  required int responseTimeMs,
}) {
  final question = prompt.meaningQuizQuestion!;
  final identity = question.contrastiveIdentity!;
  final input = question.direction == MeaningQuizDirection.wordToMeaning
      ? CurrentActivityInput.meaningMultipleChoice
      : CurrentActivityInput.meaningToWordMultipleChoice;
  return evidence.capturePinnedMeaningRecognition(
    ownerId: ownerId,
    input: input,
    sessionId: sessionId,
    wordId: question.word.id,
    isCorrect: option == question.correctOption,
    responseTimeMs: responseTimeMs,
    attemptNumber: 1,
    contentRevision: identity.revision,
    checksumSha256: question.evidenceChecksumSha256!,
  );
}

PendingCurrentActivityEvidence _captureStandardCloze({
  required CurrentActivityEvidenceAdapter evidence,
  required String ownerId,
  required String sessionId,
  required AdventureMixedReviewPrompt prompt,
  required String option,
  required int responseTimeMs,
}) {
  const adapter = ClozeModeAdapter();
  final question = prompt.clozeQuestion!;
  return evidence.captureCloze(
    ownerId: ownerId,
    sessionId: sessionId,
    wordId: question.wordId,
    isCorrect: adapter.scoresCorrect(question, option),
    responseTimeMs: responseTimeMs,
    attemptNumber: 1,
    contentRevision: question.identity.revision,
    checksumSha256: question.checksumSha256,
    typed: false,
    classification: adapter.classifyResponse(
      inputMode: ClozeInputMode.selected,
      hint: const HintUsageSnapshot.unavailable(),
    ),
  );
}

PendingCurrentActivityEvidence _captureStandardDefinitionQuiz({
  required CurrentActivityEvidenceAdapter evidence,
  required String ownerId,
  required String sessionId,
  required AdventureMixedReviewPrompt prompt,
  required String option,
  required int responseTimeMs,
}) {
  const adapter = DefinitionQuizModeAdapter();
  final question = prompt.definitionQuizQuestion!;
  return evidence.captureDefinitionRecognition(
    ownerId: ownerId,
    sessionId: sessionId,
    wordId: question.wordId,
    isCorrect: adapter.scoresCorrect(question, option),
    responseTimeMs: responseTimeMs,
    attemptNumber: 1,
    contentRevision: question.identity.revision,
    checksumSha256: question.checksumSha256,
    classification: adapter.classifyHintUsage(
      const HintUsageSnapshot.unavailable(),
    ),
  );
}

void _expectFrozenEvidenceParity({
  required FrozenPendingCurrentActivityEvidence adventure,
  required FrozenPendingCurrentActivityEvidence standard,
}) {
  expect(
    jsonEncode(_answerPayload(adventure)),
    jsonEncode(_answerPayload(standard)),
  );
  expect(
    jsonEncode(adventure.evidenceContext.toJson()),
    jsonEncode(standard.evidenceContext.toJson()),
  );
  expect(jsonEncode(adventure.toJson()), jsonEncode(standard.toJson()));
  expect(adventure.evidenceContext.toJson().keys, isNot(contains('adventure')));
}

Map<String, Object?> _answerPayload(
  FrozenPendingCurrentActivityEvidence frozen,
) => <String, Object?>{
  'sourceEvidenceId': frozen.sourceEvidenceId,
  'occurredAtUtc': frozen.occurredAtUtc.toIso8601String(),
  'sessionId': frozen.sessionId,
  'wordId': frozen.wordId,
  'promptMode': frozen.promptMode,
  'isCorrect': frozen.isCorrect,
  'responseTimeMs': frozen.responseTimeMs,
  'attemptNumber': frozen.attemptNumber,
  'providerProvenance': frozen.providerProvenance,
  'actorIdentity': frozen.actorIdentity,
};

final class _FakeLessonHost implements AdventureMixedReviewLessonHost {
  _FakeLessonHost({this.recordFailures = 0, this.requireRecoveryLease = false});

  int recordFailures;
  final bool requireRecoveryLease;
  final List<String> evidenceIds = <String>[];
  final List<LessonMode> occurrenceModes = <LessonMode>[];
  int recoveryLeaseCalls = 0;
  int maximumRecoveryLeaseDepth = 0;
  int _recoveryLeaseDepth = 0;

  @override
  bool get acceptsOperations => true;

  @override
  Future<T> runRecoveryOperation<T>(Future<T> Function() operation) async {
    recoveryLeaseCalls += 1;
    _recoveryLeaseDepth += 1;
    if (_recoveryLeaseDepth > maximumRecoveryLeaseDepth) {
      maximumRecoveryLeaseDepth = _recoveryLeaseDepth;
    }
    try {
      return await operation();
    } finally {
      _recoveryLeaseDepth -= 1;
    }
  }

  void _requireRecoveryLease() {
    if (requireRecoveryLease && _recoveryLeaseDepth != 1) {
      throw StateError('durable mixed-review work escaped its route lease');
    }
  }

  @override
  Future<QuizSession> initializeSession(
    QuizSession session, {
    PendingLearningSessionClose? recoveredClose,
  }) async => session;

  @override
  void noteSkippedItem() => _requireRecoveryLease();

  @override
  void recordInteraction() {}

  @override
  void ownRecoveryClose(
    PendingLearningSessionClose close,
    Future<void> Function() ensureDurable,
  ) => _requireRecoveryLease();

  @override
  Future<AnswerRecordResult> recordCapturedEvidence(
    PendingCurrentActivityEvidence pending, {
    required AnswerFeedbackContext feedbackContext,
    required LessonModeAdapter occurrenceAdapter,
  }) async {
    _requireRecoveryLease();
    evidenceIds.add(pending.sourceEvidenceId);
    occurrenceModes.add(occurrenceAdapter.mode);
    if (recordFailures > 0) {
      recordFailures -= 1;
      throw StateError('injected record failure');
    }
    return pending.requiresRetry ? pending.retry() : pending.record();
  }

  @override
  HintUsageSnapshot snapshotHintUsage() =>
      const HintUsageSnapshot.unavailable();

  @override
  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  ) {
    _requireRecoveryLease();
    return close.requiresRetry ? close.retry() : close.finish();
  }
}

Future<(List<ContentIdentity>, List<VocabularyWord>)> _seedWords(
  AppDatabase database,
  String ownerId,
) async {
  const categoryId = 'category:mixed-review';
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Mixed review',
          normalizedName: 'mixed review',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final identities = <ContentIdentity>[];
  final lexicalWords = <VocabularyWord>[];
  for (final (index, entry) in const <(String, String, String)>[
    ('word:station', 'station', 'สถานี'),
    ('word:ticket', 'ticket', 'ตั๋ว'),
    ('word:platform', 'platform', 'ชานชาลา'),
    ('word:journey', 'journey', 'การเดินทาง'),
    ('word:airport', 'airport', 'สนามบิน'),
  ].indexed) {
    final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: categoryId,
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
            categoryId: categoryId,
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
    lexicalWords.add(
      VocabularyWord(
        id: entry.$1,
        ownerId: ownerId,
        categoryId: categoryId,
        spelling: entry.$2,
        normalizedSpelling: entry.$2,
        meaning: entry.$3,
        normalizedMeaning: entry.$3,
        partOfSpeech: 'noun',
        source: 'manual',
        isGlobal: true,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: DateTime.utc(2026, 9, 1),
        updatedAtUtc: DateTime.utc(2026, 9, 1),
        contentRevision: 1,
        contentChecksumSha256: checksum,
        contentProvenance: ContentProvenance.packaged,
        contentReviewState: ContentReviewState.approved,
        contentPublicationState: ContentPublicationState.published,
        richMetadata: RichLexicalMetadata(
          englishDefinition: 'Definition of ${entry.$2}',
          examples: <String>['The ${entry.$2} is nearby.'],
          verifiedContentRevision: 1,
          verifiedArtifactChecksumSha256: '${index + 1}' * 64,
        ),
      ),
    );
  }
  return (identities, lexicalWords);
}

AdventureSessionPlanV1 _plan({
  required String ownerId,
  required List<ContentIdentity> content,
  LessonMode mode = LessonMode.typedRecall,
  SessionDirection direction = SessionDirection.reverse,
}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: ownerId,
    mode: mode,
    itemCount: content.length,
    direction: direction,
    difficulty: SessionDifficulty.standard,
    hintBudget: mode == LessonMode.meaningQuiz ? 0 : 1,
    timing: const SessionTiming.timed(Duration(minutes: 5)),
    packIdentity: null,
    protocolId: 'protocol:local',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:mixed-review',
  );
  const planId = 'adventure-plan:mixed-review';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: ownerId,
    createdAtUtc: DateTime.utc(2026, 9, 5, 9),
    sourceEvaluatedAtUtc: DateTime.utc(2026, 9, 5, 9),
    content: content,
    contentChecksumsSha256: <String, String>{
      for (final item in content) item.id: _checksum(item.id),
    },
    mode: mode,
    configuration: configuration,
    recommendationPolicyVersion: 'recommendation-v1',
    sourceReasonCode: 'due',
    learnerOverrideApplied: false,
    origin: const AdventureOriginContextV1(
      planId: planId,
      nodeId: 'node:mixed-review',
      catalogId: 'catalog:adventure',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      presentation: TodayExperiencePresentation.adventure,
    ),
  );
}

String _checksum(String id) {
  final values = <String, (String, String)>{
    'word:station': ('station', 'สถานี'),
    'word:ticket': ('ticket', 'ตั๋ว'),
    'word:platform': ('platform', 'ชานชาลา'),
    'word:journey': ('journey', 'การเดินทาง'),
    'word:airport': ('airport', 'สนามบิน'),
  };
  final value = values[id]!;
  return ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:mixed-review',
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
