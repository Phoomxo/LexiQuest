import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  test(
    'file-backed mixedReview replays one canonical answer after a lost acknowledgement',
    () => _expectRestartRecovery(_RecordFailureTiming.afterCommit),
  );

  test(
    'file-backed mixedReview writes frozen evidence after a pre-write failure',
    () => _expectRestartRecovery(_RecordFailureTiming.beforeWrite),
  );

  test(
    'file-backed committed close is discovered while emergency-off and replays once',
    _expectCommittedCloseRecovery,
  );

  test(
    'file-backed owner switch rejects close without a terminal checkpoint',
    _expectOwnerSwitchCloseRejected,
  );
}

Future<void> _expectCommittedCloseRecovery() async {
  final directory = await Directory.systemTemp.createTemp(
    'lexiquest-adventure-close-restart-',
  );
  final file = File('${directory.path}${Platform.pathSeparator}learning.db');
  AppDatabase? database;
  try {
    database = AppDatabase(NativeDatabase(file));
    final firstOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => _ownerId,
      nowUtc: () => DateTime.utc(2026, 9, 5, 9),
    );
    final owner = await firstOwners.getOrCreateActiveOwner();
    await _seedVocabulary(database, owner.id);
    final firstLearning = _learningAuthority(
      owners: firstOwners,
      repository: DriftLearningRepository(database),
      idPrefix: 'close-first',
      clock: DateTime.utc(2026, 9, 5, 9, 1),
    );
    final firstEvidence = CurrentActivityEvidenceAdapter(
      learning: firstLearning,
    );
    final firstRecovery = _adventureRecovery(
      learning: firstLearning,
      evidence: firstEvidence,
    );
    final plan = _plan(ownerId: owner.id);
    final run = await firstRecovery.startOrResume(
      plan: plan,
      activeOwnerId: owner.id,
    );
    final pending = await _recordOriginal(
      recovery: firstRecovery,
      evidence: firstEvidence,
      plan: plan,
    );
    final close = firstLearning.captureSessionClose(
      sessionId: run.session.id,
      ownerId: owner.id,
    );
    await firstRecovery.checkpointSessionClose(close);
    final committed = await close.finish();
    expect(
      firstRecovery.currentRun!.state.phase,
      AdventureLearningCheckpointPhase.closing,
    );
    expect(
      (await database.select(database.learningSessions).getSingle()).state,
      'completed',
    );
    await database.close();
    database = null;

    database = AppDatabase(NativeDatabase(file));
    final secondOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unexpected-owner',
      nowUtc: () => DateTime.utc(2026, 9, 5, 10),
    );
    final secondLearning = _learningAuthority(
      owners: secondOwners,
      repository: DriftLearningRepository(database),
      idPrefix: 'close-second',
      clock: DateTime.utc(2026, 9, 5, 10, 1),
    );
    final secondRecovery = _adventureRecovery(
      learning: secondLearning,
      evidence: CurrentActivityEvidenceAdapter(learning: secondLearning),
      canStart: () => false,
    );

    final recoveredClose = await secondRecovery.startOrResume(
      plan: plan,
      activeOwnerId: owner.id,
    );

    expect(recoveredClose.session.id, run.session.id);
    expect(recoveredClose.recovered, isTrue);
    expect(recoveredClose.presentation, AdventureLearningPresentation.standard);
    expect(
      recoveredClose.state.phase,
      AdventureLearningCheckpointPhase.closing,
    );
    expect(recoveredClose.pendingClose, isNotNull);
    final replayed = await recoveredClose.pendingClose!.finish();
    expect(replayed.id, committed.id);
    expect(replayed.endedAtUtc, committed.endedAtUtc);
    expect(replayed.correctCount, committed.correctCount);
    await secondRecovery.acknowledgeSessionClosed(
      close: recoveredClose.pendingClose!,
      summary: replayed,
    );
    await database.close();
    database = null;

    database = AppDatabase(NativeDatabase(file));
    final thirdOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'another-unexpected-owner',
      nowUtc: () => DateTime.utc(2026, 9, 5, 11),
    );
    final thirdLearning = _learningAuthority(
      owners: thirdOwners,
      repository: DriftLearningRepository(database),
      idPrefix: 'close-third',
      clock: DateTime.utc(2026, 9, 5, 11, 1),
    );
    final thirdRecovery = _adventureRecovery(
      learning: thirdLearning,
      evidence: CurrentActivityEvidenceAdapter(learning: thirdLearning),
      canStart: () => false,
    );

    final recoveredCompletion = await thirdRecovery.startOrResume(
      plan: plan,
      activeOwnerId: owner.id,
    );

    expect(recoveredCompletion.session.id, run.session.id);
    expect(
      recoveredCompletion.state.phase,
      AdventureLearningCheckpointPhase.completed,
    );
    expect(recoveredCompletion.state.summaryPresented, isFalse);
    final durableSummary = await thirdRecovery.loadCompletedSummary();
    expect(durableSummary.endedAtUtc, committed.endedAtUtc);
    await thirdRecovery.acknowledgeSummaryPresented();
    await thirdRecovery.acknowledgeSummaryPresented();

    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, run.session.id);
    expect(sessions.single.state, 'completed');
    final attempts = await database.select(database.answerAttempts).get();
    expect(attempts, hasLength(1));
    expect(attempts.single.id, pending.sourceEvidenceId);
    expect(
      (await database.select(database.eventsV2).get()).where(
        (event) =>
            event.eventType == 'LearningActivityCheckpoint' &&
            event.aggregateId == run.session.id,
      ),
      hasLength(5),
    );
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.achievementUnlocks).get(),
      hasLength(4),
    );
    expect(
      (await database.select(database.outboxOperations).get()).where(
        (operation) =>
            operation.entityType == 'attempt' &&
            operation.entityId == pending.sourceEvidenceId,
      ),
      hasLength(1),
    );
    expect(await database.select(database.srsStates).get(), hasLength(1));
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
  } finally {
    await database?.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<void> _expectOwnerSwitchCloseRejected() async {
  final directory = await Directory.systemTemp.createTemp(
    'lexiquest-adventure-owner-restart-',
  );
  final file = File('${directory.path}${Platform.pathSeparator}learning.db');
  AppDatabase? database;
  try {
    database = AppDatabase(NativeDatabase(file));
    final firstOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => _ownerId,
      nowUtc: () => DateTime.utc(2026, 9, 5, 9),
    );
    final owner = await firstOwners.getOrCreateActiveOwner();
    await _seedVocabulary(database, owner.id);
    final firstLearning = _learningAuthority(
      owners: firstOwners,
      repository: DriftLearningRepository(database),
      idPrefix: 'owner-first',
      clock: DateTime.utc(2026, 9, 5, 9, 1),
    );
    final firstEvidence = CurrentActivityEvidenceAdapter(
      learning: firstLearning,
    );
    final firstRecovery = _adventureRecovery(
      learning: firstLearning,
      evidence: firstEvidence,
    );
    final plan = _plan(ownerId: owner.id);
    final run = await firstRecovery.startOrResume(
      plan: plan,
      activeOwnerId: owner.id,
    );
    await _recordOriginal(
      recovery: firstRecovery,
      evidence: firstEvidence,
      plan: plan,
    );
    final close = firstLearning.captureSessionClose(
      sessionId: run.session.id,
      ownerId: owner.id,
    );
    await _switchActiveOwner(database, owner.id);

    await expectLater(
      firstRecovery.checkpointSessionClose(close),
      throwsStateError,
    );
    await database.close();
    database = null;

    database = AppDatabase(NativeDatabase(file));
    final reopenedOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unexpected-owner',
      nowUtc: () => DateTime.utc(2026, 9, 5, 10),
    );
    final reopenedLearning = _learningAuthority(
      owners: reopenedOwners,
      repository: DriftLearningRepository(database),
      idPrefix: 'owner-reopened',
      clock: DateTime.utc(2026, 9, 5, 10, 1),
    );
    final exact = await reopenedLearning.loadExactActivityRecovery(
      ownerId: owner.id,
      sessionId: run.session.id,
      activityType: mixedReviewActivityType,
    );

    expect(
      (await reopenedOwners.getOrCreateActiveOwner()).id,
      _replacementOwnerId,
    );
    expect(exact, isNotNull);
    expect(exact!.session.state, 'active');
    expect(exact.checkpoint!.revision, 2);
    expect(exact.checkpoint!.terminalAtUtc, isNull);
    expect(exact.checkpoint!.terminalAcknowledged, isFalse);
    expect(
      AdventureLearningCheckpointState.fromJson(exact.checkpoint!.state).phase,
      AdventureLearningCheckpointPhase.pendingOccurrence,
    );
    expect(
      (await database.select(database.eventsV2).get()).where(
        (event) =>
            event.eventType == 'LearningActivityCheckpoint' &&
            event.aggregateId == run.session.id,
      ),
      hasLength(2),
    );
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
  } finally {
    await database?.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<void> _expectRestartRecovery(_RecordFailureTiming timing) async {
  final directory = await Directory.systemTemp.createTemp(
    'lexiquest-adventure-restart-',
  );
  final file = File('${directory.path}${Platform.pathSeparator}learning.db');
  AppDatabase? database;
  try {
    database = AppDatabase(NativeDatabase(file));
    final firstOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => _ownerId,
      nowUtc: () => DateTime.utc(2026, 9, 5, 9),
    );
    final owner = await firstOwners.getOrCreateActiveOwner();
    await _seedVocabulary(database, owner.id);

    final durableRepository = DriftLearningRepository(database);
    final firstLearning = _learningAuthority(
      owners: firstOwners,
      repository: durableRepository,
      idPrefix: 'first',
      clock: DateTime.utc(2026, 9, 5, 9, 1),
    );
    final firstEvidence = CurrentActivityEvidenceAdapter(
      learning: firstLearning,
    );
    final firstRecovery = _adventureRecovery(
      learning: firstLearning,
      evidence: firstEvidence,
    );
    final run = await firstRecovery.startOrResume(
      plan: _plan(ownerId: owner.id),
      activeOwnerId: owner.id,
    );
    final sessionId = run.session.id;
    final pending = firstEvidence.capture(
      ownerId: owner.id,
      input: CurrentActivityInput.typedRecall,
      sessionId: sessionId,
      wordId: _wordId,
      isCorrect: true,
      responseTimeMs: 842,
      attemptNumber: run.state.nextOccurrenceOrdinal,
      providerProvenance: 'keyboard|local|v1',
    );
    await firstRecovery.checkpointPendingEvidence(
      pending: pending,
      originalIndex: 0,
      role: AdventureLearningItemRole.original,
      mode: LessonMode.typedRecall,
    );
    final frozen = await pending.freezeForRecovery();

    final failingLearning = _learningAuthority(
      owners: firstOwners,
      repository: _SingleRecordFailureRepository(
        durableRepository,
        timing: timing,
      ),
      idPrefix: 'failure',
      clock: DateTime.utc(2026, 9, 5, 9, 2),
    );
    final failingPending = CurrentActivityEvidenceAdapter(
      learning: failingLearning,
    ).restore(frozen, ownerId: owner.id);

    await expectLater(failingPending.retry(), throwsStateError);
    expect(
      await database.select(database.answerAttempts).get(),
      hasLength(timing == _RecordFailureTiming.afterCommit ? 1 : 0),
    );
    await database.close();
    database = null;

    database = AppDatabase(NativeDatabase(file));
    final reopenedOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unexpected-owner',
      nowUtc: () => DateTime.utc(2026, 9, 5, 10),
    );
    final reopenedRepository = DriftLearningRepository(database);
    final reopenedLearning = _learningAuthority(
      owners: reopenedOwners,
      repository: reopenedRepository,
      idPrefix: 'reopened',
      clock: DateTime.utc(2026, 9, 5, 10, 1),
    );
    final reopenedEvidence = CurrentActivityEvidenceAdapter(
      learning: reopenedLearning,
    );
    final reopenedRecovery = _adventureRecovery(
      learning: reopenedLearning,
      evidence: reopenedEvidence,
    );

    final recovered = await reopenedRecovery.recoverExact(
      ownerId: owner.id,
      sessionId: sessionId,
    );

    expect(recovered, isNotNull);
    expect(recovered!.session.id, sessionId);
    expect(recovered.recovered, isTrue);
    expect(
      recovered.state.pendingOccurrence!.evidence!.toJson(),
      frozen.toJson(),
    );
    expect(recovered.pendingEvidence, isNotNull);
    expect(
      recovered.pendingEvidence!.sourceEvidenceId,
      frozen.sourceEvidenceId,
    );
    expect(recovered.pendingEvidence!.requiresRetry, isTrue);
    final replay = await recovered.pendingEvidence!.retry();
    expect(replay.inserted, timing == _RecordFailureTiming.beforeWrite);
    expect(replay.isCorrect, isTrue);
    expect(recovered.pendingEvidence!.isCommitted, isTrue);

    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, sessionId);
    expect(sessions.single.activityType, mixedReviewActivityType);

    final attempts = await database.select(database.answerAttempts).get();
    expect(attempts, hasLength(1));
    expect(attempts.single.id, frozen.sourceEvidenceId);
    final sourceEventId = LearningEvidenceContract.learningEventId(
      frozen.sourceEvidenceId,
    );
    final sourceEvents = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(sourceEventId))).get();
    expect(sourceEvents, hasLength(1));
    expect(
      (await database.select(database.eventsV2).get()).where(
        (event) => event.eventType == 'LearningEvidenceDecisionSet',
      ),
      hasLength(1),
    );

    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.achievementUnlocks).get(),
      hasLength(2),
    );
    expect(
      (await database.select(database.outboxOperations).get()).where(
        (operation) =>
            operation.entityType == 'attempt' &&
            operation.entityId == frozen.sourceEvidenceId,
      ),
      hasLength(1),
    );
    expect(await database.select(database.srsStates).get(), hasLength(1));
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
  } finally {
    await database?.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<PendingCurrentActivityEvidence> _recordOriginal({
  required AdventureRecoveryUseCases recovery,
  required CurrentActivityEvidenceAdapter evidence,
  required AdventureSessionPlanV1 plan,
}) async {
  final run = recovery.currentRun!;
  final pending = evidence.capture(
    ownerId: run.state.ownerId,
    input: CurrentActivityInput.typedRecall,
    sessionId: run.session.id,
    wordId: plan.content.single.id,
    isCorrect: true,
    responseTimeMs: 842,
    attemptNumber: run.state.nextOccurrenceOrdinal,
    providerProvenance: 'keyboard|local|v1',
  );
  await recovery.checkpointPendingEvidence(
    pending: pending,
    originalIndex: 0,
    role: AdventureLearningItemRole.original,
    mode: LessonMode.typedRecall,
  );
  await pending.record();
  recovery.acceptPendingOccurrence(
    AdventureRepairAttempt(
      identity: plan.content.single,
      mode: LessonMode.typedRecall,
      promptVariant: 'typedRecall',
      outcome: AdventureAttemptOutcome.correct,
      evidenceClass: EvidenceClass.independentRecall,
      canonicalEvidenceCommitted: true,
      sourceEvidenceId: pending.sourceEvidenceId,
    ),
    nextOriginalIndex: 1,
    remainingOriginalItems: 0,
  );
  return pending;
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
              id: _replacementOwnerId,
              createdAtUtcMs: DateTime.utc(
                2026,
                9,
                5,
                12,
              ).millisecondsSinceEpoch,
              isActive: const Value(true),
            ),
          );
    });

