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
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
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
  bool afterWrite = false, answerFault = false, closeFault = false;
  Future<void> Function()? beforeAnswer;
  final checkpoints = <LearningActivityCheckpoint>[];
  final commands = <RecordAnswerCommand>[];
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    final fail = closeFault;
    closeFault = false;
    if (fail && !afterWrite) throw StateError('synthetic close before write');
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    if (fail) throw StateError('synthetic close lost ack');
    return result;
  }

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
  Future<void> confirm(PairMatchingSessionCoordinator c, String word) =>
      c.dispatch(
        PairConfirmGuidedMapping(
          operationId: '${c.state.operationRevision}:confirm',
          ownerId: owner,
          sessionId: operation.plan.learningSessionId,
          roundOrdinal: c.state.roundOrdinal,
          expectedRevision: c.state.operationRevision,
          wordId: word,
          shownSupportRevision: c.state.supportAtRevision[word]!,
          responseTimeMs: 25,
        ),
      );

  /// Adversarial but valid schedule: guess wrong while two playable identities
  /// remain; otherwise complete available spacing or explicitly confirm tail.
  Future<void> finishBounded(PairMatchingSessionCoordinator c) async {
    var steps = 0;
    while (!c.state.complete) {
      if (++steps > 18) {
        throw StateError('synthetic finite tail bound exceeded');
      }
      final playable = operation.plan.orderedLexicalItems
          .map((i) => i.wordId)
          .where(
            (id) =>
                !c.state.matchedWordIds.contains(id) &&
                c.state.repairFor(id)?.status != PairRepairStatus.waiting &&
                c.state.repairFor(id)?.status !=
                    PairRepairStatus.guidedRequired,
          )
          .toList();
      if (playable.isNotEmpty) {
        await tap(c, playable.first, PairTileSide.prompt);
        await tap(
          c,
          playable.length > 1 ? playable[1] : playable.first,
          PairTileSide.target,
        );
      } else {
        await confirm(
          c,
          c.state.repairTickets
              .firstWhere((t) => t.status == PairRepairStatus.guidedRequired)
              .wordId,
        );
      }
    }
  }
}

