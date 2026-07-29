import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/learning_commit.dart';
import 'package:vocab_learning_app/learning/learning_event.dart';
import 'package:vocab_learning_app/learning/learning_repository.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database.dart';
import 'package:vocab_learning_app/learning/sync_outbox_entry.dart';

void main() {
  late LearningDatabase database;
  late DriftLearningRepository repository;

  setUp(() {
    database = LearningDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('applies an identical commit exactly once', () async {
    final commit = _commit(
      commitId: 'commit-1',
      associationId: 'association-1',
    );

    final first = await repository.commit(commit);
    final second = await repository.commit(commit);

    expect(first.disposition, CommitDisposition.applied);
    expect(first.writtenRecords, commit.recordCount);
    expect(second.disposition, CommitDisposition.alreadyApplied);
    expect(second.writtenRecords, 0);
    expect(await database.select(database.learningCommits).get(), hasLength(1));
    expect(await database.select(database.associations).get(), hasLength(1));
  });

  test('rejects reuse of a commit id with different content', () async {
    await repository.commit(
      _commit(commitId: 'commit-1', associationId: 'association-1'),
    );

    await expectLater(
      repository.commit(
        _commit(commitId: 'commit-1', associationId: 'association-2'),
      ),
      throwsA(
        isA<LearningRepositoryException>().having(
          (error) => error.code,
          'code',
          LearningRepositoryErrorCode.idempotencyConflict,
        ),
      ),
    );
  });

  test('rolls back every write when an append-only event conflicts', () async {
    final event = _event(ownerId: 'owner-a', eventId: 'event-1');
    await repository.commit(
      LearningCommit(
        commitId: 'commit-1',
        ownerId: 'owner-a',
        recordedAtUtc: _now,
        learningEvents: [event],
      ),
    );

    await expectLater(
      repository.commit(
        LearningCommit(
          commitId: 'commit-2',
          ownerId: 'owner-a',
          recordedAtUtc: _now,
          associations: [_association(id: 'association-new')],
          learningEvents: [event],
        ),
      ),
      throwsA(
        isA<LearningRepositoryException>().having(
          (error) => error.code,
          'code',
          LearningRepositoryErrorCode.writeConflict,
        ),
      ),
    );

    expect(await database.select(database.learningCommits).get(), hasLength(1));
    expect(await database.select(database.associations).get(), isEmpty);
    expect(await database.select(database.learningEvents).get(), hasLength(1));
  });

  test('never returns another owner records', () async {
    await repository.commit(
      _commit(commitId: 'commit-a', associationId: 'association-a'),
    );

    expect(
      await repository.readAssociations(ownerId: 'owner-b', wordKey: 'word-a'),
      isEmpty,
    );
    expect(
      await repository.readAssociations(ownerId: 'owner-a', wordKey: 'word-a'),
      hasLength(1),
    );
  });

  test('round trips session, memory and pending outbox records', () async {
    final session = ReadingSession(
      sessionId: 'session-1',
      ownerId: 'owner-a',
      cefrLevel: 'A2',
      targetWordKeys: const ['word-a'],
      mixPolicyVersion: 'mixer-v1',
      contentId: 'content-1',
      contentVersion: 'content-v1',
      currentStage: ReadingSessionStage.recall,
      startedAtUtc: _now,
      updatedAtUtc: _now,
    );
    final memory = MemoryState(
      ownerId: 'owner-a',
      wordKey: 'word-a',
      strength: 1.5,
      cueDependency: 0.25,
      stability: 2,
      difficulty: 4,
      lapseCount: 1,
      lastReviewedAtUtc: _now,
      nextDueAtUtc: _now.add(const Duration(days: 2)),
      lastErrorType: 'meaning',
      algorithmVersion: 'associative-v1',
      updatedAtUtc: _now,
    );
    final outbox = SyncOutboxEntry(
      outboxId: 'outbox-1',
      ownerId: 'owner-a',
      eventId: 'event-1',
      operation: OutboxOperation.recordProgressSession,
      payloadJson: jsonEncode({
        'sessionId': 'session-1',
        'eventIds': ['event-1'],
        'correctAnswers': 1,
        'completedAt': _now.toIso8601String(),
      }),
      createdAtUtc: _now,
    );

    await repository.commit(
      LearningCommit(
        commitId: 'commit-round-trip',
        ownerId: 'owner-a',
        recordedAtUtc: _now,
        sessions: [session],
        memoryStates: [memory],
        outboxEntries: [outbox],
      ),
    );

    expect(
      (await repository.readSession(
        ownerId: 'owner-a',
        sessionId: 'session-1',
      ))?.currentStage,
      ReadingSessionStage.recall,
    );
    expect(
      (await repository.readMemoryState(
        ownerId: 'owner-a',
        wordKey: 'word-a',
      ))?.cueDependency,
      0.25,
    );
    expect(
      await repository.readPendingOutbox(ownerId: 'owner-a'),
      hasLength(1),
    );
  });
}

final DateTime _now = DateTime.utc(2026, 7, 29, 10);

LearningCommit _commit({
  required String commitId,
  required String associationId,
}) {
  return LearningCommit(
    commitId: commitId,
    ownerId: 'owner-a',
    recordedAtUtc: _now,
    associations: [_association(id: associationId)],
  );
}

AssociationRecord _association({required String id}) {
  return AssociationRecord(
    associationId: id,
    ownerId: 'owner-a',
    wordKey: 'word-a',
    cueType: AssociationCueType.keyword,
    cueText: 'a private cue',
    origin: AssociationOrigin.userCreated,
    createdAtUtc: _now,
    updatedAtUtc: _now,
  );
}

LearningEvent _event({required String ownerId, required String eventId}) {
  return LearningEvent(
    eventId: eventId,
    schemaVersion: 1,
    pseudonymousUserId: ownerId,
    occurredAtUtc: _now,
    activity: LearningActivity.multipleChoiceQuiz,
    contentId: 'content-1',
    categoryId: 'category-1',
    cefrLevel: 'A2',
    skill: LearningSkill.meaningRecall,
    correct: true,
    score: 100,
    responseTimeMs: 1200,
    attemptNumber: 1,
    appVersion: '1.0.0',
    buildId: '1',
  );
}
