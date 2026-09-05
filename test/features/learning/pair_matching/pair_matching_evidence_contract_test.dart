import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'pair_matching_source_composer_test.dart' as f;

/// Faults wrap real SQL persistence; no fake answer/evidence authority.
class PairFaultRepository
    implements
        LearningRepository,
        LearningActivityRecoveryRepository,
        LearningEvidenceReplayRepository {
  PairFaultRepository(this.delegate);
  final DriftLearningRepository delegate;
  int? checkpointFault;
  bool afterWrite = false, answerFault = false;
  Future<void> Function()? beforeAnswer;
  final checkpoints = <LearningActivityCheckpoint>[];
  final commands = <RecordAnswerCommand>[];
  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    checkpoints.add(checkpoint);
    final fail = checkpointFault == checkpoint.revision;
    if (fail) checkpointFault = null;
    if (fail && !afterWrite) {
      throw StateError('synthetic checkpoint before commit');
    }
    await delegate.appendActivityCheckpoint(
      ownerId: ownerId,
      checkpoint: checkpoint,
    );
    if (fail) throw StateError('synthetic checkpoint lost ack');
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    await beforeAnswer?.call();
    final fail = answerFault;
    answerFault = false;
    if (fail && !afterWrite) throw StateError('synthetic answer before commit');
    final result = await delegate.recordAnswer(command);
    if (fail) throw StateError('synthetic answer lost ack');
    return result;
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) => delegate.replayCommittedAnswer(candidate);
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

