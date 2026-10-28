import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../research/domain/research_session_proof.dart';
import '../domain/export_contracts.dart';

/// Personal evidence projections, read within the archive's owner-pinned
/// transaction. Withdrawal/tombstones restrict collection, not personal access.
/// Proof identity/pin fields are read privately for strict codec validation;
/// only the explicit personal projection leaves this reader.
final class ResearchLifecycleExportReader {
  const ResearchLifecycleExportReader(this.database);

  final AppDatabase database;

  Future<Map<String, List<Map<String, Object?>>>> load(String ownerId) async {
    final runs = await database
        .customSelect(
          'SELECT id, protocol_id, protocol_version, treatment, instrument_id, '
          'instrument_version, form_id, form_version, app_version, build_id, '
          'database_schema_version, content_revision, evidence_policy_version, '
          'state, started_at_utc_ms, closed_at_utc_ms, is_deleted '
          'FROM motivation_measurement_runs WHERE owner_id = ? '
          'ORDER BY started_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.motivationMeasurementRuns},
        )
        .get();
    final permits = await database
        .customSelect(
          'SELECT id, participant_class, age_band_code, assigned_treatment, '
          'protocol_id, protocol_version, issued_at_utc_ms, expires_at_utc_ms, '
          'revoked_at_utc_ms, is_deleted '
          'FROM research_participation_permits WHERE owner_id = ? '
          'ORDER BY issued_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.researchParticipationPermits},
        )
        .get();
    final responses = await database
        .customSelect(
          'SELECT run_id, item_id, item_catalog_version, response_code, '
          'ordinal_value, answered_at_utc_ms, is_deleted '
          'FROM motivation_responses WHERE owner_id = ? '
          'ORDER BY answered_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.motivationResponses},
        )
        .get();
    final opportunities = await database
        .customSelect(
          'SELECT measurement_run_id, permit_id, assigned_treatment, '
          'effective_presentation, presented_event_id IS NOT NULL AS has_presented, '
          'learning_session_id IS NOT NULL AS has_session, '
          'started_event_id IS NOT NULL AS has_started, '
          'completed_event_id IS NOT NULL AS has_completed, '
          'last_switch_ordinal, suppressed_switch_count, opened_at_utc_ms, '
          'closed_at_utc_ms, is_deleted '
          'FROM measurement_opportunities WHERE owner_id = ? '
          'ORDER BY opened_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.measurementOpportunities},
        )
        .get();
    final proofRows = await database
        .customSelect(
          'SELECT id, owner_id, measurement_run_id, permit_id, learning_session_id, '
          'proof_revision, activity_type, session_state, started_at_utc_ms, ended_at_utc_ms, '
          'app_version, build_id, session_configuration_identity, session_configuration_json, '
          'pair_start_operation, pair_checkpoint_event_version, pair_owner_lineage_json, '
          'permit_payload_sha256, permit_revision, is_deleted '
          'FROM research_session_proofs WHERE owner_id = ? '
          'ORDER BY started_at_utc_ms, learning_session_id, proof_revision, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.researchSessionProofs},
        )
        .get();
    // Decode before projecting, including Pair purpose and configuration. A
    // storage-shaped matching row alone does not establish learning purpose.
    final proofs = [for (final row in proofRows) _decodeProof(row)];
    final sessionAliases = <String, String>{};
    for (final proof in proofs) {
      sessionAliases.putIfAbsent(
        proof.learningSessionId,
        () => 'research-session-${sessionAliases.length + 1}',
      );
    }
    // Local ordinal aliases retain linkage without exposing or hashing IDs.
    // Include every parent, even when withdrawn, revoked or tombstoned.
    final runAliases = _aliases(runs, 'motivation-run');
    final permitAliases = _aliases(permits, 'research-permit');
    return {
      'research_session_proofs': [
        {'recordCount': proofs.length},
        for (var index = 0; index < proofs.length; index++)
          {
            'proofAlias': 'research-proof-${index + 1}',
            'sessionAlias': _requireAlias(
              sessionAliases,
              proofs[index].learningSessionId,
            ),
            'runAlias': _requireAlias(
              runAliases,
              proofs[index].measurementRunId,
            ),
            'permitAlias': _requireAlias(permitAliases, proofs[index].permitId),
            'proofRevision': proofs[index].proofRevision,
            'activityType': _code(proofs[index].activityType),
            'sessionState': proofs[index].sessionState,
            'startedAtUtc': _iso(proofs[index].startedAtUtcMs),
            'endedAtUtc': _nullableIso(proofs[index].endedAtUtcMs),
            'appVersion': _code(proofs[index].appVersion),
            'buildId': _code(proofs[index].buildId),
            'sessionConfigurationIdentity':
                proofs[index].sessionConfigurationIdentity,
            'purpose': proofs[index].activityType == 'matching'
                ? 'learning'
                : null,
            'isDeleted': proofRows[index].read<bool>('is_deleted'),
          },
      ],
      'motivation_measurement_runs': [
        {'recordCount': runs.length},
        for (final row in runs)
          {
            'measurementAxis': 'motivation',
            'runAlias': _requireAlias(runAliases, row.read<String>('id')),
            'protocolId': _code(row.read<String>('protocol_id')),
            'protocolVersion': _code(row.read<String>('protocol_version')),
            'assignedTreatment': _code(row.read<String>('treatment')),
            'instrumentId': _code(row.read<String>('instrument_id')),
            'instrumentVersion': _code(row.read<String>('instrument_version')),
            'formId': _code(row.read<String>('form_id')),
            'formVersion': _code(row.read<String>('form_version')),
            'appVersion': _code(row.read<String>('app_version')),
            'buildId': _code(row.read<String>('build_id')),
            'databaseSchemaVersion': row.read<int>('database_schema_version'),
            'contentRevision': _code(row.read<String>('content_revision')),
            'evidencePolicyVersion': _code(
              row.read<String>('evidence_policy_version'),
            ),
            'state': _code(row.read<String>('state')),
            'startedAtUtc': _iso(row.read<int>('started_at_utc_ms')),
            'closedAtUtc': _nullableIso(
              row.readNullable<int>('closed_at_utc_ms'),
            ),
            'isDeleted': row.read<bool>('is_deleted'),
          },
      ],
      'motivation_responses': [
        {'recordCount': responses.length},
        for (final row in responses)
          {
            'measurementAxis': 'motivation',
            'runAlias': _requireAlias(runAliases, row.read<String>('run_id')),
            'itemId': _code(row.read<String>('item_id')),
            'itemCatalogVersion': _code(
              row.read<String>('item_catalog_version'),
            ),
            'responseCode': _code(row.read<String>('response_code')),
            'ordinalValue': row.readNullable<int>('ordinal_value'),
            'answeredAtUtc': _iso(row.read<int>('answered_at_utc_ms')),
            'isDeleted': row.read<bool>('is_deleted'),
          },
      ],
      'research_participation_permits': [
        {'recordCount': permits.length},
        for (final row in permits)
          {
            'permitAlias': _requireAlias(permitAliases, row.read<String>('id')),
            'participantClass': _code(row.read<String>('participant_class')),
            'ageBandCode': _code(row.read<String>('age_band_code')),
            'assignedTreatment': _code(row.read<String>('assigned_treatment')),
            'protocolId': _code(row.read<String>('protocol_id')),
            'protocolVersion': _code(row.read<String>('protocol_version')),
            'issuedAtUtc': _iso(row.read<int>('issued_at_utc_ms')),
            'expiresAtUtc': _iso(row.read<int>('expires_at_utc_ms')),
            'revokedAtUtc': _nullableIso(
              row.readNullable<int>('revoked_at_utc_ms'),
            ),
            'isDeleted': row.read<bool>('is_deleted'),
          },
      ],
      'measurement_opportunities': [
        {'recordCount': opportunities.length},
        for (final row in opportunities)
          {
            'measurementAxis': 'engagement',
            'runAlias': _requireAlias(
              runAliases,
              row.read<String>('measurement_run_id'),
            ),
            'permitAlias': _requireAlias(
              permitAliases,
              row.read<String>('permit_id'),
            ),
            'assignedTreatment': _code(row.read<String>('assigned_treatment')),
            'effectivePresentation': _code(
              row.read<String>('effective_presentation'),
            ),
            'hasPresentationEvent': row.read<bool>('has_presented'),
            'hasAcceptedSession': row.read<bool>('has_session'),
            'hasStartEvent': row.read<bool>('has_started'),
            'hasCompletionEvent': row.read<bool>('has_completed'),
            'lastSwitchOrdinal': row.read<int>('last_switch_ordinal'),
            'suppressedSwitchCount': row.read<int>('suppressed_switch_count'),
            'openedAtUtc': _iso(row.read<int>('opened_at_utc_ms')),
            'closedAtUtc': _nullableIso(
              row.readNullable<int>('closed_at_utc_ms'),
            ),
            'isDeleted': row.read<bool>('is_deleted'),
          },
      ],
    };
  }
}

