import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/measurement_opportunity_harness.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

const _owner = 'owner-a';
const _otherOwner = 'owner-b';

void main() {
  late OpportunityFixture fixture;
  setUp(() async {
    fixture = await OpportunityFixture.open(
      treatment: TodayExperiencePresentation.adventure,
    );
  });
  tearDown(() => fixture.database.close());

  test(
    'full personal export preserves all pending switch fields and exact Changed envelopes after ordinary completion',
    () async {
      final graph = await _completedWithPendingChange(fixture);
      final before = await _allRows(fixture.database);
      final otherBefore = await _snapshot(fixture, _otherOwner);

      final snapshot = await _snapshot(fixture, _owner);
      final decoded = jsonDecode(utf8.decode(snapshot.bytes)) as Map;
      final data = decoded['data']! as Map;

      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      expect(decoded['ownerId'], _owner);
      expect(decoded['schemaVersion'], 18);
      expect(data['assessment_runs'], isEmpty);
      expect(data.keys.toSet(), requiredFullAccountExportScopes);
      final opportunity = (data['measurement_opportunities']! as List).single;
      expect(opportunity, hasLength(19));
      expect(opportunity, graph.opportunity);
      expect(opportunity['last_switch_ordinal'], 10);
      expect(opportunity['suppressed_switch_count'], 2);
      expect(opportunity['started_effective_presentation'], 'adventure');
      expect(
        opportunity['pending_presentation_change_json'],
        graph.receipt.canonicalJson,
      );
      expect(
        PendingPresentationChange.fromJson(
          opportunity['pending_presentation_change_json']! as String,
        ).toJson(),
        graph.receipt.toJson(),
      );
      final exportedEvents = (data['events_v2']! as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      expect(exportedEvents, await _ownerEvents(fixture.database, _owner));
      expect(exportedEvents, hasLength(12));
      for (final event in exportedEvents) {
        expect(event, hasLength(22));
        expect(event['owner_id'], _owner);
        expect(event['actor_identity'], _owner);
        expect(event['privacy_classification'], 'ownerOnly');
      }
      _expectChanged(exportedEvents, fixture.opportunityId);
      expect(
        exportedEvents.singleWhere(
          (row) => row['event_type'] == measurementPresentedEventType,
        ),
        graph.presented,
      );
      expect(
        exportedEvents.singleWhere(
          (row) => row['event_type'] == measurementMissionStartedEventType,
        ),
        graph.started,
      );
      for (final scope in [
        'experiment_assignments',
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'events_v2',
      ]) {
        final rows = data[scope]! as List;
        expect(rows, isNotEmpty, reason: scope);
        expect(rows.every((row) => row['owner_id'] == _owner), isTrue);
      }
      expect((data['learning_sessions']! as List).single['state'], 'completed');
      expect(
        (data['learning_sessions']! as List).single['ended_at_utc_ms'],
        graph.endedAtUtcMs,
      );
      expect((data['answer_attempts']! as List), hasLength(1));
      expect((data['achievement_unlocks']! as List), hasLength(2));
      final outbox = data['outbox_operations']! as List;
      expect(outbox, hasLength(3));
      expect(outbox.map((row) => row['entity_type']).toSet(), {
        'attempt',
        'srsState',
        'achievementUnlock',
      });
      expect(await fixture.facts(), isNull);
      expect(await _allRows(fixture.database), before);
      expect((await _snapshot(fixture, _otherOwner)).bytes, otherBefore.bytes);
      final encoded = utf8.decode(snapshot.bytes);
      expect(encoded, isNot(contains('synthetic-permit:owner-b')));
      expect(encoded, isNot(contains('uid-b')));
    },
  );

  test(
    'persistent cloud-confirmed purge removes pending history and completed learning while preserving the other owner byte for byte',
    () async {
      final graph = await _completedWithPendingChange(fixture);
      final database = fixture.database;
      final otherBefore = await _snapshot(fixture, _otherOwner);
      final otherOwnerBefore = await _ownerRecord(database, _otherOwner);
      final owner = await _ownerRecord(database, _owner);
      final firebaseUid = owner['firebase_uid']! as String;
      expect(firebaseUid, 'uid-a');
      expect(owner['is_active'], 1);
      expect(graph.opportunity['pending_presentation_change_json'], isNotNull);
      final ownerWrites = fixture.participation.ownerWrites;
      const deletionKey = 'delete:synthetic-pending-presentation-owner';
      final token = await ownerWrites.beginDeletion(
        ownerId: _owner,
        firebaseUid: firebaseUid,
        idempotencyKey: deletionKey,
      );
      await ownerWrites.markPending(token);
      // Synthetic cloud completion evidence is bound to the actual stored UID.
      // No cloud gateway, credentials or participant service is contacted.
      final cloud = CloudDeletionReceipt(
        receiptId: 'synthetic-pending-presentation-cloud-receipt',
        ownerId: _owner,
        firebaseUid: firebaseUid,
        idempotencyKey: deletionKey,
        completedAtUtc: fixture.participation.clock.now,
      ).durableMarker();
      await ownerWrites.markCloud(token, cloud);
      expect(
        (await ownerWrites.inspect())!.phase,
        DeletionIntentPhase.cloudConfirmed,
      );
      final purgedSecrets = <String>[];
      final local = await DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => fixture.participation.clock.now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          purgedSecrets.add('$ownerId/$firebaseUid');
        },
      ).deleteAfterCloud(ownerId: _owner, cloudReceipt: cloud);
      await ownerWrites.markLocal(token, cloud, local);

      expect(purgedSecrets, ['$_owner/$firebaseUid']);
      expect(local.deletedOwnerId, _owner);
      expect(
        local.newGuestOwnerId,
        accountDeletionReplacementGuestOwnerId(cloud),
      );
      final completed = (await ownerWrites.inspect())!;
      expect(completed.phase, DeletionIntentPhase.localCompleted);
      expect(completed.casToken!.sameAttempt(token), isTrue);
      expect(completed.localReceipt!.newGuestOwnerId, local.newGuestOwnerId);
      expect(completed.localReceipt!.completedAtUtc, local.completedAtUtc);
      for (final table in ownerUpgradeInventory) {
        expect(
          await _ownerRows(database, table, _owner),
          isEmpty,
          reason: table,
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        await database.customSelect('SELECT * FROM outbox_operations').get(),
        isEmpty,
      );
      expect(
        await database.customSelect('SELECT * FROM learning_sessions').get(),
        isEmpty,
      );
      expect(await _ownerRecord(database, _otherOwner), otherOwnerBefore);
      expect((await _snapshot(fixture, _otherOwner)).bytes, otherBefore.bytes);
      expect(
        await _ownerRows(database, 'measurement_opportunities', _otherOwner),
        hasLength(1),
      );
      expect(await _ownerEvents(database, _otherOwner), hasLength(1));
      final guest = await _ownerRecord(database, local.newGuestOwnerId);
      expect(guest['firebase_uid'], isNull);
      expect(guest['account_state'], 'localGuest');
      expect(guest['is_active'], 1);
      expect(
        await database
            .customSelect(
              'SELECT * FROM local_owners WHERE id = ?',
              variables: [drift.Variable<String>(_owner)],
            )
            .get(),
        isEmpty,
      );
      // Clearing the persistent fence rechecks the complete local purge proof.
      await ownerWrites.clearCompleted(token);
      expect(await ownerWrites.inspect(), isNull);
      expect((await _snapshot(fixture, _otherOwner)).bytes, otherBefore.bytes);
    },
  );
}

