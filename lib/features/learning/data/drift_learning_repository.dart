import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../motivation/domain/timezone_policy.dart';
import '../../motivation/data/drift_streak_repository.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_associative_learning_adapter.dart';
import 'drift_learning_projection_rebuilder.dart';
import '../application/learning_layer_adapter.dart' show AssociationRecord;
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/quiz_round.dart';
import '../domain/review_ladder.dart';
import '../domain/scramble_prompt_policy.dart';
import '../domain/source_reading_round.dart';
import '../domain/srs_policy.dart';
import '../domain/srs_recall_snapshot.dart';
import '../domain/answer_motivation_evidence.dart';

typedef AnswerCalendarCapture =
    LearningCalendarWindow Function(
      DateTime occurredAtUtc,
      String timezoneId, {
      DateTime? epochEffectiveAtUtc,
      DateTime? epochExpiresAtUtc,
    });

final class DriftLearningRepository
    implements
        DurableQuizRepository,
        DurableSourceReadingRepository,
        ReviewLadderRepository {
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

  static const _reviewLadderActivity = 'reviewLadder';

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
    if (session.activityType == _reviewLadderActivity) {
      throw ArgumentError('Review ladder requires a reviewed word pair');
    }
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
            ? encodeSrsRecallSnapshot(command.srsRecallSnapshot)
            : encodeQuizResponse(command.quiz!.response, plan: round.plan);
        if (existing.answerEvidenceJson != expectedEvidence ||
            (round != null) != (command.quiz != null)) {
          throw StateError(
            'attempt id already exists with different answer snapshot',
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

      final sourceReading = _readSourceReadingRound(session);
      final reviewLadder = _readReviewLadderRound(session);
      if (sourceReading != null) {
        final pinned = _requireSourceReadingAttempt(command, sourceReading);
        await _requireQuizWord(command.ownerId, pinned, row: word);
      }
      if (reviewLadder != null) {
        _requireReviewLadderAttempt(command, reviewLadder);
        await _requireReviewLadderPair(command.ownerId, reviewLadder.pair);
      }
      final round = sourceReading == null && reviewLadder == null
          ? await _readRound(session)
          : null;
      final admission = command.quiz;
      if (command.srsRecallSnapshot != null &&
          (round != null ||
              (session.activityType != 'srsReview' &&
                  session.activityType != 'sourcePractice'))) {
        throw StateError('SRS recall snapshot requires a review session');
      }
      String? answerEvidence = encodeSrsRecallSnapshot(
        command.srsRecallSnapshot,
      );
      if (round != null && admission != null) {
        final cursor = round.cursor;
        final question = round.plan.questions[cursor.slot];
        final response = admission.response;
        answerEvidence = encodeQuizResponse(response, plan: round.plan);
        if (cursor.phase != QuizPhase.awaitingAnswer ||
            cursor.revision != admission.expectedRevision ||
            cursor.slot != response.slot ||
            question.word.id != command.wordId ||
            question.kind.name != command.promptMode ||
            command.attemptNumber != round.committedAnswers + 1 ||
            (command.responseTimeMs ?? -1) < cursor.activeResponseMs ||
            command.isCorrect != response.isCorrectFor(question)) {
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

  SourceReadingRound? _readSourceReadingRound(db.LearningSession row) {
    final raw = row.continuationJson;
    if (row.activityType != 'associativeReading' || raw == null) return null;
    if (row.questionPlanJson != null ||
        row.legacyEvidenceDisposition != null ||
        row.state != 'active') {
      throw StateError('Invalid source reading session');
    }
    return decodeSourceReadingRound(raw, sessionId: row.id);
  }

  @override
  Future<SourceReadingRound> openSourceReadingRound({
    required LearningSessionDraft session,
    required SourceReadingScope scope,
  }) => database.transaction(() async {
    if (session.activityType != 'associativeReading' ||
        session.quizPlan != null) {
      throw ArgumentError('Expected a source reading session');
    }
    final ownerId = _required(session.ownerId, 'ownerId');
    final sessionId = _required(session.id, 'id');
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await _requireActiveOwner(ownerId);
    final initial = SourceReadingRound(
      sessionId: sessionId,
      scope: scope,
      revision: 0,
      draft: SourceReadingDraft.initial(scope.words.length),
    );
    final encoded = encodeSourceReadingRound(initial);
    for (final word in scope.words) {
      await _requireQuizWord(ownerId, word);
    }
    final candidates =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.activityType.equals('associativeReading') &
                    row.state.equals('active') &
                    row.questionPlanJson.isNull() &
                    row.continuationJson.isNotNull() &
                    row.legacyEvidenceDisposition.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.startedAtUtcMs),
                (row) => OrderingTerm.desc(row.id),
              ]))
            .get();
    for (final row in candidates) {
      try {
        final round = _readSourceReadingRound(row)!;
        if (round.scope.sameAs(scope)) return round;
      } on FormatException {
        // Leave unreadable drafts intact. A different source can still open.
      }
    }
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: sessionId,
            ownerId: ownerId,
            activityType: session.activityType,
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
            continuationJson: Value(encoded),
          ),
        );
    return initial;
  });

  @override
  Future<SourceReadingRound> saveSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required SourceReadingDraft draft,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, expected.sessionId);
    final reading = row == null ? null : _readSourceReadingRound(row);
    if (row == null ||
        reading == null ||
        !reading.scope.sameAs(expected.scope)) {
      throw StateError('Source reading round changed');
    }
    final next = SourceReadingRound(
      sessionId: expected.sessionId,
      scope: expected.scope,
      revision: expected.revision + 1,
      draft: draft,
    );
    final encoded = encodeSourceReadingRound(next);
    for (final word in reading.scope.words) {
      await _requireQuizWord(ownerId, word);
    }
    if (encoded == row.continuationJson) return reading;
    if (encodeSourceReadingRound(expected) != row.continuationJson ||
        !_validSourceReadingTransition(reading, draft)) {
      throw StateError('Source reading round changed');
    }
    await _writeActiveContinuation(
      row,
      db.LearningSessionsCompanion(continuationJson: Value(encoded)),
    );
    if (reading.draft.phase == SourceReadingPhase.association &&
        draft.phase == SourceReadingPhase.sentence) {
      final scope = reading.scope;
      final associations = DriftAssociativeLearningAdapter(database);
      final createdAtUtc = DateTime.now().toUtc();
      for (final (slot, word) in scope.words.indexed) {
        final cue = draft.cues[slot].trim();
        if (cue.isEmpty) continue;
        await associations.saveAssociation(
          AssociationRecord(
            associationId:
                'assoc:$ownerId:${scope.documentId}:${scope.documentRevision}:'
                '${word.id}',
            ownerId: ownerId,
            wordKey: word.spelling,
            type: 'keyword',
            content: cue,
            createdAtUtc: createdAtUtc,
          ),
        );
      }
    }
    return next;
  });

  bool _validSourceReadingTransition(
    SourceReadingRound reading,
    SourceReadingDraft next,
  ) {
    final current = reading.draft;
    final first = current.first;
    final nextFirst = next.first;
    if (first != null &&
        (nextFirst == null ||
            first.checkedAtUtc != nextFirst.checkedAtUtc ||
            !_sameSourceAnswers(first.answers, nextFirst.answers))) {
      return false;
    }
    if (first == null &&
        nextFirst != null &&
        (current.phase != SourceReadingPhase.recall ||
            !_sameSourceAnswers(nextFirst.answers, next.recall))) {
      return false;
    }
    if (current.phase == next.phase) return true;
    return switch (current.phase) {
      SourceReadingPhase.supported => next.phase == SourceReadingPhase.reread,
      SourceReadingPhase.reread => next.phase == SourceReadingPhase.recall,
      SourceReadingPhase.recall =>
        nextFirst != null &&
            next.phase ==
                (_sourceMisses(reading.scope, nextFirst.answers).isEmpty
                    ? SourceReadingPhase.association
                    : SourceReadingPhase.comparison),
      SourceReadingPhase.comparison =>
        next.phase == SourceReadingPhase.correction ||
            next.phase == SourceReadingPhase.association,
      SourceReadingPhase.correction =>
        first != null &&
            next.phase ==
                (_sourceMisses(reading.scope, first.answers).every(
                      (slot) => sourceRecallMatches(
                        next.recall[slot],
                        reading.scope.words[slot].spelling,
                      ),
                    )
                    ? SourceReadingPhase.association
                    : SourceReadingPhase.comparison),
      SourceReadingPhase.association =>
        next.phase == SourceReadingPhase.sentence,
      SourceReadingPhase.sentence => next.phase == SourceReadingPhase.summary,
      SourceReadingPhase.summary => false,
    };
  }

  bool _sameSourceAnswers(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var slot = 0; slot < left.length; slot++) {
      if (left[slot] != right[slot]) return false;
    }
    return true;
  }

  Iterable<int> _sourceMisses(
    SourceReadingScope scope,
    List<String> answers,
  ) sync* {
    for (var slot = 0; slot < scope.words.length; slot++) {
      if (!sourceRecallMatches(answers[slot], scope.words[slot].spelling)) {
        yield slot;
      }
    }
  }

  RecordAnswerCommand _sourceReadingAttempt(
    String ownerId,
    SourceReadingRound reading,
    int slot,
  ) {
    final first = reading.draft.first;
    if (first == null || slot < 0 || slot >= reading.scope.words.length) {
      throw StateError('Source reading answer was not checked');
    }
    final word = reading.scope.words[slot];
    return RecordAnswerCommand(
      id: 'attempt:${reading.sessionId}:associative:$slot',
      ownerId: ownerId,
      sessionId: reading.sessionId,
      wordId: word.id,
      promptMode: 'associativeRecall',
      isCorrect: sourceRecallMatches(first.answers[slot], word.spelling),
      responseTimeMs: null,
      attemptNumber: slot + 1,
      occurredAtUtc: first.checkedAtUtc,
    );
  }

  QuizWord _requireSourceReadingAttempt(
    RecordAnswerCommand command,
    SourceReadingRound reading,
  ) {
    if (reading.draft.phase != SourceReadingPhase.summary) {
      throw StateError('Source reading round is not ready to finish');
    }
    final slot = command.attemptNumber - 1;
    final expected = _sourceReadingAttempt(command.ownerId, reading, slot);
    if (command.id != expected.id ||
        command.sessionId != expected.sessionId ||
        command.wordId != expected.wordId ||
        command.promptMode != expected.promptMode ||
        command.isCorrect != expected.isCorrect ||
        command.occurredAtUtc.millisecondsSinceEpoch !=
            expected.occurredAtUtc.millisecondsSinceEpoch ||
        command.responseTimeMs != null ||
        command.providerProvenance != null ||
        command.quiz != null ||
        command.srsRecallSnapshot != null) {
      throw StateError('Source reading answer differs from the first check');
    }
    return reading.scope.words[slot];
  }

  Future<void> _writeActiveContinuation(
    db.LearningSession row,
    db.LearningSessionsCompanion changes,
  ) async {
    final updated =
        await (database.update(database.learningSessions)..where(
              (candidate) =>
                  candidate.id.equals(row.id) &
                  candidate.ownerId.equals(row.ownerId) &
                  candidate.state.equals('active') &
                  candidate.continuationJson.equals(row.continuationJson!),
            ))
            .write(changes);
    if (updated != 1) throw StateError('Learning continuation changed');
  }

  @override
  Future<LearningSessionSummary> finishSourceReadingRound({
    required String ownerId,
    required SourceReadingRound expected,
    required DateTime endedAtUtc,
  }) => database.transaction(() async {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, expected.sessionId);
    final encoded = encodeSourceReadingRound(expected);
    if (row == null ||
        row.activityType != 'associativeReading' ||
        row.legacyEvidenceDisposition != null ||
        row.questionPlanJson != null ||
        expected.draft.phase != SourceReadingPhase.summary ||
        (row.state == 'completed'
            ? row.continuationJson != null || row.endedAtUtcMs == null
            : row.state != 'active' || row.continuationJson != encoded)) {
      throw StateError('Source reading round cannot finish');
    }
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (attempt) =>
                    attempt.ownerId.equals(ownerId) &
                    attempt.sessionId.equals(row.id),
              )
              ..orderBy([(attempt) => OrderingTerm.asc(attempt.attemptNumber)]))
            .get();
    if (attempts.length != expected.scope.words.length) {
      throw StateError('Source reading answers are incomplete');
    }
    for (var slot = 0; slot < attempts.length; slot++) {
      final attempt = attempts[slot];
      final command = _sourceReadingAttempt(ownerId, expected, slot);
      if (attempt.id != command.id ||
          attempt.answerEvidenceJson != null ||
          attempt.legacyEvidenceDisposition != null ||
          !_sameAttempt(attempt, command)) {
        throw StateError('Source reading answers differ from the first check');
      }
    }
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    final score = _score(row);
    if (row.correctCount != correct ||
        row.wrongCount != attempts.length - correct ||
        (row.state == 'completed' && row.score != score)) {
      throw StateError('Source reading score differs from saved answers');
    }
    if (row.state == 'completed') return _summary(row);
    await _writeActiveContinuation(
      row,
      db.LearningSessionsCompanion(
        continuationJson: const Value(null),
        state: const Value('completed'),
        endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
        score: Value(score),
      ),
    );
    await projections.rebuildAchievements(ownerId);
    return _summary((await _session(ownerId, row.id))!);
  });

  @override
  Future<ReviewLadderPair?> findReviewLadderPair({required String ownerId}) =>
      database.transaction(() async {
        await _requireActiveOwner(ownerId);
        for (final row in await _reviewLadderCandidates(ownerId)) {
          final pair = await _reviewLadderPair(ownerId, row);
          if (pair != null) return pair;
        }
        return null;
      });

  Future<List<TypedResult>> _reviewLadderCandidates(
    String ownerId, {
    String? attemptId,
  }) {
    final answers = database.answerAttempts;
    final sessions = database.learningSessions;
    final words = database.vocabularyWords;
    final categories = database.vocabularyCategories;
    return (database.select(answers).join([
            innerJoin(
              sessions,
              sessions.id.equalsExp(answers.sessionId) &
                  sessions.ownerId.equalsExp(answers.ownerId),
            ),
            innerJoin(
              words,
              words.id.equalsExp(answers.wordId) &
                  words.ownerId.equalsExp(answers.ownerId),
            ),
            innerJoin(
              categories,
              categories.id.equalsExp(words.categoryId) &
                  categories.ownerId.equalsExp(words.ownerId),
            ),
          ])
          ..where(
            answers.ownerId.equals(ownerId) &
                (attemptId == null
                    ? const Constant(true)
                    : answers.id.equals(attemptId)) &
                answers.promptMode.equals('srsRecall') &
                answers.answerEvidenceJson.isNotNull() &
                answers.legacyEvidenceDisposition.isNull() &
                sessions.activityType.isIn(['srsReview', 'sourcePractice']) &
                sessions.state.equals('completed') &
                sessions.endedAtUtcMs.isNotNull() &
                sessions.legacyEvidenceDisposition.isNull() &
                words.normalizedSpelling.equals('station') &
                words.normalizedMeaning.equals('สถานี') &
                words.isDeleted.equals(false) &
                categories.isDeleted.equals(false),
          )
          ..orderBy([
            OrderingTerm.desc(answers.occurredAtUtcMs),
            OrderingTerm.desc(answers.id),
          ]))
        .get();
  }

  Future<ReviewLadderPair?> _reviewLadderPair(
    String ownerId,
    TypedResult row,
  ) async {
    final attempt = row.readTable(database.answerAttempts);
    final target = row.readTable(database.vocabularyWords);
    final category = row.readTable(database.vocabularyCategories);
    try {
      final original = decodeSrsRecallSnapshot(attempt.answerEvidenceJson!);
      if (original.spelling != target.spelling ||
          original.meaning != target.meaning ||
          original.partOfSpeech != target.partOfSpeech) {
        return null;
      }
    } on FormatException {
      return null;
    }
    final candidates = await listQuizWords(
      ownerId: ownerId,
      categoryId: category.id,
      normalizedSpellings: ['station', 'platform'],
      normalizedMeanings: ['สถานี', 'ชานชาลา'],
      limit: 3,
    );
    if (candidates.length != 2) return null;
    final station = candidates
        .where((word) => word.id == target.id)
        .firstOrNull;
    final platform = candidates
        .where((word) => word.id != target.id)
        .firstOrNull;
    if (station == null ||
        platform == null ||
        station.spelling.trim().toLowerCase() != 'station' ||
        station.meaning.trim() != 'สถานี' ||
        station.partOfSpeech.trim().toLowerCase() != 'noun' ||
        platform.spelling.trim().toLowerCase() != 'platform' ||
        platform.meaning.trim() != 'ชานชาลา' ||
        platform.partOfSpeech.trim().toLowerCase() != 'noun') {
      return null;
    }
    return ReviewLadderPair(
      target: station,
      contrast: platform,
      categoryName: category.name,
      reviewAttemptId: attempt.id,
    );
  }

  Future<void> _requireReviewLadderPair(
    String ownerId,
    ReviewLadderPair expected,
  ) async {
    final rows = await _reviewLadderCandidates(
      ownerId,
      attemptId: expected.reviewAttemptId,
    );
    final current = rows.isEmpty
        ? null
        : await _reviewLadderPair(ownerId, rows.single);
    if (current == null || !current.sameAs(expected)) {
      throw QuizVocabularyChanged();
    }
  }

  ReviewLadderRound? _readReviewLadderRound(db.LearningSession row) {
    if (row.activityType != _reviewLadderActivity) return null;
    final raw = row.continuationJson;
    if (raw == null ||
        row.questionPlanJson != null ||
        row.legacyEvidenceDisposition != null ||
        (row.state != 'active' && row.state != 'completed')) {
      throw StateError('Invalid review ladder session');
    }
    final round = decodeReviewLadderRound(raw, sessionId: row.id);
    if (row.state == 'completed' &&
        (row.endedAtUtcMs == null || round.phase != ReviewLadderPhase.result)) {
      throw StateError('Invalid completed review ladder session');
    }
    return round;
  }

  @override
  Future<ReviewLadderRound?> readLatestReviewLadder({
    required String ownerId,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final row =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.activityType.equals(_reviewLadderActivity) &
                    row.state.equals('completed') &
                    row.legacyEvidenceDisposition.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.endedAtUtcMs),
                (row) => OrderingTerm.desc(row.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _readReviewLadderRound(row);
  });

  @override
  Future<ReviewLadderRound> openReviewLadderRound({
    required LearningSessionDraft session,
    required ReviewLadderPair pair,
  }) => database.transaction(() async {
    if (session.activityType != _reviewLadderActivity ||
        session.quizPlan != null) {
      throw ArgumentError('Expected a review ladder session');
    }
    final ownerId = _required(session.ownerId, 'ownerId');
    final sessionId = _required(session.id, 'id');
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await _requireActiveOwner(ownerId);
    await _requireReviewLadderPair(ownerId, pair);
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.activityType.equals(_reviewLadderActivity) &
                    row.state.equals('active') &
                    row.legacyEvidenceDisposition.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.startedAtUtcMs),
                (row) => OrderingTerm.desc(row.id),
              ]))
            .get();
    for (final row in rows) {
      final round = _readReviewLadderRound(row)!;
      if (round.pair.sameAs(pair)) return round;
    }
    final initial = ReviewLadderRound.initial(sessionId: sessionId, pair: pair);
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: sessionId,
            ownerId: ownerId,
            activityType: _reviewLadderActivity,
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
            continuationJson: Value(encodeReviewLadderRound(initial)),
          ),
        );
    return initial;
  });

  @override
  Future<ReviewLadderRound> changeReviewLadderRound({
    required String ownerId,
    required ReviewLadderRound expected,
    required ReviewLadderAction action,
    required DateTime atUtc,
    int? option,
    String? text,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, expected.sessionId);
    final saved = row == null ? null : _readReviewLadderRound(row);
    if (row == null ||
        saved == null ||
        row.state != 'active' ||
        !saved.pair.sameAs(expected.pair)) {
      throw StateError('Review ladder round changed');
    }
    await _requireReviewLadderPair(ownerId, saved.pair);
    final next = expected.advance(
      action,
      atUtc: atUtc,
      option: option,
      text: text,
    );
    final encoded = encodeReviewLadderRound(next);
    if (encoded == row.continuationJson) return saved;
    if (encodeReviewLadderRound(expected) != row.continuationJson) {
      throw StateError('Review ladder round changed');
    }
    await _writeActiveContinuation(
      row,
      db.LearningSessionsCompanion(continuationJson: Value(encoded)),
    );
    return next;
  });

  RecordAnswerCommand? _reviewLadderAttempt(
    String ownerId,
    ReviewLadderRound round,
  ) {
    final choice = round.independentChoice;
    if (choice == null || choice.assisted) return null;
    return RecordAnswerCommand(
      id: 'attempt:${round.sessionId}:review:0',
      ownerId: ownerId,
      sessionId: round.sessionId,
      wordId: round.pair.target.id,
      promptMode: 'meaningChoice',
      isCorrect: choice.option == 1,
      responseTimeMs: null,
      attemptNumber: 1,
      occurredAtUtc: choice.checkedAtUtc,
    );
  }

  void _requireReviewLadderAttempt(
    RecordAnswerCommand command,
    ReviewLadderRound round,
  ) {
    final expected = _reviewLadderAttempt(command.ownerId, round);
    if (round.phase != ReviewLadderPhase.result ||
        expected == null ||
        command.id != expected.id ||
        command.sessionId != expected.sessionId ||
        command.wordId != expected.wordId ||
        command.promptMode != expected.promptMode ||
        command.isCorrect != expected.isCorrect ||
        command.attemptNumber != expected.attemptNumber ||
        command.occurredAtUtc.millisecondsSinceEpoch !=
            expected.occurredAtUtc.millisecondsSinceEpoch ||
        command.responseTimeMs != null ||
        command.providerProvenance != null ||
        command.quiz != null ||
        command.srsRecallSnapshot != null) {
      throw StateError('Review ladder answer differs from the first check');
    }
  }

  @override
  Future<LearningSessionSummary> finishReviewLadderRound({
    required String ownerId,
    required ReviewLadderRound expected,
    required DateTime endedAtUtc,
  }) => database.transaction(() async {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, expected.sessionId);
    final saved = row == null ? null : _readReviewLadderRound(row);
    if (row == null ||
        saved == null ||
        saved.phase != ReviewLadderPhase.result ||
        row.continuationJson != encodeReviewLadderRound(expected)) {
      throw StateError('Review ladder round cannot finish');
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (attempt) =>
                  attempt.ownerId.equals(ownerId) &
                  attempt.sessionId.equals(row.id),
            ))
            .get();
    final command = _reviewLadderAttempt(ownerId, saved);
    if (command == null
        ? attempts.isNotEmpty
        : attempts.length != 1 ||
              attempts.single.id != command.id ||
              attempts.single.answerEvidenceJson != null ||
              attempts.single.legacyEvidenceDisposition != null ||
              !_sameAttempt(attempts.single, command)) {
      throw StateError('Review ladder answers differ from the first check');
    }
    final correct = command?.isCorrect == true ? 1 : 0;
    final score = command == null ? null : _score(row);
    if (row.correctCount != correct ||
        row.wrongCount != attempts.length - correct ||
        (row.state == 'completed' && row.score != score)) {
      throw StateError('Review ladder score differs from saved answer');
    }
    if (row.state == 'completed') return _summary(row);
    await _requireReviewLadderPair(ownerId, saved.pair);
    await _writeActiveContinuation(
      row,
      db.LearningSessionsCompanion(
        state: const Value('completed'),
        endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
        score: Value(score),
      ),
    );
    if (command != null) await projections.rebuildAchievements(ownerId);
    return _summary((await _session(ownerId, row.id))!);
  });

  Future<QuizRound?> _roundForAttempt(RecordAnswerCommand command) async {
    final session = await _session(command.ownerId, command.sessionId);
    if (session == null) return null;
    if (_readReviewLadderRound(session) case final ladder?) {
      _requireReviewLadderAttempt(command, ladder);
      if (session.state == 'active') {
        await _requireReviewLadderPair(command.ownerId, ladder.pair);
      }
      return null;
    }
    if (_readSourceReadingRound(session) case final reading?) {
      _requireSourceReadingAttempt(command, reading);
      return null;
    }
    return _readRound(session);
  }

  Future<QuizRound?> _readRound(
    db.LearningSession session, {
    QuizPlan? plan,
  }) async {
    if (session.activityType == _reviewLadderActivity) return null;
    final encodedPlan = session.questionPlanJson;
    final continuation = session.continuationJson;
    if (encodedPlan == null && continuation == null) return null;
    if (_readSourceReadingRound(session) != null) return null;
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
  Future<QuizRound> openOrStartAuthoredRound(
    LearningSessionDraft draft, {
    required bool skipUnavailable,
  }) => database.transaction(() async {
    final plan = draft.quizPlan;
    if (plan == null) {
      throw ArgumentError('Expected a pinned authored quiz draft');
    }
    final origin = plan.origin;
    final admitted = switch (draft.activityType) {
      'cloze' => origin.route == 'cloze' && origin.promptKind.isCloze,
      'wordScramble' || 'sentenceScramble' =>
        origin.route == 'word-games' &&
            origin.promptKind.name == draft.activityType,
      _ => false,
    };
    if (!admitted) {
      throw ArgumentError('Expected a pinned authored quiz draft');
    }
    if (origin.promptKind.isScramble && origin.parentId != null) {
      await _requireScrambleParent(draft.ownerId, plan);
    }
    final existing = await findOpenQuizRound(
      ownerId: draft.ownerId,
      origin: origin,
      skipUnavailable: skipUnavailable,
    );
    if (existing != null) return existing;
    await startSession(draft);
    final saved = await _session(draft.ownerId, draft.id);
    if (saved == null) throw StateError('Saved authored round is missing');
    return (await _readRound(saved))!;
  });

  Future<void> _requireScrambleParent(String ownerId, QuizPlan child) async {
    final origin = child.origin;
    if (origin.promptKind != QuizPromptKind.sentenceScramble ||
        child.questions.length != 1 ||
        origin.wordIds?.length != 1) {
      throw StateError('Invalid sentence source link');
    }
    await _requireActiveOwner(ownerId);
    final row = await _session(ownerId, origin.parentId!);
    if (row == null || row.legacyEvidenceDisposition != null) {
      throw StateError('Sentence source round is unavailable');
    }
    final parent = await _readRound(row);
    if (parent == null) {
      throw StateError('Sentence source round is unavailable');
    }
    final parentOrigin = parent.plan.origin;
    final admitted = switch (row.activityType) {
      'cloze' =>
        parentOrigin.route == 'cloze' &&
            parentOrigin.promptKind.isCloze &&
            !parent.isPaused,
      'wordScramble' =>
        parentOrigin.route == 'word-games' &&
            parentOrigin.promptKind == QuizPromptKind.wordScramble &&
            parent.cursor.phase == QuizPhase.finished,
      _ => false,
    };
    final source = parent.plan.questions[parent.cursor.slot];
    final target = child.questions.single;
    final example = ScramblePromptPolicy.sentenceFor(source.word);
    if (!admitted ||
        parent.feedback?.isCorrectFor(source) != true ||
        origin.wordIds!.single != source.word.id ||
        origin.categoryId != source.word.categoryId ||
        target.word.localRevision != source.word.localRevision ||
        target.word.spelling != source.word.spelling ||
        target.word.meaning != source.word.meaning ||
        target.word.partOfSpeech != source.word.partOfSpeech ||
        example == null ||
        target.correctAnswer != example.sentence ||
        target.promptText != example.meaning ||
        target.sourcePin != example.pin) {
      throw StateError('Sentence source answer is unavailable');
    }
  }

  @override
  Future<Set<String>> loadCompletedQuizMistakeIds({
    required String ownerId,
    required String sessionId,
  }) => database.transaction(() async {
    await _requireActiveOwner(ownerId);
    final session = await _session(ownerId, sessionId);
    if (session == null ||
        session.state != 'completed' ||
        session.activityType != 'quiz' ||
        session.legacyEvidenceDisposition != null) {
      return const {};
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.sessionId.equals(sessionId) &
                  row.isCorrect.equals(false),
            ))
            .get();
    return attempts.map((attempt) => attempt.wordId).toSet();
  });

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
    if (command.srsRecallSnapshot != null &&
        (command.promptMode != 'srsRecall' || command.quiz != null)) {
      throw ArgumentError('SRS recall snapshot requires a flashcard rating');
    }
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
