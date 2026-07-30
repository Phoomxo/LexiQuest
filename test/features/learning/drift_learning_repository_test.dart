import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  test('quiz words come from active local vocabulary for the owner', () async {
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      categoryId: 'category-1',
      limit: 10,
    );

    expect(words.map((word) => word.id), ['word-1', 'word-2']);
    expect(words.first.meaning, 'สถานี');
  });

  test('answer transaction is idempotent and updates SRS and points', () async {
    const session = LearningSessionDraft(
      id: 'session-1',
      ownerId: 'owner-1',
      activityType: 'quiz',
      startedAtUtc: null,
      appVersion: '1.0.0',
      buildId: 'test',
    );
    await repository.startSession(
      session.copyWith(startedAtUtc: DateTime.utc(2026, 7, 30, 10)),
    );
    final command = RecordAnswerCommand(
      id: 'attempt-1',
      ownerId: 'owner-1',
      sessionId: 'session-1',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 420,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
    );

    final first = await repository.recordAnswer(command);
    final replay = await repository.recordAnswer(command);

    expect(first.inserted, isTrue);
    expect(replay.inserted, isFalse);
    expect(replay.srs.intervalDays, 1);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    final storedSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('session-1'))).getSingle();
    expect(storedSession.correctCount, 1);
    expect(storedSession.wrongCount, 0);
  });

  test('finishing session stores auditable score and counts', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    await repository.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 800,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );

    final result = await repository.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
    );

    expect(result.state, 'completed');
    expect(result.correctCount, 0);
    expect(result.wrongCount, 1);
    expect(result.score, 0);
  });

  test('reading progress is monotonic and completion is idempotent', () async {
    final first = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-1',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 80,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
      ),
    );
    final rewound = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-2',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 30,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );
    final completed = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );
    final replay = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );

    expect(first.lastPosition, 80);
    expect(rewound.lastPosition, 80);
    expect(completed.isCompleted, isTrue);
    expect(replay, completed);
    expect(await database.select(database.readingEvents).get(), hasLength(3));
  });
}