final class _PendingGraph {
  const _PendingGraph({
    required this.opportunity,
    required this.receipt,
    required this.presented,
    required this.started,
    required this.endedAtUtcMs,
  });
  final Map<String, Object?> opportunity;
  final PendingPresentationChange receipt;
  final Map<String, Object?> presented;
  final Map<String, Object?> started;
  final int endedAtUtcMs;
}

Future<_PendingGraph> _completedWithPendingChange(
  OpportunityFixture fixture,
) async {
  await fixture.ready();
  final accepted = await fixture.accept();
  final originalSession = await fixture.storedSession();
  final initial = await fixture.storedOpportunity();
  final initialEvents = await _ownerEvents(fixture.database, _owner);
  final presented = initialEvents.singleWhere(
    (row) => row['event_type'] == measurementPresentedEventType,
  );
  final started = initialEvents.singleWhere(
    (row) => row['event_type'] == measurementMissionStartedEventType,
  );
  expect(jsonDecode(started['payload_json']! as String), {
    'assignedTreatment': 'adventure',
    'effectivePresentation': 'adventure',
    'opportunityId': fixture.opportunityId,
    'planId': accepted.plan.id,
    'mode': accepted.plan.mode,
  });
  expect(accepted.plan.id, isNot(accepted.sessionId));
  expect(accepted.plan.mode, 'meaning-quiz');

  for (var position = 1; position <= 12; position++) {
    fixture.participation.clock.now = fixture.participation.clock.now.add(
      const Duration(milliseconds: 1),
    );
    final prepared = await _prepare(fixture, position);
    final receipt = prepared.pendingPresentationChange!;
    fixture.participation.clock.now = fixture.participation.clock.now.add(
      const Duration(milliseconds: 1),
    );
    final committed = await fixture.repository.commitPresentationChange(
      _owner,
      fixture.opportunityId,
      receipt: receipt,
      stillVisible: () => true,
    );
    expect(committed.pendingPresentationChange, isNull);
    expect(committed.lastSwitchOrdinal, position.clamp(0, 10));
    expect(committed.suppressedSwitchCount, position > 10 ? position - 10 : 0);
    expect(
      committed.currentPresentation,
      position.isEven
          ? TodayExperiencePresentation.adventure
          : TodayExperiencePresentation.standard,
    );
    expect(
      committed.startedEffectivePresentation,
      TodayExperiencePresentation.adventure,
    );
    final beforeReplay = await _allRows(fixture.database);
    final replay = await fixture.repository.commitPresentationChange(
      _owner,
      fixture.opportunityId,
      receipt: receipt,
      stillVisible: () => true,
    );
    expect(replay.localRevision, committed.localRevision);
    expect(await _allRows(fixture.database), beforeReplay);
    expect(
      (await _ownerEvents(fixture.database, _owner)).singleWhere(
        (row) => row['event_type'] == measurementMissionStartedEventType,
      ),
      started,
    );
    expect(await fixture.facts(), isNotNull);
  }
  final events = await _ownerEvents(fixture.database, _owner);
  expect(events, hasLength(12));
  _expectChanged(events, fixture.opportunityId);
  expect(await fixture.storedSession(), originalSession);
  final afterSwitches = await fixture.storedOpportunity();
  for (final key in [
    'effective_presentation',
    'presented_event_id',
    'presented_at_utc_ms',
    'learning_session_id',
    'learning_session_started_at_utc_ms',
    'started_effective_presentation',
  ]) {
    expect(afterSwitches[key], initial[key], reason: key);
  }
  expect(
    events.singleWhere(
      (row) => row['event_type'] == measurementPresentedEventType,
    ),
    presented,
  );
  expect(
    events.singleWhere(
      (row) => row['event_type'] == measurementMissionStartedEventType,
    ),
    started,
  );

  final prepared = await _prepare(fixture, 13);
  final receipt = prepared.pendingPresentationChange!;
  final pendingBeforeFinish = await fixture.storedOpportunity();
  expect(receipt.position, 13);
  expect(receipt.baseOrdinal, 10);
  expect(receipt.baseSuppressed, 2);
  expect(receipt.from, TodayExperiencePresentation.adventure);
  expect(receipt.to, TodayExperiencePresentation.standard);
  expect(await fixture.facts(), isNull);

  // Ordinary canonical learning may finish while research is uncertain. The
  // sidecar must leave the pending marker and prior research facts untouched.
  await fixture.finish();
  final finished = await fixture.learning.inspectConfiguredQuiz(
    sessionId: accepted.sessionId,
    expectedOwnerId: _owner,
  );
  expect(finished.state, 'completed');
  expect(finished.checkpoint, isA<CompletedQuizSession>());
  expect(finished.plan.id, accepted.plan.id);
  expect(finished.startedAtUtc, accepted.startedAtUtc);
  expect(finished.endedAtUtc, fixture.participation.clock.now);
  expect(await fixture.storedOpportunity(), pendingBeforeFinish);
  expect(await _ownerEvents(fixture.database, _owner), events);
  expect(await fixture.facts(), isNull);
  await fixture.expectArtifacts(
    opportunities: 1,
    events: 12,
    sessions: 1,
    ordinaryAchievementSessionId: accepted.sessionId,
  );

  // Existing historical synthetic helpers preserve a second owner's signed
  // graph. They grant no collection rights and invent no switch history.
  final assignment = await seedOwnerAssignment(fixture.database, _otherOwner);
  final permit = await insertOwnerParticipation(
    fixture.database,
    _otherOwner,
    assignmentId: assignment,
  );
  await fixture.database.customStatement(
    'INSERT INTO research_consents '
    '(id,owner_id,consent_version,consent_state,decided_at_utc_ms) '
    "VALUES ('synthetic-pending-other-consent', ?, 1, 'accepted', 1)",
    [_otherOwner],
  );
  final measurement = await insertOwnerMotivationMeasurement(
    fixture.database,
    permit,
  );
  await insertOwnerMeasurementOpportunity(
    fixture.database,
    permit: permit,
    measurement: measurement,
  );
  return _PendingGraph(
    opportunity: pendingBeforeFinish,
    receipt: receipt,
    presented: presented,
    started: started,
    endedAtUtcMs: finished.endedAtUtc!.millisecondsSinceEpoch,
  );
}

