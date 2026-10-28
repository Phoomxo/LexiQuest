import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'pair_matching_evidence_contract_test.dart';

class RecoverableResearchProvider
    implements CurrentActivityResearchStateProvider {
  bool fail = true;
  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required ownerId,
    required input,
    required occurredAtUtc,
    required rolloutMode,
  }) async {
    if (fail) throw StateError('synthetic context outage');
    return const BaselineCurrentActivityResearchStateProvider().resolveActivity(
      ownerId: ownerId,
      input: input,
      occurredAtUtc: occurredAtUtc,
      rolloutMode: rolloutMode,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'freeze failure retains exact captured identity and neutral retryable state',
    () async {
      var generated = 0;
      final h = PairHarness(
        evidenceId: () => 'synthetic-frozen-${++generated}',
      );
      addTearDown(h.db.close);
      await h.initialize();
      final provider = RecoverableResearchProvider();
      final c = await PairMatchingSessionCoordinator.restore(
        operation: h.operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(
          learning: h.learning,
          researchStateProvider: provider,
        ),
        activeOwnerId: () => h.owner,
      );
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      final before = jsonEncode(c.state.toJson());
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      expect(jsonEncode(c.state.toJson()), before);
      expect(generated, 1);
      expect(h.repository.checkpoints, isEmpty);
      provider.fail = false;
      await c.retryPending();
      expect(generated, 1);
      expect(
        h.repository.commands.single.id,
        'attempt:synthetic-frozen-1',
      );
      expect(c.state.matchedWordIds, {'synthetic-0'});
    },
  );
  test(
    'synchronous evidence generator failure leaves selection retryable',
    () async {
      var fail = true;
      final h = PairHarness(
        evidenceId: () {
          if (fail) throw StateError('synthetic id outage');
          return 'synthetic-recovered';
        },
      );
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      expect(c.state.pending, isNull);
      expect(c.state.selected!.wordId, 'synthetic-0');
      fail = false;
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      expect(c.state.matchedWordIds, {'synthetic-0'});
    },
  );
  test('host admission and recovery leases fence revoked callbacks', () async {
    final h = PairHarness();
    addTearDown(h.db.close);
    await h.initialize();
    var accepts = true, revokeInsideLease = false, insideLease = false;
    var admitted = 0, recovery = 0;
    final c = await PairMatchingSessionCoordinator.restore(
      operation: h.operation,
      learning: h.learning,
      evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
      activeOwnerId: () => h.owner,
      acceptsOperation: () => accepts && insideLease,
      runAdmittedOperation: (action) async {
        admitted++;
        if (revokeInsideLease) accepts = false;
        insideLease = true;
        try {
          await action();
        } finally {
          insideLease = false;
        }
      },
      runRecoveryOperation: (action) async {
        recovery++;
        insideLease = true;
        try {
          await action();
        } finally {
          insideLease = false;
        }
      },
    );
    await h.tap(c, 'synthetic-0', PairTileSide.prompt);
    revokeInsideLease = true;
    await expectLater(
      h.tap(c, 'synthetic-0', PairTileSide.target),
      throwsStateError,
    );
    expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
    expect(h.repository.checkpoints, isEmpty);
    revokeInsideLease = false;
    accepts = true;
    h.repository.answerFault = true;
    await expectLater(
      h.tap(c, 'synthetic-0', PairTileSide.target),
      throwsStateError,
    );
    await c.retryPending();
    expect(admitted, 3);
    expect(recovery, 1);
    expect(c.state.matchedWordIds, {'synthetic-0'});
  });
  test(
    'file reopen recovers exact frozen evidence without minting another ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-pm2-synthetic-',
      );
      final file = File('${directory.path}/pair.sqlite');
      final h = PairHarness(executor: NativeDatabase(file));
      await h.initialize();
      final c = await h.restore();
      h.repository.answerFault = true;
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      final operationBytes = h.operation.stableSerialization;
      c.dispose();
      await h.db.close();
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await file.delete();
        await directory.delete();
      });
      final learning = LearningUseCases(
        owners: DriftLocalOwnerRepository(
          db,
          generateId: () => throw StateError('must not create owner'),
          nowUtc: () => DateTime.utc(2026, 9, 5),
        ),
        repository: DriftLearningRepository(db),
        generateId: () => throw StateError('must not mint evidence'),
        nowUtc: () => DateTime.utc(2026, 9, 5, 1),
        buildInfo: const AppBuildInfo(
          version: 'synthetic',
          buildId: 'synthetic',
        ),
      );
      final restored = await PairMatchingSessionCoordinator.restore(
        operation: PairMatchingStartOperation.fromStableSerialization(
          operationBytes,
        ),
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        activeOwnerId: () => 'synthetic-owner',
      );
      await restored.retryPending();
      expect(
        (await db.select(db.answerAttempts).get()).single.id,
        'attempt:synthetic-evidence-1',
      );
      expect(restored.state.matchedWordIds, {'synthetic-0'});
    },
  );
  test(
    'committed command duplicates and disposed callbacks cannot write again',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      final command = PairSelectTile(
        operationId: '1:exact',
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        roundOrdinal: 0,
        expectedRevision: 1,
        tile: const PairTile(PairTileSide.target, 'synthetic-0'),
        responseTimeMs: 25,
      );
      await c.dispatch(command);
      await c.dispatch(command);
      expect(h.nextId, 1);
      expect(h.repository.checkpoints, hasLength(2));
      await expectLater(
        c.dispatch(
          PairSelectTile(
            operationId: '1:exact',
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            roundOrdinal: 0,
            expectedRevision: 1,
            tile: const PairTile(PairTileSide.target, 'synthetic-1'),
            responseTimeMs: 25,
          ),
        ),
        throwsStateError,
      );
      c.dispose();
      await expectLater(c.dispatch(command), throwsStateError);
      expect(await h.db.select(h.db.answerAttempts).get(), hasLength(1));
    },
  );
  for (final after in [false, true]) {
    for (final boundary in ['pending', 'answer', 'clear']) {
      test('real Drift exact retry $boundary afterWrite=$after', () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        var c = await h.restore();
        h.repository.afterWrite = after;
        if (boundary == 'answer') {
          h.repository.answerFault = true;
        } else {
          h.repository.checkpointFault = boundary == 'pending' ? 2 : 3;
        }
        await h.tap(c, 'synthetic-0', PairTileSide.prompt);
        await expectLater(
          h.tap(c, 'synthetic-0', PairTileSide.target),
          throwsStateError,
        );
        final frozen = h.repository.checkpoints.first;
        if (boundary == 'pending' && !after) {
          await c.retryPending();
        } else {
          c.dispose();
          c = await h.restore();
          await c.retryPending();
        }
        expect(
          (await h.db.select(h.db.answerAttempts).get()).single.id,
          'attempt:synthetic-evidence-1',
        );
        expect(h.nextId, 1);
        expect(c.state.matchedWordIds, {'synthetic-0'});
        expect((await h.restore()).state.attempts, hasLength(1));
        if (boundary == 'pending' && !after) {
          expect(
            jsonEncode(h.repository.checkpoints[1].state),
            jsonEncode(frozen.state),
          );
          expect(
            h.repository.checkpoints[1].occurredAtUtc,
            frozen.occurredAtUtc,
          );
        }
      });
    }
  }
}
