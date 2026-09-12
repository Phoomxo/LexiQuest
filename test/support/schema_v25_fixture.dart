// Frozen from actual schema 25 (48 tables), before the schema 26 change.
// Source capture SHA256: 956ece02ac2af7506b6f2e476b75b7910354f82fe872b28507311811b74d6180.
// Never replace these literals with current generated DDL or guard installers.
import '../database/migration_v24_to_v25_test.dart' as legacy;

void createSchemaTwentyFiveFixture(dynamic sqlite) {
  final foreignKeys =
      sqlite.select('PRAGMA foreign_keys').single.values.single as int;
  sqlite.execute('PRAGMA foreign_keys = OFF');
  try {
    legacy.createSchemaTwentyFourFixture(sqlite);
    // Older fixture constructors may enable FK internally. Disable it after
    // that chain, before dropping parents, so retained child rows cannot cascade.
    sqlite.execute('PRAGMA foreign_keys = OFF');
    if (sqlite.select('PRAGMA foreign_keys').single.values.single != 0) {
      throw StateError(
        'Historical overlay requires FK off outside a transaction',
      );
    }
    final retained = <String, List<Map<String, Object?>>>{
      for (final table in schemaTwentyFiveOverlayTables.keys)
        table: [
          for (final row in sqlite.select('SELECT * FROM $table'))
            Map<String, Object?>.from(row),
        ],
    };
    for (final table in [
      'measurement_opportunities',
      'motivation_responses',
      'motivation_measurement_runs',
      'research_participation_permits',
      'quest_instances',
    ]) {
      sqlite.execute('DROP TABLE $table');
    }
    for (final sql in schemaTwentyFiveOverlayTables.values) {
      sqlite.execute(sql);
    }
    for (final entry in retained.entries) {
      for (final original in entry.value) {
        final row = <String, Object?>{...original};
        if (entry.key == 'quest_instances') {
          // The inherited v13 history has an empty objective catalog and a
          // nonempty progress child. Schema25 therefore retains unknown pins;
          // only the documented legacy key/start backfill is added here.
          row['period_key'] = 'legacy:${original['instance_id']}';
          row['period_start_at_utc_ms'] = original['assigned_at_utc_ms'];
        }
        sqlite.execute(
          'INSERT INTO ${entry.key} (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
          row.values.toList(),
        );
      }
    }
    for (final sql in schemaTwentyFiveGuards.values) {
      sqlite.execute(sql);
    }
    sqlite.execute('PRAGMA user_version = 25');
  } finally {
    sqlite.execute('PRAGMA foreign_keys = $foreignKeys');
  }
}

