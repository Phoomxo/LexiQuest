import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import 'drift_learning_event_store.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/learning_models.dart';
import '../domain/srs_policy.dart';

final class DriftLearningProjectionRebuilder {
  DriftLearningProjectionRebuilder(
    this.database, {
    this.srsPolicy = const BinarySm2SrsPolicy(),
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
  }) : evidenceDecisions = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  final db.AppDatabase database;
  final SrsPolicy srsPolicy;
  final DriftLearningEventStore evidenceDecisions;

  Future<SrsSnapshot?> rebuildWord({
    required String ownerId,
    required String wordId,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) {
      throw StateError('cannot rebuild SRS without answer evidence');
    }

    final decisions = <String, LearningEvidenceDecisionSet>{};
    for (final attempt in attempts) {
      decisions[attempt.id] = await evidenceDecisions
          .ensureDecisionSetForAttempt(attempt: attempt);
    }
    final masteryAttempts = attempts
        .where(
          (attempt) =>
              decisions[attempt.id]!.allows(LearningProjection.masterySrs),
        )
        .toList(growable: false);
    final xpAttempts = attempts
        .where(
          (attempt) => decisions[attempt.id]!.allows(LearningProjection.xp),
        )
        .toList(growable: false);

    final attemptIds = attempts.map((attempt) => attempt.id).toList();
    await (database.delete(database.pointsLedgerEntries)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entryType.equals('quizCorrect') &
              row.sourceEventId.isIn(attemptIds),
        ))
        .go();
    for (final attempt in xpAttempts.where((attempt) => attempt.isCorrect)) {
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            db.PointsLedgerEntriesCompanion.insert(
              id: 'points:${attempt.id}',
              ownerId: ownerId,
              idempotencyKey: 'correct-answer:${attempt.id}',
              entryType: 'quizCorrect',
              amount: 1,
              sourceEventId: Value(attempt.id),
              occurredAtUtcMs: attempt.occurredAtUtcMs,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    if (masteryAttempts.isEmpty) {
      await (database.delete(database.srsStates)..where(
            (row) => row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
          ))
          .go();
      return null;
    }

    SrsSnapshot? state;
    for (final attempt in masteryAttempts) {
      state = srsPolicy.review(
        previous: state,
        isCorrect: attempt.isCorrect,
        nowUtc: _utc(attempt.occurredAtUtcMs),
      );
    }

    final next = state!;
    await (database.delete(database.srsStates)..where(
          (row) => row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
        ))
        .go();
    await database
        .into(database.srsStates)
        .insert(
          db.SrsStatesCompanion.insert(
            id: 'srs:$ownerId:$wordId',
            ownerId: ownerId,
            wordId: wordId,
            stability: Value(next.stability),
            difficulty: Value(next.difficulty),
            intervalDays: Value(next.intervalDays),
            repetitions: Value(next.repetitions),
            lapses: Value(next.lapses),
            lastReviewAtUtcMs: Value(
              next.lastReviewAtUtc?.millisecondsSinceEpoch,
            ),
            dueAtUtcMs: next.dueAtUtc!.millisecondsSinceEpoch,
            algorithmVersion: next.algorithmVersion,
          ),
        );
    return next;
  }

  Future<void> rebuildSession({
    required String ownerId,
    required String sessionId,
  }) async {
    final session =
        await (database.select(database.learningSessions)..where(
              (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null) {
      throw StateError('owner-scoped learning session not found');
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.sessionId.equals(sessionId),
            ))
            .get();
    final eligible = <db.AnswerAttempt>[];
    for (final attempt in attempts) {
      final decisionSet = await evidenceDecisions.ensureDecisionSetForAttempt(
        attempt: attempt,
      );
      if (decisionSet.allows(LearningProjection.sessionOutcome)) {
        eligible.add(attempt);
      }
    }
    final correct = eligible.where((attempt) => attempt.isCorrect).length;
    final wrong = eligible.length - correct;
    final score = eligible.isEmpty
        ? 0
        : ((correct * 100) / eligible.length).round();
    await (database.update(database.learningSessions)..where(
          (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
        ))
        .write(
          db.LearningSessionsCompanion(
            correctCount: Value(correct),
            wrongCount: Value(wrong),
            score: session.state == 'completed'
                ? Value(score)
                : const Value.absent(),
          ),
        );
  }

  Future<void> rebuildAchievements(String ownerId) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final eligible = <db.AnswerAttempt>[];
    for (final attempt in attempts) {
      final decisionSet = await evidenceDecisions.ensureDecisionSetForAttempt(
        attempt: attempt,
      );
      if (decisionSet.allows(LearningProjection.achievement)) {
        eligible.add(attempt);
      }
    }
    final desired = <String, db.AnswerAttempt>{};
    if (eligible.isNotEmpty) desired['first_answer'] = eligible.first;
    final correct = eligible
        .where((attempt) => attempt.isCorrect)
        .toList(growable: false);
    if (correct.isNotEmpty) {
      desired['first_correct'] = correct.first;
    }
    if (correct.length >= 10) {
      desired['ten_correct'] = correct[9];
    }
    const managedAchievementIds = <String>{
      'first_answer',
      'first_correct',
      'ten_correct',
    };
    final obsolete = managedAchievementIds.difference(desired.keys.toSet());
    if (obsolete.isNotEmpty) {
      await (database.delete(database.achievementUnlocks)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.definitionVersion.equals(1) &
                row.achievementId.isIn(obsolete),
          ))
          .go();
    }
    for (final entry in desired.entries) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: entry.key,
        source: entry.value,
      );
    }
  }

  Future<LearningEvidenceDecisionSet> decisionSetForAttempt(
    db.AnswerAttempt attempt,
  ) => evidenceDecisions.ensureDecisionSetForAttempt(attempt: attempt);

  Future<ReadingProgressSnapshot> rebuildReading({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final events =
        await (database.select(database.readingEvents)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.documentId.equals(documentId) &
                    row.documentRevision.equals(documentRevision),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (events.isEmpty) {
      throw StateError('cannot rebuild reading progress without evidence');
    }
    var position = 0;
    var completed = false;
    var updatedAtUtcMs = 0;
    for (final event in events) {
      final eventPosition = event.position ?? 0;
      if (eventPosition > position) position = eventPosition;
      if (event.eventType == 'completed') completed = true;
      if (event.occurredAtUtcMs > updatedAtUtcMs) {
        updatedAtUtcMs = event.occurredAtUtcMs;
      }
    }
    await (database.delete(database.readingProgressEntries)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.documentId.equals(documentId) &
              row.documentRevision.equals(documentRevision),
        ))
        .go();
    await database
        .into(database.readingProgressEntries)
        .insert(
          db.ReadingProgressEntriesCompanion.insert(
            id: 'reading:$ownerId:$documentId:$documentRevision',
            ownerId: ownerId,
            documentId: documentId,
            documentRevision: Value(documentRevision),
            lastPosition: Value(position),
            isCompleted: Value(completed),
            updatedAtUtcMs: updatedAtUtcMs,
          ),
        );
    return ReadingProgressSnapshot(
      documentId: documentId,
      documentRevision: documentRevision,
      lastPosition: position,
      isCompleted: completed,
      updatedAtUtc: _utc(updatedAtUtcMs),
    );
  }

  Future<void> _insertAchievement({
    required String ownerId,
    required String achievementId,
    required db.AnswerAttempt source,
  }) async {
    const definitionVersion = 1;
    final existing =
        await (database.select(database.achievementUnlocks)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.achievementId.equals(achievementId) &
                  row.definitionVersion.equals(definitionVersion),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (source.id == existing.sourceEventId &&
          source.occurredAtUtcMs == existing.unlockedAtUtcMs) {
        return;
      }

      // Preserve the unlock identity while rebuilding canonical provenance
      // exclusively from eligible evidence.
      await (database.update(
        database.achievementUnlocks,
      )..where((row) => row.id.equals(existing.id))).write(
        db.AchievementUnlocksCompanion(
          sourceEventId: Value(source.id),
          unlockedAtUtcMs: Value(source.occurredAtUtcMs),
        ),
      );
      return;
    }
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: 'achievement:$ownerId:$achievementId:$definitionVersion',
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: source.id,
            unlockedAtUtcMs: source.occurredAtUtcMs,
          ),
        );
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
