import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/local_learning_repository.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';

void main() {
  group('B1 Domain Records & Local Learning Repository Tests', () {
    final now = DateTime.utc(2026, 7, 27, 10, 0, 0);

    test('AssociationRecord serializes and deserializes correctly', () {
      final record = AssociationRecord(
        associationId: 'assoc-1',
        ownerId: 'user-123',
        wordKey: 'ephemeral',
        cueType: CueType.personalStory,
        cueText: 'Fleeting like morning dew on leaves.',
        source: AssociationSource.user,
        createdAt: now,
        updatedAt: now,
      );

      final json = record.toJson();
      final restored = AssociationRecord.fromJson(json);

      expect(restored.associationId, 'assoc-1');
      expect(restored.cueType, CueType.personalStory);
      expect(restored.cueText, 'Fleeting like morning dew on leaves.');
      expect(restored.privacy, AssociationPrivacy.private);
      expect(restored.schemaVersion, 1);
    });

    test('AssociationRecord rejects empty or oversized cueText', () {
      expect(
        () => AssociationRecord(
          associationId: 'a1',
          ownerId: 'u1',
          wordKey: 'w1',
          cueType: CueType.keyword,
          cueText: '',
          source: AssociationSource.user,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      final longText = 'a' * 501;
      expect(
        () => AssociationRecord(
          associationId: 'a2',
          ownerId: 'u1',
          wordKey: 'w1',
          cueType: CueType.keyword,
          cueText: longText,
          source: AssociationSource.user,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test(
      'RecallAttempt serializes correctly and validates confidence/latency',
      () {
        final attempt = RecallAttempt(
          attemptId: 'att-1',
          sessionId: 'sess-1',
          wordKey: 'ephemeral',
          recallMode: RecallMode.cloze,
          cueLevel: CueLevel.associationHint,
          correctness: true,
          responseTimeMs: 850,
          confidence: 4,
          occurredAt: now,
        );

        final json = attempt.toJson();
        final restored = RecallAttempt.fromJson(json);

        expect(restored.attemptId, 'att-1');
        expect(restored.correctness, true);
        expect(restored.confidence, 4);

        expect(
          () => RecallAttempt(
            attemptId: 'att-2',
            sessionId: 'sess-1',
            wordKey: 'ephemeral',
            recallMode: RecallMode.cloze,
            cueLevel: CueLevel.none,
            correctness: false,
            responseTimeMs: -10,
            confidence: 3,
            occurredAt: now,
          ),
          throwsArgumentError,
        );
      },
    );

    test('MemoryState and ReadingSession round-trip serialization', () {
      final state = MemoryState(
        ownerId: 'user-123',
        wordKey: 'ephemeral',
        strength: 2.5,
        cueDependency: 0.2,
        stability: 3.0,
        difficulty: 4.5,
        lapseCount: 1,
        nextDueAt: now.add(const Duration(days: 3)),
      );

      final restoredState = MemoryState.fromJson(state.toJson());
      expect(restoredState.ownerId, 'user-123');
      expect(restoredState.stability, 3.0);

      final session = ReadingSession(
        sessionId: 'sess-100',
        ownerId: 'user-123',
        cefrLevel: 'B2',
        targetWordKeys: ['ephemeral', 'resilient'],
        contentId: 'story-42',
        startedAt: now,
      );

      final restoredSession = ReadingSession.fromJson(session.toJson());
      expect(restoredSession.sessionId, 'sess-100');
      expect(restoredSession.targetWordKeys, ['ephemeral', 'resilient']);
    });

    test('LocalLearningRepository persists and retrieves records', () async {
      final repo = LocalLearningRepository();
      final record = AssociationRecord(
        associationId: 'assoc-99',
        ownerId: 'user-777',
        wordKey: 'tenacious',
        cueType: CueType.synonym,
        cueText: 'Persistent / stubborn',
        source: AssociationSource.curated,
        createdAt: now,
        updatedAt: now,
      );

      await repo.saveAssociation(record);
      final fetched = await repo.getAssociation('assoc-99');
      expect(fetched?.cueText, 'Persistent / stubborn');

      final list = await repo.getAssociationsForWord('user-777', 'tenacious');
      expect(list.length, 1);

      await repo.deleteAssociation('assoc-99');
      expect(await repo.getAssociation('assoc-99'), isNull);
    });
  });
}
