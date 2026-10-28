import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import 'research_admission_signing.dart';

final class SeededMotivationMeasurement {
  SeededMotivationMeasurement({
    required Map<String, Object?> run,
    required Map<String, Object?> response,
  }) : run = Map.unmodifiable(run),
       response = Map.unmodifiable(response);

  final Map<String, Object?> run;
  final Map<String, Object?> response;
  String get runId => run['id']! as String;
  String get responseId => response['id']! as String;
}

MotivationInstrument lifecycleMotivationInstrument() => MotivationInstrument(
  instrumentId: 'synthetic-lifecycle-instrument',
  instrumentVersion: 'synthetic-v1',
  formId: 'synthetic-lifecycle-form',
  formVersion: 'synthetic-v1',
  itemCatalogVersion: 'synthetic-items-v1',
  items: [
    for (final point in MotivationTimepoint.values)
      MotivationItem(
        id: 'synthetic-${point.name}',
        timepoint: point,
        prompts: const {'th': 'คำถามข้อมูลจำลอง', 'en': 'Synthetic item'},
        options: [
          MotivationResponseOption(
            code: 'synthetic-low',
            ordinalValue: 0,
            labels: const {'th': 'ระดับจำลองต่ำ', 'en': 'Synthetic low'},
          ),
          MotivationResponseOption(
            code: 'synthetic-high',
            ordinalValue: 100,
            labels: const {'th': 'ระดับจำลองสูง', 'en': 'Synthetic high'},
          ),
        ],
      ),
  ],
);

// Seeds historical synthetic facts; this helper never grants collection rights.
Future<SeededMotivationMeasurement> insertOwnerMotivationMeasurement(
  AppDatabase database,
  ResearchParticipationPermit permit, {
  String state = 'started',
}) async {
  if (!const {'started', 'skipped', 'abandoned', 'withdrawn'}.contains(state) ||
      !admissionP256Verifier().verify(
        issuerKeyId: permit.issuerKeyId,
        canonicalPayload: permit.canonicalPayload(),
        signature: permit.signature,
      )) {
    throw StateError('invalid synthetic measurement fixture');
  }
  final assignment = await database
      .customSelect(
        'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
        variables: [
          Variable<String>(permit.assignmentId),
          Variable<String>(permit.ownerId),
        ],
      )
      .getSingle();
  final consent = await database
      .customSelect(
        'SELECT consent_version, decided_at_utc_ms FROM research_consents '
        "WHERE owner_id = ? AND consent_state = 'accepted' "
        'ORDER BY consent_version DESC LIMIT 1',
        variables: [Variable<String>(permit.ownerId)],
      )
      .getSingleOrNull();
  final decision = consent?.read<int>('decided_at_utc_ms') ?? 1;
  final startCandidates = [
    decision,
    assignment.read<int>('assigned_at_utc_ms'),
    permit.issuedAtUtc.millisecondsSinceEpoch,
  ]..sort();
  final started = startCandidates.last + 1;
  final instrument = lifecycleMotivationInstrument();
  final runId = motivationMeasurementRunId(
    ownerId: permit.ownerId,
    permitId: permit.id,
    protocolId: permit.protocolId,
    protocolVersion: permit.protocolVersion,
    instrumentChecksumSha256: instrument.checksumSha256,
  );
  final item = instrument.itemsAt(MotivationTimepoint.baseline).single;
  final option = instrument.response(item.id, 'synthetic-high');
  final run = <String, Object?>{
    'id': runId,
    'owner_id': permit.ownerId,
    'local_revision': 1,
    'permit_id': permit.id,
    'permit_payload_sha256': permit.payloadSha256,
    'assignment_id': permit.assignmentId,
    'assignment_revision': 1,
    'consent_version': consent?.read<int>('consent_version') ?? 1,
    'consent_decided_at_utc_ms': decision,
    'protocol_id': permit.protocolId,
    'protocol_version': permit.protocolVersion,
    'protocol_revision': 1,
    'treatment': permit.assignedTreatment.name,
    'instrument_id': instrument.instrumentId,
    'instrument_version': instrument.instrumentVersion,
    'instrument_revision': 1,
    'instrument_checksum_sha256': instrument.checksumSha256,
    'form_id': instrument.formId,
    'form_version': instrument.formVersion,
    'item_catalog_version': instrument.itemCatalogVersion,
    'scoring_rule_version': motivationScoringRuleVersion,
    'app_version': 'synthetic-lifecycle-v1',
    'build_id': 'synthetic-lifecycle-build',
    'database_schema_version': database.schemaVersion,
    'content_revision': 'synthetic-content-v1',
    'evidence_policy_version': 'learning-evidence-v1',
    'catalog_version': 'synthetic-catalog-v1',
    'state': state,
    'started_at_utc_ms': started,
    'closed_at_utc_ms': state == 'started' ? null : started + 3,
  };
  final response = <String, Object?>{
    'id': motivationResponseId(runId: runId, itemId: item.id),
    'owner_id': permit.ownerId,
    'local_revision': 1,
    'run_id': runId,
    'item_id': item.id,
    'item_catalog_version': instrument.itemCatalogVersion,
    'response_code': option.code,
    'ordinal_value': option.ordinalValue,
    'answered_at_utc_ms': started + 1,
  };
  await database.customStatement(
    'INSERT INTO motivation_measurement_runs (${run.keys.join(', ')}) '
    'VALUES (${List.filled(run.length, '?').join(', ')})',
    run.values.toList(),
  );
  await database.customStatement(
    'INSERT INTO motivation_responses (${response.keys.join(', ')}) '
    'VALUES (${List.filled(response.length, '?').join(', ')})',
    response.values.toList(),
  );
  return SeededMotivationMeasurement(run: run, response: response);
}
