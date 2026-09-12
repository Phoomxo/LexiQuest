/// Cross-row owner/assignment pins cannot be expressed by a scalar CHECK.
/// Install these guards for both freshly created and upgraded databases.
Future<void> installResearchSchemaGuards(
  Future<void> Function(String) execute,
) async {
  for (final name in [
    'measurement_opportunities_owner_insert',
    'measurement_opportunities_owner_update',
    'motivation_measurement_runs_referenced_pins_v24_update',
    'research_participation_permits_referenced_pins_v24_update',
  ]) {
    await execute('DROP TRIGGER IF EXISTS $name');
  }
  await execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS research_session_proofs_owner_phase_v26 ON research_session_proofs(owner_id,measurement_run_id,permit_id,learning_session_id,proof_revision)',
  );
  await execute(
    'CREATE INDEX IF NOT EXISTS measurement_opportunities_session_authority_v26 ON measurement_opportunities(owner_id,learning_session_id,measurement_run_id,permit_id) WHERE learning_session_id IS NOT NULL',
  );
  const predicates = <String, String>{
    'motivation_measurement_runs': '''NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.treatment)''',
    'research_participation_permits': '''NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.assigned_treatment)''',
    'motivation_responses': '''NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r WHERE r.id = NEW.run_id
      AND r.owner_id = NEW.owner_id)''',
  };
  for (final entry in predicates.entries) {
    for (final operation in ['INSERT', 'UPDATE']) {
      await execute(
        '''CREATE TRIGGER IF NOT EXISTS ${entry.key}_owner_${operation.toLowerCase()}
        BEFORE $operation ON ${entry.key} WHEN ${entry.value}
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END''',
      );
    }
  }
  for (final entry in {
    'measurement_opportunities': researchOpportunityAuthorityMismatch('NEW'),
    'research_session_proofs': researchSessionProofOwnerMismatch('NEW'),
  }.entries) {
    for (final operation in ['INSERT', 'UPDATE']) {
      await execute(
        '''CREATE TRIGGER IF NOT EXISTS ${entry.key}_owner_v26_${operation.toLowerCase()}
        BEFORE $operation ON ${entry.key} WHEN ${entry.value}
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END''',
      );
    }
  }

  // These additional names also install on an already-opened v24 schema whose
  // original IF NOT EXISTS owner guards are still present.
  final invalidReceipts = [
    'NEW.consent_receipt_id IS NULL',
    "(NEW.participant_class = 'minor' AND "
        '(NEW.guardian_permission_receipt_ref IS NULL OR '
        'NEW.learner_assent_receipt_ref IS NULL))',
    for (final field in [
      'consent_receipt_id',
      'guardian_permission_receipt_ref',
      'learner_assent_receipt_ref',
    ])
      '(NEW.$field IS NOT NULL AND ('
          "typeof(NEW.$field) <> 'text' OR "
          'length(NEW.$field) NOT BETWEEN 1 AND 128 OR '
          // SQLite length/GLOB stop at NUL; reject it explicitly.
          'instr(NEW.$field, char(0)) > 0 OR '
          "NEW.$field GLOB '*[^A-Za-z0-9_.:-]*'))",
  ].join(' OR ');
  for (final operation in ['INSERT', 'UPDATE']) {
    await execute('''
      CREATE TRIGGER IF NOT EXISTS
        research_participation_permits_strict_receipts_v24_${operation.toLowerCase()}
      BEFORE $operation ON research_participation_permits
      WHEN $invalidReceipts
      BEGIN SELECT RAISE(ABORT, 'research_receipt_reference_invalid'); END
    ''');
  }

  const parentPins = <String, List<String>>{
    'motivation_measurement_runs': [
      'id',
      'owner_id',
      'assignment_id',
      'consent_version',
      'consent_decided_at_utc_ms',
      'protocol_id',
      'protocol_version',
      'treatment',
      'instrument_id',
      'instrument_version',
      'form_id',
      'form_version',
      'app_version',
      'build_id',
      'database_schema_version',
      'content_revision',
      'evidence_policy_version',
      'started_at_utc_ms',
    ],
    'research_participation_permits': [
      'id',
      'owner_id',
      'assignment_id',
      'participant_class',
      'age_band_code',
      'consent_receipt_id',
      'guardian_permission_receipt_ref',
      'learner_assent_receipt_ref',
      'protocol_id',
      'protocol_version',
      'assigned_treatment',
      'issued_at_utc_ms',
    ],
    'experiment_assignments': [
      'id',
      'owner_id',
      'experiment_id',
      'experiment_version',
      'cohort',
      'protocol_version',
      'assigned_at_utc_ms',
    ],
    'learning_sessions': ['id', 'owner_id'],
  };
  const referencedByResearch = <String, String>{
    'motivation_measurement_runs': '''
      EXISTS (SELECT 1 FROM motivation_responses WHERE run_id = OLD.id)
      OR EXISTS (SELECT 1 FROM measurement_opportunities
        WHERE measurement_run_id = OLD.id)
      OR EXISTS (SELECT 1 FROM research_session_proofs
        WHERE measurement_run_id = OLD.id)''',
    'research_participation_permits': '''
      EXISTS (SELECT 1 FROM measurement_opportunities WHERE permit_id = OLD.id)
      OR EXISTS (SELECT 1 FROM research_session_proofs WHERE permit_id = OLD.id)''',
    'experiment_assignments': '''
      EXISTS (SELECT 1 FROM motivation_measurement_runs
        WHERE assignment_id = OLD.id)
      OR EXISTS (SELECT 1 FROM research_participation_permits
        WHERE assignment_id = OLD.id)''',
    'learning_sessions': '''
      EXISTS (SELECT 1 FROM measurement_opportunities
        WHERE learning_session_id = OLD.id)''',
  };
  for (final entry in parentPins.entries) {
    // Include tombstones. Null-safe value comparison permits full-row importer
    // updates that repeat pins while changing signed revisions/revocation, expiry,
    // issuer/signature/hash, acknowledgement metadata or lifecycle state.
    final changedPins = entry.value
        .map((field) => 'NEW.$field IS NOT OLD.$field')
        .join(' OR ');
    final version =
        entry.key == 'motivation_measurement_runs' ||
            entry.key == 'research_participation_permits'
        ? 26
        : 24;
    await execute('''
      CREATE TRIGGER IF NOT EXISTS ${entry.key}_referenced_pins_v${version}_update
      BEFORE UPDATE OF ${entry.value.join(', ')} ON ${entry.key}
      WHEN (${referencedByResearch[entry.key]}) AND ($changedPins)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END
    ''');
  }
  await _installSessionProofGuards(execute);
}