const schemaTwentyFiveOverlayTables = <String, String>{
  'quest_instances':
      r"""CREATE TABLE "quest_instances" ("instance_id" TEXT NOT NULL, "quest_id" TEXT NOT NULL REFERENCES quest_definitions (quest_id), "owner_id" TEXT NOT NULL REFERENCES local_owners (id), "catalog_version" INTEGER NOT NULL, "assigned_at_utc_ms" INTEGER NOT NULL, "state" TEXT NOT NULL, "completed_at_utc_ms" INTEGER NULL, "expired_at_utc_ms" INTEGER NULL, "period_policy" TEXT NOT NULL DEFAULT 'legacyDuration', "period_key" TEXT NOT NULL DEFAULT '', "period_timezone_id" TEXT NULL, "period_start_at_utc_ms" INTEGER NOT NULL DEFAULT 0, "period_end_at_utc_ms" INTEGER NULL, "deadline_at_utc_ms" INTEGER NULL, "is_canonical" INTEGER NOT NULL DEFAULT 1 CHECK ("is_canonical" IN (0, 1)), "definition_snapshot_json" TEXT NULL, PRIMARY KEY ("instance_id"))""",
  'research_participation_permits':
      r"""CREATE TABLE "research_participation_permits" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL REFERENCES local_owners (id) ON DELETE CASCADE, "local_revision" INTEGER NOT NULL DEFAULT 1 CHECK (local_revision > 0), "cloud_revision" INTEGER NOT NULL DEFAULT 0 CHECK (cloud_revision >= 0), "last_acknowledged_at_utc_ms" INTEGER CHECK (last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0), "server_updated_at_utc_ms" INTEGER CHECK (server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "participant_class" TEXT NOT NULL, "age_band_code" TEXT NOT NULL, "assignment_id" TEXT NOT NULL REFERENCES experiment_assignments (id), "assigned_treatment" TEXT NOT NULL, "consent_receipt_id" TEXT NOT NULL, "guardian_permission_receipt_ref" TEXT NULL, "learner_assent_receipt_ref" TEXT NULL, "protocol_id" TEXT NOT NULL, "protocol_version" TEXT NOT NULL, "issued_at_utc_ms" INTEGER NOT NULL, "expires_at_utc_ms" INTEGER NOT NULL, "revoked_at_utc_ms" INTEGER NULL, "issuer_key_id" TEXT NOT NULL, "payload_sha256" TEXT NOT NULL, "signature" TEXT NOT NULL, PRIMARY KEY ("id"), CHECK (participant_class IN ('adult', 'minor')), CHECK (assigned_treatment IN ('standard', 'adventure')), CHECK (participant_class = 'adult' OR (guardian_permission_receipt_ref IS NOT NULL AND learner_assent_receipt_ref IS NOT NULL)), CHECK (issued_at_utc_ms >= 0 AND expires_at_utc_ms > issued_at_utc_ms), CHECK (revoked_at_utc_ms IS NULL OR revoked_at_utc_ms >= issued_at_utc_ms), CHECK (length(payload_sha256) = 64 AND payload_sha256 NOT GLOB '*[^0-9a-f]*'))""",
  'motivation_measurement_runs':
      r"""CREATE TABLE "motivation_measurement_runs" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL REFERENCES local_owners (id) ON DELETE CASCADE, "local_revision" INTEGER NOT NULL DEFAULT 1 CHECK (local_revision > 0), "cloud_revision" INTEGER NOT NULL DEFAULT 0 CHECK (cloud_revision >= 0), "last_acknowledged_at_utc_ms" INTEGER CHECK (last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0), "server_updated_at_utc_ms" INTEGER CHECK (server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "assignment_id" TEXT NOT NULL REFERENCES experiment_assignments (id), "consent_version" INTEGER NOT NULL, "consent_decided_at_utc_ms" INTEGER NOT NULL, "protocol_id" TEXT NOT NULL, "protocol_version" TEXT NOT NULL, "treatment" TEXT NOT NULL, "instrument_id" TEXT NOT NULL, "instrument_version" TEXT NOT NULL, "form_id" TEXT NOT NULL, "form_version" TEXT NOT NULL, "app_version" TEXT NOT NULL, "build_id" TEXT NOT NULL, "database_schema_version" INTEGER NOT NULL, "content_revision" TEXT NOT NULL, "evidence_policy_version" TEXT NOT NULL, "state" TEXT NOT NULL, "started_at_utc_ms" INTEGER NOT NULL, "closed_at_utc_ms" INTEGER NULL, PRIMARY KEY ("id"), CHECK (consent_version > 0 AND consent_decided_at_utc_ms >= 0 AND database_schema_version > 0), CHECK (treatment IN ('standard', 'adventure')), CHECK (state IN ('started', 'completed', 'skipped', 'abandoned', 'withdrawn')), CHECK (started_at_utc_ms >= consent_decided_at_utc_ms), CHECK ((state = 'started' AND closed_at_utc_ms IS NULL) OR (state <> 'started' AND closed_at_utc_ms >= started_at_utc_ms AND closed_at_utc_ms IS NOT NULL)))""",
  'motivation_responses':
      r"""CREATE TABLE "motivation_responses" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL REFERENCES local_owners (id) ON DELETE CASCADE, "local_revision" INTEGER NOT NULL DEFAULT 1 CHECK (local_revision > 0), "cloud_revision" INTEGER NOT NULL DEFAULT 0 CHECK (cloud_revision >= 0), "last_acknowledged_at_utc_ms" INTEGER CHECK (last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0), "server_updated_at_utc_ms" INTEGER CHECK (server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "run_id" TEXT NOT NULL REFERENCES motivation_measurement_runs (id) ON DELETE CASCADE, "item_id" TEXT NOT NULL, "item_catalog_version" TEXT NOT NULL, "response_code" TEXT NOT NULL, "ordinal_value" INTEGER NULL, "answered_at_utc_ms" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("owner_id", "run_id", "item_id"), CHECK (answered_at_utc_ms >= 0), CHECK (ordinal_value IS NULL OR ordinal_value BETWEEN 0 AND 100))""",
  'measurement_opportunities':
      r"""CREATE TABLE "measurement_opportunities" ("id" TEXT NOT NULL, "owner_id" TEXT NOT NULL REFERENCES local_owners (id) ON DELETE CASCADE, "local_revision" INTEGER NOT NULL DEFAULT 1 CHECK (local_revision > 0), "cloud_revision" INTEGER NOT NULL DEFAULT 0 CHECK (cloud_revision >= 0), "last_acknowledged_at_utc_ms" INTEGER CHECK (last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0), "server_updated_at_utc_ms" INTEGER CHECK (server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0), "is_deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("is_deleted" IN (0, 1)), "measurement_run_id" TEXT NOT NULL REFERENCES motivation_measurement_runs (id) ON DELETE CASCADE, "permit_id" TEXT NOT NULL REFERENCES research_participation_permits (id), "entry_attempt_id" TEXT NOT NULL, "assigned_treatment" TEXT NOT NULL, "effective_presentation" TEXT NOT NULL, "presented_event_id" TEXT NULL, "learning_session_id" TEXT NULL REFERENCES learning_sessions (id), "started_event_id" TEXT NULL, "completed_event_id" TEXT NULL, "last_switch_ordinal" INTEGER NOT NULL DEFAULT 0, "suppressed_switch_count" INTEGER NOT NULL DEFAULT 0, "opened_at_utc_ms" INTEGER NOT NULL, "closed_at_utc_ms" INTEGER NULL, PRIMARY KEY ("id"), UNIQUE ("owner_id", "measurement_run_id", "permit_id", "entry_attempt_id"), CHECK (assigned_treatment IN ('standard', 'adventure')), CHECK (effective_presentation IN ('standard', 'adventure')), CHECK (last_switch_ordinal BETWEEN 0 AND 10 AND suppressed_switch_count >= 0), CHECK (opened_at_utc_ms >= 0 AND (closed_at_utc_ms IS NULL OR closed_at_utc_ms >= opened_at_utc_ms)), CHECK (started_event_id IS NULL OR learning_session_id IS NOT NULL), CHECK (completed_event_id IS NULL OR (started_event_id IS NOT NULL AND closed_at_utc_ms IS NOT NULL)))""",
};

