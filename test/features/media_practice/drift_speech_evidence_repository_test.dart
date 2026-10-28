import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/media_practice/data/drift_speech_evidence_repository.dart';
import 'package:vocab_learning_app/features/media_practice/domain/speech_evidence_use_cases.dart';

final _occurred = DateTime.utc(2026, 7, 31, 12);

void main() {
  late AppDatabase database;
  late DriftSpeechEvidenceRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftSpeechEvidenceRepository(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
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
            id: 'word-1',
            ownerId: 'owner-1',
            categoryId: 'category-1',
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
            id: 'session-1',
            ownerId: 'owner-1',
            activityType: 'shadowing',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
  });

  tearDown(() => database.close());

  test('records a real speech evidence row and returns its id', () async {
    final id = await repository.recordSpeechEvidence(
      RecordSpeechEvidenceCommand(
        id: 'speech-evidence:1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'shadowing',
        targetContent: 'cat',
        recognizedTranscript: 'cat',
        locale: 'en-US',
        sttEngine: 'platform-speech-recognizer',
        similarityAlgorithm: 'transcript-edit-distance-v1',
        similarityScore: 100,
        isExactMatch: true,
        recognitionConfidence: 0.9,
        sampleSize: 1,
        unavailableReason: null,
        occurredAtUtc: _occurred,
      ),
    );

    expect(id, 'speech-evidence:1');
    final rows = await database.select(database.speechEvidence).get();
    expect(rows, hasLength(1));
    final evidence = rows.single;
    expect(evidence.ownerId, 'owner-1');
    expect(evidence.sessionId, 'session-1');
    expect(evidence.recognizedTranscript, 'cat');
    expect(evidence.similarityScore, 100);
    expect(evidence.isExactMatch, isTrue);
    expect(evidence.recognitionConfidence, 0.9);
    expect(evidence.unavailableReason, isNull);
  });

  test('records an unavailable reason without a score', () async {
    await repository.recordSpeechEvidence(
      RecordSpeechEvidenceCommand(
        id: 'speech-evidence:silence',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'shadowing',
        targetContent: 'cat',
        recognizedTranscript: '',
        locale: 'en-US',
        sttEngine: 'platform-speech-recognizer',
        similarityAlgorithm: 'transcript-edit-distance-v1',
        similarityScore: null,
        isExactMatch: false,
        recognitionConfidence: null,
        sampleSize: 0,
        unavailableReason: 'silence',
        occurredAtUtc: _occurred,
      ),
    );

    final evidence = await (database.select(
      database.speechEvidence,
    )..where((row) => row.id.equals('speech-evidence:silence'))).getSingle();
    expect(evidence.similarityScore, isNull);
    expect(evidence.unavailableReason, 'silence');
  });

  test('stamps the occurred timestamp from the command', () async {
    await repository.recordSpeechEvidence(
      RecordSpeechEvidenceCommand(
        id: 'speech-evidence:ts',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'shadowing',
        targetContent: 'cat',
        recognizedTranscript: 'cat',
        locale: 'en-US',
        sttEngine: 'platform-speech-recognizer',
        similarityAlgorithm: 'transcript-edit-distance-v1',
        similarityScore: 80,
        isExactMatch: false,
        recognitionConfidence: null,
        sampleSize: 1,
        unavailableReason: null,
        occurredAtUtc: _occurred,
        durationMs: 1234,
      ),
    );

    final evidence = await (database.select(
      database.speechEvidence,
    )..where((row) => row.id.equals('speech-evidence:ts'))).getSingle();
    expect(evidence.durationMs, 1234);
    expect(evidence.occurredAtUtcMs, greaterThan(0));
  });
}
