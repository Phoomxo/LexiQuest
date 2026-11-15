import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/features/learning/domain/source_reading_round.dart';

final _at = DateTime.utc(2026, 11, 15, 10);

void main() {
  test('reopened reading finishes only its original admitted answer', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-reading-',
    );
    final file = File('${directory.path}/round.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    try {
      await _seed(db);
      var repository = DriftLearningRepository(db);
      var round = await _open(repository, 'reading-a');
      expect(round.draft.phase, SourceReadingPhase.supported);
      await expectLater(repository.recordAnswer(_answer()), throwsStateError);

      Future<SourceReadingRound> save(
        SourceReadingPhase phase, {
        String text = '',
        String sentence = '',
        SourceReadingFirstRecall? first,
      }) => repository.saveSourceReadingRound(
        ownerId: 'owner-a',
        expected: round,
        draft: SourceReadingDraft(
          phase: phase,
          recall: [text],
          cues: const [''],
          sentence: sentence,
          first: first,
        ),
      );

      round = await save(SourceReadingPhase.reread);
      round = await save(SourceReadingPhase.recall, text: 'ctation');
      final beforeCheck = round;
      final first = (answers: const ['ctation'], checkedAtUtc: _at);
      round = await save(
        SourceReadingPhase.comparison,
        text: 'ctation',
        first: first,
      );
      await expectLater(repository.recordAnswer(_answer()), throwsStateError);
      final replay = await repository.saveSourceReadingRound(
        ownerId: 'owner-a',
        expected: beforeCheck,
        draft: round.draft,
      );
      expect(replay.revision, round.revision);
      await expectLater(
        repository.saveSourceReadingRound(
          ownerId: 'owner-a',
          expected: beforeCheck,
          draft: beforeCheck.draft,
        ),
        throwsStateError,
      );
      round = await save(
        SourceReadingPhase.correction,
        text: 'stat',
        first: first,
      );
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      repository = DriftLearningRepository(db);
      final reopened = await _open(repository, 'unused-reopen-id');
      expect(reopened.sessionId, round.sessionId);
      expect(reopened.revision, round.revision);
      expect(reopened.draft.recall, ['stat']);
      expect(reopened.draft.first!.answers, ['ctation']);
      round = reopened;
      round = await save(
        SourceReadingPhase.association,
        text: 'station',
        first: first,
      );
      round = await save(
        SourceReadingPhase.sentence,
        text: 'station',
        first: first,
      );
      round = await save(
        SourceReadingPhase.summary,
        text: 'station',
        sentence: 'I am at the station.',
        first: first,
      );
      await expectLater(
        repository.finishSourceReadingRound(
          ownerId: 'owner-a',
          expected: round,
          endedAtUtc: _at,
        ),
        throwsStateError,
      );
      await expectLater(
        repository.recordAnswer(_answer(correct: true)),
        throwsStateError,
      );
      expect((await repository.recordAnswer(_answer())).inserted, isTrue);
      expect((await repository.recordAnswer(_answer())).inserted, isFalse);
      final summary = await repository.finishSourceReadingRound(
        ownerId: 'owner-a',
        expected: round,
        endedAtUtc: _at,
      );
      expect(
        (
          summary.id,
          summary.state,
          summary.correctCount,
          summary.wrongCount,
          summary.score,
        ),
        ('reading-a', 'completed', 0, 1, 0),
      );
      final session = await db.select(db.learningSessions).getSingle();
      expect(session.continuationJson, isNull);
      expect(session.questionPlanJson, isNull);
      final sameResult = await repository.finishSourceReadingRound(
        ownerId: 'owner-a',
        expected: round,
        endedAtUtc: _at.add(const Duration(minutes: 1)),
      );
      expect((sameResult.id, sameResult.score), ('reading-a', 0));
      expect(await db.select(db.learningSessions).getSingle(), session);
      expect((await db.select(db.answerAttempts).getSingle()).id, _answer().id);
      expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
      expect(await db.select(db.rewardTransactions).get(), isEmpty);
    } finally {
      await db.close();
      if (await file.exists()) await file.delete();
      await directory.delete();
    }
  });

  test('stale owner and same-revision vocabulary edits fail closed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final repository = DriftLearningRepository(db);
    final round = await _open(repository, 'reading-a');
    final draft = SourceReadingDraft(
      phase: SourceReadingPhase.reread,
      recall: const [''],
      cues: const [''],
      sentence: '',
    );
    await db.customStatement(
      "UPDATE vocabulary_words SET meaning='edited' WHERE id='station'",
    );
    await expectLater(
      repository.saveSourceReadingRound(
        ownerId: 'owner-a',
        expected: round,
        draft: draft,
      ),
      throwsA(isA<QuizVocabularyChanged>()),
    );
    await db.customStatement(
      "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
    );
    await db
        .into(db.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2));
    await expectLater(
      repository.saveSourceReadingRound(
        ownerId: 'owner-a',
        expected: round,
        draft: draft,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.saveSourceReadingRound(
        ownerId: 'owner-b',
        expected: round,
        draft: draft,
      ),
      throwsStateError,
    );
    expect(
      (await db.select(db.learningSessions).getSingle()).ownerId,
      'owner-a',
    );
    expect(await db.select(db.answerAttempts).get(), isEmpty);
    expect(await db.select(db.outboxOperations).get(), isEmpty);
  });

  test('a cue publishes only with its pinned transition to sentence', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    await db
        .into(db.associationRecords)
        .insert(
          AssociationRecordsCompanion.insert(
            id: 'prior-station-cue',
            ownerId: 'owner-a',
            wordKey: 'station',
            type: 'keyword',
            content: 'prior cue',
            createdAtUtcMs: 1,
          ),
        );
    final priorCue = await db.select(db.associationRecords).getSingle();
    final repository = DriftLearningRepository(db);
    var round = await _open(repository, 'reading-cue');
    final first = (answers: const ['station'], checkedAtUtc: _at);

    Future<SourceReadingRound> save(
      SourceReadingPhase phase, {
      SourceReadingFirstRecall? first,
      String cue = '',
    }) => repository.saveSourceReadingRound(
      ownerId: 'owner-a',
      expected: round,
      draft: SourceReadingDraft(
        phase: phase,
        recall: [first == null ? '' : 'station'],
        cues: [cue],
        sentence: '',
        first: first,
      ),
    );

    round = await save(SourceReadingPhase.reread);
    round = await save(SourceReadingPhase.recall);
    round = await save(SourceReadingPhase.association, first: first);
    const newCue = 'ป้ายรถไฟสีเขียว';
    round = await save(
      SourceReadingPhase.association,
      first: first,
      cue: newCue,
    );
    expect(await db.select(db.associationRecords).getSingle(), priorCue);
    final savedDraft = await db.select(db.learningSessions).getSingle();

    final words = db.update(db.vocabularyWords)
      ..where((row) => row.id.equals('station'));
    await words.write(const VocabularyWordsCompanion(meaning: Value('edited')));
    expect(
      (await db.select(db.vocabularyWords).getSingle()).localRevision,
      round.scope.words.single.localRevision,
    );
    await expectLater(
      save(SourceReadingPhase.sentence, first: first, cue: newCue),
      throwsA(isA<QuizVocabularyChanged>()),
    );
    expect(await db.select(db.learningSessions).getSingle(), savedDraft);
    expect(await db.select(db.associationRecords).getSingle(), priorCue);

    await words.write(const VocabularyWordsCompanion(meaning: Value('สถานี')));
    final sentence = await save(
      SourceReadingPhase.sentence,
      first: first,
      cue: newCue,
    );
    expect(sentence.draft.phase, SourceReadingPhase.sentence);
    final published = await db.select(db.associationRecords).getSingle();
    expect(published.ownerId, 'owner-a');
    expect(published.wordKey, 'station');
    expect(published.content, newCue);

    final replay = await save(
      SourceReadingPhase.sentence,
      first: first,
      cue: newCue,
    );
    expect(replay.revision, sentence.revision);
    expect(await db.select(db.associationRecords).getSingle(), published);
  });
}

Future<SourceReadingRound> _open(
  DriftLearningRepository repository,
  String id,
) => repository.openSourceReadingRound(
  session: LearningSessionDraft(
    id: id,
    ownerId: 'owner-a',
    activityType: 'associativeReading',
    startedAtUtc: _at,
    appVersion: 'test',
    buildId: 'test',
  ),
  scope: SourceReadingScope(
    categoryId: 'category-a',
    documentId: 'local-source:reading-a',
    documentRevision: 1,
    passageDigest: 'a' * 64,
    words: const [
      QuizWord(
        id: 'station',
        categoryId: 'category-a',
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
      ),
    ],
  ),
);

RecordAnswerCommand _answer({bool correct = false}) => RecordAnswerCommand(
  id: 'attempt:reading-a:associative:0',
  ownerId: 'owner-a',
  sessionId: 'reading-a',
  wordId: 'station',
  promptMode: 'associativeRecall',
  isCorrect: correct,
  responseTimeMs: null,
  attemptNumber: 1,
  occurredAtUtc: _at,
);

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1));
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-a',
          ownerId: 'owner-a',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'station',
          ownerId: 'owner-a',
          categoryId: 'category-a',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          localRevision: const Value(1),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}
