import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'pair_matching_source_composer_test.dart' as f;
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';

void main() {
  late AppDatabase db;
  late DriftLearningRepository repo;
  late PairMatchingPlanV1 plan;
  late PairMatchingStartOperation operation;
  late InternalPairMatchingCapability capability;
  late _SyntheticOwnerRace race;
  var enabled = true;
  setUp(() async {
    race = _SyntheticOwnerRace();
    db = AppDatabase(NativeDatabase.memory().interceptWith(race));
    repo = DriftLearningRepository(db);
    enabled = true;
    await db
        .into(db.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'synthetic-owner', createdAtUtcMs: 1),
        );
    await db
        .into(db.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-category',
            ownerId: 'synthetic-owner',
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final items = List.generate(4, f.fixture);
    for (final i in items) {
      await db
          .into(db.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: i.wordId,
              ownerId: 'synthetic-owner',
              categoryId: 'synthetic-category',
              spelling: i.spelling,
              normalizedSpelling: i.spelling,
              meaning: i.meaning,
              normalizedMeaning: i.meaning,
              partOfSpeech: 'noun',
              contentRevision: Value(i.contentRevision),
              contentChecksumSha256: Value(i.checksum),
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    plan = (f.compose(items) as PairPlanReady).plan;
    operation = PairMatchingStartOperation(
      plan: plan,
      launchOperationId: 'synthetic-operation',
      appVersion: 'synthetic',
      buildId: 'synthetic',
    );
    capability = InternalPairMatchingCapability(
      allowlist: PairCuratedAllowlist(version: 'synthetic-v1', items: items),
      isEnabled: () => enabled,
    );
  });
  tearDown(() => db.close());
  Future<void> start([PairMatchingStartOperation? value]) =>
      PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      ).start(value ?? operation);
  test(
    'measured admission writes exact initial and zero receipt once, including gate-off retry',
    () async {
      final adapter = PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      );
      await adapter.startMeasured(operation);
      final first = await repo.loadExactActivityRecovery(
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        activityType: 'matching',
      );
      expect(first!.checkpoint!.revision, 2);
      expect(
        PairMatchingCheckpointCodec.decode(
          first.checkpoint!.state,
        ).timer!.interactiveElapsedMs,
        0,
      );
      final before = await db.select(db.eventsV2).get();
      enabled = false;
      await adapter.startMeasured(operation);
      final after = await db.select(db.eventsV2).get();
      expect(after.map((e) => e.payloadJson), before.map((e) => e.payloadJson));
      expect(
        (await repo.read(
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
        )).snapshot!.timer!.interactiveElapsedMs,
        0,
      );
    },
  );
  test(
    'measured API cannot retrofit historical initial-only admission',
    () async {
      await start();
      await PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      ).startMeasured(operation);
      final recovered = await repo.loadExactActivityRecovery(
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        activityType: 'matching',
      );
      expect(recovered!.checkpoint!.revision, 1);
      expect(
        PairMatchingCheckpointCodec.decode(recovered.checkpoint!.state).timer,
        isNull,
      );
    },
  );
  for (final boundary in ['BEFORE', 'AFTER']) {
    test(
      'measured revision2 $boundary insert failure rolls back both receipts',
      () async {
        final initialBytes = jsonEncode(operation.initialCheckpoint.state);
        final startBytes = operation.stableSerialization;
        await db.customStatement(
          "CREATE TRIGGER synthetic_measured_crash $boundary INSERT ON events_v2 "
          "WHEN json_extract(NEW.payload_json, '\$.revision') = 2 "
          "BEGIN SELECT RAISE(ABORT, 'synthetic measured revision2 crash'); END",
        );
        final adapter = PairMatchingAtomicStartAdapter(
          repository: repo,
          capability: capability,
        );
        await expectLater(adapter.startMeasured(operation), throwsA(anything));
        expect(await db.select(db.learningSessions).get(), isEmpty);
        expect(await db.select(db.eventsV2).get(), isEmpty);
        expect(await db.select(db.answerAttempts).get(), isEmpty);
        await db.customStatement('DROP TRIGGER synthetic_measured_crash');
        await adapter.startMeasured(
          PairMatchingStartOperation.fromStableSerialization(startBytes),
        );
        final rows = await db.select(db.eventsV2).get();
        expect(rows, hasLength(2));
        final initial = rows.singleWhere(
          (row) => (jsonDecode(row.payloadJson) as Map)['revision'] == 1,
        );
        expect(
          jsonEncode((jsonDecode(initial.payloadJson) as Map)['state']),
          initialBytes,
        );
        expect(
          (await repo.read(
            ownerId: plan.ownerId,
            sessionId: plan.learningSessionId,
          )).snapshot!.timer!.interactiveElapsedMs,
          0,
        );
        expect(operation.stableSerialization, startBytes);
      },
    );
  }
  test(
    'measured committed write with lost caller acknowledgement retries exact bytes gate-off',
    () async {
      final adapter = PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      );
      final startBytes = operation.stableSerialization;
      Future<void> loseAcknowledgement() async {
        await adapter.startMeasured(operation);
        // The real transaction committed; simulate loss only at its caller boundary.
        throw StateError('synthetic committed admission acknowledgement lost');
      }

      await expectLater(loseAcknowledgement(), throwsStateError);
      final before = await db.select(db.eventsV2).get();
      expect(before, hasLength(2));
      enabled = false;
      await adapter.startMeasured(
        PairMatchingStartOperation.fromStableSerialization(startBytes),
      );
      expect(await db.select(db.eventsV2).get(), before);
      expect(await db.select(db.learningSessions).get(), hasLength(1));
      expect(await db.select(db.answerAttempts).get(), isEmpty);
    },
  );
  test(
    'measured failure immediately before transaction commit rolls back durable admission',
    () async {
      final adapter = PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      );
      race.failMeasuredCommit = true;
      await expectLater(adapter.startMeasured(operation), throwsStateError);
      expect(race.measuredRowsBeforeFailedCommit, 2);
      expect(await db.select(db.learningSessions).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
      await adapter.startMeasured(operation);
      expect(await db.select(db.learningSessions).get(), hasLength(1));
      expect(await db.select(db.eventsV2).get(), hasLength(2));
    },
  );
  test(
    'generic append cannot forge measured admission at any revision or occurrence',
    () async {
      await start();
      final before = await db.select(db.eventsV2).get();
      final zero = PairMatchingCheckpointSnapshot(
        engine: PairMatchingState.initial(plan),
        startOperation: operation.stableSerialization,
        timer: PairTimerState.initial(
          plan.timerPreset,
        ).copy(interactiveElapsedMs: 0),
      ).toJson();
      for (final revision in [2, 3]) {
        for (final offset in [Duration.zero, const Duration(seconds: 1)]) {
          await expectLater(
            repo.appendActivityCheckpoint(
              ownerId: plan.ownerId,
              checkpoint: LearningActivityCheckpoint(
                sessionId: plan.learningSessionId,
                activityType: 'matching',
                revision: revision,
                occurredAtUtc: plan.createdAtUtc.add(offset),
                state: zero,
              ),
            ),
            throwsStateError,
          );
          expect(await db.select(db.eventsV2).get(), before);
        }
      }
      await PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      ).startMeasured(operation);
      expect(await db.select(db.eventsV2).get(), before);
    },
  );
  test(
    'persisted measured admission with changed occurrence fails strict purpose reader',
    () async {
      await PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      ).startMeasured(operation);
      expect(
        (await repo.read(
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
        )).snapshot!.timer!.interactiveElapsedMs,
        0,
      );
      await db.customStatement(
        "UPDATE events_v2 SET occurred_at_utc = occurred_at_utc + 1 "
        "WHERE aggregate_id = ? AND json_extract(payload_json, '\$.revision') = 2",
        [plan.learningSessionId],
      );
      await expectLater(
        repo.read(ownerId: plan.ownerId, sessionId: plan.learningSessionId),
        throwsStateError,
      );
    },
  );
  test(
    'measured coverage cannot be initialized a second time after durable null',
    () async {
      await PairMatchingAtomicStartAdapter(
        repository: repo,
        capability: capability,
      ).startMeasured(operation);
      final unmeasured = PairMatchingCheckpointSnapshot(
        engine: PairMatchingState.initial(plan),
        startOperation: operation.stableSerialization,
        timer: PairTimerState.initial(plan.timerPreset),
      );
      await repo.appendActivityCheckpoint(
        ownerId: plan.ownerId,
        checkpoint: LearningActivityCheckpoint(
          sessionId: plan.learningSessionId,
          activityType: 'matching',
          revision: 3,
          occurredAtUtc: plan.createdAtUtc,
          state: unmeasured.toJson(),
        ),
      );
      final before = await db.select(db.eventsV2).get();
      final zero = PairMatchingCheckpointSnapshot(
        engine: unmeasured.engine,
        startOperation: operation.stableSerialization,
        timer: unmeasured.timer!.copy(interactiveElapsedMs: 0),
      );
      await expectLater(
        repo.appendActivityCheckpoint(
          ownerId: plan.ownerId,
          checkpoint: LearningActivityCheckpoint(
            sessionId: plan.learningSessionId,
            activityType: 'matching',
            revision: 4,
            occurredAtUtc: plan.createdAtUtc,
            state: zero.toJson(),
          ),
        ),
        throwsStateError,
      );
      expect(await db.select(db.eventsV2).get(), before);
      expect(
        (await repo.read(
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
        )).snapshot!.timer!.interactiveElapsedMs,
        isNull,
      );
    },
  );
  test(
    'Pair initial rejects progressed codec and mismatched start build',
    () async {
      final progressed = PairMatchingCheckpointSnapshot(
        engine: PairMatchingState.initial(plan),
        startOperation: operation.stableSerialization,
      ).toJson();
      final changedStart =
          jsonDecode(operation.stableSerialization) as Map<String, dynamic>;
      changedStart['buildId'] = 'synthetic-other-build';
      for (final state in [
        progressed,
        {
          ...operation.initialCheckpoint.state,
          'startOperation': jsonEncode(changedStart),
        },
      ]) {
        await expectLater(
          repo.startPinnedPairSession(
            session: operation.session,
            plan: plan,
            launchOperationId: operation.launchOperationId,
            checkpoint: LearningActivityCheckpoint(
              sessionId: plan.learningSessionId,
              activityType: 'matching',
              revision: 1,
              occurredAtUtc: plan.createdAtUtc,
              state: state,
            ),
            capability: capability,
          ),
          throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
        );
        expect(await db.select(db.learningSessions).get(), isEmpty);
      }
    },
  );
  test('generic learning start cannot bypass Pair capability', () async {
    await expectLater(
      repo.startSessionWithCheckpoint(
        session: operation.session,
        checkpoint: operation.initialCheckpoint,
      ),
      throwsStateError,
    );
    await expectLater(
      () => repo.startExactPinnedSessionWithCheckpoint(
        session: operation.session,
        content: plan.orderedLexicalItems
            .map(
              (i) => PinnedQuizContent(
                identity: ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: i.wordId,
                  revision: i.contentRevision,
                ),
                checksumSha256: i.checksum,
              ),
            )
            .toList(),
        checkpoint: operation.initialCheckpoint,
      ),
      throwsStateError,
    );
    expect(await db.select(db.learningSessions).get(), isEmpty);
    await repo.startSession(operation.session);
    await expectLater(
      repo.appendActivityCheckpoint(
        ownerId: plan.ownerId,
        checkpoint: operation.initialCheckpoint,
      ),
      throwsStateError,
    );
    expect(await db.select(db.eventsV2).get(), isEmpty);
  });
  test(
    'atomic start/restart lost ack uses identical session and initial checkpoint',
    () async {
      await start();
      final restored = PairMatchingStartOperation.fromStableSerialization(
        operation.stableSerialization,
      );
      await start(restored);
      expect(await db.select(db.learningSessions).get(), hasLength(1));
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      final recovery = await repo.loadExactActivityRecovery(
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        activityType: 'matching',
      );
      expect(recovery!.checkpoint!.state['schemaVersion'], 6);
      expect(
        recovery.checkpoint!.state['planFingerprint'],
        plan.planFingerprint,
      );
    },
  );
  test(
    'same-revision checksum tampering rejects start without writes',
    () async {
      await (db.update(
        db.vocabularyWords,
      )..where((r) => r.id.equals('synthetic-0'))).write(
        VocabularyWordsCompanion(
          contentChecksumSha256: Value(List.filled(64, 'f').join()),
        ),
      );
      expect(
        (await (db.select(
              db.vocabularyWords,
            )..where((r) => r.id.equals('synthetic-0'))).getSingle())
            .contentRevision,
        1,
      );
      await expectLater(start(), throwsA(isA<ContentQualityFailure>()));
      expect(await db.select(db.learningSessions).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
    },
  );
  test('reported content rejected before session write', () async {
    await db
        .into(db.contentQualityReports)
        .insert(
          ContentQualityReportsCompanion.insert(
            id: 'synthetic-report',
            ownerId: plan.ownerId,
            contentType: 'lexicalMetadata',
            contentId: plan.orderedLexicalItems.first.wordId,
            contentRevision: 1,
            reasonCode: 'incorrectMeaning',
            submittedAtUtcMs: 1,
          ),
        );
    await expectLater(start(), throwsStateError);
    expect(await db.select(db.learningSessions).get(), isEmpty);
  });
  test(
    'file-backed process restart reconciles exact serialized launch',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'lexiquest-pm1-synthetic-',
      );
      final file = File(
        '${temporary.path}${Platform.pathSeparator}synthetic.sqlite',
      );
      final owners = await db.select(db.localOwners).get();
      final categories = await db.select(db.vocabularyCategories).get();
      final words = await db.select(db.vocabularyWords).get();
      await db.close();
      var persisted = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await persisted.close();
        // Delete only this test-created directory in the expected temp parent.
        if (temporary.parent.absolute.path !=
                Directory.systemTemp.absolute.path ||
            !temporary.path.contains('lexiquest-pm1-synthetic-')) {
          throw StateError('Unexpected synthetic temporary directory');
        }
        await temporary.delete(recursive: true);
      });
      for (final row in owners) {
        await persisted
            .into(persisted.localOwners)
            .insert(row.toCompanion(false));
      }
      for (final row in categories) {
        await persisted
            .into(persisted.vocabularyCategories)
            .insert(row.toCompanion(false));
      }
      for (final row in words) {
        await persisted
            .into(persisted.vocabularyWords)
            .insert(row.toCompanion(false));
      }
      final bytes = operation.stableSerialization;
      await PairMatchingAtomicStartAdapter(
        repository: DriftLearningRepository(persisted),
        capability: capability,
      ).start(operation);
      await persisted.close();
      persisted = AppDatabase(NativeDatabase(file));
      await PairMatchingAtomicStartAdapter(
        repository: DriftLearningRepository(persisted),
        capability: capability,
      ).start(PairMatchingStartOperation.fromStableSerialization(bytes));
      expect(
        await persisted.select(persisted.learningSessions).get(),
        hasLength(1),
      );
      expect(await persisted.select(persisted.eventsV2).get(), hasLength(1));
      expect(await persisted.select(persisted.answerAttempts).get(), isEmpty);
    },
  );
  test(
    'owner switch between Pair source check and canonical start rolls back',
    () async {
      race.armed = true;
      await expectLater(start(), throwsStateError);
      expect(race.didSwitch, isTrue);
      expect(await db.select(db.learningSessions).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
    },
  );
  test('concurrent duplicate start commits one immutable operation', () async {
    await Future.wait([start(), start()]);
    expect(await db.select(db.learningSessions).get(), hasLength(1));
    expect(await db.select(db.eventsV2).get(), hasLength(1));
    final altered = PairMatchingStartOperation(
      plan: plan,
      launchOperationId: 'synthetic-operation',
      appVersion: 'changed-synthetic',
      buildId: 'synthetic',
    );
    await expectLater(start(altered), throwsStateError);
    expect(await db.select(db.eventsV2).get(), hasLength(1));
  });
  test(
    'gate-off after commit permits exact lost-ack reconciliation only',
    () async {
      await start();
      enabled = false;
      await start(
        PairMatchingStartOperation.fromStableSerialization(
          operation.stableSerialization,
        ),
      );
      expect(await db.select(db.learningSessions).get(), hasLength(1));
      expect(await db.select(db.eventsV2).get(), hasLength(1));
      final changed = PairMatchingStartOperation(
        plan: plan,
        launchOperationId: 'synthetic-operation',
        appVersion: 'changed-synthetic',
        buildId: 'synthetic',
      );
      await expectLater(start(changed), throwsStateError);
    },
  );
  test(
    'owner switch, deleted, revision drift and disabled delivery fail closed',
    () async {
      enabled = false;
      await expectLater(start(), throwsStateError);
      enabled = true;
      await (db.update(db.vocabularyWords)
            ..where((r) => r.id.equals('synthetic-0')))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
      await expectLater(start(), throwsStateError);
      await (db.update(
        db.vocabularyWords,
      )..where((r) => r.id.equals('synthetic-0'))).write(
        const VocabularyWordsCompanion(
          isDeleted: Value(false),
          contentRevision: Value(2),
        ),
      );
      await expectLater(start(), throwsStateError);
      await (db.update(db.localOwners)..where((r) => r.id.equals(plan.ownerId)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await expectLater(start(), throwsStateError);
      expect(await db.select(db.learningSessions).get(), isEmpty);
    },
  );
  test(
    'SQLite crash at checkpoint insert rolls back canonical session',
    () async {
      await db.customStatement(
        "CREATE TRIGGER synthetic_pair_crash BEFORE INSERT ON events_v2 BEGIN SELECT RAISE(ABORT, 'synthetic crash'); END",
      );
      await expectLater(start(), throwsA(anything));
      expect(await db.select(db.learningSessions).get(), isEmpty);
      await db.customStatement('DROP TRIGGER synthetic_pair_crash');
      await start();
      expect(await db.select(db.learningSessions).get(), hasLength(1));
    },
  );
  test(
    'gate revoked during persistence rolls back session and checkpoint',
    () async {
      var checks = 0;
      capability = InternalPairMatchingCapability(
        allowlist: capability.allowlist,
        isEnabled: () => ++checks < 3,
      );
      await expectLater(start(), throwsStateError);
      expect(await db.select(db.learningSessions).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
    },
  );
  test(
    'lost ack reconciles initial immutable event after checkpoint advances',
    () async {
      await start();
      await repo.appendActivityCheckpoint(
        ownerId: plan.ownerId,
        checkpoint: LearningActivityCheckpoint(
          sessionId: plan.learningSessionId,
          activityType: 'matching',
          revision: 2,
          occurredAtUtc: plan.createdAtUtc.add(const Duration(seconds: 1)),
          state: PairMatchingCheckpointSnapshot(
            engine: PairMatchingEngine.reduce(
              PairMatchingState.initial(plan),
              PairSelectTile(
                operationId: '0:select',
                ownerId: plan.ownerId,
                sessionId: plan.learningSessionId,
                roundOrdinal: 0,
                expectedRevision: 0,
                tile: const PairTile(PairTileSide.prompt, 'synthetic-0'),
                responseTimeMs: 0,
              ),
            ).state,
            startOperation: operation.stableSerialization,
          ).toJson(),
        ),
      );
      await start(
        PairMatchingStartOperation.fromStableSerialization(
          operation.stableSerialization,
        ),
      );
      expect(await db.select(db.eventsV2).get(), hasLength(2));
    },
  );
  test('category deletion and retired content rejected before write', () async {
    await (db.update(db.vocabularyCategories)
          ..where((r) => r.id.equals('synthetic-category')))
        .write(const VocabularyCategoriesCompanion(isDeleted: Value(true)));
    await expectLater(start(), throwsStateError);
    await (db.update(db.vocabularyCategories)
          ..where((r) => r.id.equals('synthetic-category')))
        .write(const VocabularyCategoriesCompanion(isDeleted: Value(false)));
    await (db.update(
      db.vocabularyWords,
    )..where((r) => r.id.equals('synthetic-0'))).write(
      const VocabularyWordsCompanion(contentPublicationState: Value('retired')),
    );
    await expectLater(start(), throwsStateError);
    expect(await db.select(db.learningSessions).get(), isEmpty);
  });
}

/// Synthetic race at a real SQL boundary, inside the same transaction. It
/// exercises the canonical owner's second check without timing assumptions.
final class _SyntheticOwnerRace extends QueryInterceptor {
  bool armed = false;
  bool didSwitch = false;
  bool failMeasuredCommit = false;
  int? measuredRowsBeforeFailedCommit;
  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    if (failMeasuredCommit) {
      final rows = await inner.runSelect(
        "SELECT payload_json FROM events_v2 WHERE event_type = 'LearningActivityCheckpoint'",
        [],
      );
      final revisions = rows
          .map(
            (row) =>
                (jsonDecode(row['payload_json'] as String) as Map)['revision'],
          )
          .toSet();
      if (revisions.contains(1) && revisions.contains(2)) {
        failMeasuredCommit = false;
        measuredRowsBeforeFailedCommit = rows.length;
        throw StateError(
          'synthetic failure before measured transaction commit',
        );
      }
    }
    await super.commitTransaction(inner);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (armed && statement.contains('vocabulary_words')) {
      armed = false;
      didSwitch = true;
      await executor.runUpdate(
        'UPDATE local_owners SET is_active = 0 WHERE id = ?',
        ['synthetic-owner'],
      );
    }
    return super.runSelect(executor, statement, args);
  }
}
