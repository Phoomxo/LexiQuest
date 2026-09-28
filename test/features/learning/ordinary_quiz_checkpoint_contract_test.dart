import 'dart:convert';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/ordinary_meaning_recovery.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_activity_recovery_limits.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/ordinary_meaning_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary;
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

// S01-BT: synthetic SQLite boundary evidence, not controller/route acceptance.
void main() {
  late AppDatabase db;
  late DriftLearningRepository repository;
  late LearningUseCases learning;
  late String ownerId;
  late List<QuizWord> words;
  // Production clocks carry microseconds; SQLite and checkpoint time use ms.
  final now = DateTime.utc(2026, 9, 28).add(const Duration(microseconds: 123));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'bt-synthetic',
      nowUtc: () => now,
    );
    ownerId = (await owners.getOrCreateActiveOwner()).id;
    await db
        .into(db.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'bt-category',
            ownerId: ownerId,
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final item in [
      ('bt-a', 'apple', 'fruit'),
      ('bt-b', 'bus', 'vehicle'),
    ]) {
      await db
          .into(db.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: item.$1,
              ownerId: ownerId,
              categoryId: 'bt-category',
              spelling: item.$2,
              normalizedSpelling: item.$2,
              meaning: item.$3,
              normalizedMeaning: item.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    repository = DriftLearningRepository(db);
    learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'bt-session',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'bt-test', buildId: 'synthetic'),
      eventContextProvider: const BaselineLearningEventContextProvider(),
    );
    words = await repository.listQuizWords(ownerId: ownerId, limit: 2);
  });
  tearDown(() => db.close());

  LearningSessionDraft draft() => LearningSessionDraft(
    id: 'session:bt-session',
    ownerId: ownerId,
    activityType: 'quiz',
    startedAtUtc: now,
    appVersion: 'bt-test',
    buildId: 'synthetic',
  );
  List<PinnedQuizContent> pins() => [
    for (final word in words)
      PinnedQuizContent(
        identity: ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: word.id,
          revision: word.contentRevision!,
        ),
        checksumSha256: word.contentChecksumSha256!,
      ),
  ];
  LearningActivityCheckpoint checkpoint([Map<String, Object?>? state]) =>
      LearningActivityCheckpoint(
        sessionId: draft().id,
        activityType: 'quiz',
        revision: 1,
        occurredAtUtc: now,
        state: state ?? {'kind': 'btSyntheticGenericProbe', 'schemaVersion': 1},
      );
  Future<void> admit({LearningActivityCheckpoint? value}) async =>
      repository.startExactPinnedSessionWithCheckpoint(
        session: draft(),
        content: pins(),
        checkpoint: value ?? checkpoint(),
      );
  Future<LearningActivityRecovery?> read([String? owner]) =>
      repository.loadExactActivityRecovery(
        ownerId: owner ?? ownerId,
        sessionId: draft().id,
        activityType: 'quiz',
      );
  Future<List<Object?>> rows(String table) async => [
    for (final row in await db.customSelect('SELECT * FROM "$table"').get())
      row.data,
  ];
  Future<Map<String, Object?>> projections() async {
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    return {
      for (final table in tables)
        if (RegExp(
          'srs|reward|ledger|learning_sessions|answer_attempts',
        ).hasMatch(table.read<String>('name')))
          table.read<String>('name'): await rows(table.read<String>('name')),
    };
  }

  test(
    'BT REQUIRED ordinary start durably records its exact checkpoint',
    () async {
      final session = await learning.startQuiz(
        ordinaryMeaning: true,
        categoryId: 'bt-category',
        limit: 2,
      );
      expect(session.questions, hasLength(2));
      expect(session.ownerId, ownerId);
      final recovery = await read(); // Expected RED: absent checkpoint.
      expect(recovery!.checkpoint, isNotNull);
      expect(recovery.session.id, session.id);
    },
  );

  group('BT boundary characterization', () {
    test('BV skipped progress survives direct controller recreation', () async {
      final session = await learning.startQuiz(ordinaryMeaning: true, limit: 1);
      var review = const MeaningQuizModeAdapter().createReview(
        session: session,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
      );
      await review.skip();
      review.dispose();
      review = const MeaningQuizModeAdapter().createReview(
        session: session,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
      );
      await review.initializeDurable();
      expect(review.isSkipped, isTrue);
      expect(review.selectedOption, isNull);
      expect(await rows('answer_attempts'), isEmpty);
      review.dispose();
    });
    test(
      'BV selected draft survives unresolved evidence context and recreation',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        var review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(
            learning: learning,
            rolloutModeProvider:
                const ContextEvidencePolicyRolloutModeProvider(),
          ),
        );
        final selected = review.currentQuestion.correctOption;
        await expectLater(
          review.answer(option: selected, responseTimeMs: 5),
          throwsStateError,
        );
        review.dispose();
        final progress = OrdinaryMeaningProgress.decode(
          (await read())!.checkpoint!.state,
        );
        expect(progress.selected, selected);
        expect(progress.phase, 'awaitingAnswer');
        expect(progress.evidence, isNull);
        expect(await rows('answer_attempts'), isEmpty);
        review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
        );
        await review.initializeDurable();
        expect(review.selectedOption, selected);
        expect(review.phase, MeaningQuizReviewPhase.awaitingAnswer);
        await review.answer(option: selected, responseTimeMs: 5);
        expect(await rows('answer_attempts'), hasLength(1));
        review.dispose();
      },
    );
    test(
      'BV a recreated controller must restore before accepting a new answer',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        final original = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
        );
        await original.answer(
          option: original.currentQuestion.correctOption,
          responseTimeMs: 5,
        );
        original.dispose();
        final before = await projections();
        final other = LearningUseCases(
          owners: learning.owners,
          repository: repository,
          generateId: () => 'bv-distinct-answer',
          nowUtc: () => now,
          buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'bv'),
        );
        final recreated = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: other,
          evidence: CurrentActivityEvidenceAdapter(learning: other),
        );
        await expectLater(
          recreated.answer(
            option: recreated.currentQuestion.correctOption,
            responseTimeMs: 5,
          ),
          throwsStateError,
        );
        expect(await projections(), before);
        recreated.dispose();
      },
    );
    for (final boundary in ['owner', 'route']) {
      test(
        'BV $boundary changes after durable intent reject canonical write',
        () async {
          final session = await learning.startQuiz(
            ordinaryMeaning: true,
            limit: 1,
          );
          var accepted = true;
          final review = const MeaningQuizModeAdapter().createReview(
            session: session,
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            acceptsOperation: () => accepted,
            runEvidenceOperation: (operation) async {
              if (boundary == 'owner') {
                await db
                    .update(db.localOwners)
                    .write(const LocalOwnersCompanion(isActive: Value(false)));
                await db
                    .into(db.localOwners)
                    .insert(
                      LocalOwnersCompanion.insert(
                        id: 'new-bv-owner',
                        createdAtUtcMs: 1,
                      ),
                    );
              } else {
                accepted = false;
              }
              return operation();
            },
          );
          await expectLater(
            review.answer(
              option: review.currentQuestion.correctOption,
              responseTimeMs: 5,
            ),
            throwsStateError,
          );
          expect(await rows('answer_attempts'), isEmpty);
          expect(review.feedback, isNull);
          review.dispose();
        },
      );
    }
    test(
      'BV recovery checks stale callbacks after each asynchronous boundary',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        var total = 0;
        await OrdinaryMeaningRecovery.load(
          learning: learning,
          ownerId: ownerId,
          sessionId: session.id,
          acceptsOperation: () {
            total++;
            return true;
          },
        );
        final before = await rows('events_v2');
        for (var failAt = 1; failAt <= total; failAt++) {
          var calls = 0;
          await expectLater(
            OrdinaryMeaningRecovery.load(
              learning: learning,
              ownerId: ownerId,
              sessionId: session.id,
              acceptsOperation: () => ++calls < failAt,
            ),
            throwsStateError,
          );
        }
        expect(await rows('events_v2'), before);
      },
    );
    test(
      'BV strict progress codec rejects corrupt index phase option and occurrence',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        final review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          runEvidenceOperation: (_) async =>
              throw StateError('synthetic pending'),
        );
        await expectLater(
          review.answer(
            option: review.currentQuestion.correctOption,
            responseTimeMs: 1,
          ),
          throwsStateError,
        );
        final state = (await read())!.checkpoint!.state;
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (m) => m['version'] = 99,
          (m) => m['extra'] = true,
          (m) => m['progress']['index'] = 100,
          (m) => m['progress']['phase'] = 'completed',
          (m) => m['progress']['selected'] = 'unadmitted',
          (m) => m['progress']['evidence']['wordId'] = 'foreign',
          (m) => m['progress']['evidence']['sessionId'] = 'foreign',
          (m) => m['progress']['evidence']['isCorrect'] = false,
        ]) {
          final corrupted =
              jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
          mutate(corrupted);
          expect(
            () => OrdinaryMeaningProgress.decode(corrupted),
            throwsFormatException,
          );
        }
        review.dispose();
      },
    );
    test('BV checkpoint capacity covers all 100 admitted questions', () async {
      for (var i = 0; i < 98; i++) {
        await db
            .into(db.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'bv-$i',
                ownerId: ownerId,
                categoryId: 'bt-category',
                spelling: 'word$i',
                normalizedSpelling: 'word$i',
                meaning: 'meaning$i',
                normalizedMeaning: 'meaning$i',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
      }
      var sequence = 0;
      final authority = LearningUseCases(
        owners: learning.owners,
        repository: repository,
        generateId: () => 'bv-${sequence++}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'bv'),
      );
      final session = await authority.startQuiz(
        ordinaryMeaning: true,
        limit: 100,
      );
      final review = const MeaningQuizModeAdapter().createReview(
        session: session,
        learning: authority,
        evidence: CurrentActivityEvidenceAdapter(learning: authority),
      );
      addTearDown(review.dispose);
      for (var i = 0; i < 100; i++) {
        await review.answer(
          option: review.currentQuestion.correctOption,
          responseTimeMs: 1,
        );
        await review.advance();
      }
      expect(review.isCompleted, isTrue);
      expect(await rows('answer_attempts'), hasLength(100));
    });
    for (final lostAck in [false, true]) {
      test(
        'BV pending selected answer replays after recreation ack=$lostAck',
        () async {
          final session = await learning.startQuiz(
            ordinaryMeaning: true,
            limit: 1,
          );
          final evidence = CurrentActivityEvidenceAdapter(learning: learning);
          var review = const MeaningQuizModeAdapter().createReview(
            session: session,
            learning: learning,
            evidence: evidence,
            runEvidenceOperation: (operation) async {
              if (lostAck) await operation();
              throw StateError('synthetic interrupted acknowledgement');
            },
          );
          final selected = review.currentQuestion.options.last;
          await expectLater(
            review.answer(option: selected, responseTimeMs: 50),
            throwsStateError,
          );
          final pending = OrdinaryMeaningProgress.decode(
            (await read())!.checkpoint!.state,
          );
          expect(pending.phase, 'pending');
          expect(pending.selected, selected);
          final identity = pending.evidence!.sourceEvidenceId;
          review.dispose();
          review = const MeaningQuizModeAdapter().createReview(
            session: session,
            learning: learning,
            evidence: evidence,
          );
          await review.initializeDurable();
          expect(review.selectedOption, selected);
          expect(review.phase, MeaningQuizReviewPhase.evidenceRetryRequired);
          await review.retryEvidence();
          expect(review.isAnswered, isTrue);
          expect(
            (await db.select(db.answerAttempts).get()).single.id,
            identity,
          );
          expect(await rows('answer_attempts'), hasLength(1));
          review.dispose();
        },
      );
    }
    test(
      'BV committed close acknowledgement replays after recreation',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        var review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
          completeSession: (close) async {
            await close.finish();
            throw StateError('synthetic lost close acknowledgement');
          },
        );
        await review.answer(
          option: review.currentQuestion.correctOption,
          responseTimeMs: 5,
        );
        await expectLater(review.advance(), throwsStateError);
        final attempts = await rows('answer_attempts');
        final sessions = await rows('learning_sessions');
        final projected = await projections();
        review.dispose();
        review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
        );
        await review.initializeDurable();
        expect(review.phase, MeaningQuizReviewPhase.completionRetryRequired);
        expect(review.feedback?.isCorrect, isTrue);
        await review.retryCompletion();
        expect(review.isCompleted, isTrue);
        expect(await rows('answer_attempts'), attempts);
        expect(await rows('learning_sessions'), sessions);
        expect(await projections(), projected);
        review.dispose();
      },
    );
    test('BV late operation callback cannot publish feedback', () async {
      final session = await learning.startQuiz(ordinaryMeaning: true, limit: 1);
      var accepted = true;
      final review = const MeaningQuizModeAdapter().createReview(
        session: session,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        acceptsOperation: () => accepted,
        runEvidenceOperation: (operation) async {
          final result = await operation();
          accepted = false;
          return result;
        },
      );
      await expectLater(
        review.answer(
          option: review.currentQuestion.correctOption,
          responseTimeMs: 5,
        ),
        throwsStateError,
      );
      expect(review.feedback, isNull);
      expect(
        OrdinaryMeaningProgress.decode((await read())!.checkpoint!.state).phase,
        'pending',
      );
      review.dispose();
    });
    for (final drift in ['owner', 'content', 'route']) {
      test('BV exact recovery rejects $drift drift without mutation', () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        if (drift == 'owner') {
          await db
              .update(db.localOwners)
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await db
              .into(db.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'foreign-bv',
                  createdAtUtcMs: 1,
                ),
              );
        } else if (drift == 'content') {
          await (db.update(
            db.vocabularyWords,
          )..where((r) => r.id.equals('bt-b'))).write(
            const VocabularyWordsCompanion(
              meaning: Value('changed'),
              normalizedMeaning: Value('changed'),
            ),
          );
        }
        final before = await rows('events_v2');
        await expectLater(
          OrdinaryMeaningRecovery.load(
            learning: learning,
            ownerId: ownerId,
            sessionId: session.id,
            acceptsOperation: () => drift != 'route',
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
        expect(await rows('events_v2'), before);
      });
    }
    test(
      'BV durable answered feedback and next question survive recreation',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 2,
        );
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        var review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
        );
        final selected = review.currentQuestion.correctOption;
        await review.answer(option: selected, responseTimeMs: 123);
        final before = await rows('answer_attempts');
        review.dispose();
        final recovery = await read();
        expect(
          recovery!.checkpoint!.state['progress'],
          isNotNull,
          reason: 'BV answer intent and feedback must be durable',
        );
        expect(before, hasLength(1));
        review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
        );
        await review.initializeDurable();
        expect(review.index, 0);
        expect(review.selectedOption, selected);
        expect(review.isAnswered, isTrue);
        expect(review.feedback!.isCorrect, isTrue);
        expect(await rows('answer_attempts'), before);
        await review.advance();
        review.dispose();
        review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
        );
        await review.initializeDurable();
        expect(review.index, 1);
        expect(review.phase, MeaningQuizReviewPhase.awaitingAnswer);
        expect(await rows('answer_attempts'), before);
        review.dispose();
      },
    );
    test(
      'atomic generic admission replays same identity without score or reward writes',
      () async {
        final before = <String, List<Object?>>{};
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
            )
            .get();
        for (final table in tables) {
          final name = table.read<String>('name');
          before[name] = await rows(name);
        }
        await admit();
        final events = await rows('events_v2');
        await admit(); // Lost acknowledgement replay at repository boundary.
        expect(await rows('events_v2'), events);
        expect(await rows('learning_sessions'), hasLength(1));
        expect((await read())!.checkpoint!.revision, 1);
        for (final entry in before.entries) {
          if (entry.key == 'learning_sessions' || entry.key == 'events_v2') {
            continue;
          }
          expect(await rows(entry.key), entry.value, reason: entry.key);
        }
        await expectLater(
          admit(value: checkpoint({'changed': true})),
          throwsStateError,
        );
        expect(await rows('events_v2'), events);
      },
    );

    test(
      'failed checkpoint insert rolls back session and same command can retry',
      () async {
        await db.customStatement('''
CREATE TRIGGER bt_fail_checkpoint BEFORE INSERT ON events_v2
WHEN NEW.event_type = 'LearningActivityCheckpoint'
BEGIN SELECT RAISE(ABORT, 'BT synthetic failure'); END
''');
        final before = await rows('events_v2');
        await expectLater(
          admit(),
          throwsA(
            predicate((e) => e.toString().contains('BT synthetic failure')),
          ),
        );
        expect(await rows('learning_sessions'), isEmpty);
        expect(await rows('events_v2'), before);
        await db.customStatement('DROP TRIGGER bt_fail_checkpoint');
        await admit();
        expect((await read())!.session.id, draft().id);
      },
    );

    test(
      'exact admission rejects content drift before writing any session',
      () async {
        await (db.update(
          db.vocabularyWords,
        )..where((r) => r.id.equals(words.first.id))).write(
          const VocabularyWordsCompanion(
            meaning: Value('changed'),
            normalizedMeaning: Value('changed'),
          ),
        );
        await expectLater(admit(), throwsStateError);
        expect(await rows('learning_sessions'), isEmpty);
      },
    );

    test('exact recovery reconstruction rejects later content drift', () async {
      await admit();
      final recovery = (await read())!;
      await (db.update(
        db.vocabularyWords,
      )..where((r) => r.id.equals(words.first.id))).write(
        const VocabularyWordsCompanion(
          meaning: Value('changed'),
          normalizedMeaning: Value('changed'),
        ),
      );
      await expectLater(
        learning.reconstructPinnedQuizSession(
          session: recovery.session,
          content: pins().map((p) => p.identity).toList(),
          contentChecksumsSha256: {
            for (final p in pins()) p.identity.id: p.checksumSha256,
          },
        ),
        throwsStateError,
      );
    });

    test(
      'exact owner boundary rejects inactive admission and foreign recovery',
      () async {
        await admit();
        expect(await read('local:someone-else'), isNull);
        await (db.update(db.localOwners)..where((r) => r.id.equals(ownerId)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await expectLater(admit(), throwsStateError);
        expect(await rows('learning_sessions'), hasLength(1));
      },
    );

    test('checkpoint byte budget fails before session creation', () async {
      await expectLater(
        admit(
          value: checkpoint({
            'blob': 'x' * LearningActivityRecoveryLimits.maximumCheckpointBytes,
          }),
        ),
        throwsArgumentError,
      );
      expect(await rows('learning_sessions'), isEmpty);
    });

    test(
      'legacy session without checkpoint fails closed and remains unchanged',
      () async {
        await repository.startSession(draft());
        final before = await rows('learning_sessions');
        await expectLater(read(), throwsStateError);
        expect(await rows('learning_sessions'), before);
      },
    );

    test(
      'BU rejects opaque ordinary state unrelated to supplied pins',
      () async {
        // BT accepted this invalid ordinary payload; BU must reject atomically.
        final opaque = {
          'kind': 'ordinaryMeaningQuiz',
          'schemaVersion': 1,
          'ownerId': 'different-owner',
          'sessionId': 'different-session',
          'questions': <Object?>[],
        };
        await expectLater(
          admit(value: checkpoint(opaque)),
          throwsFormatException,
        );
        expect(await rows('learning_sessions'), isEmpty);
      },
    );

    test(
      'BU admitted plan determines options even with a different presentation pool',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          categoryId: 'bt-category',
          limit: 1,
        );
        const adapter = MeaningQuizModeAdapter();
        final before = adapter.pinQuestions(session).single;
        final after = adapter
            .pinQuestions(
              session,
              distractorWords: words.where(
                (w) => w.id != session.questions.single.word.id,
              ),
            )
            .single;
        expect(before.options, hasLength(2));
        expect(after.options, hasLength(2));
        expect(after.optionIdentities, before.optionIdentities);
        expect(
          before.options,
          session.ordinaryMeaningPlan!.questions.single.options,
        );
        expect(await rows('learning_sessions'), hasLength(1));
      },
    );
  });

  group('BU frozen admission', () {
    LearningUseCases useRepository(
      LearningRepository source, {
      Future<void> Function(String)? before,
    }) => LearningUseCases(
      owners: learning.owners,
      repository: source,
      generateId: () => 'bt-session',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'bt-test', buildId: 'synthetic'),
      beforeSessionStart: before,
    );

    test(
      'content drift between selection and admission creates no session or checkpoint',
      () async {
        final eventsBefore = await rows('events_v2');
        final subject = useRepository(
          repository,
          before: (_) async {
            await (db.update(
              db.vocabularyWords,
            )..where((r) => r.id.equals('bt-a'))).write(
              const VocabularyWordsCompanion(
                meaning: Value('changed'),
                normalizedMeaning: Value('changed'),
              ),
            );
          },
        );
        await expectLater(
          subject.startQuiz(ordinaryMeaning: true, limit: 2),
          throwsStateError,
        );
        expect(await rows('learning_sessions'), isEmpty);
        expect(await rows('events_v2'), eventsBefore);
      },
    );

    test(
      'acknowledgement loss reconciles and retries the exact admitted command',
      () async {
        final source = _LostAdmissionAck(repository);
        final s = await useRepository(
          source,
        ).startQuiz(ordinaryMeaning: true, limit: 2);
        expect(source.admissions, 2);
        expect(source.selections, 1);
        expect(s.id, 'session:bt-session');
        expect(await rows('learning_sessions'), hasLength(1));
        final accepted = (await read())!;
        expect(
          jsonEncode(
            OrdinaryMeaningPlan.decode(accepted.checkpoint!.state).toJson(),
          ),
          jsonEncode(s.ordinaryMeaningPlan!.toJson()),
        );
      },
    );

    test(
      'verified lexical artifact identity is frozen and drift rolls back admission',
      () async {
        final eventsBefore = await rows('events_v2');
        final lexical = _SyntheticLexical(words, ownerId);
        final source = DriftLearningRepository(db, lexicalVocabulary: lexical);
        late PendingOrdinaryMeaningAdmission command;
        await expectLater(
          useRepository(source).startQuiz(
            ordinaryMeaning: true,
            limit: 2,
            onMeaningAdmissionPrepared: (value) {
              command = value;
              lexical.checksum = 'b' * 64;
            },
          ),
          throwsFormatException,
        );
        expect(await rows('learning_sessions'), isEmpty);
        expect(await rows('events_v2'), eventsBefore);
        expect(
          command.plan.questions.first.contrastiveChecksumSha256,
          'a' * 64,
        );
        lexical.checksum = 'a' * 64;
        final s = await command.admit();
        expect(
          s.ordinaryMeaningPlan!.questions.first.evidenceChecksumSha256,
          isNotNull,
        );
        final state = s.ordinaryMeaningPlan!.toJson();
        final q = (state['questions'] as List).first as Map;
        q['options'] = (q['options'] as List).reversed.toList();
        final events = await rows('events_v2');
        await expectLater(
          source.startExactPinnedSessionWithCheckpoint(
            session: draft(),
            content: s.ordinaryMeaningPlan!.pins,
            checkpoint: checkpoint(state),
          ),
          throwsStateError,
        );
        expect(await rows('events_v2'), events);
      },
    );
    test(
      'presentation rejects an admitted plan attached to a foreign session',
      () async {
        final s = await learning.startQuiz(ordinaryMeaning: true, limit: 2);
        final foreign = QuizSession(
          id: s.id,
          ownerId: 'foreign',
          questions: s.questions,
          startedAtUtc: s.startedAtUtc,
          ordinaryMeaningPlan: s.ordinaryMeaningPlan,
        );
        expect(
          () => const MeaningQuizModeAdapter().pinQuestions(foreign),
          throwsFormatException,
        );
      },
    );

    test(
      'codec rejects reordered content and enforces exact UTF8 byte boundary',
      () async {
        final s = await learning.startQuiz(ordinaryMeaning: true, limit: 2);
        final value = s.ordinaryMeaningPlan!.toJson();
        value['content'] = (value['content'] as List).reversed.toList();
        expect(() => OrdinaryMeaningPlan.decode(value), throwsFormatException);
        final boundary = s.ordinaryMeaningPlan!.toJson();
        final remaining =
            OrdinaryMeaningPlan.maxBytes -
            utf8.encode(jsonEncode(boundary)).length;
        boundary['session'] = '${boundary['session']}${'x' * remaining}';
        expect(
          utf8.encode(jsonEncode(boundary)).length,
          OrdinaryMeaningPlan.maxBytes,
        );
        expect(
          OrdinaryMeaningPlan.decode(boundary).session.id,
          boundary['session'],
        );
        boundary['session'] = '${boundary['session']}x';
        expect(
          () => OrdinaryMeaningPlan.decode(boundary),
          throwsFormatException,
        );
      },
    );
    test(
      'round trip preserves ordered prompts options and all content pins',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
        );
        final stored = (await read())!.checkpoint!.state;
        final plan = OrdinaryMeaningPlan.decode(stored);
        expect(
          jsonEncode(plan.toJson()),
          jsonEncode(session.ordinaryMeaningPlan!.toJson()),
        );
        expect(plan.pins.map((p) => p.identity.id).toSet(), {'bt-a', 'bt-b'});
        expect(plan.questions.single.optionIdentities.values.toSet(), {
          'bt-a',
          'bt-b',
        });
        expect(
          () => plan.questions.single.options.add('tamper'),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'captured command replay never reselects or duplicates events',
      () async {
        late PendingOrdinaryMeaningAdmission command;
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
          onMeaningAdmissionPrepared: (value) => command = value,
        );
        final events = await rows('events_v2');
        final retry = await command.admit();
        expect(retry.id, session.id);
        expect(
          jsonEncode(retry.ordinaryMeaningPlan!.toJson()),
          jsonEncode(session.ordinaryMeaningPlan!.toJson()),
        );
        expect(await rows('events_v2'), events);
        expect(await rows('learning_sessions'), hasLength(1));
      },
    );

    test(
      'captured command fails closed after owner or distractor content drift',
      () async {
        late PendingOrdinaryMeaningAdmission command;
        await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 1,
          onMeaningAdmissionPrepared: (value) => command = value,
        );
        final events = await rows('events_v2');
        await (db.update(
          db.vocabularyWords,
        )..where((r) => r.id.equals('bt-b'))).write(
          const VocabularyWordsCompanion(
            meaning: Value('changed'),
            normalizedMeaning: Value('changed'),
          ),
        );
        await expectLater(command.admit(), throwsStateError);
        await db
            .update(db.localOwners)
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await db
            .into(db.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'foreign', createdAtUtcMs: 1),
            );
        await expectLater(command.admit(), throwsStateError);
        expect(await rows('events_v2'), events);
      },
    );

    test(
      'codec rejects unknown version fields duplicates and altered answer identity',
      () async {
        final session = await learning.startQuiz(
          ordinaryMeaning: true,
          limit: 2,
        );
        final plan = session.ordinaryMeaningPlan!;
        Map<String, Object?> copy() =>
            (jsonDecode(jsonEncode(plan.toJson())) as Map)
                .cast<String, Object?>();
        for (final mutate in <void Function(Map<String, Object?>)>[
          (m) => m['version'] = 2,
          (m) => m['version'] = 1.0,
          (m) => m['unknown'] = true,
          (m) => (m['content'] as List).add((m['content'] as List).first),
          (m) => (m['questions'] as List).add((m['questions'] as List).first),
          (m) => ((m['questions'] as List).first as Map)['answer'] = 'bt-b',
          (m) => ((m['questions'] as List).first as Map)['prompt'] = 'wrong',
          (m) =>
              ((((m['questions'] as List).first as Map)['options'] as List)
                          .first
                      as Map)['label'] =
                  'wrong',
          (m) => ((m['questions'] as List).first as Map)['artifact'] = 'a' * 64,
          (m) => m['padding'] = 'x' * OrdinaryMeaningPlan.maxBytes,
        ]) {
          final value = copy();
          mutate(value);
          expect(
            () => OrdinaryMeaningPlan.decode(value),
            throwsFormatException,
          );
        }
        final foreign = copy()..['owner'] = 'foreign';
        await expectLater(
          admit(value: checkpoint(foreign)),
          throwsFormatException,
        );
      },
    );
  });
}

