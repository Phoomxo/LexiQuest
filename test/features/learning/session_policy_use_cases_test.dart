import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository repository;
  late LearningUseCases learning;
  var nextId = 0;

  void wire() {
    repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
      lexicalContent: DriftLearningPackRepository(
        database: h.database,
        ownerWrites: h.ownerWrites,
      ),
    );
    learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'synthetic-session-policy-${++nextId}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  }

  Future<ConfiguredQuizState> start({
    MeaningQuizDirection direction = MeaningQuizDirection.reverse,
    QuizHintPolicy hints = QuizHintPolicy.disabled,
    int limit = 1,
  }) async => learning.startConfiguredQuiz(
    await learning.prepareConfiguredQuiz(
      configuration: QuizConfiguration.category(
        categoryId: configuredCategoryId,
        direction: direction,
        hints: hints,
        limit: limit,
      ),
      expectedOwnerId: configuredOwnerId,
    ),
  );

  Future<ConfiguredQuizState> answer(
    ConfiguredQuizState state, {
    bool reveal = false,
  }) async {
    final question = state.plan.questions[state.checkpoint.questionOrdinal];
    final pending = await learning.prepareQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: state.checkpointRevision,
      selectedOptionOrdinal: reveal
          ? null
          : question.options.indexOf(question.correctAnswer),
      revealed: reveal,
    );
    return (await learning.commitQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: pending.checkpointRevision,
    )).state;
  }

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    nextId = 0;
    wire();
  });
  tearDown(() => h.close());

  test(
    'forward excludes sibling meanings and normalized duplicate choices',
    () async {
      for (final word in const [
        ('000-bank', ' Bank ', '  MONEY\t reserve '),
        ('001-bank', 'bank', 'river side'),
        ('002-money', 'fund', 'money reserve'),
        ('003-stop', 'station', '  Train  STOP '),
        ('004-stop', 'platform', 'train stop'),
      ]) {
        await h.addWord(id: word.$1, spelling: word.$2, meaning: word.$3);
      }
      final state = await start(
        direction: MeaningQuizDirection.forward,
        limit: 100,
      );
      final bank = state.plan.questions.first;
      expect(bank.word.id, '000-bank');
      expect(bank.correctAnswer, '  MONEY\t reserve ');
      expect(bank.options, contains(bank.correctAnswer));
      final labels = bank.options
          .map(
            (label) =>
                label.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
          )
          .toList();
      expect(labels, isNot(contains('river side')));
      expect(labels.toSet().length, labels.length);
      expect(labels, contains('train stop'));
      expect(labels.length, greaterThanOrEqualTo(2));
      final saved = await answer(state);
      expect(saved.checkpoint.answer!.isCorrect, isTrue);
      final attempt = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      expect(attempt.wordId, '000-bank');
      expect(attempt.isCorrect, isTrue);
    },
  );

  test(
    'forward scans later owner pages without scoring outside category words',
    () async {
      const outsideCategory = 'synthetic-owner-distractors';
      await h.database
          .into(h.database.vocabularyCategories)
          .insert(
            db.VocabularyCategoriesCompanion.insert(
              id: outsideCategory,
              ownerId: configuredOwnerId,
              name: 'Synthetic distractors',
              normalizedName: 'synthetic distractors',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await h.addWord(
        id: '000-bank',
        spelling: ' River\t BANK ',
        meaning: 'financial institution',
      );
      for (final word in const [
        ('001-river', 'shore', 'aaa river edge'),
        ('002-stop', 'station', 'bbb train stop'),
        ('003-fruit', 'orange', 'ccc fruit'),
        ('004-road', 'street', 'ddd road'),
      ]) {
        await h.addWord(
          id: word.$1,
          spelling: word.$2,
          meaning: word.$3,
          categoryId: outsideCategory,
        );
      }
      for (var i = 0; i < 100; i++) {
        await h.addWord(
          id: 'page-filler-${i.toString().padLeft(3, '0')}',
          spelling: 'filler $i',
          meaning: 'zzz filler $i',
          categoryId: outsideCategory,
        );
      }
      await h.addWord(
        id: 'zzz-bank-sibling',
        spelling: 'river bank',
        meaning: 'aaa river edge',
        categoryId: outsideCategory,
      );
      await h.addWord(
        id: '000-foreign',
        spelling: 'private',
        meaning: '000 foreign secret',
        ownerId: configuredOtherOwnerId,
        categoryId: configuredOtherCategoryId,
      );
      await h.addWord(
        id: 'deleted-bank-sibling',
        spelling: 'river bank',
        meaning: 'bbb train stop',
        categoryId: outsideCategory,
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
        ['deleted-bank-sibling'],
      );
      final state = await start(direction: MeaningQuizDirection.forward);
      final question = state.plan.questions.single;
      expect(question.word.id, '000-bank');
      expect(question.word.categoryId, configuredCategoryId);
      expect(
        question.options,
        unorderedEquals([
          'financial institution',
          'bbb train stop',
          'ccc fruit',
          'ddd road',
        ]),
      );
    },
  );

  test(
    'forward bank-only selection stays empty without writing state',
    () async {
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE owner_id = ?',
        [configuredOwnerId],
      );
      await h.addWord(id: 'bank-a', spelling: 'bank', meaning: 'money');
      await h.addWord(id: 'bank-b', spelling: 'BANK', meaning: 'river');
      final launch = await learning.prepareConfiguredQuiz(
        configuration: QuizConfiguration.category(
          categoryId: configuredCategoryId,
        ),
        expectedOwnerId: configuredOwnerId,
      );
      final before = await h.snapshot();
      await expectLater(
        learning.startConfiguredQuiz(launch),
        throwsA(
          isA<ConfiguredQuizUnavailable>().having(
            (error) => error.reason,
            'reason',
            ConfiguredQuizUnavailableReason.emptySelection,
          ),
        ),
      );
      expect(await h.snapshot(), before);
      expect(await h.count('learning_sessions'), 0);
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test(
    'saved one-option forward plan replays unchanged after vocabulary edits',
    () async {
      final launch = await learning.prepareConfiguredQuiz(
        configuration: QuizConfiguration.category(
          categoryId: configuredCategoryId,
          limit: 1,
        ),
        expectedOwnerId: configuredOwnerId,
      );
      final word = (await repository.listQuizWords(
        ownerId: configuredOwnerId,
        limit: 1,
      )).single;
      final original = await repository.startConfiguredQuiz(
        session: launch.session,
        plan: AcceptedQuizPlan.create(
          configuration: launch.configuration,
          questions: [
            QuizQuestion(word: word, options: [word.meaning]),
          ],
        ),
      );
      final planJson = original.plan.stableSerialization;
      await h.addWord(
        id: '000-new-sense',
        spelling: word.spelling,
        meaning: 'changed sense',
      );
      final before = await h.snapshot();
      final restored = await learning.startConfiguredQuiz(launch);
      expect(restored.restored, isTrue);
      expect(restored.plan.stableSerialization, planJson);
      expect(restored.plan.questions.single.options, [word.meaning]);
      expect(await h.snapshot(), before);
      expect((await answer(restored)).checkpoint.answer!.isCorrect, isTrue);
    },
  );

  test(
    'single-word reading and source-bound voice keep their presentation',
    () async {
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE owner_id = ? AND id <> ?',
        [configuredOwnerId, configuredWordIds.first],
      );
      final reading = await learning.startReading(limit: 1);
      expect(reading.questions.single.word.id, configuredWordIds.first);
      expect(reading.questions.single.options, ['สถานี']);
      final sourceReading = await learning.startReadingForWords(
        wordIds: [configuredWordIds.first],
        limit: 1,
      );
      expect(sourceReading.questions.single.options, ['สถานี']);
      final intent = (await learning.prepareSourceBoundVoicePracticeStart(
        expectedOwnerId: configuredOwnerId,
        practiceKind: VoiceLearningTimePracticeKind.shadowing,
        wordIds: [configuredWordIds.first],
        callerContext: LearningTimeCallerContext.ordinary,
        stillCurrent: () => true,
      ))!;
      expect(intent.presentation.questions.single.options, ['สถานี']);
      final voice = await learning.startSourceBoundVocabularySession(
        intent,
        operationStillCurrent: () => true,
      );
      expect(voice.questions.single.word.id, configuredWordIds.first);
      expect(voice.questions.single.options, ['สถานี']);
    },
  );

  test(
    'disabled hints reject contradictory earlier evidence after advancing',
    () async {
      final first = await answer(await start(limit: 2));
      final second = await learning.advanceQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
      );
      final row = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      final evidence =
          jsonDecode(row.evidenceContextJson) as Map<String, dynamic>;
      evidence['hintLevel'] = 1;
      evidence['evidenceClass'] = 'guidedPractice';
      await h.database.customStatement(
        'UPDATE answer_attempts SET evidence_context_json = ? WHERE id = ?',
        [jsonEncode(evidence), row.id],
      );
      final before = await h.snapshot();
      await expectLater(
        learning.resumeQuiz(
          sessionId: second.sessionId,
          expectedOwnerId: configuredOwnerId,
        ),
        throwsA(
          isA<ConfiguredQuizUnavailable>().having(
            (e) => e.reason,
            'reason',
            ConfiguredQuizUnavailableReason.corrupt,
          ),
        ),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'disabled hints allow earlier reveal evidence after advancing',
    () async {
      final first = await answer(await start(limit: 2), reveal: true);
      final second = await learning.advanceQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
      );
      final restored = await learning.resumeQuiz(
        sessionId: second.sessionId,
        expectedOwnerId: configuredOwnerId,
      );
      expect(restored.checkpoint.questionOrdinal, 1);
      expect(restored.plan.configuration.allowsHints, isFalse);
    },
  );

  test(
    'reverse choice uses word options and records recognition once',
    () async {
      final state = await start();
      final question = state.plan.questions.single;
      expect(question.prompt, question.word.meaning);
      expect(question.correctAnswer, question.word.spelling);
      expect(question.options.length, greaterThanOrEqualTo(2));
      expect(question.options, contains(question.word.spelling));
      expect(question.promptMode, 'meaningChoice');
      expect(question.unassistedEvidenceClass, EvidenceClass.recognition);
      final saved = await answer(state);
      expect(saved.checkpoint.answer!.isCorrect, isTrue);
      expect(
        saved.checkpoint.answer!.evidenceContext.evidenceClass,
        EvidenceClass.recognition,
      );
      await learning.commitQuizAnswer(
        sessionId: saved.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: saved.checkpointRevision - 1,
      );
      expect(await h.count('answer_attempts'), 1);
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'disabled hints reject direct and application writes without changing data',
    () async {
      final state = await start();
      final before = await h.snapshot();
      await expectLater(
        learning.setQuizHint(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          visible: true,
        ),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
      await expectLater(
        Future<void>.sync(() async {
          await repository.saveQuizCheckpoint(
            sessionId: state.sessionId,
            expectedOwnerId: configuredOwnerId,
            expectedRevision: state.checkpointRevision,
            checkpoint: state.bindCheckpointWrite(
              AwaitingQuizAnswer(
                planId: state.plan.id,
                questionOrdinal: 0,
                assistance: QuizAssistance().showHint(
                  h.now.millisecondsSinceEpoch,
                ),
              ),
            ),
          );
        }),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'disabled hints still allow reveal with wrong assisted evidence',
    () async {
      final saved = await answer(await start(), reveal: true);
      final receipt = saved.checkpoint.answer!;
      expect(receipt.isCorrect, isFalse);
      expect(receipt.revealed, isTrue);
      expect(receipt.evidenceContext.hintLevel, 2);
      expect(saved.checkpoint.assistance.hintFirstShownAtUtcMs, isNull);
      expect(await h.count('answer_attempts'), 1);
    },
  );

  test(
    'reverse excludes ambiguous meanings and repeated spelling options',
    () async {
      await h.addWord(id: 'synonym-a', spelling: 'alpha', meaning: ' SAME ');
      await h.addWord(id: 'synonym-b', spelling: 'beta', meaning: 'same');
      await h.addWord(id: 'spelling-a', spelling: 'GAMMA', meaning: 'third');
      await h.addWord(id: 'spelling-b', spelling: 'gamma', meaning: 'fourth');
      final state = await start(limit: 100);
      expect(
        state.plan.questions.map((q) => q.word.id),
        isNot(contains(anyOf('synonym-a', 'synonym-b'))),
      );
      for (final question in state.plan.questions) {
        final labels = question.options.map(normalizeLexicalResponse).toList();
        expect(labels.toSet().length, labels.length);
        expect(labels.length, greaterThanOrEqualTo(2));
      }
    },
  );

  test(
    'reverse direction and disabled hints survive a real database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-policy-',
      );
      await h.close();
      h = await ConfiguredQuizHarness.open(
        file: File('${directory.path}/learning.sqlite'),
      );
      wire();
      try {
        final state = await start();
        final planJson = state.plan.stableSerialization;
        h = await h.reopen();
        wire();
        final restored = await learning.resumeQuiz(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
        );
        expect(restored.plan.stableSerialization, planJson);
        expect(
          restored.plan.configuration.direction,
          MeaningQuizDirection.reverse,
        );
        expect(restored.plan.configuration.allowsHints, isFalse);
        expect((await answer(restored)).checkpoint.answer!.isCorrect, isTrue);
      } finally {
        await h.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'authored definition preserves disabled hints through its real preparation API',
    () async {
      final packs = LearningPackUseCases(
        repository: repository.lexicalContent!,
        nowUtc: () => h.now,
        generateId: () => 'synthetic-policy-pack-${++nextId}',
      );
      addTearDown(packs.dispose);
      final scope = (await packs.captureOwner(stillCurrent: () => true))!;
      final installed = await packs.importPack(
        packs.prepareImport(scope: scope, pack: bundledStarterPack),
      );
      final launch = await learning.prepareLexicalQuiz(
        expectedOwnerId: configuredOwnerId,
        packVersionId: installed.id,
        entryCodes: const ['cat'],
        input: LexicalQuizInput.definitionChoice,
        limit: 1,
        hints: QuizHintPolicy.disabled,
        stillCurrent: () => true,
      );
      final state = await learning.startConfiguredQuiz(launch);
      expect(state.plan.configuration.allowsHints, isFalse);
      expect(
        (await answer(state, reveal: true)).checkpoint.answer!.isCorrect,
        isFalse,
      );
    },
  );
}