class PairHarness {
  PairHarness({
    this.direction = PairDirection.enToTh,
    this.density = PairDensity.compact4,
    this.pinnedPlan,
    this.launchId = 'synthetic-operation',
    this.buildTag = 'synthetic',
    this.evidenceId,
    QueryExecutor? executor,
  }) : db = AppDatabase(executor ?? NativeDatabase.memory());
  final AppDatabase db;
  final PairDirection direction;
  final PairDensity density;
  final PairMatchingPlanV1? pinnedPlan;
  final String launchId, buildTag;
  final String Function()? evidenceId;
  late DriftLearningRepository real;
  late PairFaultRepository repository;
  late LearningUseCases learning;
  late PairMatchingStartOperation operation;
  var nextId = 0;
  String owner = 'synthetic-owner';
  Future<void> initialize() async {
    owner = pinnedPlan?.ownerId ?? owner;
    await db
        .into(db.localOwners)
        .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
    await db
        .into(db.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-category',
            ownerId: owner,
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final items =
        pinnedPlan?.orderedLexicalItems ??
        List.generate(density.pairCount, f.fixture);
    for (final i in items) {
      await db
          .into(db.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: i.wordId,
              ownerId: owner,
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
    real = DriftLearningRepository(db);
    repository = PairFaultRepository(real);
    learning = LearningUseCases(
      owners: DriftLocalOwnerRepository(
        db,
        generateId: () => owner,
        nowUtc: () => DateTime.utc(2026, 9, 5),
      ),
      repository: repository,
      generateId: evidenceId ?? () => 'synthetic-evidence-${++nextId}',
      nowUtc: () => DateTime.utc(2026, 9, 5, 0, 1),
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'synthetic'),
    );
    final plan =
        pinnedPlan ??
        (f.compose(
                  items,
                  launch: f.intent(direction: direction, density: density),
                )
                as PairPlanReady)
            .plan;
    operation = PairMatchingStartOperation(
      plan: plan,
      launchOperationId: launchId,
      appVersion: buildTag,
      buildId: buildTag,
    );
    await PairMatchingAtomicStartAdapter(
      repository: real,
      capability: InternalPairMatchingCapability(
        allowlist: PairCuratedAllowlist(
          version: plan.allowlistVersion,
          items: items,
        ),
        isEnabled: () => true,
      ),
    ).start(operation);
  }

  Future<PairMatchingSessionCoordinator> restore() =>
      PairMatchingSessionCoordinator.restore(
        operation: operation,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        activeOwnerId: () => owner,
      );
  Future<void> tap(
    PairMatchingSessionCoordinator c,
    String word,
    PairTileSide side,
  ) => c.dispatch(
    PairSelectTile(
      operationId: '${c.state.operationRevision}:tap',
      ownerId: owner,
      sessionId: operation.plan.learningSessionId,
      roundOrdinal: c.state.roundOrdinal,
      expectedRevision: c.state.operationRevision,
      tile: PairTile(side, word),
      responseTimeMs: 25,
    ),
  );
}

void main() {
  test(
    'initial bytes fit but mandatory byte reserve rejects before session insert',
    () async {
      final items = List.generate(6, (i) {
        final item = f.fixture(
          i,
          spelling: '${'e' * 255}$i',
          meaning: '${'ก' * 255}$i',
        );
        return PairLexicalItem(
          wordId: '${'ก' * 255}$i',
          contentRevision: 1,
          checksum: item.checksum,
          spelling: item.spelling,
          meaning: item.meaning,
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: PairSourceReason.values.where(
            (r) => r != PairSourceReason.reported,
          ),
        );
      });
      final owner = '${'\u0000' * 255}o', launch = 'ก' * 256;
      final plan = PairMatchingPlanV1(
        ownerId: owner,
        orderedLexicalItems: items,
        direction: PairDirection.thToEn,
        density: PairDensity.standard6,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.seconds120,
        allowlistVersion: 'ก' * 256,
        learningSessionId: pairSessionId(owner, launch),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 'ก' * 256,
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      final op = PairMatchingStartOperation(
        plan: plan,
        launchOperationId: launch,
        appVersion: 'ก' * 256,
        buildId: 'ก' * 256,
      );
      expect(
        PairMatchingCheckpointCodec.encodedBytes(op.initialCheckpoint.state),
        lessThan(65536),
      );
      expect(
        PairMatchingCheckpointCodec.reservedCompletionBytes(
          PairMatchingCheckpointCodec.decode(op.initialCheckpoint.state),
        ),
        greaterThan(65536),
      );
      final h = PairHarness(
        pinnedPlan: plan,
        launchId: launch,
        buildTag: 'ก' * 256,
      );
      addTearDown(h.db.close);
      // A trigger would expose any attempted insert, even one rolled back later.
      await h.db.customStatement(
        "CREATE TRIGGER synthetic_no_pair_start BEFORE INSERT ON learning_sessions BEGIN SELECT RAISE(ABORT, 'session insert reached'); END",
      );
      await expectLater(
        h.initialize(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('byte capacity'),
          ),
        ),
      );
      expect(await h.db.select(h.db.learningSessions).get(), isEmpty);
      expect(await h.db.select(h.db.eventsV2).get(), isEmpty);
    },
  );
  test(
    'permitted Thai IDs and canonical long evidence IDs complete with bounded pending snapshots',
    () async {
      final items = List.generate(6, (i) {
        final item = f.fixture(
          i,
          spelling: '${'e' * 255}$i',
          meaning: '${'ก' * 255}$i',
        );
        return PairLexicalItem(
          wordId: '${'ก' * 255}$i',
          contentRevision: item.contentRevision,
          checksum: item.checksum,
          spelling: item.spelling,
          meaning: item.meaning,
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: PairSourceReason.values.where(
            (r) => r != PairSourceReason.reported,
          ),
        );
      });
      final owner = 'o' * 256, launch = 'l' * 256;
      final plan = PairMatchingPlanV1(
        ownerId: owner,
        orderedLexicalItems: items,
        direction: PairDirection.thToEn,
        density: PairDensity.standard6,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.seconds120,
        allowlistVersion: 'a' * 256,
        learningSessionId: pairSessionId(owner, launch),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 's' * 256,
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      var id = 0;
      final h = PairHarness(
        pinnedPlan: plan,
        launchId: launch,
        buildTag: 'b' * 256,
        evidenceId: () => '${'x' * 186}${(++id).toString().padLeft(3, '0')}',
      );
      addTearDown(h.db.close);
      await h.initialize();
      var c = await h.restore();
      var wrong = 0;
      for (; wrong < 23; wrong++) {
        await h.tap(c, items[0].wordId, PairTileSide.prompt);
        final before = jsonEncode(c.state.toJson());
        final idsBefore = id, writesBefore = h.repository.checkpoints.length;
        try {
          await h.tap(c, items[1].wordId, PairTileSide.target);
        } on StateError catch (error) {
          expect(error.message, contains('byte capacity'));
          expect(jsonEncode(c.state.toJson()), before);
          expect(id, idsBefore);
          expect(h.repository.checkpoints.length, writesBefore);
          break;
        }
      }
      expect(wrong, inExclusiveRange(0, 23));
      h.repository.answerFault = true;
      h.repository.afterWrite = true;
      await expectLater(
        h.tap(c, items[0].wordId, PairTileSide.target),
        throwsStateError,
      );
      c.dispose();
      c = await h.restore();
      await c.retryPending();
      for (final item in items.skip(1)) {
        await h.tap(c, item.wordId, PairTileSide.prompt);
        if (item == items[1]) {
          h.repository.checkpointFault =
              h.repository.checkpoints.last.revision + 2;
          await expectLater(
            h.tap(c, item.wordId, PairTileSide.target),
            throwsStateError,
          );
          await c.retryPending();
        } else {
          await h.tap(c, item.wordId, PairTileSide.target);
        }
      }
      expect(c.state.complete, true);
      expect(
        await h.db.select(h.db.answerAttempts).get(),
        hasLength(wrong + 6),
      );
      for (final checkpoint in h.repository.checkpoints) {
        expect(
          utf8.encode(jsonEncode(checkpoint.state)).length,
          lessThanOrEqualTo(65536),
        );
      }
    },
  );
  test(
    'owner mutation at checkpoint SQL insert rolls back entire append',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.db.customStatement(
        "CREATE TRIGGER synthetic_pair_owner_race AFTER INSERT ON events_v2 WHEN NEW.event_type = 'LearningActivityCheckpoint' BEGIN UPDATE local_owners SET is_active = 0 WHERE id = 'synthetic-owner'; END",
      );
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      expect(await h.db.select(h.db.eventsV2).get(), hasLength(1));
      expect((await h.db.select(h.db.localOwners).get()).single.isActive, true);
      expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
    },
  );
  for (final direction in PairDirection.values) {
    for (final first in PairTileSide.values) {
      test(
        'real Drift prompt-only incorrect evidence $direction $first',
        () async {
          final h = PairHarness(direction: direction);
          addTearDown(h.db.close);
          await h.initialize();
          final c = await h.restore();
          await h.tap(c, 'synthetic-0', first);
          await h.tap(c, 'synthetic-0', first);
          expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
          expect(h.repository.checkpoints, isEmpty);
          await h.tap(c, 'synthetic-0', first);
          await h.tap(
            c,
            'synthetic-1',
            first == PairTileSide.prompt
                ? PairTileSide.target
                : PairTileSide.prompt,
          );
          final attempt = (await h.db.select(h.db.answerAttempts).get()).single;
          expect(
            attempt.wordId,
            first == PairTileSide.prompt ? 'synthetic-0' : 'synthetic-1',
          );
          expect(attempt.evidenceClass, 'recognition');
          expect(attempt.isCorrect, false);
          expect(c.state.matchedWordIds, isEmpty);
          final restored = await h.restore();
          expect(
            restored.state.attempts.single.role,
            PairAttemptRole.firstOpportunity,
          );
          expect(h.nextId, 1);
        },
      );
    }
  }
  test(
    'mapping reveal survives restore without rewriting earlier evidence',
    () async {
      final h = PairHarness(density: PairDensity.standard6);
      addTearDown(h.db.close);
      await h.initialize();
      var c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-1', PairTileSide.target);
      await c.dispatch(
        PairRevealMapping(
          operationId: '${c.state.operationRevision}:reveal',
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: c.state.operationRevision,
          wordId: 'synthetic-0',
        ),
      );
      c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      final attempts = await h.db.select(h.db.answerAttempts).get();
      expect(attempts.map((a) => a.evidenceClass), [
        'recognition',
        'guidedPractice',
      ]);
      expect(c.state.matchedWordIds, {'synthetic-0'});
      expect((await h.restore()).state.attempts.map((a) => a.role), [
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.guidedCompletion,
      ]);
      expect(jsonDecode(attempts.last.evidenceContextJson)['hintLevel'], 1);
    },
  );
  test(
    'v6 deleted pinned word accepts only frozen canonical pending answer',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await (h.db.update(h.db.vocabularyWords)
            ..where((r) => r.id.equals('synthetic-0')))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      expect(
        (await h.db.select(h.db.answerAttempts).get()).single.isCorrect,
        true,
      );
    },
  );
  test(
    'owner change at actual answer boundary rejects canonical write',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      h.repository.beforeAnswer = () async {
        await (h.db.update(h.db.localOwners)
              ..where((r) => r.id.equals(h.owner)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
      };
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
    },
  );
  test('v6 checkpoint cannot downgrade or erase committed ledger', () async {
    final h = PairHarness();
    addTearDown(h.db.close);
    await h.initialize();
    final c = await h.restore();
    await h.tap(c, 'synthetic-0', PairTileSide.prompt);
    await h.tap(c, 'synthetic-0', PairTileSide.target);
    final last = h.repository.checkpoints.last;
    await expectLater(
      h.real.appendActivityCheckpoint(
        ownerId: h.owner,
        checkpoint: LearningActivityCheckpoint(
          sessionId: last.sessionId,
          activityType: 'matching',
          revision: last.revision + 1,
          occurredAtUtc: last.occurredAtUtc,
          state: {...last.state, 'schemaVersion': 5},
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      h.real.appendActivityCheckpoint(
        ownerId: h.owner,
        checkpoint: LearningActivityCheckpoint(
          sessionId: last.sessionId,
          activityType: 'matching',
          revision: last.revision + 1,
          occurredAtUtc: last.occurredAtUtc,
          state: h.operation.initialCheckpoint.state,
        ),
      ),
      throwsStateError,
    );
  });
  test(
    'M12 Pair preparation loads latest state and preserves support revision',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await c.dispatch(
        PairRevealMapping(
          operationId: '0:reveal',
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: 0,
          wordId: 'synthetic-0',
        ),
      );
      await h.tap(c, 'synthetic-1', PairTileSide.prompt);
      await c.flush();
      final latest = h.repository.checkpoints.last;
      final tampered =
          jsonDecode(jsonEncode(latest.state)) as Map<String, dynamic>;
      ((tampered['engine'] as Map)['supportAtRevision'] as Map)['0'] = 1;
      await expectLater(
        h.real.appendActivityCheckpoint(
          ownerId: h.owner,
          checkpoint: LearningActivityCheckpoint(
            sessionId: latest.sessionId,
            activityType: 'matching',
            revision: latest.revision + 1,
            occurredAtUtc: latest.occurredAtUtc,
            state: tampered,
          ),
        ),
        throwsStateError,
      );
      final restored = await const MatchingModeAdapter().preparePairSession(
        operation: h.operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
        activeOwnerId: () => h.owner,
      );
      expect(restored.state.selected!.wordId, 'synthetic-1');
      expect(restored.state.supportAtRevision['synthetic-0'], 0);
    },
  );
  test(
    'capacity boundary retains usable correct completions for six pairs',
    () async {
      final h = PairHarness(density: PairDensity.standard6);
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      for (var i = 0; i < 23; i++) {
        await h.tap(c, 'synthetic-0', PairTileSide.prompt);
        await h.tap(c, 'synthetic-1', PairTileSide.target);
      }
      expect(c.checkpointRevision, 47);
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-1', PairTileSide.target),
        throwsStateError,
      );
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      for (var i = 1; i < 6; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      expect(c.state.complete, true);
      expect(c.checkpointRevision, 59);
      expect(await h.db.select(h.db.answerAttempts).get(), hasLength(29));
      expect((await h.restore()).state.complete, true);
    },
  );
}
