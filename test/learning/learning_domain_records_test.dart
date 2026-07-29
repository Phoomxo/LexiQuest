import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/deletion_tombstone.dart';
import 'package:vocab_learning_app/learning/learning_commit.dart';
import 'package:vocab_learning_app/learning/learning_event.dart';
import 'package:vocab_learning_app/learning/learning_repository.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/sync_outbox_entry.dart';

const _ownerId = 'owner-1';
final _now = DateTime.utc(2026, 7, 29, 8);

AssociationRecord _association({String ownerId = _ownerId}) {
  return AssociationRecord(
    associationId: 'association-1',
    ownerId: ownerId,
    wordKey: 'resilient',
    cueType: AssociationCueType.personalStory,
    cueText: 'The tree recovered after the storm.',
    origin: AssociationOrigin.userCreated,
    createdAtUtc: _now,
    updatedAtUtc: _now,
  );
}

ReadingSession _session({String ownerId = _ownerId}) {
  return ReadingSession(
    sessionId: 'session-1',
    ownerId: ownerId,
    cefrLevel: 'B1',
    targetWordKeys: const ['resilient', 'recover'],
    mixPolicyVersion: 'mixer-v1',
    contentId: 'curated-b1-1',
    contentVersion: '1',
    currentStage: ReadingSessionStage.supportedReading,
    startedAtUtc: _now,
    updatedAtUtc: _now,
  );
}

RecallAttempt _attempt({String ownerId = _ownerId}) {
  return RecallAttempt(
    attemptId: 'attempt-1',
    ownerId: ownerId,
    sessionId: 'session-1',
    wordKey: 'resilient',
    recallMode: RecallMode.unaided,
    cueLevel: RecallCueLevel.none,
    correctness: true,
    responseTimeMs: 850,
    confidence: 4,
    algorithmVersion: 'associative-v1',
    occurredAtUtc: _now,
  );
}

MemoryState _memoryState({String ownerId = _ownerId}) {
  return MemoryState(
    ownerId: ownerId,
    wordKey: 'resilient',
    strength: 2,
    cueDependency: 0.1,
    stability: 3,
    difficulty: 4,
    lapseCount: 0,
    nextDueAtUtc: _now.add(const Duration(days: 3)),
    updatedAtUtc: _now,
    algorithmVersion: 'associative-v1',
  );
}

LearningEvent _event({String ownerId = _ownerId}) {
  return LearningEvent(
    eventId: 'event-1',
    schemaVersion: 1,
    pseudonymousUserId: ownerId,
    occurredAtUtc: _now,
    activity: LearningActivity.multipleChoiceQuiz,
    contentId: 'word:resilient',
    categoryId: null,
    cefrLevel: 'B1',
    skill: LearningSkill.meaningRecall,
    correct: true,
    score: 100,
    responseTimeMs: 850,
    attemptNumber: 1,
    appVersion: '1.0.0+1',
    buildId: 'build-1',
  );
}

SyncOutboxEntry _outbox({String ownerId = _ownerId}) {
  return SyncOutboxEntry(
    outboxId: 'outbox-1',
    ownerId: ownerId,
    eventId: 'event-1',
    operation: OutboxOperation.recordProgressSession,
    payloadJson: '{"sessionId":"session-1"}',
    createdAtUtc: _now,
  );
}

DeletionTombstone _tombstone({String ownerId = _ownerId}) {
  return DeletionTombstone(
    tombstoneId: 'tombstone-1',
    ownerId: ownerId,
    entityType: TombstoneEntityType.association,
    entityId: 'association-1',
    deletedAtUtc: _now,
  );
}

final class _ContractRepository implements LearningRepository {
  @override
  Future<CommitResult> commit(LearningCommit commit) async {
    return CommitResult(
      commitId: commit.commitId,
      disposition: CommitDisposition.applied,
      writtenRecords: commit.recordCount,
    );
  }
}