Future<MeasurementOpportunity> _prepare(
  OpportunityFixture fixture,
  int position,
) async {
  final current = (await fixture.repository.load(
    _owner,
    fixture.opportunityId,
  ))!;
  return fixture.repository.preparePresentationChange(
    _owner,
    fixture.opportunityId,
    attemptId:
        '30000000-0000-4000-8000-${position.toString().padLeft(12, '0')}',
    expectedRevision: current.localRevision,
    target: oppositePresentation(current.currentPresentation),
    stillCurrent: () => true,
  );
}

void _expectChanged(List<Map<String, Object?>> events, String opportunityId) {
  final changed = events
      .where(
        (row) => row['event_type'] == measurementPresentationChangedEventType,
      )
      .toList();
  expect(changed, hasLength(10));
  for (var ordinal = 1; ordinal <= 10; ordinal++) {
    final event = changed.singleWhere(
      (row) =>
          (jsonDecode(row['payload_json']! as String)
              as Map)['switchOrdinal'] ==
          ordinal,
    );
    final from = ordinal.isOdd ? 'adventure' : 'standard';
    final to = ordinal.isOdd ? 'standard' : 'adventure';
    expect(event, hasLength(22));
    expect(jsonDecode(event['payload_json']! as String), {
      'assignedTreatment': 'adventure',
      'effectivePresentation': to,
      'fromPresentation': from,
      'switchOrdinal': ordinal,
    });
    final identity = measurementPresentationChangedIdentity(
      opportunityId,
      ordinal,
    );
    final occurred = researchEventOccurrence(
      event['event_id']! as String,
      DateTime.fromMillisecondsSinceEpoch(
        (event['occurred_at_utc']! as int) * 1000,
        isUtc: true,
      ),
    );
    expect(event['event_id'], researchEventId(identity, occurred));
    expect(event['idempotency_key'], identity);
    expect(event['owner_id'], _owner);
    expect(event['aggregate_type'], 'MeasurementOpportunity');
    expect(event['aggregate_id'], opportunityId);
    expect(event['correlation_id'], opportunityId);
    expect(event['occurred_at_utc'], event['recorded_at_utc']);
    expect(event['privacy_classification'], 'ownerOnly');
  }
}

Future<LocalAccountSnapshot> _snapshot(
  OpportunityFixture fixture,
  String owner,
) => DriftAccountSnapshotBuilder(
  fixture.database,
  nowUtc: () => fixture.participation.clock.now,
).build(ownerId: owner);

Future<List<Map<String, Object?>>> _ownerEvents(
  AppDatabase database,
  String owner,
) => _ownerRows(database, 'events_v2', owner);

Future<List<Map<String, Object?>>> _ownerRows(
  AppDatabase database,
  String table,
  String owner,
) async => [
  for (final row
      in await database
          .customSelect(
            'SELECT * FROM $table WHERE owner_id = ? ORDER BY rowid',
            variables: [drift.Variable<String>(owner)],
          )
          .get())
    Map<String, Object?>.from(row.data),
];

Future<Map<String, Object?>> _ownerRecord(
  AppDatabase database,
  String owner,
) async =>
    (await database
            .customSelect(
              'SELECT * FROM local_owners WHERE id = ?',
              variables: [drift.Variable<String>(owner)],
            )
            .getSingle())
        .data;

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
};