const schemaTwentyFiveGuards = <String, String>{
  'quest_canonical_active':
      r"""CREATE UNIQUE INDEX quest_canonical_active ON quest_instances(owner_id,quest_id) WHERE is_canonical = 1 AND state = 'active'""",
  'quest_canonical_period':
      r"""CREATE UNIQUE INDEX quest_canonical_period ON quest_instances(owner_id,quest_id,period_key) WHERE is_canonical = 1""",
  'quest_definition_snapshot_immutable':
      r"""CREATE TRIGGER quest_definition_snapshot_immutable
      BEFORE UPDATE OF definition_snapshot_json ON quest_instances
      WHEN NEW.definition_snapshot_json IS NOT OLD.definition_snapshot_json
      BEGIN SELECT RAISE(ABORT, 'quest_definition_snapshot_is_immutable'); END""",
  'experiment_assignments_referenced_pins_v24_update':
      r"""CREATE TRIGGER experiment_assignments_referenced_pins_v24_update
      BEFORE UPDATE OF id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms ON experiment_assignments
      WHEN (      EXISTS (SELECT 1 FROM motivation_measurement_runs
        WHERE assignment_id = OLD.id)
      OR EXISTS (SELECT 1 FROM research_participation_permits
        WHERE assignment_id = OLD.id)) AND (NEW.id IS NOT OLD.id OR NEW.owner_id IS NOT OLD.owner_id OR NEW.experiment_id IS NOT OLD.experiment_id OR NEW.experiment_version IS NOT OLD.experiment_version OR NEW.cohort IS NOT OLD.cohort OR NEW.protocol_version IS NOT OLD.protocol_version OR NEW.assigned_at_utc_ms IS NOT OLD.assigned_at_utc_ms)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END""",
  'learning_sessions_referenced_pins_v24_update':
      r"""CREATE TRIGGER learning_sessions_referenced_pins_v24_update
      BEFORE UPDATE OF id, owner_id ON learning_sessions
      WHEN (      EXISTS (SELECT 1 FROM measurement_opportunities
        WHERE learning_session_id = OLD.id)) AND (NEW.id IS NOT OLD.id OR NEW.owner_id IS NOT OLD.owner_id)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END""",
  'measurement_opportunities_owner_insert':
      r"""CREATE TRIGGER measurement_opportunities_owner_insert
        BEFORE INSERT ON measurement_opportunities WHEN NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r
      JOIN research_participation_permits p ON p.id = NEW.permit_id
      WHERE r.id = NEW.measurement_run_id AND r.owner_id = NEW.owner_id
      AND p.owner_id = NEW.owner_id AND p.assignment_id = r.assignment_id
      AND p.protocol_id = r.protocol_id AND p.protocol_version = r.protocol_version
      AND p.assigned_treatment = r.treatment AND r.treatment = NEW.assigned_treatment)
      OR (NEW.learning_session_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM learning_sessions s WHERE s.id = NEW.learning_session_id
        AND s.owner_id = NEW.owner_id))
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'measurement_opportunities_owner_update':
      r"""CREATE TRIGGER measurement_opportunities_owner_update
        BEFORE UPDATE ON measurement_opportunities WHEN NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r
      JOIN research_participation_permits p ON p.id = NEW.permit_id
      WHERE r.id = NEW.measurement_run_id AND r.owner_id = NEW.owner_id
      AND p.owner_id = NEW.owner_id AND p.assignment_id = r.assignment_id
      AND p.protocol_id = r.protocol_id AND p.protocol_version = r.protocol_version
      AND p.assigned_treatment = r.treatment AND r.treatment = NEW.assigned_treatment)
      OR (NEW.learning_session_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM learning_sessions s WHERE s.id = NEW.learning_session_id
        AND s.owner_id = NEW.owner_id))
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'motivation_measurement_runs_owner_insert':
      r"""CREATE TRIGGER motivation_measurement_runs_owner_insert
        BEFORE INSERT ON motivation_measurement_runs WHEN NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.treatment)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'motivation_measurement_runs_owner_update':
      r"""CREATE TRIGGER motivation_measurement_runs_owner_update
        BEFORE UPDATE ON motivation_measurement_runs WHEN NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.treatment)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'motivation_measurement_runs_referenced_pins_v24_update':
      r"""CREATE TRIGGER motivation_measurement_runs_referenced_pins_v24_update
      BEFORE UPDATE OF id, owner_id, assignment_id, consent_version, consent_decided_at_utc_ms, protocol_id, protocol_version, treatment, instrument_id, instrument_version, form_id, form_version, app_version, build_id, database_schema_version, content_revision, evidence_policy_version, started_at_utc_ms ON motivation_measurement_runs
      WHEN (      EXISTS (SELECT 1 FROM motivation_responses WHERE run_id = OLD.id)
      OR EXISTS (SELECT 1 FROM measurement_opportunities
        WHERE measurement_run_id = OLD.id)) AND (NEW.id IS NOT OLD.id OR NEW.owner_id IS NOT OLD.owner_id OR NEW.assignment_id IS NOT OLD.assignment_id OR NEW.consent_version IS NOT OLD.consent_version OR NEW.consent_decided_at_utc_ms IS NOT OLD.consent_decided_at_utc_ms OR NEW.protocol_id IS NOT OLD.protocol_id OR NEW.protocol_version IS NOT OLD.protocol_version OR NEW.treatment IS NOT OLD.treatment OR NEW.instrument_id IS NOT OLD.instrument_id OR NEW.instrument_version IS NOT OLD.instrument_version OR NEW.form_id IS NOT OLD.form_id OR NEW.form_version IS NOT OLD.form_version OR NEW.app_version IS NOT OLD.app_version OR NEW.build_id IS NOT OLD.build_id OR NEW.database_schema_version IS NOT OLD.database_schema_version OR NEW.content_revision IS NOT OLD.content_revision OR NEW.evidence_policy_version IS NOT OLD.evidence_policy_version OR NEW.started_at_utc_ms IS NOT OLD.started_at_utc_ms)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END""",
  'motivation_responses_owner_insert':
      r"""CREATE TRIGGER motivation_responses_owner_insert
        BEFORE INSERT ON motivation_responses WHEN NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r WHERE r.id = NEW.run_id
      AND r.owner_id = NEW.owner_id)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'motivation_responses_owner_update':
      r"""CREATE TRIGGER motivation_responses_owner_update
        BEFORE UPDATE ON motivation_responses WHEN NOT EXISTS (
      SELECT 1 FROM motivation_measurement_runs r WHERE r.id = NEW.run_id
      AND r.owner_id = NEW.owner_id)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'research_participation_permits_owner_insert':
      r"""CREATE TRIGGER research_participation_permits_owner_insert
        BEFORE INSERT ON research_participation_permits WHEN NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.assigned_treatment)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'research_participation_permits_owner_update':
      r"""CREATE TRIGGER research_participation_permits_owner_update
        BEFORE UPDATE ON research_participation_permits WHEN NOT EXISTS (
      SELECT 1 FROM experiment_assignments a WHERE a.id = NEW.assignment_id
      AND a.owner_id = NEW.owner_id AND a.protocol_version = NEW.protocol_version
      AND a.cohort = NEW.assigned_treatment)
        BEGIN SELECT RAISE(ABORT, 'research_owner_or_assignment_mismatch'); END""",
  'research_participation_permits_referenced_pins_v24_update':
      r"""CREATE TRIGGER research_participation_permits_referenced_pins_v24_update
      BEFORE UPDATE OF id, owner_id, assignment_id, participant_class, age_band_code, consent_receipt_id, guardian_permission_receipt_ref, learner_assent_receipt_ref, protocol_id, protocol_version, assigned_treatment, issued_at_utc_ms ON research_participation_permits
      WHEN (      EXISTS (SELECT 1 FROM measurement_opportunities WHERE permit_id = OLD.id)) AND (NEW.id IS NOT OLD.id OR NEW.owner_id IS NOT OLD.owner_id OR NEW.assignment_id IS NOT OLD.assignment_id OR NEW.participant_class IS NOT OLD.participant_class OR NEW.age_band_code IS NOT OLD.age_band_code OR NEW.consent_receipt_id IS NOT OLD.consent_receipt_id OR NEW.guardian_permission_receipt_ref IS NOT OLD.guardian_permission_receipt_ref OR NEW.learner_assent_receipt_ref IS NOT OLD.learner_assent_receipt_ref OR NEW.protocol_id IS NOT OLD.protocol_id OR NEW.protocol_version IS NOT OLD.protocol_version OR NEW.assigned_treatment IS NOT OLD.assigned_treatment OR NEW.issued_at_utc_ms IS NOT OLD.issued_at_utc_ms)
      BEGIN SELECT RAISE(ABORT, 'research_referenced_parent_pin_changed'); END""",
  'research_participation_permits_strict_receipts_v24_insert':
      r"""CREATE TRIGGER research_participation_permits_strict_receipts_v24_insert
      BEFORE INSERT ON research_participation_permits
      WHEN NEW.consent_receipt_id IS NULL OR (NEW.participant_class = 'minor' AND (NEW.guardian_permission_receipt_ref IS NULL OR NEW.learner_assent_receipt_ref IS NULL)) OR (NEW.consent_receipt_id IS NOT NULL AND (typeof(NEW.consent_receipt_id) <> 'text' OR length(NEW.consent_receipt_id) NOT BETWEEN 1 AND 128 OR instr(NEW.consent_receipt_id, char(0)) > 0 OR NEW.consent_receipt_id GLOB '*[^A-Za-z0-9_.:-]*')) OR (NEW.guardian_permission_receipt_ref IS NOT NULL AND (typeof(NEW.guardian_permission_receipt_ref) <> 'text' OR length(NEW.guardian_permission_receipt_ref) NOT BETWEEN 1 AND 128 OR instr(NEW.guardian_permission_receipt_ref, char(0)) > 0 OR NEW.guardian_permission_receipt_ref GLOB '*[^A-Za-z0-9_.:-]*')) OR (NEW.learner_assent_receipt_ref IS NOT NULL AND (typeof(NEW.learner_assent_receipt_ref) <> 'text' OR length(NEW.learner_assent_receipt_ref) NOT BETWEEN 1 AND 128 OR instr(NEW.learner_assent_receipt_ref, char(0)) > 0 OR NEW.learner_assent_receipt_ref GLOB '*[^A-Za-z0-9_.:-]*'))
      BEGIN SELECT RAISE(ABORT, 'research_receipt_reference_invalid'); END""",
  'research_participation_permits_strict_receipts_v24_update':
      r"""CREATE TRIGGER research_participation_permits_strict_receipts_v24_update
      BEFORE UPDATE ON research_participation_permits
      WHEN NEW.consent_receipt_id IS NULL OR (NEW.participant_class = 'minor' AND (NEW.guardian_permission_receipt_ref IS NULL OR NEW.learner_assent_receipt_ref IS NULL)) OR (NEW.consent_receipt_id IS NOT NULL AND (typeof(NEW.consent_receipt_id) <> 'text' OR length(NEW.consent_receipt_id) NOT BETWEEN 1 AND 128 OR instr(NEW.consent_receipt_id, char(0)) > 0 OR NEW.consent_receipt_id GLOB '*[^A-Za-z0-9_.:-]*')) OR (NEW.guardian_permission_receipt_ref IS NOT NULL AND (typeof(NEW.guardian_permission_receipt_ref) <> 'text' OR length(NEW.guardian_permission_receipt_ref) NOT BETWEEN 1 AND 128 OR instr(NEW.guardian_permission_receipt_ref, char(0)) > 0 OR NEW.guardian_permission_receipt_ref GLOB '*[^A-Za-z0-9_.:-]*')) OR (NEW.learner_assent_receipt_ref IS NOT NULL AND (typeof(NEW.learner_assent_receipt_ref) <> 'text' OR length(NEW.learner_assent_receipt_ref) NOT BETWEEN 1 AND 128 OR instr(NEW.learner_assent_receipt_ref, char(0)) > 0 OR NEW.learner_assent_receipt_ref GLOB '*[^A-Za-z0-9_.:-]*'))
      BEGIN SELECT RAISE(ABORT, 'research_receipt_reference_invalid'); END""",
};
