import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_practice_replay.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  test(
    'configured maximum Thai plan counts actual envelope bytes and rejects before INSERT',
    () async {
      const policy = SessionConfigurationPolicy(),
          limits = SessionConfigurationProtocolLimits.standard();
      final registration = LessonModeRegistration(
        adapter: const MatchingModeAdapter(),
        feature: Feature.quiz,
        productionEntryId: 'home/learn/quiz',
        routeName: 'learning/test',
        deliveryState: LessonModeDeliveryState.enabled,
      );
      final owner = 'o' * 256, launch = 'l' * 256;
      final configuration = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 6),
        registration: registration,
        limits: limits,
        ownerId: owner,
        availablePackIdentities: const [],
      );
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
      final plan = PairMatchingPlanV1(
        ownerId: owner,
        orderedLexicalItems: items,
        direction: PairDirection.enToTh,
        density: PairDensity.standard6,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.seconds120,
        allowlistVersion: 'a' * 256,
        learningSessionId: pairSessionId(owner, launch),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 's' * 256,
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      final bare = PairMatchingStartOperation(
        plan: plan,
        launchOperationId: launch,
        appVersion: 'b' * 256,
        buildId: 'b' * 256,
      );
      final configured = PairMatchingStartOperation(
        plan: plan,
        launchOperationId: launch,
        appVersion: 'b' * 256,
        buildId: 'b' * 256,
        configuration: configuration,
      );
      final a = PairMatchingCheckpointCodec.reservedCompletionBytes(
        PairMatchingCheckpointCodec.decode(bare.initialCheckpoint.state),
      );
      final b = PairMatchingCheckpointCodec.reservedCompletionBytes(
        PairMatchingCheckpointCodec.decode(configured.initialCheckpoint.state),
      );
      expect(b, greaterThan(a));
      expect(
        b - a,
        greaterThanOrEqualTo(
          utf8.encode(configuration.stableSerialization).length,
        ),
      );
      final h = PairHarness(
        pinnedPlan: plan,
        launchId: launch,
        buildTag: 'b' * 256,
        configuration: configuration,
      );
      addTearDown(h.db.close);
      await h.db.customStatement(
        "CREATE TRIGGER synthetic_no_configured_pair_start BEFORE INSERT ON learning_sessions BEGIN SELECT RAISE(ABORT, 'session insert reached'); END",
      );
      await expectLater(
        h.initialize(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'capacity',
            contains('byte capacity'),
          ),
        ),
      );
      expect(await h.db.select(h.db.learningSessions).get(), isEmpty);
    },
  );
  test(
    'provided real policy configuration is immutable in atomic start and progressed recovery',
    () async {
      const policy = SessionConfigurationPolicy();
      const limits = SessionConfigurationProtocolLimits.standard();
      final registration = LessonModeRegistration(
        adapter: const MatchingModeAdapter(),
        feature: Feature.quiz,
        productionEntryId: 'home/learn/quiz',
        routeName: 'learning/test',
        deliveryState: LessonModeDeliveryState.enabled,
      );
      final configuration = policy.validate(
        draft: policy
            .defaultsFor(registration: registration, limits: limits)
            .copyWith(itemCount: 4),
        registration: registration,
        limits: limits,
        ownerId: 'synthetic-owner',
        availablePackIdentities: const [],
      );
      final h = PairHarness(configuration: configuration);
      addTearDown(h.db.close);
      await h.initialize();
      expect(jsonDecode(h.operation.stableSerialization)['schemaVersion'], 2);
      final row = (await h.db.select(h.db.learningSessions).get()).single;
      expect(row.sessionConfigurationIdentity, configuration.contentIdentity);
      expect(row.sessionConfigurationJson, configuration.stableSerialization);
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      final restored = PairMatchingStartOperation.fromStableSerialization(
        h.operation.stableSerialization,
      );
      expect(restored.configuration, configuration);
      expect(
        (await DriftPairMatchingSessionPurposeReader(
          h.db,
        ).read(ownerId: h.owner, sessionId: row.id)).snapshot!.startOperation,
        h.operation.stableSerialization,
      );
      await h.finishBounded(c);
      await c.finish();
      final source = h.operation;
      final replay = PairPracticeReplay(
        reader: DriftPairMatchingSessionPurposeReader(h.db),
        start: PairMatchingAtomicStartAdapter(
          repository: h.real,
          capability: InternalPairMatchingCapability(
            allowlist: PairCuratedAllowlist(
              version: source.plan.allowlistVersion,
              items: source.plan.orderedLexicalItems,
            ),
            isEnabled: () => true,
          ),
        ),
      );
      h.operation = await replay.prepare(
        ownerId: h.owner,
        sourceSessionId: row.id,
        launchOperationId: 'synthetic-config-replay',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
        appVersion: 'synthetic',
        buildId: 'synthetic',
      );
      final droppedConfiguration = PairMatchingStartOperation(
        plan: h.operation.plan,
        launchOperationId: h.operation.launchOperationId,
        appVersion: h.operation.appVersion,
        buildId: h.operation.buildId,
      );
      await expectLater(
        replay.start.start(droppedConfiguration),
        throwsStateError,
      );
      await replay.start.start(h.operation);
      await expectLater(
        h.real.addSessionConfigurationActiveEffort(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          configurationIdentity: configuration.contentIdentity,
          delta: const Duration(seconds: 1),
        ),
        throwsStateError,
      );
      final replayCoordinator = await h.restore();
      await h.finishBounded(replayCoordinator);
      await replayCoordinator.finish();
      await replay.start.start(
        PairMatchingStartOperation.fromStableSerialization(
          h.operation.stableSerialization,
        ),
      );
      await (await h.restore()).finish();
      final replayRow = (await h.db.select(h.db.learningSessions).get())
          .singleWhere((s) => s.id == h.operation.plan.learningSessionId);
      expect(replayRow.configurationActiveEffortUs, 0);
      expect(
        replayRow.sessionConfigurationJson,
        configuration.stableSerialization,
      );
      await h.db.customStatement(
        "UPDATE learning_sessions SET session_configuration_identity='changed' WHERE id=?",
        [row.id],
      );
      await expectLater(
        DriftPairMatchingSessionPurposeReader(
          h.db,
        ).read(ownerId: h.owner, sessionId: row.id),
        throwsStateError,
      );
    },
  );
}
