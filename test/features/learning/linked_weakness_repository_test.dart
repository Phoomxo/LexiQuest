import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/quiz_round.dart';

final _at = DateTime.utc(2026, 11, 15, 10);

void main() {
  late AppDatabase db;
  late DriftLearningRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(db);
    await _seed(db, 'a', active: true);
    await _seed(db, 'b', active: false);
  });
  tearDown(() => db.close());

  Future<void> createParent({
    String id = 'parent',
    String owner = 'a',
    String activity = 'quiz',
    bool completed = true,
  }) async {
    await repository.startSession(
      _session(id, owner: owner, activity: activity),
    );
    for (final (index, answer) in [
      ('missed', false),
      ('correct', true),
    ].indexed) {
      await repository.recordAnswer(
        RecordAnswerCommand(
          id: 'attempt:$id:$index',
          ownerId: 'owner-$owner',
          sessionId: id,
          wordId: '${answer.$1}-$owner',
          promptMode: activity == 'srsReview' ? 'srsRecall' : 'meaningChoice',
          isCorrect: answer.$2,
          responseTimeMs: null,
          attemptNumber: index + 1,
          occurredAtUtc: _at,
        ),
      );
    }
    if (completed) {
      await repository.finishSession(
        ownerId: 'owner-$owner',
        sessionId: id,
        endedAtUtc: _at,
      );
    }
  }

  for (final condition in ['missing', 'foreign', 'incomplete', 'assessment']) {
    test(
      'linked weakness rejects a $condition parent before inserting',
      () async {
        switch (condition) {
          case 'foreign':
            await _selectOwner(db, 'b');
            await createParent(owner: 'b');
            await _selectOwner(db, 'a');
          case 'incomplete':
            await createParent(completed: false);
          case 'assessment':
            await createParent(activity: 'assessment');
        }
        final before = await db.select(db.learningSessions).get();
        await expectLater(repository.startSession(_linked()), throwsStateError);
        expect(await db.select(db.learningSessions).get(), before);
      },
    );
  }

  for (final target in ['correct-a', 'unrelated-a']) {
    test('linked weakness rejects non-missed target $target', () async {
      await createParent();
      final before = await db.select(db.learningSessions).get();
      await expectLater(
        repository.startSession(_linked(target: target)),
        throwsStateError,
      );
      await expectLater(
        repository.startSession(_linked(requested: ['missed-a', target])),
        throwsStateError,
      );
      expect(await db.select(db.learningSessions).get(), before);
    });
  }

  for (final activity in ['quiz', 'sourcePractice', 'srsReview']) {
    test(
      'linked weakness opens from a completed owned $activity miss',
      () async {
        await createParent(activity: activity);
        final draft = _linked();
        final before = await db.select(db.answerAttempts).get();
        await repository.startSession(draft);
        final opened = await repository.findOpenQuizRound(
          ownerId: draft.ownerId,
          origin: draft.quizPlan!.origin,
        );
        expect(opened?.sessionId, draft.id);
        expect(opened?.plan.questions.single.word.id, 'missed-a');
        expect(await db.select(db.answerAttempts).get(), before);
      },
    );
  }

  test(
    'linked weakness uses compatible v25 misses without changing them',
    () async {
      await createParent();
      final parentQuery = db.select(db.learningSessions)
        ..where((row) => row.id.equals('parent'));
      await (db.update(
        db.learningSessions,
      )..where((row) => row.id.equals('parent'))).write(
        const LearningSessionsCompanion(
          legacyEvidenceDisposition: Value('base-v25'),
        ),
      );
      await (db.update(
        db.answerAttempts,
      )..where((row) => row.sessionId.equals('parent'))).write(
        const AnswerAttemptsCompanion(
          legacyEvidenceDisposition: Value('base-v25'),
        ),
      );
      final parentBefore = await parentQuery.getSingle();
      final attemptsBefore = await db.select(db.answerAttempts).get();
      final draft = _linked();
      await repository.startSession(draft);
      final child = await repository.findOpenQuizRound(
        ownerId: draft.ownerId,
        origin: draft.quizPlan!.origin,
      );
      expect(child?.plan.questions.single.word.id, 'missed-a');
      expect(await parentQuery.getSingle(), parentBefore);
      expect(await db.select(db.answerAttempts).get(), attemptsBefore);
    },
  );

  test(
    'linked weakness rejects an assessment-session ID even with quiz activity',
    () async {
      const parentId = 'assessment-session:misclassified';
      await createParent(id: parentId);
      await expectLater(
        repository.startSession(_linked(parent: parentId)),
        throwsStateError,
      );
      expect(await db.select(db.learningSessions).get(), hasLength(1));
    },
  );

  for (final change in ['owner', 'mistake']) {
    test(
      'linked weakness will not resume after the parent loses its $change',
      () async {
        await createParent();
        final draft = _linked();
        await repository.startSession(draft);
        if (change == 'owner') {
          await (db.update(
            db.learningSessions,
          )..where((row) => row.id.equals('parent'))).write(
            const LearningSessionsCompanion(ownerId: Value('owner-b')),
          );
        } else {
          await (db.update(db.answerAttempts)
                ..where((row) => row.id.equals('attempt:parent:0')))
              .write(const AnswerAttemptsCompanion(isCorrect: Value(true)));
        }
        final before = await db.select(db.learningSessions).get();
        await expectLater(
          repository.findOpenQuizRound(
            ownerId: draft.ownerId,
            origin: draft.quizPlan!.origin,
          ),
          throwsStateError,
        );
        expect(await db.select(db.learningSessions).get(), before);
      },
    );
  }

  test(
    'an already open paused linked quiz cannot resume after losing its parent',
    () async {
      await createParent();
      final draft = _linked();
      await repository.startSession(draft);
      final opened = (await repository.loadQuizRound(
        ownerId: draft.ownerId,
        sessionId: draft.id,
      ))!;
      final paused = await repository.advanceQuizRound(
        ownerId: draft.ownerId,
        sessionId: draft.id,
        expectedRevision: opened.cursor.revision,
        step: QuizStep.pause,
        atUtc: _at,
      );
      expect(paused.isPaused, isTrue);
      await (db.update(db.learningSessions)
            ..where((row) => row.id.equals('parent')))
          .write(const LearningSessionsCompanion(state: Value('active')));
      final before = await db.select(db.learningSessions).get();
      await expectLater(
        repository.advanceQuizRound(
          ownerId: draft.ownerId,
          sessionId: draft.id,
          expectedRevision: paused.cursor.revision,
          step: QuizStep.resume,
          atUtc: _at,
        ),
        throwsStateError,
      );
      expect(await db.select(db.learningSessions).get(), before);
    },
  );

  test(
    'unlinked weakness does not require an unrelated historical parent',
    () async {
      final draft = _linked(parent: null, target: 'unrelated-a');
      await repository.startSession(draft);
      final opened = await repository.findOpenQuizRound(
        ownerId: draft.ownerId,
        origin: draft.quizPlan!.origin,
      );
      expect(opened?.plan.questions.single.word.id, 'unrelated-a');
    },
  );
}

