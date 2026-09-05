/// Cross-row owner/assignment pins cannot be expressed by a scalar CHECK.
/// Install these guards for both freshly created and upgraded databases.
Future<void> installResearchSchemaGuards(
  Future<void> Function(String) execute,
) async {
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
    'measurement_opportunities': '''NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r
      JOIN research_participation_permits p ON p.id = NEW.permit_id
      WHERE r.id = NEW.measurement_run_id AND r.owner_id = NEW.owner_id
      AND p.owner_id = NEW.owner_id AND p.assignment_id = r.assignment_id
      AND p.protocol_id = r.protocol_id AND p.protocol_version = r.protocol_version
      AND p.assigned_treatment = r.treatment AND r.treatment = NEW.assigned_treatment)
      OR (NEW.learning_session_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM learning_sessions s WHERE s.id = NEW.learning_session_id
        AND s.owner_id = NEW.owner_id))''',
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
        WHERE measurement_run_id = OLD.id)''',
    'research_participation_permits': '''
      EXISTS (SELECT 1 FROM measurement_opportunities WHERE permit_id = OLD.id)''',
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
    await execute('''
      CREATE TRIGGER IF NOT EXISTS ${entry.key}_referenced_pins_v24_update
      BEFORE UPDATE OF ${entry.value.join(', ')} ON ${entry.key}
      WHEN (${referencedByResearch[entry.key]}) AND ($changedPins)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END
    ''');
  }
}
