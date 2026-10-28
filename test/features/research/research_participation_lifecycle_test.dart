import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/data/research_lifecycle_export_reader.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/motivation_research_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  late _LifecycleAuthority authority;
  late DriftResearchParticipationRepository participation;
  late DriftResearchConsentRepository consent;

  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize(enroll: false);
    authority = _LifecycleAuthority();
    participation = DriftResearchParticipationRepository(
      f.database,
      study: f.study,
      validator: ResearchParticipationPermitValidator(
        protocolId: f.study.protocolId,
        protocolVersion: f.study.protocolVersion,
        signatures: authority,
        receipts: authority,
      ),
      nowUtc: () => f.now,
    );
    consent = DriftResearchConsentRepository(f.database);
  });
  tearDown(() => f.database.close());

  ResearchParticipationPermit permit([
    Map<String, Object?> changes = const {},
  ]) => _signedPermit(f.permit(), changes);

  Future<void> decide(bool accepted, {int version = 1, DateTime? at}) =>
      consent.decide(
        ownerId: 'owner:a',
        version: version,
        accepted: accepted,
        decidedAtUtc: at ?? f.now,
      );

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await f.database.customSelect('SELECT * FROM $table').get())
      row.data,
  ];

  Future<ResearchParticipationPermitRow> storedPermit() =>
      f.database.select(f.database.researchParticipationPermits).getSingle();

  Future<ActivePresentationPermit?> active() =>
      participation.readActivePermit(ownerId: 'owner:a', evaluatedAtUtc: f.now);

  test(
    'newer signed renewal is durable and exact replay is idempotent',
    () async {
      await participation.importPermit(permit());
      final renewed = permit({
        'localRevision': 2,
        'cloudRevision': 2,
        'expiresAtUtc': f.now.add(const Duration(days: 7)),
      });
      await participation.importPermit(renewed);
      final first = await storedPermit();
      expect(first.localRevision, 2);
      expect(
        permitFromRow(first).canonicalPayload(),
        renewed.canonicalPayload(),
      );
      expect(first.signature, renewed.signature);
      expect(await active(), isNotNull);
      await participation.importPermit(renewed);
      expect(await storedPermit(), first);
    },
  );

  test(
    'authentic revocation imports while inactive and replays unchanged',
    () async {
      await participation.importPermit(permit());
      final revoked = permit({
        'localRevision': 2,
        'cloudRevision': 2,
        'revokedAtUtc': f.now,
      });
      authority.receiptsActive = false;
      await participation.importPermit(revoked);
      final row = await storedPermit();
      expect(row.revokedAtUtcMs, f.now.millisecondsSinceEpoch);
      expect(row.signature, revoked.signature);
      expect(await active(), isNull);
      await participation.importPermit(revoked);
      expect(await storedPermit(), row);
    },
  );

  test(
    'authentic revocation still imports after expiry and local withdrawal',
    () async {
      await participation.importPermit(permit());
      final revoked = permit({
        'localRevision': 2,
        'cloudRevision': 2,
        'revokedAtUtc': f.now,
      });
      await decide(false);
      f.now = f.permit().expiresAtUtc;
      authority.receiptsActive = false;
      await participation.importPermit(revoked);
      expect((await storedPermit()).localRevision, 2);
      expect(await active(), isNull);
    },
  );

  test(
    'revocation before enrollment never creates a participation row',
    () async {
      final revoked = permit({
        'localRevision': 2,
        'cloudRevision': 2,
        'revokedAtUtc': f.now,
      });
      await expectLater(participation.importPermit(revoked), throwsA(anything));
      expect(await rows('research_participation_permits'), isEmpty);
    },
  );

  for (final update in <String, Map<String, Object?>>{
    'rollback': {'localRevision': 1, 'cloudRevision': 1},
    'same revision different payload': {
      'localRevision': 2,
      'cloudRevision': 2,
      'expiresAtUtc': DateTime.utc(2026, 10),
    },
    'un-revoke': {'localRevision': 3, 'cloudRevision': 3},
    'move revocation later': {
      'localRevision': 3,
      'cloudRevision': 3,
      'revokedAtUtc': DateTime.utc(2026, 9, 6),
    },
  }.entries) {
    test('revoked permit rejects ${update.key}', () async {
      await participation.importPermit(permit());
      await participation.importPermit(
        permit({'localRevision': 2, 'cloudRevision': 2, 'revokedAtUtc': f.now}),
      );
      final before = await storedPermit();
      await expectLater(
        participation.importPermit(permit(update.value)),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await storedPermit(), before);
      expect(await active(), isNull);
    });
  }

  for (final changed in <String, Object?>{
    'ownerId': 'owner:b',
    'assignmentId': 'assignment:replacement',
    'protocolId': 'other-protocol',
    'protocolVersion': '2',
    'assignedTreatment': TodayExperiencePresentation.standard,
    'participantClass': ResearchParticipantClass.minor,
    'ageBandCode': 'changed',
    'consentReceiptId': 'receipt:replacement',
    'guardianPermissionReceiptRef': 'guardian:replacement',
    'learnerAssentReceiptRef': 'assent:replacement',
    'issuedAtUtc': DateTime.utc(2026, 9, 5, 11, 1),
  }.entries) {
    test('signed update cannot replace immutable ${changed.key}', () async {
      await participation.importPermit(permit());
      final before = await storedPermit();
      await expectLater(
        participation.importPermit(
          permit({
            'localRevision': 2,
            'cloudRevision': 2,
            changed.key: changed.value,
          }),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await storedPermit(), before);
    });
  }

  for (final malformed in <String, Map<String, Object?>>{
    'unequal revisions': {'localRevision': 2, 'cloudRevision': 1},
    'zero revisions': {'localRevision': 0, 'cloudRevision': 0},
    'revocation before issuance': {'revokedAtUtc': DateTime.utc(2026, 9, 1)},
    'untrusted issuer': {'issuerKeyId': 'untrusted'},
    'bad digest': {'payloadSha256': '0' * 64},
    'bad signature': {'signature': 'forged'},
  }.entries) {
    test('reject malformed signed update: ${malformed.key}', () async {
      await participation.importPermit(permit());
      final before = await storedPermit();
      await expectLater(
        participation.importPermit(
          permit({
            'localRevision': 2,
            'cloudRevision': 2,
            'revokedAtUtc': f.now,
            ...malformed.value,
          }),
        ),
        throwsA(anything),
      );
      expect(await storedPermit(), before);
    });
  }

  test('old signature cannot authenticate a new revocation payload', () async {
    final original = permit();
    await participation.importPermit(original);
    await expectLater(
      participation.importPermit(
        permit({
          'localRevision': 2,
          'cloudRevision': 2,
          'revokedAtUtc': f.now,
          'signature': original.signature,
        }),
      ),
      throwsA(isA<ResearchCaptureDenied>()),
    );
    expect((await storedPermit()).signature, original.signature);
    expect((await storedPermit()).revokedAtUtcMs, isNull);
  });

  test(
    'missing receipt authority denies renewal without changing stored permit',
    () async {
      await participation.importPermit(permit());
      final before = await storedPermit();
      authority.receiptsActive = false;
      await expectLater(
        participation.importPermit(
          permit({'localRevision': 2, 'cloudRevision': 2}),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await storedPermit(), before);
    },
  );

  test(
    'unavailable signature authority denies revocation without mutation',
    () async {
      await participation.importPermit(permit());
      final before = await storedPermit();
      authority.signaturesAvailable = false;
      await expectLater(
        participation.importPermit(
          permit({
            'localRevision': 2,
            'cloudRevision': 2,
            'revokedAtUtc': f.now,
          }),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await storedPermit(), before);
    },
  );

  test('receipt revoked during awaited lookup denies enrollment', () async {
    authority.onRead = () async {
      authority.onRead = null;
      authority.receiptsActive = false;
    };
    await expectLater(
      participation.importPermit(permit()),
      throwsA(isA<ResearchCaptureDenied>()),
    );
    expect(await rows('research_participation_permits'), isEmpty);
  });

  test('expiry crossed during receipt lookup denies enrollment', () async {
    final expiring = permit({
      'expiresAtUtc': f.now.add(const Duration(seconds: 1)),
    });
    authority.onRead = () async {
      authority.onRead = null;
      f.now = expiring.expiresAtUtc;
    };
    await expectLater(
      participation.importPermit(expiring),
      throwsA(isA<ResearchCaptureDenied>()),
    );
    expect(await rows('research_participation_permits'), isEmpty);
  });

  test(
    'local withdrawal during authority lookup denies import before write',
    () async {
      authority.onRead = () async {
        authority.onRead = null;
        await decide(false);
      };
      await expectLater(
        participation.importPermit(permit()),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await rows('research_participation_permits'), isEmpty);
    },
  );

  test('owner switch during authority lookup denies import', () async {
    authority.onRead = () async {
      authority.onRead = null;
      await f.database.customStatement("UPDATE local_owners SET is_active = 0");
    };
    await expectLater(participation.importPermit(permit()), throwsA(anything));
    expect(await rows('research_participation_permits'), isEmpty);
  });

  test(
    'withdrawal preserves signed permits and response/denominator evidence',
    () async {
      await participation.importPermit(permit());
      await _seedRun(f, 'active');
      await _seedRun(f, 'completed', state: 'completed');
      await _seedRun(f, 'other-version', version: 2);
      await _seedOpportunity(f, 'opportunity:active', 'active');
      await _seedOpportunity(
        f,
        'opportunity:completed',
        'completed',
        closed: true,
      );
      await f.database
          .into(f.database.motivationResponses)
          .insert(
            MotivationResponsesCompanion.insert(
              id: 'response:active',
              ownerId: 'owner:a',
              runId: 'active',
              itemId: 'baseline',
              itemCatalogVersion: '1',
              responseCode: 'high',
              ordinalValue: const Value(5),
              answeredAtUtcMs: f.now.millisecondsSinceEpoch,
            ),
          );
      final permitBefore = await storedPermit();
      final responseBefore = await rows('motivation_responses');
      final opportunityBefore = await rows('measurement_opportunities');
      f.now = f.now.add(const Duration(minutes: 1));
      await decide(false);
      final runs = {
        for (final row in await rows('motivation_measurement_runs'))
          row['id']: row,
      };
      expect(runs['active']!['state'], 'withdrawn');
      expect(runs['completed']!['state'], 'withdrawn');
      expect(runs['other-version']!['state'], 'started');
      expect(runs['active']!['local_revision'], 2);
      expect(runs['active']!['closed_at_utc_ms'], f.now.millisecondsSinceEpoch);
      expect(await storedPermit(), permitBefore);
      expect(await rows('motivation_responses'), responseBefore);
      final opportunities = await rows('measurement_opportunities');
      expect(opportunities, hasLength(2));
      expect(
        opportunities.first['closed_at_utc_ms'],
        f.now.millisecondsSinceEpoch,
      );
      expect(
        opportunities.first['last_switch_ordinal'],
        opportunityBefore.first['last_switch_ordinal'],
      );
      expect(
        opportunities.first['suppressed_switch_count'],
        opportunityBefore.first['suppressed_switch_count'],
      );
      expect(opportunities.last, opportunityBefore.last);
      expect(await active(), isNull);
      final after = await rows('motivation_measurement_runs');
      await decide(false);
      expect(await rows('motivation_measurement_runs'), after);
    },
  );

  test(
    'withdrawal suppresses only matching research upserts and invalidates leases',
    () async {
      await participation.importPermit(permit());
      await _seedRun(f, 'active');
      await _seedRun(f, 'other-version', version: 2);
      await _seedOpportunity(f, 'opportunity:active', 'active');
      await f.database
          .into(f.database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner:b',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      for (final entry in <(String, String, String, String, String, String)>[
        (
          'run:pending',
          'motivationMeasurementRun',
          'active',
          'pending',
          'upsert',
          'owner:a',
        ),
        (
          'op:retry',
          'measurementOpportunity',
          'opportunity:active',
          'retryWaiting',
          'upsert',
          'owner:a',
        ),
        (
          'permit:flight',
          'researchParticipationPermit',
          'permit:a',
          'inFlight',
          'upsert',
          'owner:a',
        ),
        (
          'run:delete',
          'motivationMeasurementRun',
          'active',
          'pending',
          'delete',
          'owner:a',
        ),
        (
          'run:ack',
          'motivationMeasurementRun',
          'active',
          'acknowledged',
          'upsert',
          'owner:a',
        ),
        (
          'run:version2',
          'motivationMeasurementRun',
          'other-version',
          'pending',
          'upsert',
          'owner:a',
        ),
        (
          'run:other-owner',
          'motivationMeasurementRun',
          'active',
          'pending',
          'upsert',
          'owner:b',
        ),
        ('learning', 'word', 'word:1', 'pending', 'upsert', 'owner:a'),
      ]) {
        await f.database
            .into(f.database.outboxOperations)
            .insert(
              OutboxOperationsCompanion.insert(
                operationId: entry.$1,
                ownerId: entry.$6,
                entityType: entry.$2,
                entityId: entry.$3,
                operationKind: entry.$5,
                createdAtUtcMs: f.now.millisecondsSinceEpoch,
                state: Value(entry.$4),
                leaseToken: entry.$4 == 'inFlight'
                    ? const Value('synthetic-lease')
                    : const Value.absent(),
                leaseExpiresAtUtcMs: entry.$4 == 'inFlight'
                    ? Value(
                        f.now
                            .add(const Duration(minutes: 5))
                            .millisecondsSinceEpoch,
                      )
                    : const Value.absent(),
              ),
            );
      }
      final before = {
        for (final row in await rows('outbox_operations'))
          row['operation_id']: row,
      };
      await decide(false);
      final after = {
        for (final row in await rows('outbox_operations'))
          row['operation_id']: row,
      };
      for (final id in ['run:pending', 'op:retry', 'permit:flight']) {
        expect(after[id]!['state'], 'superseded', reason: id);
        expect(
          after[id]!['failure_code'],
          'researchConsentWithdrawn',
          reason: id,
        );
        expect(after[id]!['lease_token'], isNull, reason: id);
        expect(after[id]!['lease_expires_at_utc_ms'], isNull, reason: id);
      }
      for (final id in [
        'run:delete',
        'run:ack',
        'run:version2',
        'run:other-owner',
        'learning',
      ]) {
        expect(after[id], before[id], reason: id);
      }
    },
  );

  test(
    'withdrawal rolls back consent, runs and opportunities if suppression fails',
    () async {
      await participation.importPermit(permit());
      await _seedRun(f, 'active');
      await _seedOpportunity(f, 'opportunity:active', 'active');
      await f.database
          .into(f.database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'run:pending',
              ownerId: 'owner:a',
              entityType: 'motivationMeasurementRun',
              entityId: 'active',
              operationKind: 'upsert',
              createdAtUtcMs: f.now.millisecondsSinceEpoch,
            ),
          );
      final before = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'research_consents',
        'motivation_measurement_runs',
        'measurement_opportunities',
        'outbox_operations',
      ]) {
        before[table] = await rows(table);
      }
      await f.database.customStatement('''
      CREATE TEMP TRIGGER synthetic_suppression_failure
      BEFORE UPDATE ON outbox_operations
      BEGIN SELECT RAISE(ABORT, 'synthetic suppression failure'); END
    ''');
      await expectLater(decide(false), throwsA(anything));
      for (final table in before.keys) {
        expect(await rows(table), before[table], reason: table);
      }
    },
  );

  for (final useEventNames in [false, true]) {
    test(
      'neutral event suppression requires an exact event type and related opportunity (typed=$useEventNames)',
      () async {
        await participation.importPermit(permit());
        await _seedRun(f, 'active');
        await _seedRun(f, 'other-version', version: 2);
        await _seedOpportunity(f, 'opportunity:active', 'active');
        await _seedOpportunity(f, 'opportunity:other', 'other-version');
        final scenarios = <(String, String?, String, String, String, bool)>[
          (
            'TodayExperiencePresented',
            'opportunity:active',
            'MeasurementOpportunity',
            'opportunity:active',
            'upsert',
            true,
          ),
          (
            'TodayExperiencePresentationChanged',
            'opportunity:active',
            'MeasurementOpportunity',
            'opportunity:active',
            'upsert',
            true,
          ),
          (
            'TodayExperienceMissionStarted',
            'opportunity:active',
            'LearningSession',
            'session:synthetic',
            'upsert',
            true,
          ),
          (
            'TodayExperienceMissionCompleted',
            'opportunity:active',
            'LearningSession',
            'session:synthetic',
            'upsert',
            true,
          ),
          (
            'TodayExperiencePresented',
            null,
            'MeasurementOpportunity',
            'opportunity:active',
            'upsert',
            true,
          ),
          (
            'LearningSessionStarted',
            'opportunity:active',
            'LearningSession',
            'session:synthetic',
            'upsert',
            false,
          ),
          (
            'TodayExperiencePresented',
            'opportunity:other',
            'MeasurementOpportunity',
            'opportunity:other',
            'upsert',
            false,
          ),
          (
            'TodayExperiencePresented',
            null,
            'LearningSession',
            'opportunity:active',
            'upsert',
            false,
          ),
          (
            'TodayExperiencePresented',
            'opportunity:active',
            'MeasurementOpportunity',
            'opportunity:active',
            'delete',
            false,
          ),
        ];
        for (var i = 0; i < scenarios.length; i++) {
          final s = scenarios[i];
          final eventId = researchEventId('synthetic-lifecycle:$i', f.now);
          await f.database
              .into(f.database.eventsV2)
              .insert(
                EventsV2Companion.insert(
                  eventId: eventId,
                  eventType: s.$1,
                  eventVersion: 1,
                  occurredAtUtc: f.now,
                  recordedAtUtc: f.now,
                  actorIdentity: 'owner:a',
                  ownerId: 'owner:a',
                  aggregateType: s.$3,
                  aggregateId: s.$4,
                  correlationId: Value(s.$2),
                  idempotencyKey: 'synthetic-lifecycle:$i',
                  consentContextJson:
                      '{"researchConsentVersion":1,"aiConsentGranted":false,"voiceConsentGranted":false,"socialConsentGranted":false}',
                  appVersion: '1',
                  buildId: 'test',
                  privacyClassification: 'ownerOnly',
                  payloadJson: '{}',
                ),
              );
          await f.database
              .into(f.database.outboxOperations)
              .insert(
                OutboxOperationsCompanion.insert(
                  operationId: 'event-operation:$i',
                  ownerId: 'owner:a',
                  entityType: useEventNames ? s.$1 : 'eventsV2',
                  entityId: eventId,
                  operationKind: s.$5,
                  createdAtUtcMs: f.now.millisecondsSinceEpoch,
                ),
              );
        }
        final before = await rows('events_v2');
        await decide(false);
        final operations = {
          for (final row in await rows('outbox_operations'))
            row['operation_id']: row,
        };
        for (var i = 0; i < scenarios.length; i++) {
          expect(
            operations['event-operation:$i']!['state'],
            scenarios[i].$6 ? 'superseded' : 'pending',
            reason: 'scenario $i',
          );
        }
        expect(await rows('events_v2'), before);
      },
    );
  }

  test('personal research export remains available after withdrawal', () async {
    await participation.importPermit(permit());
    await _seedRun(f, 'active');
    await _seedOpportunity(f, 'opportunity:active', 'active');
    await decide(false);
    final exported = await ResearchLifecycleExportReader(
      f.database,
    ).load('owner:a');
    expect(exported['motivation_measurement_runs']!.first['recordCount'], 1);
    expect(exported['motivation_measurement_runs']!.last['state'], 'withdrawn');
    expect(exported['measurement_opportunities']!.first['recordCount'], 1);
    expect(exported['research_participation_permits']!.first['recordCount'], 1);
  });

  for (final withRun in [false, true]) {
    test(
      'withdraw and reaccept never resurrects old permit (run=$withRun)',
      () async {
        final original = permit();
        await participation.importPermit(original);
        if (withRun) await _seedRun(f, 'active');
        await decide(false);
        f.now = f.now.add(const Duration(minutes: 1));
        await decide(true);
        expect(
          (await consent.load(ownerId: 'owner:a', version: 1)).accepted,
          isTrue,
        );
        expect(await active(), isNull);
        await expectLater(
          participation.importPermit(original),
          throwsA(anything),
        );
        await expectLater(
          participation.importPermit(
            permit({'localRevision': 2, 'cloudRevision': 2}),
          ),
          throwsA(anything),
        );
        expect((await storedPermit()).signature, original.signature);
      },
    );
  }

  test('backdated reaccept cannot replace withdrawal evidence', () async {
    await participation.importPermit(permit());
    await decide(false);
    final before = await rows('research_consents');
    await expectLater(
      decide(true, at: DateTime.utc(2026, 9, 5, 10)),
      throwsA(anything),
    );
    expect(await rows('research_consents'), before);
    expect(await active(), isNull);
  });

  test(
    'withdrawal of a nonparticipant creates no research capture or outbox',
    () async {
      await decide(false);
      for (final table in [
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'events_v2',
        'outbox_operations',
      ]) {
        expect(await rows(table), isEmpty, reason: table);
      }
    },
  );
}