const _words = {
  'missed': ('station', 'สถานี'),
  'correct': ('ticket', 'ตั๋ว'),
  'unrelated': ('bus', 'รถเมล์'),
};

LearningSessionDraft _session(
  String id, {
  required String owner,
  required String activity,
  QuizPlan? plan,
}) => LearningSessionDraft(
  id: id,
  ownerId: 'owner-$owner',
  activityType: activity,
  startedAtUtc: _at,
  appVersion: 'test',
  buildId: 'test',
  quizPlan: plan,
);

LearningSessionDraft _linked({
  String? parent = 'parent',
  String target = 'missed-a',
  List<String>? requested,
}) {
  final (spelling, meaning) = _words[target.split('-').first]!;
  final alternative = _words.values.firstWhere((pair) => pair.$2 != meaning).$2;
  return _session(
    'child',
    owner: 'a',
    activity: 'weaknessPractice',
    plan: QuizPlan(
      origin: QuizOrigin(
        route: 'weakness',
        promptKind: QuizPromptKind.meaningChoice,
        wordIds: requested ?? [target],
        parentId: parent,
      ),
      questions: [
        QuizQuestion(
          word: QuizWord(
            id: target,
            categoryId: 'category-a',
            spelling: spelling,
            meaning: meaning,
            partOfSpeech: 'noun',
          ),
          options: [meaning, alternative],
        ),
      ],
    ),
  );
}

Future<void> _selectOwner(AppDatabase db, String owner) async {
  await db.customStatement('UPDATE local_owners SET is_active = id = ?', [
    'owner-$owner',
  ]);
}

Future<void> _seed(AppDatabase db, String owner, {required bool active}) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'owner-$owner',
          createdAtUtcMs: 1,
          isActive: Value(active),
        ),
      );
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-$owner',
          ownerId: 'owner-$owner',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final entry in _words.entries) {
    final (spelling, meaning) = entry.value;
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: '${entry.key}-$owner',
            categoryId: 'category-$owner',
            ownerId: 'owner-$owner',
            spelling: spelling,
            normalizedSpelling: spelling,
            meaning: meaning,
            normalizedMeaning: meaning,
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
}
