import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/associative_reading_checkpoint.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  group('R06 canonical reading recovery', () {
    late _ReadingFixture fixture;
    setUp(() async => fixture = await _ReadingFixture.create());
    tearDown(() => fixture.database.close());

    test(
      'strict codec rejects score caches, corrupt passage and duplicate pins',
      () {
        final state = fixture.state.toJson();
        expect(
          () => AssociativeReadingCheckpoint.fromJson({...state, 'correct': 2}),
          throwsFormatException,
        );
        expect(
          () => AssociativeReadingCheckpoint.fromJson({
            ...state,
            'passage': 'corrupt',
          }),
          throwsFormatException,
        );
        expect(
          () => AssociativeReadingCheckpoint.fromJson({
            ...state,
            'words': [
              fixture.state.words.first.toJson(),
              fixture.state.words.first.toJson(),
            ],
          }),
          throwsFormatException,
        );
        expect(
          AssociativeReadingCheckpoint.fromJson(
            state,
          ).sameContent(fixture.state),
          isTrue,
        );
      },
    );

    test(
      'partial committed recall restores authenticated occurrence and cannot advance early',
      () async {
        await fixture.advance(2);
        await fixture.advance(3);
        await fixture.answer(0, correct: true);
        final recovery = await fixture.read();
        expect(fixture.state.recallResults(recovery), [true, null]);
        await expectLater(fixture.advance(4), throwsStateError);
        expect((await fixture.read()).checkpoint!.revision, 3);
        await fixture.answer(1, correct: false);
        await fixture.advance(4);
        expect(fixture.state.recallResults(await fixture.read()), [
          true,
          false,
        ]);
        expect(
          await fixture.database.select(fixture.database.answerAttempts).get(),
          hasLength(2),
        );
      },
    );

    test(
      'reading completion uses durable millisecond terminal identity',
      () async {
        await fixture.completeRecall();
        await fixture.advance(5);
        await fixture.advance(6);
        final rawTime = DateTime.utc(2026, 9, 9, 1, 0, 0, 123, 456);
        final close = fixture.learning.restoreSessionClose(
          sessionId: fixture.session.id,
          ownerId: fixture.ownerId,
          completedAtUtc: rawTime,
        );
        final completed = await close.finish();
        final recovery = await fixture.read();
        expect(completed.state, 'completed');
        expect(completed.endedAtUtc, DateTime.utc(2026, 9, 9, 1, 0, 0, 123));
        expect(recovery.checkpoint!.terminalAtUtc, completed.endedAtUtc);
        expect(recovery.checkpoint!.terminalAcknowledged, isTrue);
        final before =
            (await fixture.database.select(fixture.database.eventsV2).get())
                .length;
        await fixture.repository.finishSession(
          ownerId: fixture.ownerId,
          sessionId: fixture.session.id,
          endedAtUtc: rawTime,
        );
        expect(
          (await fixture.database.select(fixture.database.eventsV2).get())
              .length,
          before,
        );
        await expectLater(
          fixture.repository.finishSession(
            ownerId: fixture.ownerId,
            sessionId: fixture.session.id,
            endedAtUtc: rawTime.add(const Duration(milliseconds: 1)),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'terminal checkpoint failure rolls completion back and captured retry keeps identity',
      () async {
        await fixture.completeRecall();
        await fixture.advance(5);
        await fixture.advance(6);
        final before =
            (await fixture.database.select(fixture.database.eventsV2).get())
                .length;
        await fixture.database.customStatement('''
CREATE TRIGGER fail_reading_terminal BEFORE INSERT ON events_v2
WHEN NEW.event_type = 'LearningActivityCheckpoint'
 AND json_extract(NEW.payload_json, '\$.terminalAcknowledged') = 1
BEGIN SELECT RAISE(ABORT, 'synthetic reading terminal failure'); END
''');
        final pending = fixture.learning.captureSessionClose(
          sessionId: fixture.session.id,
          ownerId: fixture.ownerId,
        );
        await expectLater(
          pending.finish(),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'synthetic reading terminal failure',
              ),
            ),
          ),
        );
        expect((await fixture.read()).session.state, 'active');
        expect(
          (await fixture.database.select(fixture.database.eventsV2).get())
              .length,
          before,
        );
        await fixture.database.customStatement(
          'DROP TRIGGER fail_reading_terminal',
        );
        final result = await pending.retry();
        final recovery = await fixture.read();
        expect(result.state, 'completed');
        expect(recovery.checkpoint!.terminalAtUtc, result.endedAtUtc);
        expect(recovery.checkpoint!.terminalAcknowledged, isTrue);
        final events =
            (await fixture.database.select(fixture.database.eventsV2).get())
                .length;
        await fixture.repository.finishSession(
          ownerId: fixture.ownerId,
          sessionId: fixture.session.id,
          endedAtUtc: result.endedAtUtc!,
        );
        expect(
          (await fixture.database.select(fixture.database.eventsV2).get())
              .length,
          events,
        );
        final progress = await fixture.learning.loadReadingProgress(
          documentId: fixture.state.documentId,
          documentRevision: fixture.state.documentRevision,
        );
        expect(progress!.isCompleted, isTrue);
      },
    );

    for (final damage in ['missing', 'downgraded']) {
      test(
        '$damage canonical checkpoints cannot authorize recovery or generic completion',
        () async {
          if (damage == 'missing') {
            await (fixture.database.delete(
              fixture.database.eventsV2,
            )..where((row) => row.aggregateId.equals(fixture.session.id))).go();
          } else {
            final checkpoint =
                await (fixture.database.select(fixture.database.eventsV2)
                      ..where(
                        (row) => row.aggregateId.equals(fixture.session.id),
                      ))
                    .getSingle();
            final payload =
                jsonDecode(checkpoint.payloadJson) as Map<String, dynamic>;
            payload['state'] = {'schemaVersion': 1};
            await (fixture.database.update(
              fixture.database.eventsV2,
            )..where((row) => row.eventId.equals(checkpoint.eventId))).write(
              EventsV2Companion(payloadJson: Value(jsonEncode(payload))),
            );
          }
          await expectLater(fixture.read(), throwsA(anything));
          await expectLater(
            fixture.learning.finishSession(fixture.session.id),
            throwsA(anything),
          );
          expect(
            (await fixture.database
                    .select(fixture.database.learningSessions)
                    .getSingle())
                .state,
            'active',
          );
        },
      );
    }

    test('generic admission cannot claim reserved reading identity', () async {
      await expectLater(
        fixture.repository.startSession(
          LearningSessionDraft(
            id: 'reading:forged',
            ownerId: fixture.ownerId,
            activityType: 'associativeReading',
            startedAtUtc: DateTime.utc(2026, 9, 9),
            appVersion: 'test',
            buildId: 'synthetic',
          ),
        ),
        throwsStateError,
      );
      expect(
        await fixture.database.select(fixture.database.learningSessions).get(),
        hasLength(1),
      );
    });

    test(
      'foreign owner and changed content cannot recover; explicit abandon remains stopped',
      () async {
        await expectLater(
          fixture.repository.loadReadingRecovery(
            ownerId: 'foreign',
            content: fixture.state,
          ),
          throwsStateError,
        );
        final changed = AssociativeReadingCheckpoint(
          documentId: fixture.state.documentId,
          documentRevision: fixture.state.documentRevision,
          cefrLevel: 'C1',
          passage: fixture.state.passage,
          stage: 1,
          words: fixture.state.words,
        );
        await expectLater(
          fixture.repository.loadReadingRecovery(
            ownerId: fixture.ownerId,
            content: changed,
          ),
          throwsStateError,
        );
        await fixture.learning.abandonSession(
          ownerId: fixture.ownerId,
          sessionId: fixture.session.id,
          abandonedAtUtc: DateTime.utc(2026, 9, 9, 1),
        );
        expect(
          await fixture.repository.loadReadingRecovery(
            ownerId: fixture.ownerId,
            content: fixture.state,
          ),
          isNull,
        );
        expect((await fixture.read()).session.state, 'abandoned');
        await expectLater(fixture.advance(2), throwsStateError);
      },
    );

    test(
      'missing canonical answer source cannot supply a recall score',
      () async {
        await fixture.advance(2);
        await fixture.advance(3);
        await fixture.answer(0, correct: true);
        final answer = await fixture.database
            .select(fixture.database.answerAttempts)
            .getSingle();
        await (fixture.database.delete(fixture.database.eventsV2)..where(
              (event) => event.eventId.equals(
                LearningEvidenceContract.learningEventId(answer.id),
              ),
            ))
            .go();
        await expectLater(fixture.read(), throwsStateError);
      },
    );

    for (final drift in [
      'edited',
      'deleted',
      'category deleted',
      'target history',
    ]) {
      test(
        'completed reading with $drift content does not block owner upgrade',
        () async {
          await fixture.completeRecall();
          await fixture.advance(5);
          await fixture.advance(6);
          await fixture.learning
              .captureSessionClose(
                sessionId: fixture.session.id,
                ownerId: fixture.ownerId,
              )
              .finish();
          var operation = 0;
          final upgrade = DriftOwnerUpgradeRepository(
            fixture.database,
            nowUtc: () => DateTime.utc(2026, 9, 9, 1),
            generateConflictId: () => 'drift-conflict-${++operation}',
            generateOwnerId: () => 'unexpected-drift-owner',
            generateOwnerOperationToken: () => 'drift-operation-${++operation}',
            deleteOwnerSecrets: (_) async {},
          );
          var sourceOwner = fixture.ownerId;
          if (drift == 'target history') {
            await upgrade.upgrade(
              activeOwnerId: fixture.ownerId,
              firebaseUid: 'synthetic-drift-account',
            );
            await (fixture.database.update(fixture.database.localOwners)
                  ..where((row) => row.id.equals(fixture.ownerId)))
                .write(const LocalOwnersCompanion(isActive: Value(false)));
            sourceOwner = 'new-drift-guest';
            await fixture.database
                .into(fixture.database.localOwners)
                .insert(
                  LocalOwnersCompanion.insert(
                    id: sourceOwner,
                    createdAtUtcMs: 2,
                  ),
                );
          }
          final wordUpdate = fixture.database.update(
            fixture.database.vocabularyWords,
          )..where((row) => row.id.equals(fixture.state.words.first.id));
          if (drift == 'deleted') {
            await wordUpdate.write(
              const VocabularyWordsCompanion(isDeleted: Value(true)),
            );
          } else if (drift == 'category deleted') {
            await (fixture.database.update(
              fixture.database.vocabularyCategories,
            )..where((row) => row.id.equals('category:recovery'))).write(
              const VocabularyCategoriesCompanion(isDeleted: Value(true)),
            );
          } else {
            await wordUpdate.write(
              const VocabularyWordsCompanion(
                spelling: Value('changed'),
                normalizedSpelling: Value('changed'),
                contentRevision: Value(2),
                contentChecksumSha256: Value(null),
              ),
            );
          }
          final before = await fixture.read();
          final answerIds = before.attempts
              .map((attempt) => attempt.id)
              .toList();
          await upgrade.upgrade(
            activeOwnerId: sourceOwner,
            firebaseUid: 'synthetic-drift-account',
          );
          final after = await fixture.repository.loadExactActivityRecovery(
            ownerId: fixture.ownerId,
            sessionId: fixture.session.id,
            activityType: 'associativeReading',
          );
          expect(after!.session.state, 'completed');
          expect(after.session.id, before.session.id);
          expect(after.checkpoint!.state, before.checkpoint!.state);
          expect(after.attempts.map((attempt) => attempt.id), answerIds);
          expect(fixture.state.recallResults(after), [true, false]);
          await expectLater(
            fixture.repository.loadReadingRecovery(
              ownerId: fixture.ownerId,
              content: fixture.state,
            ),
            throwsStateError,
          );
        },
      );
    }

    for (final withAnswers in [false, true]) {
      test(
        'collision owner upgrade preserves reading pins ${withAnswers ? 'after recall' : 'before recall'}',
        () async {
          if (withAnswers) await fixture.completeRecall();
          await fixture.database
              .into(fixture.database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'reading-account',
                  firebaseUid: const Value('synthetic-reading-firebase'),
                  accountState: const Value('firebaseBound'),
                  createdAtUtcMs: 2,
                  isActive: const Value(false),
                ),
              );
          await fixture.database
              .into(fixture.database.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'category:reading-account',
                  ownerId: 'reading-account',
                  name: 'Recovery',
                  normalizedName: 'recovery',
                  createdAtUtcMs: 2,
                  updatedAtUtcMs: 2,
                ),
              );
          await fixture.database
              .into(fixture.database.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'category:reading-deleted',
                  ownerId: 'reading-account',
                  name: 'Recovery (บทเรียนเดิม)',
                  normalizedName: 'recovery (บทเรียนเดิม)',
                  isDeleted: const Value(true),
                  createdAtUtcMs: 2,
                  updatedAtUtcMs: 2,
                ),
              );
          for (final pin in fixture.state.words) {
            await fixture.database
                .into(fixture.database.vocabularyWords)
                .insert(
                  VocabularyWordsCompanion.insert(
                    id: 'account:${pin.id}',
                    ownerId: 'reading-account',
                    categoryId: 'category:reading-account',
                    spelling: pin.spelling,
                    normalizedSpelling: pin.canonicalAnswer,
                    meaning: pin.spelling,
                    normalizedMeaning: pin.spelling,
                    partOfSpeech: 'verb',
                    createdAtUtcMs: 2,
                    updatedAtUtcMs: 2,
                  ),
                );
          }
          var conflict = 0;
          await DriftOwnerUpgradeRepository(
            fixture.database,
            nowUtc: () => DateTime.utc(2026, 9, 9, 1),
            generateConflictId: () => 'reading-conflict-${++conflict}',
            generateOwnerId: () => 'unexpected-reading-owner',
            generateOwnerOperationToken: () => 'reading-upgrade-operation',
            deleteOwnerSecrets: (_) async {},
          ).upgrade(
            activeOwnerId: fixture.ownerId,
            firebaseUid: 'synthetic-reading-firebase',
          );
          final recovery = await fixture.repository.loadReadingRecovery(
            ownerId: 'reading-account',
            content: fixture.state,
          );
          expect(recovery, isNotNull);
          expect(recovery!.session.id, fixture.session.id);
          expect(recovery.session.id, startsWith('reading:'));
          expect(recovery.session.ownerId, 'reading-account');
          expect(
            fixture.state.recallResults(recovery),
            withAnswers ? [true, false] : [null, null],
          );
          expect(
            await fixture.database
                .select(fixture.database.answerAttempts)
                .get(),
            hasLength(withAnswers ? 2 : 0),
          );
          final retained = await (fixture.database.select(
            fixture.database.vocabularyCategories,
          )..where((row) => row.id.equals('category:recovery'))).getSingle();
          expect(retained.name, 'Recovery (บทเรียนเดิม 2)');
          expect(retained.localRevision, 2);
          expect(retained.ownerId, 'reading-account');
          for (final pin in fixture.state.words) {
            final word = await (fixture.database.select(
              fixture.database.vocabularyWords,
            )..where((row) => row.id.equals(pin.id))).getSingle();
            expect(word.isDeleted, isFalse);
            expect(word.categoryId, 'category:recovery');
            expect(word.contentRevision, pin.revision);
          }
          final exported = await DriftExportReader(fixture.database).load(
            ownerId: 'reading-account',
            vocabulary: true,
            attempts: true,
            reading: true,
          );
          expect(exported.attempts, hasLength(withAnswers ? 2 : 0));
          expect(
            exported.attempts.map((attempt) => attempt.sessionId),
            everyElement(fixture.session.id),
          );
          await LocalDataDeletion(
            fixture.database,
            deleteOwnerSecrets: (_) async {},
          ).eraseAll(ownerId: 'reading-account');
          expect(
            await fixture.database
                .select(fixture.database.learningSessions)
                .get(),
            isEmpty,
          );
          expect(
            await fixture.database
                .select(fixture.database.answerAttempts)
                .get(),
            isEmpty,
          );
          expect(
            await fixture.database.select(fixture.database.eventsV2).get(),
            isEmpty,
          );
        },
      );
    }
  });
  test(
    'file-backed exact recovery restores one pending answer through two retries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-recovery-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}learning.db',
      );
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        var firstId = 0;
        final firstOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'recovery-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 12),
        );
        final owner = await firstOwners.getOrCreateActiveOwner();
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category:recovery',
                ownerId: owner.id,
                name: 'Recovery',
                normalizedName: 'recovery',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final word in const <(String, String, String)>[
          ('word:recover', 'recover', 'กู้คืน'),
          ('word:resume', 'resume', 'ทำต่อ'),
        ]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: word.$1,
                  ownerId: owner.id,
                  categoryId: 'category:recovery',
                  spelling: word.$2,
                  normalizedSpelling: word.$2,
                  meaning: word.$3,
                  normalizedMeaning: word.$3,
                  partOfSpeech: 'verb',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
        final firstLearning = LearningUseCases(
          owners: firstOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'first-${++firstId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 12, 0, firstId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final session = await firstLearning.startCheckpointedQuiz(
          activityType: 'adventureRepair',
          pinnedContent: <PinnedQuizContent>[
            _recoveryPin('word:recover', 'recover', 'กู้คืน'),
          ],
          limit: 1,
          initialState: (_) => const <String, Object?>{
            'schemaVersion': 1,
            'pendingEvidence': null,
          },
        );
        final captured = CurrentActivityEvidenceAdapter(learning: firstLearning)
            .capture(
              ownerId: owner.id,
              input: CurrentActivityInput.typedRecall,
              sessionId: session.id,
              wordId: 'word:recover',
              isCorrect: true,
              responseTimeMs: 842,
              attemptNumber: 1,
              providerProvenance: 'keyboard|local|v1',
            );
        final frozen = await captured.freezeForRecovery();
        await firstLearning.appendActivityCheckpoint(
          LearningActivityCheckpoint(
            sessionId: session.id,
            activityType: 'adventureRepair',
            revision: 2,
            occurredAtUtc: DateTime.utc(2026, 8, 30, 12, 1),
            state: <String, Object?>{
              'schemaVersion': 1,
              'pendingEvidence': frozen.toJson(),
            },
          ),
          ownerId: owner.id,
        );
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        await database.close();
        database = null;

        database = AppDatabase(NativeDatabase(file));
        var reopenedId = 0;
        final reopenedOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13),
        );
        final durableRepository = DriftLearningRepository(database);
        final recoveryReader = LearningUseCases(
          owners: reopenedOwners,
          repository: durableRepository,
          generateId: () => 'reader-${++reopenedId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13, 0, reopenedId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final recovery = await recoveryReader.loadExactActivityRecovery(
          ownerId: owner.id,
          sessionId: session.id,
          activityType: 'adventureRepair',
        );
        expect(recovery, isNotNull);
        expect(recovery!.session.id, session.id);
        expect(recovery.attempts, isEmpty);
        final checkpointState = recovery.checkpoint!.state;
        final frozenJson = (checkpointState['pendingEvidence']! as Map)
            .cast<String, Object?>();
        final decoded = FrozenPendingCurrentActivityEvidence.fromJson(
          (jsonDecode(jsonEncode(frozenJson)) as Map).cast<String, Object?>(),
        );
        expect(decoded.toJson(), frozen.toJson());

        final lostAcknowledgement = _LoseFirstRecordAcknowledgement(
          durableRepository,
        );
        final reopenedLearning = LearningUseCases(
          owners: reopenedOwners,
          repository: lostAcknowledgement,
          generateId: () => 'retry-${++reopenedId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13, 1, reopenedId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final restored = CurrentActivityEvidenceAdapter(
          learning: reopenedLearning,
        ).restore(decoded);

        await expectLater(restored.record(), throwsStateError);
        await expectLater(restored.retry(), throwsStateError);
        expect(restored.requiresRetry, isTrue);
        await database.close();
        database = null;

        database = AppDatabase(NativeDatabase(file));
        final finalRepository = DriftLearningRepository(database);
        final finalOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-final-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 14),
        );
        final finalLearning = LearningUseCases(
          owners: finalOwners,
          repository: finalRepository,
          generateId: () => 'unexpected-final-id',
          nowUtc: () => DateTime.utc(2026, 8, 30, 14, 1),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final finalRecovery = await finalLearning.loadExactActivityRecovery(
          ownerId: owner.id,
          sessionId: session.id,
          activityType: 'adventureRepair',
        );
        expect(finalRecovery!.attempts, hasLength(1));
        final afterTermination = CurrentActivityEvidenceAdapter(
          learning: finalLearning,
        ).restore(decoded);
        await expectLater(afterTermination.record(), throwsStateError);
        final replay = await afterTermination.retry();
        expect(replay.isCorrect, isTrue);
        expect(replay.inserted, isFalse);
        expect(afterTermination.isCommitted, isTrue);

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.id, frozen.sourceEvidenceId);
        final expectedEventId = LearningEvidenceContract.learningEventId(
          frozen.sourceEvidenceId,
        );
        final sourceEvents = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(expectedEventId))).get();
        expect(sourceEvents, hasLength(1));
        expect(sourceEvents.single.eventId, expectedEventId);
        expect(
          attempts.map((attempt) => attempt.id).toSet().length,
          attempts.length,
        );
        expect(
          sourceEvents.map((event) => event.eventId).toSet().length,
          sourceEvents.length,
        );
        expect(
          (await database.select(database.eventsV2).get()).where(
            (event) => event.eventType == 'LearningEvidenceDecisionSet',
          ),
          hasLength(1),
        );
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          hasLength(1),
        );
        expect(
          await database.select(database.achievementUnlocks).get(),
          hasLength(2),
        );
        expect(
          (await database.select(database.outboxOperations).get()).where(
            (operation) =>
                operation.entityType == 'attempt' &&
                operation.entityId == frozen.sourceEvidenceId,
          ),
          hasLength(1),
        );
        expect(await database.select(database.srsStates).get(), hasLength(1));
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
      } finally {
        await database?.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'generic frozen pre-write retry uses the upgraded session owner',
    () => _expectGenericOwnerUpgrade(writeBeforeUpgrade: false),
  );

  test(
    'generic frozen post-write replay preserves the historical actor',
    () => _expectGenericOwnerUpgrade(writeBeforeUpgrade: true),
  );
}

