import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  late AppDatabase database;
  late VocabularyUseCases vocabulary;
  late DriftLearningRepository learning;
  late DriftProgressQueries progress;
  late String ownerId;
  late String categoryId;
  late List<QuizWord> words;
  final now = DateTime.utc(2026, 11, 14);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-history-owner',
      nowUtc: () => now,
    );
    ownerId = (await owners.getOrCreateActiveOwner()).id;
    var id = 0;
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-history-${++id}',
      nowUtc: () => now,
    );
    learning = DriftLearningRepository(database);
    progress = DriftProgressQueries(database);
    categoryId = (await vocabulary.createCategory('ชุดเดินทางเดิม')).id;
    for (final (spelling, meaning) in [
      ('platform', 'ชานชาลา'),
      ('ticket', 'ตั๋ว'),
    ]) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: categoryId,
          spelling: spelling,
          meaning: meaning,
          partOfSpeech: 'noun',
        ),
      );
    }
    words = await learning.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      limit: 2,
    );
  });

  Future<SessionHistoryEntry> history(String id) async =>
      (await progress.loadSession(ownerId: ownerId, sessionId: id))!;

  test(
    'Quiz history keeps original answers after edits and deletion',
    () async {
      const id = 'original-round';
      const options = ['ตั๋ว', 'ชานชาลา'];
      await learning.startSession(
        LearningSessionDraft(
          id: id,
          ownerId: ownerId,
          activityType: 'quiz',
          startedAtUtc: now,
          appVersion: 'test',
          buildId: 'test',
          quizPlan: QuizPlan(
            origin: QuizOrigin(
              route: 'category',
              categoryId: categoryId,
              promptKind: QuizPromptKind.meaningChoice,
            ),
            categoryName: 'ชุดเดินทางเดิม',
            questions: [
              for (final word in words)
                QuizQuestion(word: word, options: options),
            ],
          ),
        ),
      );

      var revision = 0;
      for (var slot = 0; slot < words.length; slot++) {
        final correct = slot == 1;
        final saved = await learning.recordAnswer(
          RecordAnswerCommand(
            id: 'original-answer-$slot',
            ownerId: ownerId,
            sessionId: id,
            wordId: words[slot].id,
            promptMode: 'meaningChoice',
            isCorrect: correct,
            responseTimeMs: 400,
            attemptNumber: slot + 1,
            occurredAtUtc: now.add(Duration(seconds: slot * 2 + 1)),
            quiz: (
              expectedRevision: revision,
              response: (slot: slot, selectedOption: 0),
            ),
          ),
        );
        final moved = await learning.advanceQuizRound(
          ownerId: ownerId,
          sessionId: id,
          expectedRevision: saved.durableRound!.cursor.revision,
          step: correct ? QuizStep.finish : QuizStep.next,
          atUtc: now.add(Duration(seconds: slot * 2 + 2)),
        );
        revision = moved.cursor.revision;
      }

      final first = await history(id);
      expect(first.mistakes.single.spelling, 'platform');
      expect(first.summary.score, 50);

      await vocabulary.updateWord(
        UpdateWordCommand(
          id: words.first.id,
          categoryId: categoryId,
          spelling: 'railway platform',
          meaning: 'ชานชาลารถไฟ',
          partOfSpeech: 'noun',
        ),
      );
      await vocabulary.renameCategory(categoryId, 'ชุดเดินทางใหม่');
      final edited = await history(id);
      expect(edited.categoryId, categoryId);
      expect(edited.categoryName, 'ชุดเดินทางเดิม');
      expect(edited.mistakes.single.id, words.first.id);
      expect(edited.mistakes.single.spelling, 'railway platform');
      expect(edited.mistakes.single.meaning, 'ชานชาลารถไฟ');

      await vocabulary.deleteWord(words.first.id);
      final deleted = await history(id);
      expect(deleted.mistakes, isEmpty);
      expect(deleted.categoryName, 'ชุดเดินทางเดิม');
      for (final entry in [first, edited, deleted]) {
        expect(
          (
            entry.summary.id,
            entry.summary.score,
            entry.summary.correctCount,
            entry.summary.wrongCount,
          ),
          (id, 50, 1, 1),
        );
        final original = entry.originalAnswers!;
        expect(original, hasLength(2));
        expect(
          original.map(
            (a) => (a.question.promptText, a.chosenAnswer, a.isCorrect),
          ),
          [('platform', 'ตั๋ว', false), ('ticket', 'ตั๋ว', true)],
        );
        expect(original.first.question.options, options);
        expect(original.first.question.word.meaning, 'ชานชาลา');
        expect(
          original.first.question.word.localRevision,
          words.first.localRevision,
        );
      }
      expect(
        await progress.loadSession(ownerId: 'different-owner', sessionId: id),
        isNull,
      );
    },
  );

  test(
    'legacy history keeps counts and marks original answers unavailable',
    () async {
      const id = 'legacy-round';
      await learning.startSession(
        LearningSessionDraft(
          id: id,
          ownerId: ownerId,
          activityType: 'quiz',
          startedAtUtc: now,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
      await learning.recordAnswer(
        RecordAnswerCommand(
          id: 'legacy-answer',
          ownerId: ownerId,
          sessionId: id,
          wordId: words.first.id,
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 400,
          attemptNumber: 1,
          occurredAtUtc: now,
        ),
      );
      await learning.finishSession(
        ownerId: ownerId,
        sessionId: id,
        endedAtUtc: now.add(const Duration(seconds: 1)),
      );

      final entry = await history(id);
      expect(entry.summary.score, 0);
      expect(entry.summary.wrongCount, 1);
      expect(entry.mistakes.single.spelling, 'platform');
      expect(entry.originalAnswers, isNull);
    },
  );
}
