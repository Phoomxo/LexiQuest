import 'dart:convert';

import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, TableUpdate;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_recall_ladder_reader.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/recall_ladder.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/authored_lexical_pack.dart';
import '../../support/configured_quiz_harness.dart';
import '../../support/measurement_opportunity_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository canonical;
  late LearningUseCases learning;
  late DriftRecallLadderReader reader;
  LearningPackUseCases? packs;
  var sequence = 0;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    sequence = 0;
    packs = null;
    final content = DriftLearningPackRepository(
      database: h.database,
      ownerWrites: h.ownerWrites,
    );
    canonical = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
      lexicalContent: content,
    );
    learning = LearningUseCases(
      owners: h.owners,
      repository: canonical,
      generateId: () => 'synthetic-ladder-${++sequence}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-ladder',
      ),
    );
    reader = DriftRecallLadderReader(
      database: h.database,
      ownerWrites: h.ownerWrites,
    );
  });
  tearDown(() async {
    await packs?.dispose();
    await h.close();
  });

  Future<RecallLadderSnapshot> read([String? word]) => reader.load(
    expectedOwnerId: configuredOwnerId,
    wordId: word,
    stillCurrent: () => true,
  );

  Future<ConfiguredQuizState> answerMeaning() async {
    var state = await learning.startConfiguredQuiz(
      await learning.prepareConfiguredQuiz(
        configuration: QuizConfiguration.sourcePractice(
          wordIds: [configuredWordIds.first],
          limit: 1,
        ),
        expectedOwnerId: configuredOwnerId,
      ),
    );
    final question = state.plan.questions.single;
    state = await learning.prepareQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: state.checkpointRevision,
      selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
    );
    return (await learning.commitQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: state.checkpointRevision,
    )).state;
  }

  test(
    'absent recent evidence is an all-table pure read and no word is invented',
    () async {
      final before = await h.snapshot();
      final snapshot = await read();
      expect(snapshot.word, isNotNull);
      expect(snapshot.observations, isEmpty);
      expect(snapshot.suggestedStage, RecallLadderStage.exposure);
      final absent = await read('synthetic-nonexistent-word');
      expect(absent.word, isNull);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'actual configured recognition suggests matching and stale vocabulary does not',
    () async {
      await answerMeaning();
      final before = await h.snapshot();
      final snapshot = await read(configuredWordIds.first);
      expect(
        snapshot.observations.single.evidenceClass,
        EvidenceClass.recognition,
      );
      expect(snapshot.suggestedStage, RecallLadderStage.matching);
      expect(await h.snapshot(), before);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = 2 WHERE id = ?',
        [configuredWordIds.first],
      );
      final changed = await h.snapshot();
      expect((await read(configuredWordIds.first)).observations, isEmpty);
      expect(await h.snapshot(), changed);
    },
  );

  test(
    'actual matching plan proves recognition without turning it into recall',
    () async {
      final matching = MatchingUseCases(
        repository: DriftMatchingRepository(canonical),
        generateId: () => 'synthetic-ladder-match-${++sequence}',
        nowUtc: () => h.now,
        buildInfo: const AppBuildInfo(
          version: 'synthetic',
          buildId: 'synthetic-ladder',
        ),
      );
      var state = await matching.start(
        (await matching.prepare(
          expectedOwnerId: configuredOwnerId,
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ))!,
        stillCurrent: () => true,
      );
      state = await matching.saveSelection(
        state,
        wordIndex: 0,
        meaningIndex: 0,
        stillCurrent: () => true,
      );
      state = await matching.save(
        state,
        matching.preparePair(state, responseTime: Duration.zero),
        stillCurrent: () => true,
      );
      state = await matching.commit(state, stillCurrent: () => true);
      final before = await h.snapshot();
      final snapshot = await read(state.plan.words.first.id);
      expect(snapshot.observations.single.stage, RecallLadderStage.matching);
      expect(
        snapshot.observations.single.evidenceClass,
        EvidenceClass.recognition,
      );
      expect(snapshot.suggestedStage, RecallLadderStage.cloze);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'actual lexical typed answer requires retained current authored pins',
    () async {
      packs = LearningPackUseCases(
        repository: DriftLearningPackRepository(
          database: h.database,
          ownerWrites: h.ownerWrites,
        ),
        nowUtc: () => h.now,
        generateId: () => 'synthetic-ladder-content-${++sequence}',
      );
      final owner = (await packs!.captureOwner(stillCurrent: () => true))!;
      final installed = await packs!.importPack(
        packs!.prepareImport(scope: owner, pack: authoredLexicalPack()),
      );
      var state = await learning.startConfiguredQuiz(
        await learning.prepareLexicalQuiz(
          expectedOwnerId: configuredOwnerId,
          packVersionId: installed.id,
          entryCodes: const ['cat'],
          input: LexicalQuizInput.definitionTyped,
          limit: 1,
          stillCurrent: () => true,
        ),
      );
      final word = state.plan.questions.single.word;
      state = await learning.prepareQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
        typedResponse: word.spelling,
      );
      await learning.commitQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
      );
      expect((await read(word.id)).suggestedStage, RecallLadderStage.dictation);
      await h.database.customStatement(
        "UPDATE lexical_content_snapshots SET lexical_json='{}' WHERE word_id = ?",
        [word.id],
      );
      final before = await h.snapshot();
      expect((await read(word.id)).observations, isEmpty);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'actual native dictation source pins suggest speaking from independent recall',
    () async {
      final exercise = await learning.startNativeExercise(
        (await learning.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ))!,
        stillCurrent: () => true,
      );
      final command = learning.prepareNativeAnswer(
        DictationAnswerInput(
          exercise: exercise,
          response: exercise.word.spelling,
          assisted: false,
          responseTime: Duration.zero,
        ),
      );
      await learning.commitNativeAnswer(
        exercise,
        command,
        stillCurrent: () => true,
      );
      final before = await h.snapshot();
      final snapshot = await read(exercise.word.id);
      expect(
        snapshot.observations.single.evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(snapshot.suggestedStage, RecallLadderStage.speaking);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'canonical pronunciation remains pronunciation and never a recall result',
    () async {
      final words = await canonical.listQuizWords(
        ownerId: configuredOwnerId,
        wordIds: [configuredWordIds.first],
        limit: 1,
      );
      final word = words.single;
      const id = 'synthetic-ladder-speaking';
      await canonical.startSession(
        LearningSessionDraft(
          id: id,
          ownerId: configuredOwnerId,
          activityType: 'pronunciationTranscript',
          startedAtUtc: h.now,
          appVersion: 'synthetic',
          buildId: 'synthetic-ladder',
        ),
      );
      await canonical.recordAnswer(
        RecordAnswerCommand(
          id: 'synthetic-ladder-speaking-attempt',
          ownerId: configuredOwnerId,
          sessionId: id,
          wordId: word.id,
          promptMode: 'pronunciationTranscript',
          isCorrect: true,
          responseTimeMs: null,
          attemptNumber: 1,
          occurredAtUtc: h.now,
          evidenceContext: captureCurrentActivityEvidence(
            promptMode: 'pronunciationTranscript',
            contentRevision: word.contentRevision,
          ),
        ),
      );
      final before = await h.snapshot();
      final snapshot = await read(word.id);
      expect(
        snapshot.observations.single.evidenceClass,
        EvidenceClass.pronunciation,
      );
      expect(snapshot.observedCount(RecallLadderStage.typedRecall), 0);
      expect(snapshot.suggestedStage, RecallLadderStage.speaking);
      expect(await h.snapshot(), before);
      await h.database.customStatement(
        "UPDATE learning_sessions SET activity_type='assessment' WHERE id = ?",
        [id],
      );
      expect((await read(word.id)).observations, isEmpty);
    },
  );

  test(
    'actual Study-linked canonical answers do not enter ordinary suggestions',
    () async {
      final controlled = await OpportunityFixture.open();
      addTearDown(controlled.database.close);
      await controlled.ready();
      await controlled.accept();
      await controlled.finish();
      final studyReader = DriftRecallLadderReader(
        database: controlled.database,
        ownerWrites: controlled.participation.ownerWrites,
      );
      final before = await _rows(controlled);
      final snapshot = await studyReader.load(
        expectedOwnerId: 'owner-a',
        wordId: opportunityWordId,
        stillCurrent: () => true,
      );
      expect(snapshot.observations, isEmpty);
      expect(await _rows(controlled), before);
    },
  );

  test(
    'an actual SQL owner ABA during the first probe retires the read',
    () async {
      await answerMeaning();
      final before = await h.snapshot();
      final interference = _OwnerAbaDuringProbe(h.database);
      await expectLater(
        h.database.runWithInterceptor(
          () => read(configuredWordIds.first),
          interceptor: interference,
        ),
        throwsStateError,
      );
      expect(interference.fired, isTrue);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'owner mismatch cancellation and deletion fence deny reads without row changes',
    () async {
      await answerMeaning();
      final before = await h.snapshot();
      await expectLater(
        reader.load(
          expectedOwnerId: configuredOtherOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      await expectLater(
        reader.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => false,
        ),
        throwsStateError,
      );
      expect(await h.snapshot(), before);
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-ladder-delete',
      );
      final fenced = await h.snapshot();
      await expectLater(read(configuredWordIds.first), throwsStateError);
      expect(await h.snapshot(), fenced);
    },
  );
}

Future<Map<String, Object?>> _rows(OpportunityFixture fixture) async => {
  for (final table in fixture.database.allTables)
    table.actualTableName:
        (await fixture.database
                .customSelect(
                  'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
                )
                .get())
            .map((row) => jsonEncode(row.data))
            .toList(),
};

final class _OwnerAbaDuringProbe extends QueryInterceptor {
  _OwnerAbaDuringProbe(this.database);
  final AppDatabase database;
  var fired = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!fired && statement.contains('owner_transaction_probe')) {
      fired = true;
      for (var step = 0; step < 2; step++) {
        await executor.runUpdate(
          'UPDATE local_owners SET is_active = 1 - is_active',
          const [],
        );
        database.notifyUpdates({const TableUpdate('local_owners')});
        await Future<void>.delayed(Duration.zero);
      }
    }
    return rows;
  }
}
