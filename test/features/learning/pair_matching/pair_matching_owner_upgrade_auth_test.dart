import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'pair_matching_source_composer_test.dart' as f;

const _target = 'synthetic-account';
const _uid = 'synthetic-firebase-uid';
final _upgradeTime = DateTime.utc(2026, 9, 5, 0, 2);

DriftOwnerUpgradeRepository _upgrade(PairHarness h, {DateTime? atUtc}) =>
    DriftOwnerUpgradeRepository(
      h.db,
      nowUtc: () => atUtc ?? _upgradeTime,
      generateConflictId: () => 'synthetic-conflict-${++h.nextId}',
      generateOwnerId: () => 'synthetic-new-owner-${++h.nextId}',
      generateOwnerOperationToken: () => 'synthetic-gate-${++h.nextId}',
      deleteOwnerSecrets: (_) async {},
    );

Future<void> _targetOwner(
  PairHarness h, {
  String collision = 'none',
  String targetId = _target,
}) async {
  await h.db
      .into(h.db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: targetId,
          firebaseUid: const Value(_uid),
          accountState: const Value('firebaseBound'),
          createdAtUtcMs: 1,
          isActive: const Value(false),
        ),
      );
  if (collision == 'none') return;
  await h.db
      .into(h.db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'synthetic-target-category',
          ownerId: targetId,
          name: 'Synthetic',
          normalizedName: 'synthetic',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  if (collision != 'word') return;
  final item = h.operation.plan.orderedLexicalItems.first;
  await h.db
      .into(h.db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'synthetic-target-word',
          ownerId: targetId,
          categoryId: 'synthetic-target-category',
          spelling: item.spelling,
          normalizedSpelling: item.spelling,
          meaning: item.meaning,
          normalizedMeaning: item.meaning,
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<List<Map<String, Object?>>> _rows(PairHarness h, String table) async => [
  for (final row
      in await h.db.customSelect('SELECT * FROM $table ORDER BY 1').get())
    row.data,
];

Future<Map<String, Object?>> _snapshot(PairHarness h) async => {
  for (final table in [
    'local_owners',
    'vocabulary_categories',
    'vocabulary_words',
    'learning_sessions',
    'answer_attempts',
    'events_v2',
    'outbox_operations',
  ])
    table: await _rows(h, table),
};

SessionConfiguration _configuration(
  PairDirection direction,
  PairDensity density,
) => SessionConfiguration.validated(
  schemaVersion: 2,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'synthetic-owner',
  mode: LessonMode.matching,
  itemCount: density.pairCount,
  direction: direction == PairDirection.enToTh
      ? SessionDirection.forward
      : SessionDirection.reverse,
  difficulty: SessionDifficulty.standard,
  hintBudget: 2,
  timing: const SessionTiming.untimedAlternative(
    maximumActiveEffort: Duration(minutes: 10),
  ),
  packIdentity: null,
  protocolId: 'protocol:local-standard',
  protocolVersion: '1',
  protocolLimitsIdentity:
      (const SessionConfigurationProtocolLimits.standard()).contentIdentity,
  pairDensityPreference: PairDensityPreference(
    density: density,
    provenance: PairDensityProvenance.learner,
  ),
);

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'actual near-ceiling Pair upgrade to control256 owner refuses atomically before remapping pins',
    () async {
      final items = List.generate(4, (i) {
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
            (reason) => reason != PairSourceReason.reported,
          ),
        );
      });
      final owner = 'o' * 256, launch = 'l' * 256;
      final h = PairHarness(
        pinnedPlan: PairMatchingPlanV1(
          ownerId: owner,
          orderedLexicalItems: items,
          direction: PairDirection.thToEn,
          density: PairDensity.compact4,
          shuffleSeed: 42,
          timerPreset: PairTimerPreset.seconds120,
          allowlistVersion: 'a' * 256,
          learningSessionId: pairSessionId(owner, launch),
          entryKind: PairSourceSurface.learn,
          sourceSnapshotId: 's' * 256,
          createdAtUtc: DateTime.utc(2026, 9, 5),
        ),
        launchId: launch,
        buildTag: 'b' * 256,
      );
      addTearDown(h.db.close);
      await h.initialize();
      final reserved = PairMatchingCheckpointCodec.reservedCompletionBytes(
        PairMatchingCheckpointCodec.decode(h.operation.initialCheckpoint.state),
      );
      expect(reserved, inInclusiveRange(64000, 65536));
      final destination = '\u0001' * 256;
      await _targetOwner(h, targetId: destination, collision: 'word');
      final before = await _snapshot(h);
      await expectLater(
        _upgrade(h).upgrade(activeOwnerId: owner, firebaseUid: _uid),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'reason',
            contains('capacity'),
          ),
        ),
      );
      expect(await _snapshot(h), before);
      // A refused rehome must leave the previously admitted same-owner tail usable.
      final coordinator = await h.restore();
      addTearDown(coordinator.dispose);
      await h.finishBounded(coordinator);
      await coordinator.finish();
      expect(
        (await _rows(h, 'learning_sessions')).single['state'],
        'completed',
      );
    },
  );

  for (final ownerKind in ['thai256', 'control256']) {
    test(
      'actual Pair upgrade to $ownerKind retains pins and completes new current-actor answers',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final destination = (ownerKind == 'thai256' ? 'ก' : '\u0001') * 256;
        await _targetOwner(h, targetId: destination);
        final original = h.operation.stableSerialization;
        await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
        final coordinator = await PairMatchingSessionCoordinator.restore(
          operation: h.operation,
          learning: h.learning,
          evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
          activeOwnerId: () => destination,
        );
        addTearDown(coordinator.dispose);
        for (final item in h.operation.plan.orderedLexicalItems) {
          await h.tap(coordinator, item.wordId, PairTileSide.prompt);
          await h.tap(coordinator, item.wordId, PairTileSide.target);
        }
        await coordinator.finish();
        final purpose = await DriftPairMatchingSessionPurposeReader(h.db).read(
          ownerId: destination,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(purpose.snapshot!.startOperation, original);
        expect(purpose.snapshot!.terminal!.acknowledged, true);
        final attempts = await _rows(h, 'answer_attempts');
        final events = await _rows(h, 'events_v2');
        expect(attempts, hasLength(4));
        for (final attempt in attempts) {
          expect(attempt['owner_id'], destination);
          final source = events.singleWhere(
            (row) =>
                row['event_id'] ==
                LearningEvidenceContract.learningEventId(
                  attempt['id'] as String,
                ),
          );
          expect(source['owner_id'], destination);
          expect(source['actor_identity'], destination);
        }
        expect(
          h.repository.checkpoints.every(
            (checkpoint) =>
                utf8.encode(jsonEncode(checkpoint.state)).length <= 65536,
          ),
          true,
        );
      },
    );
  }

  test(
    'actual Pair upgrade preserves a frozen fractional occurrence without rounding it',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final fractional = DateTime.utc(2026, 9, 5, 0, 1, 0, 123, 456);
      final coordinator = await PairMatchingSessionCoordinator.restore(
        operation: h.operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(
          learning: h.learning,
          nowUtc: () => fractional,
        ),
        activeOwnerId: () => h.owner,
      );
      await h.tap(coordinator, 'synthetic-0', PairTileSide.prompt);
      h.repository.answerFault = true;
      await expectLater(
        h.tap(coordinator, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      final before = await reader.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(
        before.snapshot!.frozenEvidence?['occurredAtUtc'],
        fractional.toIso8601String(),
      );
      await _targetOwner(h);
      await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      final moved = await reader.read(
        ownerId: _target,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(moved.snapshot!.frozenEvidence, before.snapshot!.frozenEvidence);
      expect(await _rows(h, 'answer_attempts'), isEmpty);
    },
  );

  test(
    'actual anonymous bind retains strict Pair original plan and actor',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final before = await _rows(h, 'events_v2');
      final result = await _upgrade(
        h,
      ).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      expect(result.mode, OwnerUpgradeMode.anonymousBound);
      final purpose = await DriftPairMatchingSessionPurposeReader(
        h.db,
      ).read(ownerId: h.owner, sessionId: h.operation.plan.learningSessionId);
      expect(purpose.snapshot!.startOperation, h.operation.stableSerialization);
      expect(
        (await _rows(
          h,
          'events_v2',
        )).singleWhere((row) => row['event_id'] == before.single['event_id']),
        before.single,
      );
    },
  );

  for (final collision in ['none', 'category', 'word']) {
    for (final direction in PairDirection.values) {
      test(
        'actual Pair zero-answer upgrade authenticates $collision $direction without rewriting pins',
        () async {
          final density = direction == PairDirection.enToTh
              ? PairDensity.compact4
              : PairDensity.standard6;
          final config = _configuration(direction, density);
          final h = PairHarness(
            direction: direction,
            density: density,
            configuration: config,
          );
          addTearDown(h.db.close);
          await h.initialize();
          await _targetOwner(h, collision: collision);
          final initial = (await _rows(h, 'events_v2')).single;
          final plan = h.operation.plan;
          final result = await _upgrade(
            h,
          ).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
          expect(result.mode, OwnerUpgradeMode.mergedExisting);
          final owners = await _rows(h, 'local_owners');
          expect(
            owners.singleWhere((r) => r['id'] == h.owner)['account_state'],
            'mergedInto:$_target',
          );
          expect(owners.singleWhere((r) => r['id'] == _target)['is_active'], 1);
          final purpose = await DriftPairMatchingSessionPurposeReader(
            h.db,
          ).read(ownerId: _target, sessionId: plan.learningSessionId);
          expect(
            purpose.snapshot!.startOperation,
            h.operation.stableSerialization,
          );
          expect(purpose.snapshot!.engine.plan.toJson(), plan.toJson());
          final checkpoint = (await _rows(
            h,
            'events_v2',
          )).singleWhere((r) => r['event_id'] == initial['event_id']);
          expect(checkpoint['payload_json'], initial['payload_json']);
          expect(checkpoint['actor_identity'], h.owner);
          expect(checkpoint['owner_id'], _target);
          final session = (await _rows(h, 'learning_sessions')).single;
          expect(session['state'], 'active');
          final rebound = SessionConfiguration.fromStableSerialization(
            session['session_configuration_json'] as String,
          );
          expect(rebound.ownerId, _target);
          expect(rebound.direction, config.direction);
          expect(rebound.pairDensityPreference!.density, density);
          expect(rebound.protocolLimitsIdentity, config.protocolLimitsIdentity);
          final pinned = (await _rows(h, 'vocabulary_words')).singleWhere(
            (r) => r['id'] == plan.orderedLexicalItems.first.wordId,
          );
          expect(pinned['owner_id'], _target);
          expect(pinned['spelling'], plan.orderedLexicalItems.first.spelling);
          expect(pinned['is_deleted'], collision == 'word' ? 1 : 0);
          if (collision != 'none') {
            expect(
              pinned['content_checksum_sha256'],
              isNot(plan.orderedLexicalItems.first.checksum),
            );
          }
          expect(await _rows(h, 'answer_attempts'), isEmpty);
        },
      );
    }
  }

  test(
    'malformed strict Pair preflight rolls back before category collision writes',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await _targetOwner(h, collision: 'category');
      final event = (await _rows(h, 'events_v2')).single;
      final payload = jsonDecode(event['payload_json'] as String) as Map;
      (payload['state'] as Map)['planFingerprint'] = 'synthetic-corrupt';
      await h.db.customStatement(
        'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
        [jsonEncode(payload), event['event_id']],
      );
      final before = await _snapshot(h);
      await expectLater(
        _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid),
        throwsStateError,
      );
      expect(await _snapshot(h), before);
    },
  );

  for (final corrupted in ['{', '[]', '{}', '{"state":{"schemaVersion":7}}']) {
    test(
      'present undecodable checkpoint $corrupted rejects actual category-only upgrade atomically',
      () async {
        final h = PairHarness(
          configuration: _configuration(
            PairDirection.enToTh,
            PairDensity.compact4,
          ),
        );
        addTearDown(h.db.close);
        await h.initialize();
        await _targetOwner(h, collision: 'category');
        await h.db.customStatement(
          'UPDATE events_v2 SET payload_json=? WHERE event_type=?',
          [corrupted, 'LearningActivityCheckpoint'],
        );
        final before = await _snapshot(h);
        await expectLater(
          _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid),
          throwsStateError,
        );
        expect(await _snapshot(h), before);
      },
    );
  }

  for (final version in [1, 2, 3, 4, 5]) {
    for (final validEnvelope in [false, true]) {
      test(
        'legacy classification rejects marker-only schema $version validEnvelope=$validEnvelope before category-only upgrade',
        () async {
          final h = PairHarness();
          addTearDown(h.db.close);
          await h.initialize();
          await _targetOwner(h, collision: 'category');
          final event = (await _rows(h, 'events_v2')).single;
          final payload = validEnvelope
              ? (jsonDecode(event['payload_json'] as String) as Map)
              : <String, Object?>{};
          payload['state'] = {'schemaVersion': version};
          await h.db.customStatement(
            'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
            [jsonEncode(payload), event['event_id']],
          );
          final before = await _snapshot(h);
          await expectLater(
            _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid),
            throwsStateError,
          );
          expect(await _snapshot(h), before);
        },
      );
    }

    test(
      'legacy classification preserves actual schema $version through category-only upgrade',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        await h.real.abandonSession(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          abandonedAtUtc: h.learning.nowUtc(),
        );
        final learning = LearningUseCases(
          owners: h.learning.owners,
          repository: h.real,
          generateId: h.learning.generateId,
          nowUtc: h.learning.nowUtc,
          buildInfo: h.learning.buildInfo,
        );
        const adapter = MatchingModeAdapter();
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final original = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'synthetic-category',
          itemCount: 4,
        );
        final event = (await h.db.select(h.db.eventsV2).get()).singleWhere(
          (row) => row.aggregateId == original.session.id,
        );
        final payload = jsonDecode(event.payloadJson) as Map;
        final state = payload['state'] as Map;
        expect(state['schemaVersion'], 5);
        state['schemaVersion'] = version;
        if (version < 5) state.remove('timingKind');
        if (version < 4) state.remove('summaryPresented');
        if (version < 3) {
          state.remove('timeoutAnchorUtc');
          state.remove('timeoutDurationMs');
        }
        if (version < 2) {
          state.remove('timeoutDeadlineUtc');
          payload['schemaVersion'] = 1;
          payload.remove('terminalAtUtc');
          payload.remove('terminalAcknowledged');
        }
        final historicalBytes = jsonEncode(payload);
        await h.db.customStatement(
          'UPDATE events_v2 SET payload_json=?, event_version=? WHERE event_id=?',
          [
            historicalBytes,
            version == 1 ? 1 : event.eventVersion,
            event.eventId,
          ],
        );
        await _targetOwner(h, collision: 'category');
        await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
        final moved = (await h.db.select(h.db.eventsV2).get()).singleWhere(
          (row) => row.eventId == event.eventId,
        );
        expect(moved.ownerId, _target);
        expect(moved.actorIdentity, h.owner);
        expect(moved.payloadJson, historicalBytes);
        final restored = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'synthetic-target-category',
          itemCount: 4,
        );
        expect(restored.session.id, original.session.id);
        expect(
          restored.session.questions.map((question) => question.word.id),
          original.session.questions.map((question) => question.word.id),
        );
        expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
      },
    );
  }

  test(
    'legacy classification preserves existing no-checkpoint upgrade policy',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await h.real.abandonSession(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
        abandonedAtUtc: h.learning.nowUtc(),
      );
      const sessionId = 'synthetic-no-checkpoint-matching';
      await h.real.startSession(
        LearningSessionDraft(
          id: sessionId,
          ownerId: h.owner,
          activityType: 'matching',
          startedAtUtc: h.learning.nowUtc(),
          appVersion: 'synthetic',
          buildId: 'synthetic',
        ),
      );
      await _targetOwner(h, collision: 'category');
      await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      final moved = (await h.db.select(h.db.learningSessions).get())
          .singleWhere((row) => row.id == sessionId);
      expect(moved.ownerId, _target);
      expect(moved.state, 'active');
      expect(
        (await h.db.select(h.db.eventsV2).get()).where(
          (row) => row.aggregateId == sessionId,
        ),
        isEmpty,
      );
    },
  );

  test(
    'actual later-created destination accepts historical plan but rejects marker before destination existence',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await _targetOwner(h);
      final planTime = h.operation.plan.createdAtUtc;
      await h.db.customStatement(
        'UPDATE local_owners SET created_at_utc_ms=? WHERE id=?',
        [
          planTime.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          _target,
        ],
      );
      await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      expect(
        (await reader.read(
          ownerId: _target,
          sessionId: h.operation.plan.learningSessionId,
        )).snapshot,
        isNotNull,
      );
      await h.db.customStatement(
        'UPDATE local_owners SET upgraded_at_utc_ms=? WHERE id=?',
        [
          planTime.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
          h.owner,
        ],
      );
      final before = await _snapshot(h);
      await expectLater(
        reader.read(
          ownerId: _target,
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
      expect(await _snapshot(h), before);
    },
  );

  for (final tamper in [
    'missing',
    'active',
    'wrong-target',
    'null-time',
    'seconds-time',
    'before-plan',
    'created-after-plan',
    'rewritten-first-actor',
    'drop-config',
    'change-direction',
  ]) {
    test('actual merged Pair purpose rejects $tamper without writes', () async {
      final h = PairHarness(
        configuration: _configuration(
          PairDirection.enToTh,
          PairDensity.compact4,
        ),
      );
      addTearDown(h.db.close);
      await h.initialize();
      await _targetOwner(h);
      await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      expect(
        (await reader.read(
          ownerId: _target,
          sessionId: h.operation.plan.learningSessionId,
        )).allowsLearningAuthority,
        true,
      );
      switch (tamper) {
        case 'missing':
          await h.db.customStatement('DELETE FROM local_owners WHERE id=?', [
            h.owner,
          ]);
        case 'active':
          await h.db.customStatement(
            'UPDATE local_owners SET is_active=1 WHERE id=?',
            [h.owner],
          );
        case 'wrong-target':
          await h.db.customStatement(
            "UPDATE local_owners SET account_state='mergedInto:foreign' WHERE id=?",
            [h.owner],
          );
        case 'null-time':
          await h.db.customStatement(
            'UPDATE local_owners SET upgraded_at_utc_ms=NULL WHERE id=?',
            [h.owner],
          );
        case 'seconds-time':
          await h.db.customStatement(
            'UPDATE local_owners SET upgraded_at_utc_ms=? WHERE id=?',
            [_upgradeTime.millisecondsSinceEpoch ~/ 1000, h.owner],
          );
        case 'before-plan':
          await h.db.customStatement(
            'UPDATE local_owners SET upgraded_at_utc_ms=? WHERE id=?',
            [h.operation.plan.createdAtUtc.millisecondsSinceEpoch - 1, h.owner],
          );
        case 'created-after-plan':
          await h.db.customStatement(
            'UPDATE local_owners SET created_at_utc_ms=? WHERE id=?',
            [_upgradeTime.millisecondsSinceEpoch, h.owner],
          );
        case 'rewritten-first-actor':
          final key = PairMatchingSessionPurpose.checkpointKey(
            _target,
            h.operation.plan.learningSessionId,
            1,
          );
          await h.db.customStatement(
            'UPDATE events_v2 SET actor_identity=?, event_id=?, idempotency_key=? WHERE event_type=?',
            [_target, key, key, 'LearningActivityCheckpoint'],
          );
        case 'drop-config':
          await h.db.customStatement(
            'UPDATE learning_sessions SET session_configuration_json=NULL, session_configuration_identity=NULL',
          );
        case 'change-direction':
          final row = (await _rows(h, 'learning_sessions')).single;
          final json =
              jsonDecode(row['session_configuration_json'] as String) as Map;
          json['direction'] = 'reverse';
          await h.db.customStatement(
            'UPDATE learning_sessions SET session_configuration_json=?',
            [jsonEncode(json)],
          );
      }
      final before = await _snapshot(h);
      await expectLater(
        reader.read(
          ownerId: _target,
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
      expect(await _snapshot(h), before);
    });
  }

  for (final field in [
    'schema',
    'mode',
    'count',
    'direction',
    'difficulty',
    'hints',
    'timing',
    'pack',
    'protocol',
    'protocol-version',
    'protocol-limits',
    'density',
  ]) {
    test(
      'merged Pair rejects self-consistent replacement configuration $field',
      () async {
        final h = PairHarness(
          configuration: _configuration(
            PairDirection.enToTh,
            PairDensity.compact4,
          ),
        );
        addTearDown(h.db.close);
        await h.initialize();
        await _targetOwner(h);
        await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
        final row = (await _rows(h, 'learning_sessions')).single;
        final accepted = SessionConfiguration.fromStableSerialization(
          row['session_configuration_json'] as String,
        );
        final older = field == 'schema' || field == 'mode';
        final replacement = SessionConfiguration.validated(
          schemaVersion: older ? 1 : accepted.schemaVersion,
          policyVersion: accepted.policyVersion,
          ownerId: accepted.ownerId,
          mode: field == 'mode' ? LessonMode.meaningQuiz : accepted.mode,
          itemCount: field == 'count' ? 6 : accepted.itemCount,
          direction: field == 'direction'
              ? SessionDirection.reverse
              : accepted.direction,
          difficulty: field == 'difficulty'
              ? SessionDifficulty.challenge
              : accepted.difficulty,
          hintBudget: field == 'hints' ? 1 : accepted.hintBudget,
          timing: field == 'timing'
              ? const SessionTiming.timed(Duration(minutes: 2))
              : accepted.timing,
          packIdentity: field == 'pack'
              ? const ContentIdentity(
                  type: ContentType.learningPack,
                  id: 'synthetic-injected-pack',
                  revision: 1,
                )
              : accepted.packIdentity,
          protocolId: field == 'protocol'
              ? 'synthetic-other-protocol'
              : accepted.protocolId,
          protocolVersion: field == 'protocol-version'
              ? '2'
              : accepted.protocolVersion,
          protocolLimitsIdentity: field == 'protocol-limits'
              ? 'synthetic-other-limits'
              : accepted.protocolLimitsIdentity,
          pairDensityPreference: older
              ? null
              : field == 'density'
              ? PairDensityPreference(
                  density: PairDensity.standard6,
                  provenance: PairDensityProvenance.learner,
                )
              : accepted.pairDensityPreference,
        );
        expect(
          SessionConfiguration.fromStableSerialization(
            replacement.stableSerialization,
          ).contentIdentity,
          replacement.contentIdentity,
        );
        await h.db.customStatement(
          'UPDATE learning_sessions SET session_configuration_json=?, session_configuration_identity=? WHERE id=?',
          [
            replacement.stableSerialization,
            replacement.contentIdentity,
            row['id'],
          ],
        );
        final before = await _snapshot(h);
        await expectLater(
          DriftPairMatchingSessionPurposeReader(h.db).read(
            ownerId: _target,
            sessionId: h.operation.plan.learningSessionId,
          ),
          throwsStateError,
        );
        expect(await _snapshot(h), before);
      },
    );
  }

  test(
    'actual logout and new guest merge preserve the earlier direct Pair lineage',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      await _targetOwner(h);
      final original = (await _rows(h, 'events_v2')).single;
      final upgrade = _upgrade(h);
      await upgrade.upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      final marker = (await _rows(
        h,
        'local_owners',
      )).singleWhere((row) => row['id'] == h.owner);
      final guest = await upgrade.createLocalGuestAfterLogout();
      // Explicitly scoped inactive history is readable without an R write lease.
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      expect(
        (await reader.read(
          ownerId: _target,
          sessionId: h.operation.plan.learningSessionId,
        )).snapshot!.startOperation,
        h.operation.stableSerialization,
      );
      await _upgrade(
        h,
        atUtc: _upgradeTime.add(const Duration(minutes: 1)),
      ).upgrade(activeOwnerId: guest.targetOwnerId, firebaseUid: _uid);
      expect(
        (await _rows(
          h,
          'local_owners',
        )).singleWhere((row) => row['id'] == h.owner),
        marker,
      );
      final latest = await reader.read(
        ownerId: _target,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(latest.snapshot!.engine.plan.toJson(), h.operation.plan.toJson());
      final checkpoint = (await _rows(
        h,
        'events_v2',
      )).singleWhere((row) => row['event_id'] == original['event_id']);
      expect(checkpoint['payload_json'], original['payload_json']);
      expect(checkpoint['actor_identity'], h.owner);
    },
  );

  test(
    'actual second repository merge rewrites direct Pair lineage and retains original actor key',
    () async {
      final h = PairHarness(
        configuration: _configuration(
          PairDirection.enToTh,
          PairDensity.compact4,
        ),
      );
      addTearDown(h.db.close);
      await h.initialize();
      await _targetOwner(h, collision: 'word');
      final original = (await _rows(h, 'events_v2')).single;
      await _upgrade(h).upgrade(activeOwnerId: h.owner, firebaseUid: _uid);
      // This is the repository's supported merge topology with synthetic owners;
      // it does not assert that the authentication UI offers account merging.
      const destination = 'synthetic-second-account';
      await h.db
          .into(h.db.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: destination,
              firebaseUid: const Value('synthetic-second-uid'),
              accountState: const Value('firebaseBound'),
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      final secondAt = _upgradeTime.add(const Duration(minutes: 1));
      final result = await _upgrade(
        h,
        atUtc: secondAt,
      ).upgrade(activeOwnerId: _target, firebaseUid: 'synthetic-second-uid');
      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      final owners = await _rows(h, 'local_owners');
      for (final id in [h.owner, _target]) {
        final marker = owners.singleWhere((row) => row['id'] == id);
        expect(marker['is_active'], 0);
        expect(marker['account_state'], 'mergedInto:$destination');
        expect(marker['upgraded_at_utc_ms'], secondAt.millisecondsSinceEpoch);
      }
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      final purpose = await reader.read(
        ownerId: destination,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(purpose.snapshot!.startOperation, h.operation.stableSerialization);
      final checkpoint = (await _rows(
        h,
        'events_v2',
      )).singleWhere((row) => row['event_id'] == original['event_id']);
      expect(checkpoint['payload_json'], original['payload_json']);
      expect(checkpoint['actor_identity'], h.owner);
      expect(checkpoint['idempotency_key'], original['idempotency_key']);
      expect(checkpoint['owner_id'], destination);
      await h.db.customStatement(
        'UPDATE local_owners SET account_state=? WHERE id=?',
        ['mergedInto:$_target', h.owner],
      );
      final before = await _snapshot(h);
      await expectLater(
        reader.read(
          ownerId: destination,
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
      expect(await _snapshot(h), before);
    },
  );

  test(
    'historical owner query tracks current original checkpoint and frozen actors',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final checkpoint = (await _rows(h, 'events_v2')).single;
      final payload = jsonDecode(checkpoint['payload_json'] as String) as Map;
      (payload['state'] as Map)['frozenEvidence'] = {
        'ownerId': 'synthetic-pending-owner',
        'actorIdentity': 'synthetic-pending-actor',
      };
      final query = PairMatchingSessionPurpose.historicalOwnerQuery(_target, [
        {
          ...checkpoint,
          'actor_identity': 'synthetic-checkpoint-actor',
          'payload_json': jsonEncode(payload),
        },
      ]);
      expect(query.args.toSet(), {
        _target,
        h.owner,
        'synthetic-checkpoint-actor',
        'synthetic-pending-owner',
        'synthetic-pending-actor',
      });
      expect(
        await h.db
            .customSelect(
              query.sql,
              variables: [for (final id in query.args) Variable(id as String)],
            )
            .get(),
        isNotEmpty,
      );
    },
  );
}