// Synthetic signing material, confined to this test. Never a production issuer.
final _testCurve = ECCurve_secp256r1();
final _testPrivateKey = ECPrivateKey(BigInt.one, _testCurve);
final _testVerifier = ResearchP256SignatureVerifier(
  publicKeysSec1Hex: {
    'lifecycle-synthetic': _testCurve.G
        .getEncoded(false)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
  },
);

final class _LifecycleAuthority
    implements ResearchPermitSignatureVerifier, ResearchReceiptAuthority {
  bool receiptsActive = true;
  bool signaturesAvailable = true;
  Future<void> Function()? onRead;

  @override
  bool verify({
    required String issuerKeyId,
    required String canonicalPayload,
    required String signature,
  }) {
    if (!signaturesAvailable) {
      throw StateError('Synthetic authority unavailable');
    }
    return _testVerifier.verify(
      issuerKeyId: issuerKeyId,
      canonicalPayload: canonicalPayload,
      signature: signature,
    );
  }

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    final captured = receiptsActive;
    await onRead?.call();
    return captured && ownerId == 'owner:a';
  }
}

ResearchParticipationPermit _signedPermit(
  ResearchParticipationPermit source,
  Map<String, Object?> changes,
) {
  ResearchParticipationPermit make(String digest, String signature) =>
      ResearchParticipationPermit(
        id: changes['id'] as String? ?? source.id,
        ownerId: changes['ownerId'] as String? ?? source.ownerId,
        participantClass:
            changes['participantClass'] as ResearchParticipantClass? ??
            source.participantClass,
        ageBandCode: changes['ageBandCode'] as String? ?? source.ageBandCode,
        assignmentId: changes['assignmentId'] as String? ?? source.assignmentId,
        assignedTreatment:
            changes['assignedTreatment'] as TodayExperiencePresentation? ??
            source.assignedTreatment,
        consentReceiptId:
            changes['consentReceiptId'] as String? ?? source.consentReceiptId,
        guardianPermissionReceiptRef:
            changes['guardianPermissionReceiptRef'] as String? ??
            source.guardianPermissionReceiptRef,
        learnerAssentReceiptRef:
            changes['learnerAssentReceiptRef'] as String? ??
            source.learnerAssentReceiptRef,
        protocolId: changes['protocolId'] as String? ?? source.protocolId,
        protocolVersion:
            changes['protocolVersion'] as String? ?? source.protocolVersion,
        issuedAtUtc: changes['issuedAtUtc'] as DateTime? ?? source.issuedAtUtc,
        expiresAtUtc:
            changes['expiresAtUtc'] as DateTime? ?? source.expiresAtUtc,
        revokedAtUtc: changes['revokedAtUtc'] as DateTime?,
        issuerKeyId: changes['issuerKeyId'] as String? ?? 'lifecycle-synthetic',
        payloadSha256: changes['payloadSha256'] as String? ?? digest,
        signature: changes['signature'] as String? ?? signature,
        localRevision: changes['localRevision'] as int? ?? source.localRevision,
        cloudRevision: changes['cloudRevision'] as int? ?? source.cloudRevision,
        isDeleted: changes['isDeleted'] as bool? ?? false,
      );
  final payload = utf8.encode(make('', '').canonicalPayload());
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(_testPrivateKey));
  final signature = signer.generateSignature(payload) as ECSignature;
  final raw =
      '${signature.r.toRadixString(16).padLeft(64, '0')}${signature.s.toRadixString(16).padLeft(64, '0')}';
  return make(
    sha256.convert(payload).toString(),
    base64Encode([
      for (var i = 0; i < raw.length; i += 2)
        int.parse(raw.substring(i, i + 2), radix: 16),
    ]),
  );
}

