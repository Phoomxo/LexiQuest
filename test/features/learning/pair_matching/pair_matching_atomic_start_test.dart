import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'pair_matching_source_composer_test.dart' as f;

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
          state: {...operation.initialCheckpoint.state, 'operationRevision': 1},
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
