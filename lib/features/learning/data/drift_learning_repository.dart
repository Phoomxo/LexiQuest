import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_learning_event_store.dart'
    hide
        ContextEvidencePolicyRolloutModeProvider,
        EvidencePolicyRolloutModeProvider,
        FixedEvidencePolicyRolloutModeProvider;
import 'drift_learning_projection_rebuilder.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';
import '../domain/srs_operation_identity.dart';

final class DriftLearningRepository
    implements
        LearningRepository,
        LearningEvidenceReplayRepository,
        LearningSessionLifecycleRepository {
  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database),
       events = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  final db.AppDatabase database;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;
  final DriftLearningEventStore events;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            row.ownerId.equals(ownerId) &
            row.isDeleted.equals(false) &
            (categoryId == null
                ? const Constant(true)
                : row.categoryId.equals(categoryId)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => QuizWord(
            id: row.id,
            categoryId: row.categoryId,
            spelling: row.spelling,
            meaning: row.meaning,
            partOfSpeech: row.partOfSpeech,
            normalizedSpelling: row.normalizedSpelling,
            normalizedMeaning: row.normalizedMeaning,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: _required(session.id, 'id'),
            ownerId: _required(session.ownerId, 'ownerId'),
            activityType: _required(session.activityType, 'activityType'),
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) {
    _validateCandidate(candidate, requireSourceIdentity: true);
    return database.transaction(() async {
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(candidate.id))).getSingleOrNull();
      if (existing == null) return null;
      if (!_sameAttempt(existing, candidate)) {
        throw StateError('attempt id already exists with different evidence');
      }
      final event = await events.readBySourceEvidenceId(candidate.id);
      if (event == null ||
          await events.validateSourceForAttempt(
                attempt: existing,
                source: event,
              ) !=
              null) {
        throw StateError('committed answer has missing or corrupt event');
      }
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: existing,
        sourceEvent: event,
      );
      return CommittedAnswerReplay(
        result: AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: candidate.ownerId,
                  wordId: candidate.wordId,
                )
              : null,
        ),
        event: event,
      );
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command.candidate)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final storedEvent = await events.readBySourceEvidenceId(command.id);
        late final LearningEvidenceDecisionSet decisionSet;
        if (command.isFrozenV13LegacyIngress) {
          if (storedEvent != null) {
            throw StateError('canonical event cannot be omitted during replay');
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
          );
        } else {
          final candidateEvent = command.event!;
          if (storedEvent == null ||
              await events.validateSourceForAttempt(
                    attempt: existing,
                    source: storedEvent,
                  ) !=
                  null) {
            throw StateError('canonical event cannot be retrofitted on replay');
          }
          if (jsonEncode(storedEvent.toJson()) !=
              jsonEncode(candidateEvent.toJson())) {
            throw StateError(
              'learning event identity already exists with different evidence',
            );
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
            sourceEvent: storedEvent,
          );
        }
        return AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: command.ownerId,
                  wordId: command.wordId,
                )
              : null,
        );
      }

      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.state.equals('active'),
              ))
              .getSingleOrNull();
      if (session == null) {
        throw StateError('active learning session not found');
      }
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(command.wordId) &
                    row.ownerId.equals(command.ownerId) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (word == null) {
        throw StateError('active vocabulary word not found');
      }

      await database
          .into(database.answerAttempts)
          .insert(
            db.AnswerAttemptsCompanion.insert(
              id: command.id,
              ownerId: command.ownerId,
              sessionId: command.sessionId,
              wordId: command.wordId,
              promptMode: command.promptMode,
              isCorrect: command.isCorrect,
              responseTimeMs: Value(command.responseTimeMs),
              attemptNumber: command.attemptNumber,
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
              providerProvenance: Value(command.providerProvenance),
              evidenceClass: Value(command.evidenceContext.evidenceClass.name),
              evidenceContextJson: Value(
                jsonEncode(command.evidenceContext.toJson()),
              ),
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
      );
      final event = command.event;
      if (event != null) await events.append(event);
      final insertedAttempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingle();
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: insertedAttempt,
        sourceEvent: event,
      );
      final rebuildWord =
          decisionSet.allows(LearningProjection.masterySrs) ||
          decisionSet.allows(LearningProjection.xp);
      final next = rebuildWord
          ? await projections.rebuildWord(
              ownerId: command.ownerId,
              wordId: command.wordId,
            )
          : null;
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      if (decisionSet.allows(LearningProjection.achievement)) {
        await projections.rebuildAchievements(command.ownerId);
      }
      if (decisionSet.allows(LearningProjection.xp) ||
          decisionSet.allows(LearningProjection.coins)) {
        await rewardProjections.rebuild(command.ownerId);
      }
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      if (decisionSet.allows(LearningProjection.masterySrs) && next != null) {
        await _appendSrsOutbox(
          ownerId: command.ownerId,
          wordId: command.wordId,
          answerAttemptId: command.id,
          occurredAtUtc: command.occurredAtUtc,
        );
      }
      return AnswerRecordResult(
        inserted: true,
        isCorrect: command.isCorrect,
        srs: decisionSet.allows(LearningProjection.masterySrs) ? next : null,
      );
    });
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(sessionId) &
                    candidate.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      final total = row.correctCount + row.wrongCount;
      final score = total == 0 ? 0 : ((row.correctCount * 100) / total).round();
      if (row.state != 'completed') {
        await (database.update(
          database.learningSessions,
        )..where((candidate) => candidate.id.equals(sessionId))).write(
          db.LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
            score: Value(score),
          ),
        );
        final sessionAttempts =
            await (database.select(database.answerAttempts)..where(
                  (attempt) =>
                      attempt.ownerId.equals(ownerId) &
                      attempt.sessionId.equals(sessionId),
                ))
                .get();
        final achievementAttempts = <db.AnswerAttempt>[];
        for (final attempt in sessionAttempts) {
          final decisionSet = await projections.decisionSetForAttempt(attempt);
          if (decisionSet.allows(LearningProjection.achievement)) {
            achievementAttempts.add(attempt);
          }
        }
        if (achievementAttempts.isNotEmpty) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'first_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
          if (achievementAttempts.every((attempt) => attempt.isCorrect)) {
            await _unlockAchievement(
              ownerId: ownerId,
              achievementId: 'perfect_session',
              sourceEventId: sessionId,
              unlockedAtUtc: endedAtUtc,
            );
          }
        }
      }
      return LearningSessionSummary(
        id: row.id,
        ownerId: row.ownerId,
        activityType: row.activityType,
        state: 'completed',
        startedAtUtc: _fromEpoch(row.startedAtUtcMs)!,
        endedAtUtc: endedAtUtc,
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: score,
      );
    });
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    _requiredUtc(nowUtc, 'nowUtc');
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query =
        database.select(database.vocabularyWords).join([
            innerJoin(
              database.srsStates,
              database.srsStates.wordId.equalsExp(database.vocabularyWords.id) &
                  database.srsStates.ownerId.equals(ownerId) &
                  database.srsStates.dueAtUtcMs.isSmallerOrEqualValue(
                    nowUtc.millisecondsSinceEpoch,
                  ),
            ),
          ])
          ..where(
            database.vocabularyWords.ownerId.equals(ownerId) &
                database.vocabularyWords.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(database.srsStates.dueAtUtcMs)])
          ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(database.vocabularyWords))
        .map(
          (word) => QuizWord(
            id: word.id,
            categoryId: word.categoryId,
            spelling: word.spelling,
            meaning: word.meaning,
            partOfSpeech: word.partOfSpeech,
            normalizedSpelling: word.normalizedSpelling,
            normalizedMeaning: word.normalizedMeaning,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final row =
        await (database.select(database.readingProgressEntries)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.documentId.equals(documentId) &
                  candidate.documentRevision.equals(documentRevision),
            ))
            .getSingleOrNull();
    return row == null ? null : _readingSnapshot(row);
  }

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) {
    _validateReading(command);
    return database.transaction(() async {
      final priorEvent = await (database.select(
        database.readingEvents,
      )..where((row) => row.id.equals(command.eventId))).getSingleOrNull();
      if (priorEvent != null) {
        if (!_sameReadingEvent(priorEvent, command)) {
          throw StateError(
            'reading event id already exists with different evidence',
          );
        }
        return projections.rebuildReading(
          ownerId: command.ownerId,
          documentId: command.documentId,
          documentRevision: command.documentRevision,
        );
      }
      await database
          .into(database.readingEvents)
          .insert(
            db.ReadingEventsCompanion.insert(
              id: command.eventId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              documentRevision: Value(command.documentRevision),
              eventType: command.isCompleted ? 'completed' : 'checkpoint',
              position: Value(command.position),
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'readingEvent',
        entityId: command.eventId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return projections.rebuildReading(
        ownerId: command.ownerId,
        documentId: command.documentId,
        documentRevision: command.documentRevision,
      );
    });
  }

  Future<void> _unlockAchievement({
    required String ownerId,
    required String achievementId,
    required String sourceEventId,
    required DateTime unlockedAtUtc,
  }) async {
    const definitionVersion = 1;
    final achievementId_ =
        'achievement:$ownerId:$achievementId:$definitionVersion';
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: achievementId_,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // Outbox hook — sync achievement unlock to Firestore (Phase 0 Week 12-13).
    await _appendImmutableOutbox(
      ownerId: ownerId,
      entityType: 'achievementUnlock',
      entityId: achievementId_,
      occurredAtUtc: unlockedAtUtc,
    );
  }

  Future<void> _appendImmutableOutbox({
    required String ownerId,
    required String entityType,
    required String entityId,
    required DateTime occurredAtUtc,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId:
                entityType == 'attempt' &&
                    LearningEvidenceContract.validSourceEvidenceId(entityId)
                ? LearningEvidenceContract.answerAttemptOutboxOperationId(
                    entityId,
                  )
                : '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _appendSrsOutbox({
    required String ownerId,
    required String wordId,
    required String answerAttemptId,
    required DateTime occurredAtUtc,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (attempt) =>
                  attempt.ownerId.equals(ownerId) &
                  attempt.wordId.equals(wordId),
            ))
            .get();
    var revision = 0;
    for (final attempt in attempts) {
      final decisionSet = await projections.decisionSetForAttempt(attempt);
      if (decisionSet.allows(LearningProjection.masterySrs)) revision++;
    }
    if (revision < 1) {
      throw StateError('SRS revision requires durable answer evidence');
    }
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: SrsOperationIdentity.create(
              ownerId: ownerId,
              wordId: wordId,
              answerAttemptId: answerAttemptId,
              revision: revision,
            ),
            ownerId: ownerId,
            entityType: 'srsState',
            entityId: wordId,
            operationKind: 'upsert',
            baseRevision: Value(revision - 1),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<SrsSnapshot?> _readSrsSnapshot({
    required String ownerId,
    required String wordId,
  }) async {
    final row =
        await (database.select(database.srsStates)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SrsSnapshot(
      intervalDays: row.intervalDays,
      repetitions: row.repetitions,
      lapses: row.lapses,
      stability: row.stability,
      difficulty: row.difficulty,
      lastReviewAtUtc: _fromEpoch(row.lastReviewAtUtcMs),
      dueAtUtc: _fromEpoch(row.dueAtUtcMs),
      algorithmVersion: row.algorithmVersion,
    );
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCandidate candidate) {
    return row.ownerId == candidate.ownerId &&
        row.sessionId == candidate.sessionId &&
        row.wordId == candidate.wordId &&
        row.promptMode == candidate.promptMode &&
        row.isCorrect == candidate.isCorrect &&
        row.responseTimeMs == candidate.responseTimeMs &&
        row.attemptNumber == candidate.attemptNumber &&
        row.occurredAtUtcMs == candidate.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == candidate.providerProvenance &&
        LearningEvidenceContract.sameEvidenceMetadata(
          evidenceClass: row.evidenceClass,
          evidenceContextJson: row.evidenceContextJson,
          expectedContext: candidate.evidenceContext,
        );
  }

  bool _sameReadingEvent(db.ReadingEvent row, ReadingProgressCommand command) {
    return row.ownerId == command.ownerId &&
        row.documentId == command.documentId &&
        row.documentRevision == command.documentRevision &&
        row.eventType == (command.isCompleted ? 'completed' : 'checkpoint') &&
        row.position == command.position &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch;
  }

  ReadingProgressSnapshot _readingSnapshot(db.ReadingProgressEntry row) {
    return ReadingProgressSnapshot(
      documentId: row.documentId,
      documentRevision: row.documentRevision,
      lastPosition: row.lastPosition,
      isCompleted: row.isCompleted,
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs)!,
    );
  }

  void _validateAnswer(RecordAnswerCommand command) {
    final candidate = command.candidate;
    _validateCandidate(
      candidate,
      requireSourceIdentity: !command.isFrozenV13LegacyIngress,
    );
    if (command.isFrozenV13LegacyIngress) {
      if (command.event != null ||
          !LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
            command.evidenceContext,
          )) {
        throw ArgumentError.value(
          command,
          'command',
          'invalid frozen-v13 legacy ingress',
        );
      }
      return;
    }
    final event = command.event;
    if (event == null ||
        !events.isExactDeclaredSourceForCandidate(
          candidate: candidate,
          source: event,
        )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
    }
  }

  void _validateCandidate(
    RecordAnswerCandidate candidate, {
    required bool requireSourceIdentity,
  }) {
    final occurredAt = _requiredUtc(candidate.occurredAtUtc, 'occurredAtUtc');
    if ((requireSourceIdentity &&
            (!LearningEvidenceContract.validSourceEvidenceId(candidate.id) ||
                LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
                  candidate.evidenceContext,
                ))) ||
        !LearningEvidenceContract.validAttempt(
          id: candidate.id,
          ownerId: candidate.ownerId,
          sessionId: candidate.sessionId,
          wordId: candidate.wordId,
          promptMode: candidate.promptMode,
          responseTimeMs: candidate.responseTimeMs,
          attemptNumber: candidate.attemptNumber,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          providerProvenance: candidate.providerProvenance,
          evidenceClass: candidate.evidenceContext.evidenceClass.name,
          evidenceContextJson: jsonEncode(candidate.evidenceContext.toJson()),
        )) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'invalid answer evidence',
      );
    }
  }

  void _validateReading(ReadingProgressCommand command) {
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validReading(
      eventId: command.eventId,
      ownerId: command.ownerId,
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      eventType: command.isCompleted ? 'completed' : 'checkpoint',
      position: command.position,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
    )) {
      throw ArgumentError.value(command, 'command', 'invalid reading evidence');
    }
  }

  String _required(String value, String field) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError.value(value, field, 'blank');
    return result;
  }

  DateTime _requiredUtc(DateTime? value, String field) {
    if (value == null || !value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  DateTime? _fromEpoch(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  @override
  Future<LearningSessionSummary?> getActiveSession({
    required String ownerId,
  }) async {
    final row =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('active'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _rowToSummary(row);
  }

  @override
  Future<void> abandonActiveSessions({required String ownerId}) async {
    await (database.update(database.learningSessions)
          ..where((t) => t.ownerId.equals(ownerId) & t.state.equals('active')))
        .write(const db.LearningSessionsCompanion(state: Value('abandoned')));
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredSessionId = _required(sessionId, 'sessionId');
    final terminalAt = _requiredUtc(abandonedAtUtc, 'abandonedAtUtc');
    final terminalAtUtcMs = terminalAt.millisecondsSinceEpoch;
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      if (row.state == 'abandoned') {
        if (row.endedAtUtcMs == terminalAtUtcMs) return _rowToSummary(row);
        throw StateError(
          'learning session was abandoned with a different terminal time',
        );
      }
      if (row.state != 'active') {
        throw StateError('learning session is not active');
      }
      await (database.update(database.learningSessions)..where(
            (candidate) =>
                candidate.id.equals(requiredSessionId) &
                candidate.ownerId.equals(requiredOwnerId) &
                candidate.state.equals('active'),
          ))
          .write(
            db.LearningSessionsCompanion(
              state: const Value('abandoned'),
              endedAtUtcMs: Value(terminalAtUtcMs),
            ),
          );
      final updated =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingle();
      return _rowToSummary(updated);
    });
  }

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) async {
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('completed'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(limit))
            .get();
    return rows.map(_rowToSummary).toList(growable: false);
  }

  LearningSessionSummary _rowToSummary(db.LearningSession row) {
    return LearningSessionSummary(
      id: row.id,
      ownerId: row.ownerId,
      activityType: row.activityType,
      state: row.state,
      startedAtUtc: _fromEpoch(row.startedAtUtcMs)!,
      endedAtUtc: _fromEpoch(row.endedAtUtcMs),
      correctCount: row.correctCount,
      wrongCount: row.wrongCount,
      score: row.score ?? 0,
      appVersion: row.appVersion,
      buildId: row.buildId,
    );
  }
}
