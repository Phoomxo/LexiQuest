import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/app_database.dart' as db;
import '../../quest/data/drift_quest_progress_reader.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../domain/learning_models.dart';
import '../domain/srs_policy.dart';

final class DriftLearningProjectionRebuilder {
  const DriftLearningProjectionRebuilder(
    this.database, {
    this.srsPolicy = const BinarySm2SrsPolicy(),
    this.questCatalog,
  });

  final db.AppDatabase database;
  final SrsPolicy srsPolicy;
  final TrustedQuestAnswerCatalog? questCatalog;

  Future<void> rebuildQuestXp(String ownerId) => database.transaction(() async {
    final receipts = await DriftQuestProgressReader(
      database,
      catalog: questCatalog,
    ).validatedReceipts(ownerId: ownerId);
    for (final receipt in receipts) {
      final id = 'points:quest:${receipt.id}';
      final key = 'quest-claim:${receipt.id}';
      final conflictingSource =
          await (database.select(database.pointsLedgerEntries)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.entryType.equals('questClaimXpV1') &
                      row.sourceEventId.equals(receipt.id) &
                      (row.id.equals(id).not() |
                          row.idempotencyKey.equals(key).not()),
                )
                ..limit(1))
              .getSingleOrNull();
      if (conflictingSource != null) {
        throw StateError('Conflicting immutable Quest XP provenance');
      }
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            db.PointsLedgerEntriesCompanion.insert(
              id: id,
              ownerId: ownerId,
              idempotencyKey: key,
              entryType: 'questClaimXpV1',
              amount: receipt.xpAmount,
              sourceEventId: Value(receipt.id),
              occurredAtUtcMs: receipt.issuedAtUtcMs,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final row = await (database.select(
        database.pointsLedgerEntries,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (row == null ||
          row.ownerId != ownerId ||
          row.idempotencyKey != key ||
          row.entryType != 'questClaimXpV1' ||
          row.amount != receipt.xpAmount ||
          row.sourceEventId != receipt.id ||
          row.occurredAtUtcMs != receipt.issuedAtUtcMs) {
        throw StateError('Conflicting immutable Quest XP provenance');
      }
    }
  });

  Future<SrsSnapshot> rebuildWord({
    required String ownerId,
    required String wordId,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.wordId.equals(wordId) &
                    (row.legacyEvidenceDisposition.isNull() |
                        row.legacyEvidenceDisposition.equals('base-v25')),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) {
      throw StateError('cannot rebuild SRS without answer evidence');
    }

    SrsSnapshot? state;
    for (final attempt in attempts) {
      state = srsPolicy.review(
        previous: state,
        isCorrect: attempt.isCorrect,
        nowUtc: _utc(attempt.occurredAtUtcMs),
      );
      if (attempt.isCorrect && attempt.legacyEvidenceDisposition == null) {
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
    if (session.legacyEvidenceDisposition != null) {
      return;
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.sessionId.equals(sessionId),
            ))
            .get();
    if (attempts.any((attempt) => attempt.legacyEvidenceDisposition != null)) {
      return;
    }
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    final wrong = attempts.length - correct;
    final score = attempts.isEmpty
        ? 0
        : ((correct * 100) / attempts.length).round();
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

  Future<void> rebuildAchievements(
    String ownerId, {
    bool enqueueNewUnlocks = true,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.legacyEvidenceDisposition.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) return;
    await _insertAchievement(
      ownerId: ownerId,
      achievementId: 'first_answer',
      sourceEventId: attempts.first.id,
      unlockedAtUtcMs: attempts.first.occurredAtUtcMs,
      enqueue: enqueueNewUnlocks,
    );
    final correct = attempts
        .where((attempt) => attempt.isCorrect)
        .toList(growable: false);
    if (correct.isNotEmpty) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: 'first_correct',
        sourceEventId: correct.first.id,
        unlockedAtUtcMs: correct.first.occurredAtUtcMs,
        enqueue: enqueueNewUnlocks,
      );
    }
    if (correct.length >= 10) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: 'ten_correct',
        sourceEventId: correct[9].id,
        unlockedAtUtcMs: correct[9].occurredAtUtcMs,
        enqueue: enqueueNewUnlocks,
      );
    }
    final counts = <String, ({int total, int wrong})>{};
    for (final attempt in attempts) {
      final prior = counts[attempt.sessionId] ?? (total: 0, wrong: 0);
      counts[attempt.sessionId] = (
        total: prior.total + 1,
        wrong: prior.wrong + (attempt.isCorrect ? 0 : 1),
      );
    }
    final sessions =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.legacyEvidenceDisposition.isNull() &
                    row.state.equals('completed') &
                    row.endedAtUtcMs.isNotNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.endedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    db.LearningSession? firstSession;
    db.LearningSession? perfectSession;
    for (final session in sessions) {
      final facts = counts[session.id];
      if (facts == null || facts.total == 0) continue;
      firstSession ??= session;
      if (facts.wrong == 0) perfectSession ??= session;
      if (perfectSession != null) break;
    }
    for (final entry in [
      ('first_session', firstSession),
      ('perfect_session', perfectSession),
    ]) {
      final source = entry.$2;
      if (source == null) continue;
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: entry.$1,
        sourceEventId: source.id,
        unlockedAtUtcMs: source.endedAtUtcMs!,
        enqueue: enqueueNewUnlocks,
      );
    }
  }

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
    required String sourceEventId,
    required int unlockedAtUtcMs,
    required bool enqueue,
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
    if (existing != null) return;
    var id = 'achievement:$ownerId:$achievementId:$definitionVersion';
    while (await database
            .customSelect(
              'SELECT 1 FROM achievement_unlocks WHERE id = ? '
              'UNION ALL SELECT 1 FROM outbox_operations WHERE operation_id = ? '
              "OR (entity_type = 'achievementUnlock' AND entity_id = ?) LIMIT 1",
              variables: [
                Variable<String>(id),
                Variable<String>('achievementUnlock:$id:1'),
                Variable<String>(id),
              ],
            )
            .getSingleOrNull() !=
        null) {
      id = 'achievement:${const Uuid().v4()}';
    }
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: id,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtcMs,
          ),
        );
    if (enqueue) {
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: 'achievementUnlock:$id:1',
              ownerId: ownerId,
              entityType: 'achievementUnlock',
              entityId: id,
              operationKind: 'upsert',
              baseRevision: const Value(0),
              createdAtUtcMs: unlockedAtUtcMs,
            ),
          );
    }
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