final class _LostAdmissionAck
    implements
        LearningRepository,
        OrdinaryMeaningContentRepository,
        ExactPinnedLearningActivityRepository,
        LearningActivityRecoveryRepository {
  _LostAdmissionAck(this.delegate);
  final DriftLearningRepository delegate;
  var selections = 0;
  var admissions = 0;
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) {
    selections++;
    return delegate.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      limit: limit,
    );
  }

  @override
  Future<List<vocabulary.VocabularyWord>> readMeaningLexicalWords(
    List<String> ids,
  ) => delegate.readMeaningLexicalWords(ids);
  @override
  Future<void> startExactPinnedSessionWithCheckpoint({
    required LearningSessionDraft session,
    required List<PinnedQuizContent> content,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    await delegate.startExactPinnedSessionWithCheckpoint(
      session: session,
      content: content,
      checkpoint: checkpoint,
    );
    if (++admissions == 1) {
      throw StateError('synthetic lost admission acknowledgement');
    }
  }

  @override
  Future<LearningActivityRecovery?> loadExactActivityRecovery({
    required String ownerId,
    required String sessionId,
    required String activityType,
  }) => delegate.loadExactActivityRecovery(
    ownerId: ownerId,
    sessionId: sessionId,
    activityType: activityType,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Explicitly synthetic metadata authority; no real packaged artifact or approval claim.
final class _SyntheticLexical implements VocabularyRepository {
  _SyntheticLexical(this.words, this.owner);
  final List<QuizWord> words;
  final String owner;
  String checksum = 'a' * 64;
  @override
  Future<List<vocabulary.VocabularyWord>> readPinnedByIds(
    Iterable<String> ids,
  ) async => [
    for (final id in ids)
      for (final w in words.where((w) => w.id == id))
        vocabulary.VocabularyWord(
          id: w.id,
          ownerId: owner,
          categoryId: w.categoryId,
          spelling: w.spelling,
          normalizedSpelling: w.normalizedSpelling!,
          meaning: w.meaning,
          normalizedMeaning: w.normalizedMeaning!,
          partOfSpeech: w.partOfSpeech,
          source: 'synthetic',
          isGlobal: true,
          localRevision: 1,
          isDeleted: false,
          createdAtUtc: DateTime.utc(2026),
          updatedAtUtc: DateTime.utc(2026),
          contentRevision: w.contentRevision!,
          contentChecksumSha256: w.contentChecksumSha256,
          contentProvenance: ContentProvenance.packaged,
          contentReviewState: ContentReviewState.approved,
          contentPublicationState: ContentPublicationState.published,
          richMetadata: vocabulary.RichLexicalMetadata(
            verifiedContentRevision: w.contentRevision,
            verifiedArtifactChecksumSha256: checksum,
          ),
        ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