LearningUseCases _learningAuthority({
  required DriftLocalOwnerRepository owners,
  required LearningRepository repository,
  required String idPrefix,
  required DateTime clock,
}) {
  var nextId = 0;
  var nextTick = 0;
  return LearningUseCases(
    owners: owners,
    repository: repository,
    generateId: () => '$idPrefix-${++nextId}',
    nowUtc: () => clock.add(Duration(seconds: nextTick++)),
    buildInfo: const AppBuildInfo(
      version: 'test',
      buildId: 'adventure-restart-test',
    ),
  );
}

AdventureRecoveryUseCases _adventureRecovery({
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  bool Function()? canStart,
}) => AdventureRecoveryUseCases(
  learning: learning,
  evidence: evidence,
  canStartNewMission: canStart ?? () => true,
  isRepairModeEligible: (_, _, _) => false,
);

Future<void> _seedVocabulary(AppDatabase database, String ownerId) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: _categoryId,
          ownerId: ownerId,
          name: 'Adventure restart',
          normalizedName: 'adventure restart',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: _wordId,
          ownerId: ownerId,
          categoryId: _categoryId,
          spelling: _spelling,
          normalizedSpelling: _spelling,
          meaning: _meaning,
          normalizedMeaning: _meaning,
          partOfSpeech: 'noun',
          source: const Value('manual'),
          isGlobal: const Value(false),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(_contentChecksum()),
          contentProvenance: Value(ContentProvenance.userAuthored.name),
          contentReviewState: Value(ContentReviewState.unreviewed.name),
          contentPublicationState: Value(ContentPublicationState.private.name),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