void main() {
  group('immutable learning records', () {
    test('normalize timestamps to UTC and expose immutable target words', () {
      final localTime = DateTime(2026, 7, 29, 15);
      final sourceWords = <String>['resilient', 'recover'];
      final session = ReadingSession(
        sessionId: 'session-1',
        ownerId: _ownerId,
        cefrLevel: 'B1',
        targetWordKeys: sourceWords,
        mixPolicyVersion: 'mixer-v1',
        contentId: 'curated-b1-1',
        contentVersion: '1',
        currentStage: ReadingSessionStage.supportedReading,
        startedAtUtc: localTime,
        updatedAtUtc: localTime,
      );

      sourceWords.add('mutated');

      expect(session.startedAtUtc.isUtc, isTrue);
      expect(session.updatedAtUtc.isUtc, isTrue);
      expect(session.targetWordKeys, ['resilient', 'recover']);
      expect(
        () => session.targetWordKeys.add('blocked'),
        throwsUnsupportedError,
      );
    });

    test('reject blank ownership and invalid recall evidence', () {
      expect(() => _association(ownerId: ' \t'), throwsArgumentError);
      expect(
        () => RecallAttempt(
          attemptId: 'attempt-invalid',
          ownerId: _ownerId,
          sessionId: 'session-1',
          wordKey: 'resilient',
          recallMode: RecallMode.unaided,
          cueLevel: RecallCueLevel.none,
          correctness: false,
          responseTimeMs: -1,
          confidence: 0,
          algorithmVersion: 'associative-v1',
          occurredAtUtc: _now,
        ),
        throwsArgumentError,
      );
    });

    test('reject non-finite or out-of-range memory projections', () {
      expect(
        () => MemoryState(
          ownerId: _ownerId,
          wordKey: 'resilient',
          strength: double.infinity,
          cueDependency: 0,
          stability: 1,
          difficulty: 5,
          lapseCount: 0,
          nextDueAtUtc: _now,
          updatedAtUtc: _now,
          algorithmVersion: 'associative-v1',
        ),
        throwsArgumentError,
      );
      expect(
        () => MemoryState(
          ownerId: _ownerId,
          wordKey: 'resilient',
          strength: 1,
          cueDependency: 1.1,
          stability: 1,
          difficulty: 5,
          lapseCount: 0,
          nextDueAtUtc: _now,
          updatedAtUtc: _now,
          algorithmVersion: 'associative-v1',
        ),
        throwsArgumentError,
      );
    });

    test('terminal session stages require the matching UTC timestamp', () {
      expect(
        () => ReadingSession(
          sessionId: 'session-completed',
          ownerId: _ownerId,
          cefrLevel: 'B1',
          targetWordKeys: const ['resilient'],
          mixPolicyVersion: 'mixer-v1',
          contentId: 'curated-b1-1',
          contentVersion: '1',
          currentStage: ReadingSessionStage.completed,
          startedAtUtc: _now,
          updatedAtUtc: _now,
        ),
        throwsArgumentError,
      );

      final completed = ReadingSession(
        sessionId: 'session-completed',
        ownerId: _ownerId,
        cefrLevel: 'B1',
        targetWordKeys: const ['resilient'],
        mixPolicyVersion: 'mixer-v1',
        contentId: 'curated-b1-1',
        contentVersion: '1',
        currentStage: ReadingSessionStage.completed,
        startedAtUtc: _now,
        updatedAtUtc: _now,
        completedAtUtc: _now,
      );

      expect(completed.completedAtUtc, _now);
      expect(completed.abandonedAtUtc, isNull);
    });

    test('outbox and tombstone reject sensitive or text-bearing payloads', () {
      expect(
        () => SyncOutboxEntry(
          outboxId: 'outbox-bad',
          ownerId: _ownerId,
          eventId: 'event-1',
          operation: OutboxOperation.recordProgressSession,
          payloadJson: '{"token":"secret"}',
          createdAtUtc: _now,
        ),
        throwsArgumentError,
      );
      expect(
        () => DeletionTombstone(
          tombstoneId: 'tombstone-bad',
          ownerId: _ownerId,
          entityType: TombstoneEntityType.association,
          entityId: 'a' * 201,
          deletedAtUtc: _now,
        ),
        throwsArgumentError,
      );
    });
  });

  group('LearningCommit', () {
    test('owns an immutable atomic batch with every durable record type', () {
      final associations = <AssociationRecord>[_association()];
      final commit = LearningCommit(
        commitId: 'commit-1',
        ownerId: _ownerId,
        recordedAtUtc: _now,
        associations: associations,
        sessions: [_session()],
        recallAttempts: [_attempt()],
        memoryStates: [_memoryState()],
        learningEvents: [_event()],
        outboxEntries: [_outbox()],
        tombstones: [_tombstone()],
      );

      associations.clear();

      expect(commit.recordedAtUtc.isUtc, isTrue);
      expect(commit.associations, hasLength(1));
      expect(commit.recordCount, 7);
      expect(() => commit.associations.clear(), throwsUnsupportedError);
    });

    test('rejects an empty batch or a record owned by another account', () {
      expect(
        () => LearningCommit(
          commitId: 'commit-empty',
          ownerId: _ownerId,
          recordedAtUtc: _now,
        ),
        throwsArgumentError,
      );
      expect(
        () => LearningCommit(
          commitId: 'commit-cross-owner',
          ownerId: _ownerId,
          recordedAtUtc: _now,
          sessions: [_session(ownerId: 'owner-2')],
        ),
        throwsArgumentError,
      );
    });

    test('CommitResult distinguishes applied and duplicate commits', () {
      const applied = CommitResult(
        commitId: 'commit-1',
        disposition: CommitDisposition.applied,
        writtenRecords: 3,
      );
      const duplicate = CommitResult(
        commitId: 'commit-1',
        disposition: CommitDisposition.alreadyApplied,
        writtenRecords: 0,
      );

      expect(applied.wasApplied, isTrue);
      expect(duplicate.wasApplied, isFalse);
    });
  });

  test('LearningRepository exposes the locked commit contract', () async {
    final repository = _ContractRepository();
    final commit = LearningCommit(
      commitId: 'commit-contract',
      ownerId: _ownerId,
      recordedAtUtc: _now,
      sessions: [_session()],
    );

    final result = await repository.commit(commit);

    expect(result.commitId, 'commit-contract');
    expect(result.wasApplied, isTrue);
  });

  test('CryptographicIdGenerator emits opaque non-timestamp identifiers', () {
    final generator = CryptographicIdGenerator();
    final ids = List<String>.generate(32, (_) => generator.nextId());

    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(id, isNot(matches(RegExp(r'^\d{10,}$'))));
    }
  });
}
