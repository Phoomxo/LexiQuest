import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../motivation/domain/timezone_policy.dart';
import '../../motivation/data/drift_streak_repository.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_learning_projection_rebuilder.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/quiz_round.dart';
import '../domain/srs_policy.dart';
import '../domain/answer_motivation_evidence.dart';

typedef AnswerCalendarCapture =
    LearningCalendarWindow Function(
      DateTime occurredAtUtc,
      String timezoneId, {
      DateTime? epochEffectiveAtUtc,
      DateTime? epochExpiresAtUtc,
    });

final class DriftLearningRepository implements DurableQuizRepository {
  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    this.questCatalog,
    this.questVisible,
    this.captureCalendarWindow = TimezonePolicy.captureWindow,
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database);

  final db.AppDatabase database;
  final TrustedQuestAnswerCatalog? questCatalog;
  final bool Function()? questVisible;
  final AnswerCalendarCapture captureCalendarWindow;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    Iterable<String>? normalizedSpellings,
    Iterable<String>? normalizedMeanings,
    required int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 100)) {
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
            (wordIds == null ? const Constant(true) : row.id.isIn(wordIds)) &
            (normalizedSpellings == null && normalizedMeanings == null
                ? const Constant(true)
                : row.normalizedSpelling.isIn(normalizedSpellings ?? const []) |
                      row.normalizedMeaning.isIn(
                        normalizedMeanings ?? const [],
                      )),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)]);
    if (limit != null) query.limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => QuizWord(
            id: row.id,
            categoryId: row.categoryId,
            spelling: row.spelling,
            meaning: row.meaning,
            partOfSpeech: row.partOfSpeech,
            localRevision: row.localRevision,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await database.transaction(() async {
      await _requireActiveOwner(session.ownerId);
      final plan = session.quizPlan;
      final encodedPlan = plan == null ? null : encodeQuizPlan(plan);
      final existing = await _session(session.ownerId, session.id);
      if (existing?.legacyEvidenceDisposition != null) {
        throw StateError('Historical learning session is read-only');
      }
      if (existing != null &&
          (plan != null || existing.questionPlanJson != null)) {
        if (existing.questionPlanJson != encodedPlan ||
            existing.activityType != session.activityType ||
            existing.startedAtUtcMs != startedAt.millisecondsSinceEpoch ||
            existing.appVersion != session.appVersion ||
            existing.buildId != session.buildId) {
          throw StateError('Session ID already has a different quiz plan');
        }
        return;
      }
      if (plan != null) {
        for (final question in plan.questions) {
          await _requireQuizWord(session.ownerId, question.word);
        }
      }
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
              questionPlanJson: Value(encodedPlan),
              continuationJson: Value(
                plan == null
                    ? null
                    : encodeQuizCursor(initialQuizCursor, plan: plan),
              ),
            ),
            mode: plan == null ? InsertMode.insertOrIgnore : InsertMode.insert,
          );
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      await _requireActiveOwner(command.ownerId);
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.legacyEvidenceDisposition != null) {
          throw StateError('Historical answer is read-only');
        }
        if (!_sameAttempt(existing, command)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final round = await _roundForAttempt(command);
        final expectedEvidence = command.quiz == null || round == null
            ? null
            : encodeQuizResponse(command.quiz!.response, plan: round.plan);
        if (existing.answerEvidenceJson != expectedEvidence ||
            (round != null) != (command.quiz != null)) {
          throw StateError(
            'attempt id already exists with different quiz evidence',
          );
        }
        final srs = await projections.rebuildWord(
          ownerId: command.ownerId,
          wordId: command.wordId,
        );
        await projections.rebuildSession(
          ownerId: command.ownerId,
          sessionId: command.sessionId,
        );
        await projections.rebuildAchievements(command.ownerId);
        await _rebuildOptionalRewards(command.ownerId);
        return AnswerRecordResult(
          inserted: false,
          srs: srs,
          durableRound: round,
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
      if (session == null || session.legacyEvidenceDisposition != null) {
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
        if (command.quiz != null) throw QuizVocabularyChanged();
        throw StateError('active vocabulary word not found');
      }

      final round = await _readRound(session);
      final admission = command.quiz;
      String? answerEvidence;
      if (round != null && admission != null) {
        final cursor = round.cursor;
        final question = round.plan.questions[cursor.slot];
        final response = admission.response;
        answerEvidence = encodeQuizResponse(response, plan: round.plan);
        final choice = response.selectedOption;
        if (cursor.phase != QuizPhase.awaitingAnswer ||
            cursor.revision != admission.expectedRevision ||
            cursor.slot != response.slot ||
            question.word.id != command.wordId ||
            question.kind.name != command.promptMode ||
            command.attemptNumber != round.committedAnswers + 1 ||
            (command.responseTimeMs ?? -1) < cursor.activeResponseMs ||
            command.isCorrect !=
                (choice != null &&
                    question.options[choice] == question.correctAnswer)) {
          throw StateError('Quiz answer does not match the current question');
        }
        await _requireQuizWord(command.ownerId, question.word, row: word);
        await _saveQuizCursor(session, round.plan, (
          revision: cursor.revision + 1,
          slot: cursor.slot,
          phase: QuizPhase.feedback,
          lastAttemptId: command.id,
          activeResponseMs: command.responseTimeMs!,
        ));
      } else if (round != null || admission != null) {
        throw StateError('Quiz answer admission is missing or unexpected');
      }

      String? calendarEvidence;
      String? questIntent;
      try {
        final metadata = await _captureOriginalMetadata(
          ownerId: command.ownerId,
          occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
        );
        calendarEvidence = encodeCalendarEvidence(metadata.calendar);
        if (metadata.quest case final intent?) {
          questIntent = encodeQuestIntent(intent);
        }
      } on Object {
        // Unverifiable optional evidence must not discard the original answer.
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
              calendarEvidence: Value(calendarEvidence),
              questIntent: Value(questIntent),
              answerEvidenceJson: Value(answerEvidence),
            ),
          );
      final next = await projections.rebuildWord(
        ownerId: command.ownerId,
        wordId: command.wordId,
      );
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
      );
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'srsState',
        entityId: command.wordId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return AnswerRecordResult(
        inserted: true,
        srs: next,
        durableRound: round == null ? null : await _roundForAttempt(command),
      );
    });
  }

  Future<OriginalAnswerMetadata> _captureOriginalMetadata({
    required String ownerId,
    required int occurredAtUtcMs,
  }) async {
    final enabled = questVisible?.call() ?? questCatalog != null;
    OwnerCalendarRule? rule;
    late final AnswerCalendarEvidence calendar;
    var retryable = false;
    try {
      rule = await DriftStreakRepository(
        database,
      ).calendarRuleAt(ownerId: ownerId, occurredAtUtcMs: occurredAtUtcMs);
      final window = captureCalendarWindow(
        DateTime.fromMillisecondsSinceEpoch(occurredAtUtcMs, isUtc: true),
        rule.ianaId,
        epochEffectiveAtUtc: DateTime.fromMicrosecondsSinceEpoch(
          rule.effectiveUtcUs,
          isUtc: true,
        ),
        epochExpiresAtUtc: rule.expiresUtcUs == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(
                rule.expiresUtcUs!,
                isUtc: true,
              ),
      );
      if (window.timezoneId != rule.ianaId) {
        throw const FormatException('Captured timezone differs from authority');
      }
      final captured = CapturedCalendarEvidence(
        originOwnerId: ownerId,
        occurredAtUtcMs: occurredAtUtcMs,
        rule: rule,
        civilDay: window.civilDay.toIso8601String().substring(0, 10),
        weekMonday: window.weekMonday.toIso8601String().substring(0, 10),
        offsetSeconds: window.offsetSeconds,
        daySegments: [
          for (final part in window.daySegments)
            (
              part.startUtc.microsecondsSinceEpoch,
              part.endUtc.microsecondsSinceEpoch,
            ),
        ],
        weekSegments: [
          for (final part in window.weekSegments)
            (
              part.startUtc.microsecondsSinceEpoch,
              part.endUtc.microsecondsSinceEpoch,
            ),
        ],
      );
      encodeCalendarEvidence(captured);
      calendar = captured;
    } on Object catch (error) {
      retryable = rule != null && error is StateError;
      calendar = UnavailableCalendarEvidence(
        originOwnerId: ownerId,
        occurredAtUtcMs: occurredAtUtcMs,
        rule: rule,
      );
    }
    QuestAnswerIntent? intent;
    if (enabled) {
      intent = UnavailableQuestIntent(
        originOwnerId: ownerId,
        occurredAtUtcMs: occurredAtUtcMs,
      );
      final catalog = questCatalog;
      if (catalog != null) {
        try {
          if (calendar is CapturedCalendarEvidence) {
            final pins = await catalog.pinsForPeriod(
              database: database,
              dailyStartUtc: DateTime.fromMicrosecondsSinceEpoch(
                calendar.daySegments.first.$1,
                isUtc: true,
              ),
              weeklyStartUtc: DateTime.fromMicrosecondsSinceEpoch(
                calendar.weekSegments.first.$1,
                isUtc: true,
              ),
            );
            intent = CapturedQuestIntent(
              originOwnerId: ownerId,
              occurredAtUtcMs: occurredAtUtcMs,
              rule: calendar.rule,
              daily: pins.daily,
              weekly: pins.weekly,
              civilDay: calendar.civilDay,
              weekMonday: calendar.weekMonday,
            );
          } else if (retryable && rule != null) {
            final pins = await catalog.pinsForPendingCalendar(
              database: database,
              occurredAtUtcMs: occurredAtUtcMs,
              epochEffectiveUtcUs: rule.effectiveUtcUs,
            );
            intent = PendingQuestIntent(
              originOwnerId: ownerId,
              occurredAtUtcMs: occurredAtUtcMs,
              rule: rule,
              daily: pins.daily,
              weekly: pins.weekly,
            );
          }
          encodeQuestIntent(intent);
        } on Object {
          // Missing original pins cannot become retryable or use today's catalog.
          intent = UnavailableQuestIntent(
            originOwnerId: ownerId,
            occurredAtUtcMs: occurredAtUtcMs,
          );
        }
      }
    }
    return OriginalAnswerMetadata(calendar: calendar, quest: intent);
  }

  Future<void> _requireActiveOwner(String ownerId) async {
    final owner =
        await (database.select(database.localOwners)..where(
              (row) => row.id.equals(ownerId) & row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (owner == null) {
      throw StateError('learning owner is no longer active');
    }
  }

  Future<db.LearningSession?> _session(String ownerId, String id) =>
      (database.select(database.learningSessions)
            ..where((row) => row.id.equals(id) & row.ownerId.equals(ownerId)))
          .getSingleOrNull();

  Future<void> _requireQuizWord(
    String ownerId,
    QuizWord word, {
    db.VocabularyWord? row,
  }) async {
    row ??= await (database.select(
      database.vocabularyWords,
    )..where((candidate) => candidate.id.equals(word.id))).getSingleOrNull();
    final category =
        await (database.select(database.vocabularyCategories)..where(
              (candidate) =>
                  candidate.id.equals(word.categoryId) &
                  candidate.ownerId.equals(ownerId) &
                  candidate.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (row == null ||
        category == null ||
        row.ownerId != ownerId ||
        row.isDeleted ||
        row.categoryId != word.categoryId ||
        row.localRevision != word.localRevision ||
        row.spelling != word.spelling ||
        row.meaning != word.meaning ||
        row.partOfSpeech != word.partOfSpeech) {
      throw QuizVocabularyChanged();
    }
  }

  Future<QuizRound?> _roundForAttempt(RecordAnswerCommand command) async {
    final session = await _session(command.ownerId, command.sessionId);
    return session == null ? null : _readRound(session);
  }

  Future<QuizRound?> _readRound(
    db.LearningSession session, {
    QuizPlan? plan,
  }) async {
    final encodedPlan = session.questionPlanJson;
    final continuation = session.continuationJson;
    if (encodedPlan == null && continuation == null) return null;
    if (encodedPlan == null || continuation == null) {
      throw StateError('Incomplete stored quiz round');
    }
    plan ??= decodeQuizPlan(encodedPlan);
    final cursor = decodeQuizCursor(continuation, plan: plan);
    final completed = session.state == 'completed';
    if ((session.state != 'active' &&
            session.state != 'paused' &&
            !completed) ||
        completed != (cursor.phase == QuizPhase.finished)) {
      throw StateError('Stored quiz state and cursor disagree');
    }
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(session.ownerId) &
                    row.sessionId.equals(session.id),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.attemptNumber)]))
            .get();
    QuizResponse? feedback;
    final mistakes = <String, QuizWord>{};
    for (final attempt in attempts) {
      final evidence = attempt.answerEvidenceJson;
      if (evidence == null) throw StateError('Quiz answer evidence is missing');
      final response = decodeQuizResponse(evidence, plan: plan);
      final word = plan.questions[response.slot].word;
      if (!attempt.isCorrect) mistakes[word.id] = word;
      if (attempt.id == cursor.lastAttemptId) feedback = response;
    }
    if (cursor.lastAttemptId != null && feedback?.slot != cursor.slot) {
      throw StateError('Stored quiz feedback does not match the cursor');
    }
    return QuizRound(
      sessionId: session.id,
      startedAtUtc: _fromEpoch(session.startedAtUtcMs)!,
      plan: plan,
      cursor: cursor,
      isPaused: session.state == 'paused',
      committedAnswers: attempts.length,
      feedback: feedback,
      mistakes: mistakes.values,
      summary: completed ? _summary(session) : null,
    );
  }

  Future<void> _saveQuizCursor(
    db.LearningSession row,
    QuizPlan plan,
    QuizCursor cursor, {
    String? state,
    DateTime? endedAtUtc,
  }) async {
    final updated =
        await (database.update(database.learningSessions)..where(
              (candidate) =>
                  candidate.id.equals(row.id) &
                  candidate.ownerId.equals(row.ownerId) &
                  candidate.state.equals(row.state) &
                  candidate.continuationJson.equals(row.continuationJson!),
            ))
            .write(
              db.LearningSessionsCompanion(
                continuationJson: Value(encodeQuizCursor(cursor, plan: plan)),
                state: state == null ? const Value.absent() : Value(state),
                endedAtUtcMs: endedAtUtc == null
                    ? const Value.absent()
                    : Value(endedAtUtc.millisecondsSinceEpoch),
                score: endedAtUtc == null
                    ? const Value.absent()
                    : Value(_score(row)),
              ),
            );
    if (updated != 1) throw StateError('Quiz cursor changed');
  }

  @override
  Future<QuizRound?> loadQuizRound({
    required String ownerId,
    required String sessionId,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, sessionId);
    return row == null ? null : _readRound(row);
  });

  @override
  Future<QuizRound?> findOpenQuizRound({
    required String ownerId,
    required QuizOrigin origin,
    bool skipUnavailable = false,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.state.isIn(['active', 'paused']) &
                    row.questionPlanJson.isNotNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.startedAtUtcMs),
                (row) => OrderingTerm.desc(row.id),
              ]))
            .get();
    for (final row in rows) {
      final QuizPlan plan;
      try {
        plan = decodeQuizPlan(row.questionPlanJson!);
      } on FormatException {
        continue;
      }
      if (plan.origin != origin) continue;
      final round = (await _readRound(row, plan: plan))!;
      try {
        final cursor = round.cursor;
        final firstPending =
            cursor.slot + (cursor.phase == QuizPhase.feedback ? 1 : 0);
        for (final question in plan.questions.skip(firstPending)) {
          await _requireQuizWord(ownerId, question.word);
        }
      } on QuizVocabularyChanged {
        if (!skipUnavailable) rethrow;
        continue;
      }
      return round;
    }
    return null;
  });

  @override
  Future<QuizRound> advanceQuizRound({
    required String ownerId,
    required String sessionId,
    required int expectedRevision,
    required QuizStep step,
    required DateTime atUtc,
    int activeResponseMs = 0,
  }) => database.transaction(() async {
    _requiredUtc(atUtc, 'atUtc');
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, sessionId);
    final round = row == null ? null : await _readRound(row);
    if (row == null || round == null) throw StateError('Quiz round not found');
    final cursor = round.cursor;
    if (cursor.phase == QuizPhase.finished && step == QuizStep.finish) {
      return round;
    }
    if (cursor.revision != expectedRevision ||
        cursor.phase == QuizPhase.finished) {
      throw StateError('Quiz cursor changed');
    }
    final feedback = cursor.phase == QuizPhase.feedback;
    var slot = cursor.slot;
    var phase = cursor.phase;
    var lastAttempt = cursor.lastAttemptId;
    var elapsed = cursor.activeResponseMs;
    var state = row.state;
    DateTime? ended;
    switch (step) {
      case QuizStep.pause:
        if (round.isPaused ||
            activeResponseMs < 0 ||
            activeResponseMs > LearningEvidenceContract.maxResponseTimeMs) {
          throw StateError('Quiz cannot be paused');
        }
        if (!feedback && activeResponseMs > elapsed) elapsed = activeResponseMs;
        state = 'paused';
      case QuizStep.resume:
        if (!round.isPaused) throw StateError('Quiz is not paused');
        for (final question in round.plan.questions.skip(
          slot + (feedback ? 1 : 0),
        )) {
          await _requireQuizWord(ownerId, question.word);
        }
        state = 'active';
      case QuizStep.retryQuestion:
      case QuizStep.next:
        if (round.isPaused || !feedback) {
          throw StateError('Quiz feedback is required');
        }
        if (step == QuizStep.next) slot++;
        if (slot >= round.plan.questions.length) {
          throw StateError('Quiz is at its last question');
        }
        await _requireQuizWord(ownerId, round.plan.questions[slot].word);
        phase = QuizPhase.awaitingAnswer;
        lastAttempt = null;
        elapsed = 0;
      case QuizStep.finish:
        if (round.isPaused ||
            !feedback ||
            slot != round.plan.questions.length - 1) {
          throw StateError('Final quiz feedback is required');
        }
        phase = QuizPhase.finished;
        state = 'completed';
        ended = atUtc;
    }
    await _saveQuizCursor(
      row,
      round.plan,
      (
        revision: cursor.revision + 1,
        slot: slot,
        phase: phase,
        lastAttemptId: lastAttempt,
        activeResponseMs: elapsed,
      ),
      state: state,
      endedAtUtc: ended,
    );
    if (ended != null) await projections.rebuildAchievements(ownerId);
    return (await _readRound((await _session(ownerId, sessionId))!))!;
  });

  int _score(db.LearningSession row) {
    final total = row.correctCount + row.wrongCount;
    return total == 0 ? 0 : ((row.correctCount * 100) / total).round();
  }

  LearningSessionSummary _summary(db.LearningSession row) =>
      LearningSessionSummary(
        id: row.id,
        state: row.state,
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: row.score ?? _score(row),
      );

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    return database.transaction(() async {
      await _requireActiveOwner(ownerId);
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(sessionId) &
                    candidate.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      if (row.legacyEvidenceDisposition != null) {
        throw StateError('Historical learning session is read-only');
      }
      if (row.state != 'completed' &&
          (row.state != 'active' ||
              row.questionPlanJson != null ||
              row.continuationJson != null)) {
        throw StateError('Learning session cannot finish through this command');
      }
      final score = row.score ?? _score(row);
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
      }
      await projections.rebuildAchievements(ownerId);
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
          ..orderBy([
            OrderingTerm.asc(database.srsStates.dueAtUtcMs),
            OrderingTerm.asc(database.vocabularyWords.id),
          ])
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
      await _requireActiveOwner(command.ownerId);
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
            operationId: '$entityType:$entityId:1',
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
        row.providerProvenance == command.providerProvenance;
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
