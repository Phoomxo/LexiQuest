import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/accepted_quiz_plan.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_learning_projection_rebuilder.dart';
import 'learning_session_lifecycle_observer.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/evidence_context.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';

final class DriftLearningRepository
    implements LearningRepository, ConfiguredQuizRepository {
  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    this.lifecycleObserver,
    DriftOwnerWriteCoordinator? ownerWrites,
  }) : _ownerWrites =
           ownerWrites ??
           DriftOwnerWriteCoordinator(
             database,
             nowUtc: () => DateTime.now().toUtc(),
           ),
       projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database) {
    if (!identical(database, _ownerWrites.database)) {
      throw ArgumentError(
        'Learning and owner coordinator must share a database',
      );
    }
    if (lifecycleObserver != null &&
        !identical(database, lifecycleObserver!.database)) {
      throw ArgumentError(
        'Learning and its lifecycle observer must share a database',
      );
    }
  }

  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator _ownerWrites;
  final LearningSessionLifecycleObserver? lifecycleObserver;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
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
                : row.categoryId.equals(categoryId)) &
            (wordIds == null ? const Constant(true) : row.id.isIn(wordIds)),
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
            contentRevision: 'local-vocabulary-v1:${row.localRevision}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      _startSession(session);

  Future<void> _startSession(
    LearningSessionDraft session, {
    Future<void> Function()? beforeObserved,
  }) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    final id = _required(session.id, 'id');
    final owner = _required(session.ownerId, 'ownerId');
    final activity = _required(session.activityType, 'activityType');
    final app = _required(session.appVersion, 'appVersion');
    final build = _required(session.buildId, 'buildId');
    await database.transaction(() async {
      await database
          .into(database.learningSessions)
          .insert(
            db.LearningSessionsCompanion.insert(
              id: id,
              ownerId: owner,
              activityType: activity,
              state: 'active',
              startedAtUtcMs: startedAt.millisecondsSinceEpoch,
              appVersion: app,
              buildId: build,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final inserted =
          (await database
                  .customSelect('SELECT changes() AS affected')
                  .getSingle())
              .read<int>('affected') ==
          1;
      final row = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (row == null ||
          row.ownerId != owner ||
          row.activityType != activity ||
          row.startedAtUtcMs != startedAt.millisecondsSinceEpoch ||
          row.appVersion != app ||
          row.buildId != build) {
        throw StateError('session id already exists with different identity');
      }
      if (inserted) await beforeObserved?.call();
      final observer = lifecycleObserver;
      if (inserted && observer != null) {
        await _observe(
          () => observer.accepted(LearningSessionLifecycleFact.fromRow(row)),
        );
      }
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      database.transaction(() async {
        if (await _isConfigured(command.sessionId)) {
          throw StateError(
            'configured quiz answers require a durable pending checkpoint',
          );
        }
        return _recordAnswer(command);
      });

  Future<AnswerRecordResult> _recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      final assessmentSession =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.activityType.equals('assessment'),
              ))
              .getSingleOrNull();
      if (assessmentSession != null) {
        throw StateError(
          'Assessment answers require the dedicated Assessment writer',
        );
      }
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final srs = await projections.rebuildWord(
          ownerId: command.ownerId,
          wordId: command.wordId,
        );
        if (srs == null) {
          throw StateError('ordinary answer has no ordinary SRS evidence');
        }
        await projections.rebuildSession(
          ownerId: command.ownerId,
          sessionId: command.sessionId,
        );
        await projections.rebuildAchievements(command.ownerId);
        await _rebuildOptionalRewards(command.ownerId);
        return AnswerRecordResult(inserted: false, srs: srs);
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
      final next = await projections.rebuildWord(
        ownerId: command.ownerId,
        wordId: command.wordId,
      );
      if (next == null) {
        throw StateError('ordinary answer has no ordinary SRS evidence');
      }
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      await projections.rebuildAchievements(command.ownerId);
      await _rebuildOptionalRewards(command.ownerId);
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
        payloadVersion:
            jsonEncode(command.evidenceContext.toJson()) ==
                LearningEvidenceContract.frozenV13LegacyEvidenceContextJson
            ? 1
            : 2,
      );
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'srsState',
        entityId: command.wordId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return AnswerRecordResult(inserted: true, srs: next);
    });
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => database.transaction(() async {
    if (await _isConfigured(sessionId)) {
      throw StateError(
        'configured quiz completion requires a durable closing checkpoint',
      );
    }
    return _finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  });

  Future<LearningSessionSummary> _finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
    bool observe = true,
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
      if (row.activityType == 'assessment') {
        throw StateError(
          'Assessment completion requires the dedicated Assessment writer',
        );
      }
      if (row.state != 'active' && row.state != 'completed') {
        throw StateError('learning session cannot be completed');
      }
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
        await _unlockAchievement(
          ownerId: ownerId,
          achievementId: 'first_session',
          sourceEventId: sessionId,
          unlockedAtUtc: endedAtUtc,
        );
        if (total > 0 && row.wrongCount == 0) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'perfect_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
        }
      }
      final observer = lifecycleObserver;
      if (observe && observer != null) {
        final completed =
            await (database.select(database.learningSessions)..where(
                  (candidate) =>
                      candidate.id.equals(sessionId) &
                      candidate.ownerId.equals(ownerId),
                ))
                .getSingle();
        await _observe(
          () => observer.completed(
            LearningSessionLifecycleFact.fromRow(completed),
          ),
        );
      }
      return LearningSessionSummary(
        id: row.id,
        state: 'completed',
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: score,
      );
    });
  }

  @override
  Future<ConfiguredQuizState?> findConfiguredQuizStart(
    ConfiguredQuizLaunch launch,
  ) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: launch.session.ownerId,
    write: () async {
      final row = await _session(launch.session.id);
      if (row == null) return null;
      _sameQuizLaunch(row, launch.session);
      final saved = await _readConfigured(row);
      if (saved.plan.configuration.stableSerialization !=
          launch.configuration.stableSerialization) {
        throw StateError('configured quiz launch identity changed');
      }
      return saved;
    },
  );

  @override
  Future<ConfiguredQuizState> startConfiguredQuiz({
    required LearningSessionDraft session,
    required AcceptedQuizPlan plan,
  }) {
    if (session.activityType != plan.activityType) {
      throw ArgumentError('quiz configuration does not match its activity');
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: session.ownerId,
      write: () async {
        final existing = await _session(session.id);
        if (existing != null) {
          _sameQuizLaunch(existing, session);
          final saved = await _readConfigured(existing);
          if (saved.plan.configuration.stableSerialization !=
              plan.configuration.stableSerialization) {
            throw StateError('configured quiz launch identity changed');
          }
          return saved.asRestored();
        }
        if (!plan.supportsCurrentPolicy) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.unsupportedPolicy,
          );
        }
        await _requireQuizContent(session.ownerId, plan);
        final checkpoint = QuizCheckpoint.initial(plan);
        await _startSession(
          session,
          beforeObserved: () => _writeQuizStorage(
            session.id,
            plan: plan,
            revision: 1,
            checkpoint: checkpoint,
          ),
        );
        return _readConfigured((await _session(session.id))!);
      },
    );
  }

  /// Read-only plan/checkpoint proof. Callers must check active owner and fence.
  Future<ConfiguredQuizState> inspectConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) => _loadQuiz(sessionId, expectedOwnerId);

  @override
  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () => _loadQuiz(sessionId, expectedOwnerId),
  );

  @override
  Future<ConfiguredQuizState> saveQuizCheckpoint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required QuizCheckpoint checkpoint,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      checkpoint.validateFor(saved.plan);
      if (expectedRevision < 1) {
        throw StateError('invalid quiz checkpoint revision');
      }
      if (checkpoint.stableSerialization ==
              saved.checkpoint.stableSerialization &&
          expectedRevision <= saved.checkpointRevision) {
        return saved;
      }
      if (expectedRevision != saved.checkpointRevision ||
          saved.state != 'active') {
        throw StateError('quiz checkpoint changed');
      }
      _requireQuizTransition(saved, checkpoint);
      if (checkpoint is AwaitingQuizAnswer || checkpoint is PendingQuizAnswer) {
        await _requireQuizContent(expectedOwnerId, saved.plan);
      }
      if (checkpoint is AbandonedQuizSession) {
        await database.customUpdate(
          "UPDATE learning_sessions SET state = 'abandoned', ended_at_utc_ms = ? "
          "WHERE id = ? AND owner_id = ? AND state = 'active'",
          variables: [
            Variable<int>(checkpoint.close.endedAtUtcMs),
            Variable<String>(sessionId),
            Variable<String>(expectedOwnerId),
          ],
          updates: {database.learningSessions},
        );
      }
      await _writeQuizStorage(
        sessionId,
        plan: saved.plan,
        revision: saved.checkpointRevision + 1,
        checkpoint: checkpoint,
        expectedRevision: expectedRevision,
      );
      return _loadQuiz(sessionId, expectedOwnerId);
    },
  );

  @override
  Future<ConfiguredQuizAnswerResult> commitQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      final checkpoint = saved.checkpoint;
      if (checkpoint is AnsweredQuizQuestion) {
        if (expectedRevision < saved.checkpointRevision - 1 ||
            expectedRevision > saved.checkpointRevision) {
          throw StateError('quiz checkpoint changed');
        }
        return ConfiguredQuizAnswerResult(
          state: saved,
          record: AnswerRecordResult(
            inserted: false,
            srs: await _savedQuizSrs(expectedOwnerId, checkpoint.answer.wordId),
          ),
        );
      }
      if (checkpoint is! PendingQuizAnswer ||
          saved.state != 'active' ||
          expectedRevision != saved.checkpointRevision) {
        throw StateError('pending quiz answer was not found');
      }
      if (checkpoint.answer.capturedOwnerId != expectedOwnerId) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.ownerChanged,
        );
      }
      final command = checkpoint.answer.toCommand(sessionId: sessionId);
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null && !_sameAttempt(existing, command)) {
        throw StateError('attempt id already exists with different evidence');
      }
      final record = existing == null
          ? await _recordAnswer(command)
          : AnswerRecordResult(
              inserted: false,
              srs: await _savedQuizSrs(expectedOwnerId, command.wordId),
            );
      await _writeQuizStorage(
        sessionId,
        plan: saved.plan,
        revision: saved.checkpointRevision + 1,
        checkpoint: AnsweredQuizQuestion(
          planId: saved.plan.id,
          questionOrdinal: checkpoint.questionOrdinal,
          assistance: checkpoint.assistance,
          answer: checkpoint.answer,
        ),
        expectedRevision: expectedRevision,
      );
      return ConfiguredQuizAnswerResult(
        state: await _loadQuiz(sessionId, expectedOwnerId),
        record: record,
      );
    },
  );

  @override
  Future<ConfiguredQuizFinishResult> finishConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      final checkpoint = saved.checkpoint;
      if (checkpoint is! ClosingQuizSession &&
          checkpoint is! CompletedQuizSession) {
        throw StateError('quiz closing receipt was not found');
      }
      if (expectedRevision < saved.checkpointRevision - 1 ||
          expectedRevision > saved.checkpointRevision ||
          (checkpoint is ClosingQuizSession &&
              expectedRevision != saved.checkpointRevision)) {
        throw StateError('quiz checkpoint changed');
      }
      final close = checkpoint.close!;
      if (close.capturedOwnerId != expectedOwnerId) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.ownerChanged,
        );
      }
      final summary = await _finishSession(
        ownerId: expectedOwnerId,
        sessionId: sessionId,
        endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          close.endedAtUtcMs,
          isUtc: true,
        ),
        observe: false,
      );
      if (checkpoint is ClosingQuizSession) {
        await _writeQuizStorage(
          sessionId,
          plan: saved.plan,
          revision: saved.checkpointRevision + 1,
          checkpoint: CompletedQuizSession(
            planId: saved.plan.id,
            questionOrdinal: checkpoint.questionOrdinal,
            assistance: checkpoint.assistance,
            close: close,
          ),
          expectedRevision: expectedRevision,
        );
      }
      final completed = (await _session(sessionId))!;
      final observer = lifecycleObserver;
      if (observer != null) {
        await _observe(
          () => observer.completed(
            LearningSessionLifecycleFact.fromRow(completed),
          ),
        );
      }
      return ConfiguredQuizFinishResult(
        state: await _loadQuiz(sessionId, expectedOwnerId),
        summary: summary,
      );
    },
  );

  Future<db.LearningSession?> _session(String id) => (database.select(
    database.learningSessions,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<bool> _isConfigured(String sessionId) async =>
      (await database
              .customSelect(
                'SELECT accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
                'FROM learning_sessions WHERE id = ?',
                variables: [Variable<String>(sessionId)],
                readsFrom: {database.learningSessions},
              )
              .getSingleOrNull())
          ?.data
          .entries
          .any(
            (entry) => entry.key == 'checkpoint_revision'
                ? entry.value != 0
                : entry.value != null,
          ) ??
      false;

  void _sameQuizLaunch(db.LearningSession row, LearningSessionDraft session) {
    if (row.ownerId != session.ownerId ||
        row.activityType != session.activityType ||
        row.startedAtUtcMs != session.startedAtUtc?.millisecondsSinceEpoch ||
        row.appVersion != session.appVersion ||
        row.buildId != session.buildId) {
      throw StateError('configured quiz id already exists with another launch');
    }
  }

  Future<ConfiguredQuizState> _loadQuiz(String id, String owner) async {
    final row = await _session(id);
    if (row == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.notFound,
      );
    }
    if (row.ownerId != owner) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    return _readConfigured(row);
  }

  Future<ConfiguredQuizState> _readConfigured(db.LearningSession row) async {
    if (row.activityType == 'syncedEvidence' || row.state == 'syncedEvidence') {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.syncedEvidence,
      );
    }
    final storage = await database
        .customSelect(
          'SELECT accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
          'FROM learning_sessions WHERE id = ?',
          variables: [Variable<String>(row.id)],
          readsFrom: {database.learningSessions},
        )
        .getSingle();
    final id = storage.readNullable<String>('accepted_plan_id');
    final json = storage.readNullable<String>('accepted_plan_json');
    final revision = storage.read<int>('checkpoint_revision');
    final checkpointJson = storage.readNullable<String>('checkpoint_json');
    if (id == null && json == null && revision == 0 && checkpointJson == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.legacy,
      );
    }
    late AcceptedQuizPlan plan;
    late QuizCheckpoint checkpoint;
    try {
      if (id == null ||
          json == null ||
          checkpointJson == null ||
          revision < 1) {
        throw const FormatException('partial configured quiz storage');
      }
      plan = AcceptedQuizPlan.parse(id: id, json: json);
      checkpoint = QuizCheckpoint.parse(checkpointJson, plan: plan);
      if (row.activityType != plan.activityType ||
          row.startedAtUtcMs < 0 ||
          (checkpoint is CompletedQuizSession
              ? row.state != 'completed'
              : checkpoint is AbandonedQuizSession
              ? row.state != 'abandoned'
              : row.state != 'active')) {
        throw const FormatException(
          'quiz checkpoint contradicts canonical session',
        );
      }
      final close = checkpoint.close;
      if (close != null &&
          (close.endedAtUtcMs < row.startedAtUtcMs ||
              (row.state != 'active' &&
                  row.endedAtUtcMs != close.endedAtUtcMs))) {
        throw const FormatException('quiz terminal receipt changed');
      }
      if (row.state == 'active' && row.endedAtUtcMs != null) {
        throw const FormatException('active quiz has terminal time');
      }
    } on Object {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    if (checkpoint.answer?.capturedOwnerId != null &&
        checkpoint.answer!.capturedOwnerId != row.ownerId) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    if (checkpoint.close?.capturedOwnerId != null &&
        checkpoint.close!.capturedOwnerId != row.ownerId) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    final attempts = await _requireQuizAttempts(row, plan, checkpoint);
    final needsFreshInput =
        checkpoint is AwaitingQuizAnswer ||
        (checkpoint is PendingQuizAnswer &&
            attempts.length == checkpoint.questionOrdinal);
    if (row.state == 'active' && needsFreshInput) {
      await _requireQuizContent(row.ownerId, plan);
    }
    return ConfiguredQuizState(
      sessionId: row.id,
      ownerId: row.ownerId,
      activityType: row.activityType,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.startedAtUtcMs,
        isUtc: true,
      ),
      appVersion: row.appVersion,
      buildId: row.buildId,
      state: row.state,
      endedAtUtc: _fromEpoch(row.endedAtUtcMs),
      plan: plan,
      checkpointRevision: revision,
      checkpoint: checkpoint,
      mistakeWords: [
        for (var index = 0; index < attempts.length; index++)
          if (!attempts[index].isCorrect) plan.questions[index].word,
      ],
    );
  }

  Future<void> _requireQuizContent(String owner, AcceptedQuizPlan plan) async {
    if (!plan.supportsCurrentPolicy) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.unsupportedPolicy,
      );
    }
    final checkedCategories = <String>{};
    for (final question in plan.questions) {
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(question.word.id) &
                    row.ownerId.equals(owner) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (word == null ||
          quizWordChecksum(
                QuizWord(
                  id: word.id,
                  categoryId: word.categoryId,
                  spelling: word.spelling,
                  meaning: word.meaning,
                  partOfSpeech: word.partOfSpeech,
                  contentRevision: 'local-vocabulary-v1:${word.localRevision}',
                ),
              ) !=
              quizWordChecksum(question.word)) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      if (checkedCategories.add(question.word.categoryId)) {
        final category =
            await (database.select(database.vocabularyCategories)..where(
                  (row) =>
                      row.id.equals(question.word.categoryId) &
                      row.ownerId.equals(owner) &
                      row.isDeleted.equals(false),
                ))
                .getSingleOrNull();
        if (category == null) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.contentChanged,
          );
        }
      }
    }
  }

  Future<List<db.AnswerAttempt>> _requireQuizAttempts(
    db.LearningSession session,
    AcceptedQuizPlan plan,
    QuizCheckpoint checkpoint,
  ) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.sessionId.equals(session.id))
              ..orderBy([(row) => OrderingTerm.asc(row.attemptNumber)]))
            .get();
    var requiredCount = checkpoint.questionOrdinal;
    if (checkpoint is AnsweredQuizQuestion) requiredCount++;
    if (checkpoint is ClosingQuizSession ||
        checkpoint is CompletedQuizSession) {
      requiredCount = plan.questions.length;
    }
    final pendingExists =
        checkpoint is PendingQuizAnswer && attempts.length == requiredCount + 1;
    final abandonedAnswered =
        checkpoint is AbandonedQuizSession &&
        attempts.length == requiredCount + 1;
    if (attempts.length != requiredCount &&
        !pendingExists &&
        !abandonedAnswered) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final question = plan.questions[index];
      EvidenceContext evidence;
      try {
        evidence = EvidenceContext.fromJson(
          jsonDecode(attempt.evidenceContextJson) as Map<String, dynamic>,
        );
      } on Object {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
      if (attempt.ownerId != session.ownerId ||
          attempt.attemptNumber != index + 1 ||
          attempt.wordId != question.word.id ||
          attempt.promptMode != 'meaningChoice' ||
          attempt.occurredAtUtcMs < session.startedAtUtcMs ||
          evidence.contentRevision != question.word.contentRevision ||
          !LearningEvidenceContract.isOrdinaryEvidence(evidence)) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
    }
    final answer = checkpoint.answer;
    if (answer != null) {
      if (answer.occurredAtUtcMs < session.startedAtUtcMs) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
      if ((checkpoint is AnsweredQuizQuestion || pendingExists) &&
          !_sameAttempt(
            attempts[checkpoint.questionOrdinal],
            answer.toCommand(sessionId: session.id),
          )) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
    }
    final close = checkpoint.close;
    if (close != null &&
        attempts.any((row) => row.occurredAtUtcMs > close.endedAtUtcMs)) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    if (session.correctCount != correct ||
        session.wrongCount != attempts.length - correct) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    return attempts;
  }

  void _requireQuizTransition(ConfiguredQuizState saved, QuizCheckpoint next) {
    final previous = saved.checkpoint;
    if (next.planId != saved.plan.id) throw StateError('quiz plan changed');
    final oldAssistance = previous.assistance;
    final assistance = next.assistance;
    if ((oldAssistance.hintFirstShownAtUtcMs != null &&
            assistance.hintFirstShownAtUtcMs !=
                oldAssistance.hintFirstShownAtUtcMs) ||
        (oldAssistance.revealRequestedAtUtcMs != null &&
            assistance.revealRequestedAtUtcMs !=
                oldAssistance.revealRequestedAtUtcMs)) {
      if (previous is! AnsweredQuizQuestion ||
          next is! AwaitingQuizAnswer ||
          next.questionOrdinal != previous.questionOrdinal + 1) {
        throw StateError('quiz assistance receipt changed');
      }
    }
    final sameItem = previous.questionOrdinal == next.questionOrdinal;
    final allowed =
        (previous is AwaitingQuizAnswer &&
            sameItem &&
            (next is AwaitingQuizAnswer || next is PendingQuizAnswer)) ||
        (previous is AnsweredQuizQuestion &&
            next is AwaitingQuizAnswer &&
            next.questionOrdinal == previous.questionOrdinal + 1 &&
            jsonEncode(next.assistance.toJson()) ==
                jsonEncode(QuizAssistance().toJson())) ||
        (previous is AnsweredQuizQuestion &&
            next is ClosingQuizSession &&
            sameItem &&
            next.questionOrdinal == saved.plan.questions.length - 1) ||
        (previous is! PendingQuizAnswer &&
            previous is! ClosingQuizSession &&
            next is AbandonedQuizSession &&
            sameItem);
    if (!allowed) throw StateError('invalid quiz checkpoint transition');
    final answer = next.answer;
    final close = next.close;
    final hint = assistance.hintFirstShownAtUtcMs;
    final reveal = assistance.revealRequestedAtUtcMs;
    if ((answer != null && answer.capturedOwnerId != saved.ownerId) ||
        (close != null && close.capturedOwnerId != saved.ownerId) ||
        (answer != null &&
            answer.occurredAtUtcMs <
                saved.startedAtUtc.millisecondsSinceEpoch) ||
        (close != null &&
            close.endedAtUtcMs < saved.startedAtUtc.millisecondsSinceEpoch) ||
        (hint != null && hint < saved.startedAtUtc.millisecondsSinceEpoch) ||
        (reveal != null &&
            reveal < saved.startedAtUtc.millisecondsSinceEpoch)) {
      throw StateError('quiz receipt owner or time changed');
    }
  }

  Future<void> _writeQuizStorage(
    String sessionId, {
    required AcceptedQuizPlan plan,
    required int revision,
    required QuizCheckpoint checkpoint,
    int? expectedRevision,
  }) async {
    checkpoint.validateFor(plan);
    final changed = await database.customUpdate(
      'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, '
      'checkpoint_revision = ?, checkpoint_json = ? WHERE id = ?'
      '${expectedRevision == null ? '' : ' AND checkpoint_revision = ?'}',
      variables: [
        Variable<String>(plan.id),
        Variable<String>(plan.stableSerialization),
        Variable<int>(revision),
        Variable<String>(checkpoint.stableSerialization),
        Variable<String>(sessionId),
        if (expectedRevision != null) Variable<int>(expectedRevision),
      ],
      updates: {database.learningSessions},
    );
    if (changed != 1) throw StateError('quiz checkpoint changed');
  }

  Future<SrsSnapshot> _savedQuizSrs(String ownerId, String wordId) async {
    final row =
        await (database.select(database.srsStates)..where(
              (row) => row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
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

  Future<void> _observe(Future<void> Function() callback) async {
    try {
      await database.transaction(callback, requireNew: true);
    } on Object {
      // The research savepoint rolls back while canonical learning continues.
    }
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
            contentRevision: 'local-vocabulary-v1:${word.localRevision}',
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
      final activeOwner =
          await (database.select(database.localOwners)..where(
                (row) =>
                    row.id.equals(command.ownerId) & row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (activeOwner == null) {
        throw StateError('reading owner is no longer active');
      }
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
    int payloadVersion = 1,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            payloadVersion: Value(payloadVersion),
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _rebuildOptionalRewards(String ownerId) async {
    try {
      await rewardProjections.rebuild(ownerId);
    } catch (_) {
      // Reward savepoint rolls back; immutable local learning still commits.
    }
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCommand command) {
    return row.ownerId == command.ownerId &&
        row.sessionId == command.sessionId &&
        row.wordId == command.wordId &&
        row.promptMode == command.promptMode &&
        row.isCorrect == command.isCorrect &&
        row.responseTimeMs == command.responseTimeMs &&
        row.attemptNumber == command.attemptNumber &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == command.providerProvenance &&
        row.evidenceClass == command.evidenceContext.evidenceClass.name &&
        jsonEncode(
              EvidenceContext.fromJson(
                jsonDecode(row.evidenceContextJson) as Map<String, dynamic>,
              ).toJson(),
            ) ==
            jsonEncode(command.evidenceContext.toJson());
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
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validAttempt(
      id: command.id,
      ownerId: command.ownerId,
      sessionId: command.sessionId,
      wordId: command.wordId,
      promptMode: command.promptMode,
      responseTimeMs: command.responseTimeMs,
      attemptNumber: command.attemptNumber,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      providerProvenance: command.providerProvenance,
      evidenceClass: command.evidenceContext.evidenceClass.name,
      evidenceContextJson: jsonEncode(command.evidenceContext.toJson()),
    )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
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
}