AdventureSessionPlanV1 _plan({required String ownerId}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: ownerId,
    mode: LessonMode.typedRecall,
    itemCount: 1,
    direction: SessionDirection.reverse,
    difficulty: SessionDifficulty.standard,
    hintBudget: 1,
    timing: const SessionTiming.timed(Duration(minutes: 5)),
    packIdentity: null,
    protocolId: 'protocol:local',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:restart',
  );
  const planId = 'adventure-plan:restart';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: ownerId,
    createdAtUtc: DateTime.utc(2026, 9, 5, 9),
    sourceEvaluatedAtUtc: DateTime.utc(2026, 9, 5, 9),
    content: const <ContentIdentity>[_identity],
    contentChecksumsSha256: <String, String>{_wordId: _contentChecksum()},
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

String _contentChecksum() => ContentQualityPolicy.vocabularyChecksumSha256(
  categoryId: _categoryId,
  spelling: _spelling,
  normalizedSpelling: _spelling,
  meaning: _meaning,
  normalizedMeaning: _meaning,
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: 'manual',
  isGlobal: false,
);

enum _RecordFailureTiming { beforeWrite, afterCommit }

final class _SingleRecordFailureRepository
    implements LearningRepository, LearningEvidenceReplayRepository {
  _SingleRecordFailureRepository(this.delegate, {required this.timing});

  final DriftLearningRepository delegate;
  final _RecordFailureTiming timing;
  bool _didFail = false;

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) => delegate.replayCommittedAnswer(candidate);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    if (!_didFail && timing == _RecordFailureTiming.beforeWrite) {
      _didFail = true;
      throw StateError('simulated pre-write evidence failure');
    }
    final result = await delegate.recordAnswer(command);
    if (!_didFail && timing == _RecordFailureTiming.afterCommit) {
      _didFail = true;
      throw StateError('simulated lost acknowledgement after commit');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ownerId = 'owner:restart';
const _replacementOwnerId = 'owner:replacement';
const _categoryId = 'category:restart';
const _wordId = 'word:station';
const _spelling = 'station';
const _meaning = 'สถานี';
const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: _wordId,
  revision: 1,
);