ResearchSessionProof _decodeProof(QueryRow row) {
  try {
    final fields = row.data;
    final lineage = fields['pair_owner_lineage_json'];
    return ResearchSessionProof.decode({
      'schema': ResearchSessionProof.schema,
      'id': fields['id'],
      'ownerId': fields['owner_id'],
      'measurementRunId': fields['measurement_run_id'],
      'permitId': fields['permit_id'],
      'learningSessionId': fields['learning_session_id'],
      'proofRevision': fields['proof_revision'],
      'activityType': fields['activity_type'],
      'sessionState': fields['session_state'],
      'startedAtUtcMs': fields['started_at_utc_ms'],
      'endedAtUtcMs': fields['ended_at_utc_ms'],
      'appVersion': fields['app_version'],
      'buildId': fields['build_id'],
      'sessionConfigurationIdentity': fields['session_configuration_identity'],
      'sessionConfigurationJson': fields['session_configuration_json'],
      'pairStartOperation': fields['pair_start_operation'],
      'pairCheckpointEventVersion': fields['pair_checkpoint_event_version'],
      'pairOwnerLineage': lineage == null
          ? null
          : jsonDecode(lineage as String),
      'permitPayloadSha256': fields['permit_payload_sha256'],
      'permitRevision': fields['permit_revision'],
    });
  } on Object {
    // Do not attach raw proof/configuration input to a user-visible error.
    throw const ExportException(ExportFailureCode.unavailable);
  }
}

Map<String, String> _aliases(List<QueryRow> rows, String prefix) => {
  for (var index = 0; index < rows.length; index++)
    rows[index].read<String>('id'): '$prefix-${index + 1}',
};

String _requireAlias(Map<String, String> aliases, String id) =>
    aliases[id] ?? (throw const ExportException(ExportFailureCode.unavailable));

final _nonCode = RegExp(r'[^A-Za-z0-9_.:-]');

String _code(String value) {
  // Match the instrument's canonical bounded identifiers. Do not trim or
  // redact answers into a different code, and do not put invalid values in errors.
  if (value.isEmpty || value.length > 128 || _nonCode.hasMatch(value)) {
    throw const ExportException(ExportFailureCode.unavailable);
  }
  return value;
}

String _iso(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
  milliseconds,
  isUtc: true,
).toIso8601String();

String? _nullableIso(int? milliseconds) =>
    milliseconds == null ? null : _iso(milliseconds);