/// Shared by row admission and migration validation, including tombstone pins.
String researchSessionProofOwnerMismatch(String row) =>
    '''NOT EXISTS (
  SELECT 1 FROM motivation_measurement_runs r
  JOIN research_participation_permits p ON p.id = $row.permit_id
  WHERE r.id = $row.measurement_run_id AND r.owner_id = $row.owner_id
  AND p.owner_id = $row.owner_id AND p.assignment_id = r.assignment_id
  AND p.protocol_id = r.protocol_id AND p.protocol_version = r.protocol_version
  AND p.assigned_treatment = r.treatment)''';

String researchOpportunityAuthorityMismatch(String row) =>
    '''
  ${researchSessionProofOwnerMismatch(row)}
  OR NOT EXISTS (SELECT 1 FROM motivation_measurement_runs r
    WHERE r.id = $row.measurement_run_id AND r.treatment = $row.assigned_treatment)
  OR ($row.learning_session_id IS NOT NULL AND NOT (
    ${_canonicalSessionExists(row)} OR ${_liveProofExists(row)}))''';

String _canonicalSessionExists(String row) =>
    '''EXISTS (
  SELECT 1 FROM learning_sessions s WHERE s.id = $row.learning_session_id
  AND s.owner_id = $row.owner_id)''';