Future<void> _seedRun(
  MotivationResearchFixture f,
  String id, {
  String state = 'started',
  int version = 1,
}) async {
  await f.database
      .into(f.database.motivationMeasurementRuns)
      .insert(
        MotivationMeasurementRunsCompanion.insert(
          id: id,
          ownerId: 'owner:a',
          assignmentId: f.assignmentId,
          consentVersion: version,
          consentDecidedAtUtcMs: DateTime.utc(
            2026,
            9,
            5,
            10,
          ).millisecondsSinceEpoch,
          protocolId: f.study.protocolId,
          protocolVersion: f.study.protocolVersion,
          treatment: 'adventure',
          instrumentId: f.instrument.instrumentId,
          instrumentVersion: f.instrument.instrumentVersion,
          formId: f.instrument.formId,
          formVersion: f.instrument.formVersion,
          appVersion: f.study.appVersion,
          buildId: f.study.buildId,
          databaseSchemaVersion: AppDatabase.currentSchemaVersion,
          contentRevision: f.study.contentRevision,
          evidencePolicyVersion: f.study.evidencePolicyVersion,
          state: state,
          startedAtUtcMs: f.now.millisecondsSinceEpoch,
          closedAtUtcMs: state == 'started'
              ? const Value.absent()
              : Value(f.now.millisecondsSinceEpoch),
        ),
      );
}

Future<void> _seedOpportunity(
  MotivationResearchFixture f,
  String id,
  String runId, {
  bool closed = false,
}) async {
  await f.database
      .into(f.database.measurementOpportunities)
      .insert(
        MeasurementOpportunitiesCompanion.insert(
          id: id,
          ownerId: 'owner:a',
          measurementRunId: runId,
          permitId: 'permit:a',
          entryAttemptId: id.endsWith('completed')
              ? '00000000-0000-4000-8000-000000000002'
              : '00000000-0000-4000-8000-000000000001',
          assignedTreatment: 'adventure',
          effectivePresentation: 'standard',
          lastSwitchOrdinal: const Value(2),
          suppressedSwitchCount: const Value(3),
          openedAtUtcMs: f.now.millisecondsSinceEpoch,
          closedAtUtcMs: closed
              ? Value(f.now.millisecondsSinceEpoch)
              : const Value.absent(),
        ),
      );
}