final class _ReadingFixture {
  _ReadingFixture(
    this.database,
    this.repository,
    this.learning,
    this.ownerId,
    this.session,
    this.state,
  );
  final AppDatabase database;
  final DriftLearningRepository repository;
  final LearningUseCases learning;
  final String ownerId;
  final LearningSessionHandle session;
  AssociativeReadingCheckpoint state;
  int revision = 1;

  static Future<_ReadingFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'reading-owner',
      nowUtc: () => DateTime.utc(2026, 9, 9),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:recovery',
            ownerId: owner.id,
            name: 'Recovery',
            normalizedName: 'recovery',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in ['recover', 'resume']) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word:$word',
              ownerId: owner.id,
              categoryId: 'category:recovery',
              spelling: word,
              normalizedSpelling: word,
              meaning: word,
              normalizedMeaning: word,
              partOfSpeech: 'verb',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    final repository = DriftLearningRepository(database);
    var id = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'reading-${++id}',
      nowUtc: () => DateTime.utc(2026, 9, 9, 0, 0, id),
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'reading-recovery',
      ),
    );
    final words = await repository.listQuizWords(ownerId: owner.id, limit: 2);
    final state = AssociativeReadingCheckpoint(
      documentId: 'reading:synthetic-document',
      documentRevision: 1,
      cefrLevel: 'B1',
      passage: 'Recover and resume.',
      stage: 1,
      words: words.map(
        (word) => ReadingWordPin(
          id: word.id,
          spelling: word.spelling,
          canonicalAnswer: word.normalizedSpelling!,
          revision: word.contentRevision!,
          checksum: word.contentChecksumSha256!,
          normalizationRevision: typedRecallNormalizationRevisionV1,
        ),
      ),
    );
    final session = await learning.startAssociativeReadingSessionHandle(
      pinnedContent: state.words.map((word) => word.content).toList(),
      initialState: (_) => state.toJson(),
    );
    return _ReadingFixture(
      database,
      repository,
      learning,
      owner.id,
      session,
      state,
    );
  }

  Future<LearningActivityRecovery> read() async =>
      (await repository.loadExactActivityRecovery(
        ownerId: ownerId,
        sessionId: session.id,
        activityType: 'associativeReading',
      ))!;
  Future<void> advance(int stage) async {
    final next = state.atStage(stage);
    await learning
        .captureReadingProgress(
          ownerId: ownerId,
          documentId: state.documentId,
          documentRevision: state.documentRevision,
          position: stage,
          isCompleted: false,
          activityCheckpoint: LearningActivityCheckpoint(
            sessionId: session.id,
            activityType: 'associativeReading',
            revision: revision + 1,
            occurredAtUtc: DateTime.utc(2026, 9, 9, 0, 1, revision),
            state: next.toJson(),
          ),
        )
        .save();
    state = next;
    revision++;
  }

  Future<void> answer(int index, {required bool correct}) async {
    final pin = state.words[index];
    await const TypedRecallModeAdapter()
        .capture(
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          ownerId: ownerId,
          sessionId: session.id,
          prompt: TypedRecallPrompt(
            wordId: pin.id,
            canonicalAnswer: pin.canonicalAnswer,
            promptKind: TypedRecallPromptKind.context,
            normalizationRevision: pin.normalizationRevision,
            contentRevision: pin.revision,
            contentChecksumSha256: pin.checksum,
          ),
          response: correct ? pin.canonicalAnswer : 'incorrect',
          responseTimeMs: 20,
          attemptNumber: index + 1,
          support: const TypedRecallSupport.unassisted(),
        )
        .pending
        .record();
  }

  Future<void> completeRecall() async {
    await advance(2);
    await advance(3);
    await answer(0, correct: true);
    await answer(1, correct: false);
    await advance(4);
  }
}