void main() {
  for (final version in [1, 2]) {
    test(
      'historical codec $version cannot admit an immediate repair answer',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final c = await h.restore();
        await h.tap(c, 'synthetic-0', PairTileSide.prompt);
        await h.tap(c, 'synthetic-1', PairTileSide.target);
        final original = c.state.attempts.single;
        Future<({Map<String, dynamic> source, Map<String, Object?> public})>
        fixture(PairAttemptRole role) async {
          final a = PairAttemptRequested(
            operationId: '${c.state.operationRevision}:forged',
            fingerprint: original.fingerprint,
            promptWordId: 'synthetic-0',
            targetWordId: 'synthetic-0',
            roundOrdinal: 0,
            role: role,
            responseTimeMs: 25,
          );
          final source =
              jsonDecode(jsonEncode(h.repository.checkpoints.last.state))
                  as Map<String, dynamic>;
          final public = c.state.toJson();
          public['pending'] = a.toJson();
          public['operationRevision'] = c.state.operationRevision + 1;
          public['lastOperationId'] = a.operationId;
          public['lastFingerprint'] = a.fingerprint;
          final ids = h.operation.plan.orderedLexicalItems
              .map((i) => i.wordId)
              .toList();
          Map<String, Object?> compact(Map<String, Object?> row) => row.map(
            (k, v) => k == 'promptWordId'
                ? MapEntry('promptIndex', ids.indexOf(v as String))
                : k == 'targetWordId'
                ? MapEntry('targetIndex', ids.indexOf(v as String))
                : MapEntry(k, v),
          );
          final engine = version == 1
              ? Map<String, Object?>.of(public)
              : Map<String, Object?>.from(source['engine'] as Map);
          engine['pending'] = compact(a.toJson());
          engine['attempts'] = c.state.attempts
              .map((a) => compact(a.toJson()))
              .toList();
          engine['operationRevision'] = public['operationRevision'];
          engine['lastOperationId'] = a.operationId;
          engine['lastFingerprint'] = a.fingerprint;
          source['engine'] = engine;
          source['codecVersion'] = version;
          // Build an actual historical shape; v3-only fields cannot belong to
          // a codec1/2 fixture. The strict chronology assertions stay unchanged.
          source.remove('timer');
          source.remove('roundSeed');
          source.remove('terminal');
          if (version == 1) {
            source['startOperation'] = h.operation.stableSerialization;
          }
          final frozen =
              await CurrentActivityEvidenceAdapter(learning: h.learning)
                  .captureMatching(
                    ownerId: h.owner,
                    sessionId: h.operation.plan.learningSessionId,
                    wordId: a.promptWordId,
                    isCorrect: a.isCorrect,
                    responseTimeMs: a.responseTimeMs,
                    attemptNumber: c.state.attempts.length + 1,
                    contentRevision: h
                        .repository
                        .commands
                        .first
                        .evidenceContext
                        .contentRevision,
                    classification: const HintEvidenceClassification(
                      evidenceClass: EvidenceClass.recognition,
                      hintLevel: 0,
                    ),
                  )
                  .freezeForRecovery();
          source['frozenEvidence'] = frozen.toJson();
          expect(
            FrozenPendingCurrentActivityEvidence.fromJson(
              source['frozenEvidence'] as Map<String, Object?>,
            ).wordId,
            a.promptWordId,
          );
          return (source: source, public: public);
        }

        final invalid = await fixture(PairAttemptRole.independentRetry);
        final source = invalid.source;
        // This direct assertion has no frozen-envelope binding boundary: the
        // failure must specifically be the repair chronology fence.
        expect(
          () => PairMatchingState.fromJson(h.operation.plan, invalid.public),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'strict path',
              'Pair repair chronology changed',
            ),
          ),
        );
        expect(
          () => PairMatchingCheckpointCodec.decode(source),
          throwsFormatException,
        );
        await expectLater(
          h.learning.appendActivityCheckpoint(
            LearningActivityCheckpoint(
              sessionId: h.operation.plan.learningSessionId,
              activityType: 'matching',
              revision: c.checkpointRevision + 1,
              occurredAtUtc: h.learning.nowUtc(),
              state: source,
            ),
            ownerId: h.owner,
          ),
          throwsStateError,
        );
        expect(await h.db.select(h.db.answerAttempts).get(), hasLength(1));
        expect((await h.restore()).state.attempts, hasLength(1));
        for (final i in [1, 2]) {
          await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(c, 'synthetic-$i', PairTileSide.target);
        }
        // Same codec shape and real capture path become valid once the two
        // committed distinct other pairs make this delayed repair available.
        final valid = await fixture(PairAttemptRole.delayedRepair);
        final decoded = PairMatchingCheckpointCodec.decode(valid.source);
        expect(decoded.engine.pending!.role, PairAttemptRole.delayedRepair);
        expect(decoded.frozenEvidence == null, false);
        expect(decoded.evidenceIds, hasLength(3));
        expect(await h.db.select(h.db.answerAttempts).get(), hasLength(3));
      },
    );
  }
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
  for (final count in [4, 6]) {
    test(
      'Thai256 IDs and canonical197 evidence IDs bounded pending admission $count',
      () async {
        final items = List.generate(count, (i) {
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
          density: count == 4 ? PairDensity.compact4 : PairDensity.standard6,
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
          // Canonical binding prefixes "attempt:" (8 bytes): 189 + 8 = 197.
          evidenceId: () => '${'x' * 186}${(++id).toString().padLeft(3, '0')}',
        );
        addTearDown(h.db.close);
        if (count == 6) {
          await h.db.customStatement(
            "CREATE TRIGGER synthetic_no_large_pair_start BEFORE INSERT ON learning_sessions BEGIN SELECT RAISE(ABORT, 'session insert reached'); END",
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
          expect(id, 0);
          return;
        }
        await h.initialize();
        var c = await h.restore();
        await h.tap(c, items[0].wordId, PairTileSide.prompt);
        h.repository.answerFault = true;
        h.repository.afterWrite = true;
        await expectLater(
          h.tap(c, items[1].wordId, PairTileSide.target),
          throwsStateError,
        );
        c.dispose();
        c = await h.restore();
        await c.retryPending();
        final before = jsonEncode(c.state.toJson());
        final idsBefore = id, writesBefore = h.repository.checkpoints.length;
        await expectLater(
          h.tap(c, items[0].wordId, PairTileSide.prompt),
          throwsStateError,
        );
        expect(jsonEncode(c.state.toJson()), before);
        expect(id, idsBefore);
        expect(h.repository.checkpoints.length, writesBefore);
        await h.tap(c, items[1].wordId, PairTileSide.prompt);
        h.repository.checkpointFault =
            h.repository.checkpoints.last.revision + 2;
        await expectLater(
          h.tap(c, items[2].wordId, PairTileSide.target),
          throwsStateError,
        );
        await c.retryPending();
        await h.finishBounded(c);
        expect(c.state.complete, true);
        expect(
          await h.db.select(h.db.answerAttempts).get(),
          hasLength(c.state.attempts.length),
        );
        for (final checkpoint in h.repository.checkpoints) {
          expect(
            utf8.encode(jsonEncode(checkpoint.state)).length,
            lessThanOrEqualTo(65536),
          );
        }
        expect(c.state.attempts.where((a) => a.isCorrect), hasLength(count));
        expect(c.state.attempts.where((a) => !a.isCorrect), isNotEmpty);
        final maximumPendingBytes = h.repository.checkpoints
            .map((c) => utf8.encode(jsonEncode(c.state)).length)
            .reduce((a, b) => a > b ? a : b);
        printOnFailure(
          'PM3 admitted Thai256 compact4 maximum written snapshot: $maximumPendingBytes bytes',
        );
      },
    );
  }
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
      for (final i in [1, 2, 3]) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      final attempts = await h.db.select(h.db.answerAttempts).get();
      expect(attempts.map((a) => a.evidenceClass), [
        'recognition',
        'recognition',
        'recognition',
        'recognition',
        'guidedPractice',
      ]);
      expect(c.state.matchedWordIds, {
        'synthetic-0',
        'synthetic-1',
        'synthetic-2',
        'synthetic-3',
      });
      expect((await h.restore()).state.attempts.map((a) => a.role), [
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.firstOpportunity,
        PairAttemptRole.delayedRepair,
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
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-1', PairTileSide.target);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.prompt),
        throwsStateError,
      );
      await h.finishBounded(c);
      expect(c.state.complete, true);
      expect(c.checkpointRevision, lessThanOrEqualTo(59));
      final answers = await h.db.select(h.db.answerAttempts).get();
      expect(answers.length, 13);
      expect(answers.where((a) => a.isCorrect), hasLength(6));
      expect((await h.restore()).state.complete, true);
      final maximumPendingBytes = h.repository.checkpoints
          .map((c) => utf8.encode(jsonEncode(c.state)).length)
          .reduce((a, b) => a > b ? a : b);
      final reservedInitial =
          PairMatchingCheckpointCodec.reservedCompletionBytes(
            PairMatchingCheckpointSnapshot(
              engine: PairMatchingState.initial(h.operation.plan),
              startOperation: h.operation.stableSerialization,
            ),
          );
      printOnFailure(
        'PM3 six-pair 13-attempt schedule: maximum written $maximumPendingBytes bytes; initial worst-future reservation $reservedInitial bytes',
      );
    },
  );
}