String _sameProofTuple(String proof, String row) =>
    '''
  $proof.owner_id = $row.owner_id
  AND $proof.measurement_run_id = $row.measurement_run_id
  AND $proof.permit_id = $row.permit_id
  AND $proof.learning_session_id = $row.learning_session_id''';

String _liveProofExists(String row, {bool excludingOld = false}) =>
    '''EXISTS (
  SELECT 1 FROM research_session_proofs p
  WHERE ${_sameProofTuple('p', row)} AND p.is_deleted = 0
  ${excludingOld ? 'AND p.id <> OLD.id' : ''})''';

const _proofStartCore = [
  'owner_id',
  'measurement_run_id',
  'permit_id',
  'learning_session_id',
  'activity_type',
  'started_at_utc_ms',
  'app_version',
  'build_id',
  'session_configuration_identity',
  'session_configuration_json',
  'pair_start_operation',
  'pair_checkpoint_event_version',
  'pair_owner_lineage_json',
  'permit_payload_sha256',
  'permit_revision',
];

String researchSessionProofSiblingMismatch(String row) {
  final changed = _proofStartCore
      .map((field) => 'p.$field IS NOT $row.$field')
      .join(' OR ');
  return '''EXISTS (SELECT 1 FROM research_session_proofs p
    WHERE ${_sameProofTuple('p', row)} AND ($changed))''';
}

Future<void> _installSessionProofGuards(
  Future<void> Function(String) execute,
) async {
  final immutable = [
    'id',
    'proof_revision',
    'session_state',
    'ended_at_utc_ms',
    ..._proofStartCore,
  ];
  final changed = immutable
      .map((field) => 'NEW.$field IS NOT OLD.$field')
      .join(' OR ');
  await execute(
    '''CREATE TRIGGER IF NOT EXISTS research_session_proofs_immutable_v26_update
    BEFORE UPDATE OF ${immutable.join(', ')} ON research_session_proofs
    WHEN $changed
    BEGIN SELECT RAISE(ABORT, 'research_session_proof_is_immutable'); END''',
  );

  // Tombstoned siblings still carry immutable start facts. Completed-first
  // insertion is valid; only a contradiction with an existing phase is denied.
  await execute(
    '''CREATE TRIGGER IF NOT EXISTS research_session_proofs_sibling_core_v26_insert
    BEFORE INSERT ON research_session_proofs
    WHEN ${researchSessionProofSiblingMismatch('NEW')}
    BEGIN SELECT RAISE(ABORT, 'research_session_proof_sibling_conflict'); END''',
  );

  final losesAuthority =
      '''EXISTS (
    SELECT 1 FROM measurement_opportunities o
    WHERE ${_sameProofTuple('OLD', 'o')}
    AND NOT (${_canonicalSessionExists('o')} OR ${_liveProofExists('o', excludingOld: true)}))''';
  await execute(
    '''CREATE TRIGGER IF NOT EXISTS research_session_proofs_last_authority_v26_delete
    BEFORE DELETE ON research_session_proofs WHEN $losesAuthority
    BEGIN SELECT RAISE(ABORT, 'research_session_authority_required'); END''',
  );
  await execute(
    '''CREATE TRIGGER IF NOT EXISTS research_session_proofs_last_authority_v26_update
    BEFORE UPDATE OF is_deleted ON research_session_proofs
    WHEN NEW.is_deleted = 1 AND OLD.is_deleted = 0 AND $losesAuthority
    BEGIN SELECT RAISE(ABORT, 'research_session_authority_required'); END''',
  );
  await execute(
    '''CREATE TRIGGER IF NOT EXISTS learning_sessions_last_authority_v26_delete
    BEFORE DELETE ON learning_sessions
    WHEN EXISTS (SELECT 1 FROM measurement_opportunities o
      WHERE o.learning_session_id = OLD.id AND NOT (${_liveProofExists('o')}))
    BEGIN SELECT RAISE(ABORT, 'research_session_authority_required'); END''',
  );
}