Future<void> _expectGenericOwnerUpgrade({
  required bool writeBeforeUpgrade,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  try {
    final suffix = writeBeforeUpgrade ? 'post' : 'pre';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'upgrade-guest-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14),
    );
    final guest = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:upgrade-$suffix',
            ownerId: guest.id,
            name: 'Upgrade',
            normalizedName: 'upgrade',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word:upgrade-$suffix',
            ownerId: guest.id,
            categoryId: 'category:upgrade-$suffix',
            spelling: 'upgrade',
            normalizedSpelling: 'upgrade',
            meaning: 'อัปเกรด',
            normalizedMeaning: 'อัปเกรด',
            partOfSpeech: 'verb',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final firstLearning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'upgrade-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'upgrade-test'),
    );
    final session = await firstLearning.startQuiz(
      categoryId: 'category:upgrade-$suffix',
      limit: 1,
    );
    final pending = CurrentActivityEvidenceAdapter(learning: firstLearning)
        .capture(
          ownerId: guest.id,
          input: CurrentActivityInput.typedRecall,
          sessionId: session.id,
          wordId: 'word:upgrade-$suffix',
          isCorrect: true,
          responseTimeMs: 420,
          attemptNumber: 1,
        );
    final frozen = await pending.freezeForRecovery();
    if (writeBeforeUpgrade) await pending.record();

    final accountId = 'upgrade-account-$suffix';
    final firebaseUid = 'firebase-upgrade-$suffix';
    await database.customInsert(
      'INSERT INTO local_owners '
      '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
      "VALUES ('$accountId', '$firebaseUid', 'firebaseBound', 2, 0)",
    );
    var upgradeId = 0;
    await DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 2),
      generateConflictId: () => 'upgrade-conflict-${++upgradeId}',
      generateOwnerId: () => 'unexpected-upgrade-owner',
      generateOwnerOperationToken: () => 'upgrade-operation-$suffix',
      deleteOwnerSecrets: (_) async {},
    ).upgrade(activeOwnerId: guest.id, firebaseUid: firebaseUid);

    final reopenedLearning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 3),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'upgrade-test'),
    );
    final restored = CurrentActivityEvidenceAdapter(
      learning: reopenedLearning,
    ).restore(frozen, ownerId: accountId);
    await expectLater(restored.record(), throwsStateError);
    final result = await restored.retry();

    expect(result.inserted, !writeBeforeUpgrade);
    final attempt = await database.select(database.answerAttempts).getSingle();
    expect(attempt.ownerId, accountId);
    final event =
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                LearningEvidenceContract.learningEventId(
                  frozen.sourceEvidenceId,
                ),
              ),
            ))
            .getSingle();
    expect(event.ownerId, accountId);
    expect(event.actorIdentity, writeBeforeUpgrade ? guest.id : accountId);
  } finally {
    await database.close();
  }
}

PinnedQuizContent _recoveryPin(String id, String spelling, String meaning) =>
    PinnedQuizContent(
      identity: ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: id,
        revision: 1,
      ),
      checksumSha256: ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category:recovery',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: meaning,
        normalizedMeaning: meaning,
        partOfSpeech: 'verb',
        cefrLevel: null,
        source: 'manual',
        isGlobal: false,
      ),
    );

final class _LoseFirstRecordAcknowledgement
    implements LearningRepository, LearningEvidenceReplayRepository {
  _LoseFirstRecordAcknowledgement(this.delegate);

  final DriftLearningRepository delegate;
  bool _loseAcknowledgement = true;

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) => delegate.replayCommittedAnswer(candidate);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    final result = await delegate.recordAnswer(command);
    if (_loseAcknowledgement) {
      _loseAcknowledgement = false;
      throw StateError('simulated lost acknowledgement');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
