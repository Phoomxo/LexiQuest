import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('inserts and reads a real speech evidence row', () async {
    await _insertBaselineDependencies(database);

    await database
        .into(database.speechEvidence)
        .insert(
          SpeechEvidenceCompanion.insert(
            id: 'speech-evidence:1',
            ownerId: 'local:guest',
            sessionId: 'session:1',
            wordId: 'word:cat',
            promptMode: 'shadowing',
            targetContent: 'cat',
            recognizedTranscript: 'cat',
            locale: 'en-US',
            sttEngine: 'platform-speech-recognizer',
            similarityAlgorithm: 'transcript-edit-distance-v1',
            similarityScore: const Value(100),
            isExactMatch: true,
            occurredAtUtcMs: 10,
          ),
        );

    final rows = await database.select(database.speechEvidence).get();
    expect(rows, hasLength(1));
    final evidence = rows.single;
    expect(evidence.id, 'speech-evidence:1');
    expect(evidence.promptMode, 'shadowing');
    expect(evidence.recognizedTranscript, 'cat');
    expect(evidence.sttEngine, 'platform-speech-recognizer');
    expect(evidence.similarityAlgorithm, 'transcript-edit-distance-v1');
    expect(evidence.similarityScore, 100);
    expect(evidence.isExactMatch, isTrue);
    expect(evidence.sampleSize, 1);
    expect(evidence.unavailableReason, isNull);
  });

  test('persists an unavailable reason without a score', () async {
    await _insertBaselineDependencies(database);

    await database
        .into(database.speechEvidence)
        .insert(
          SpeechEvidenceCompanion.insert(
            id: 'speech-evidence:silence',
            ownerId: 'local:guest',
            sessionId: 'session:1',
            wordId: 'word:cat',
            promptMode: 'shadowing',
            targetContent: 'cat',
            recognizedTranscript: '',
            locale: 'en-US',
            sttEngine: 'platform-speech-recognizer',
            similarityAlgorithm: 'transcript-edit-distance-v1',
            isExactMatch: false,
            unavailableReason: const Value('silence'),
            occurredAtUtcMs: 10,
          ),
        );

    final evidence = await (database.select(
      database.speechEvidence,
    )..where((row) => row.id.equals('speech-evidence:silence'))).getSingle();
    expect(evidence.similarityScore, isNull);
    expect(evidence.unavailableReason, 'silence');
  });

  test('deleting the session cascades to its speech evidence', () async {
    await _insertBaselineDependencies(database);
    await database
        .into(database.speechEvidence)
        .insert(
          SpeechEvidenceCompanion.insert(
            id: 'speech-evidence:2',
            ownerId: 'local:guest',
            sessionId: 'session:1',
            wordId: 'word:cat',
            promptMode: 'shadowing',
            targetContent: 'cat',
            recognizedTranscript: 'cat',
            locale: 'en-US',
            sttEngine: 'platform-speech-recognizer',
            similarityAlgorithm: 'transcript-edit-distance-v1',
            similarityScore: const Value(80),
            isExactMatch: false,
            occurredAtUtcMs: 20,
          ),
        );

    await (database.delete(
      database.learningSessions,
    )..where((row) => row.id.equals('session:1'))).go();

    final rows = await database.select(database.speechEvidence).get();
    expect(rows, isEmpty);
  });
}

Future<void> _insertBaselineDependencies(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'local:guest',
          accountState: const Value('localGuest'),
          createdAtUtcMs: 1,
          isActive: const Value(true),
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:animals',
          ownerId: 'local:guest',
          name: 'Animals',
          normalizedName: 'animals',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:cat',
          ownerId: 'local:guest',
          categoryId: 'category:animals',
          spelling: 'cat',
          normalizedSpelling: 'cat',
          meaning: 'แมว',
          normalizedMeaning: 'แมว',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:1',
          ownerId: 'local:guest',
          activityType: 'shadowing',
          state: 'active',
          startedAtUtcMs: 5,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
}
