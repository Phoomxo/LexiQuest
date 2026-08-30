import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../../../runtime/download_counter.dart';
import '../../../runtime/runtime_flag_namespaces.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../device_model/domain/model_lifecycle.dart';
import '../data/drift_export_reader.dart';
import '../../identity/domain/owner_lifecycle_manifest.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../review/domain/content_quality_report.dart';
import '../../time_tracking/domain/learning_time_segment.dart';

final class OwnerLifecycleArchiveArtifact {
  const OwnerLifecycleArchiveArtifact({
    required this.bytes,
    required this.sha256,
    required this.contentSha256,
    required this.manifestSha256,
    required this.generatedAtUtc,
  });

  final Uint8List bytes;
  final String sha256;
  final String contentSha256;
  final String manifestSha256;
  final DateTime generatedAtUtc;
}

/// Builds a deterministic, manifest-coupled owner archive from one coherent
/// Drift transaction. Secure storage is deliberately outside the reader and
/// no file picker or screen-owned dependency is accepted here.
final class OwnerLifecycleArchiveExporter {
  const OwnerLifecycleArchiveExporter({
    required this.database,
    required this.nowUtc,
  });

  final AppDatabase database;
  final DateTime Function() nowUtc;

  Future<OwnerLifecycleArchiveArtifact> prepareActive() async {
    final generatedAtUtc = nowUtc();
    if (!generatedAtUtc.isUtc) {
      throw ArgumentError.value(generatedAtUtc, 'nowUtc', 'must return UTC');
    }
    final manifestSha256 = _manifestSha256();
    final content = await database.transaction(() async {
      _requireExactManifestCoverage();
      final canonicalOwnerId = await _resolvePinnedActiveOwner();
      final documentAliases = await _documentAliases(canonicalOwnerId);
      final tables = <Map<String, Object?>>[];
      for (final descriptor in ownerLifecycleManifest) {
        final records = await _recordsFor(
          descriptor,
          ownerId: canonicalOwnerId,
          nowUtc: generatedAtUtc,
          documentAliases: documentAliases,
        );
        _requireAllowedFields(descriptor, records);
        tables.add({
          'alias': descriptor.alias,
          'authority': descriptor.authority.name,
          'exportDisposition': descriptor.exportDisposition.name,
          'deletionDisposition': descriptor.deletionDisposition.name,
          'records': records,
        });
      }
      return <String, Object?>{
        'archiveSchemaVersion': 1,
        'algorithmVersion': 1,
        'databaseSchemaVersion': database.schemaVersion,
        'manifestEntryCount': ownerLifecycleManifest.length,
        'generatedAtUtc': generatedAtUtc.toIso8601String(),
        'timeZone': 'UTC',
        'participantAlias': 'participant-1',
        'manifestSha256': manifestSha256,
        'tables': tables,
      };
    });
    final encoder = const JsonEncoder.withIndent('  ');
    final contentBytes = utf8.encode(encoder.convert(content));
    final contentSha256 = crypto.sha256.convert(contentBytes).toString();
    final bytes = Uint8List.fromList(
      utf8.encode(
        encoder.convert({'contentSha256': contentSha256, 'content': content}),
      ),
    );
    return OwnerLifecycleArchiveArtifact(
      bytes: bytes,
      sha256: crypto.sha256.convert(bytes).toString(),
      contentSha256: contentSha256,
      manifestSha256: manifestSha256,
      generatedAtUtc: generatedAtUtc,
    );
  }

  void _requireExactManifestCoverage() {
    final liveTables = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    if (liveTables.length != ownerLifecycleExportTableNames.length ||
        !liveTables.containsAll(ownerLifecycleExportTableNames)) {
      throw StateError(
        'Owner lifecycle export manifest does not match the live schema.',
      );
    }
  }

  Future<String> _resolvePinnedActiveOwner() async {
    final activeOwners = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    if (activeOwners.length != 1) {
      throw StateError(
        'Owner lifecycle archive requires the single active participant.',
      );
    }
    return activeOwners.single.id;
  }

  void _requireAllowedFields(
    OwnerLifecycleTableDescriptor descriptor,
    List<Map<String, Object?>> records,
  ) {
    final allowed = descriptor.allowedExportFields.toSet();
    for (final record in records) {
      final forbidden = record.keys.where((field) => !allowed.contains(field));
      if (forbidden.isNotEmpty) {
        throw StateError(
          'Archive field is not allowlisted for ${descriptor.alias}: '
          '${forbidden.first}',
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> _recordsFor(
    OwnerLifecycleTableDescriptor descriptor, {
    required String ownerId,
    required DateTime nowUtc,
    required Map<String, String> documentAliases,
  }) async {
    return switch (descriptor.tableName) {
      'local_owners' => _ownerRoot(ownerId),
      'research_consents' => _researchConsents(ownerId),
      'experiment_assignments' => _experimentAssignments(ownerId),
      'assessment_runs' => _assessmentRuns(ownerId),
      'saved_learning_items' => _savedLearningItems(ownerId),
      'content_quality_reports' => _contentQualityReports(ownerId),
      'vocabulary_categories' => _vocabularyCategories(ownerId),
      'vocabulary_words' => _vocabularyWords(ownerId),
      'vocabulary_imports' => _vocabularyImports(ownerId),
      'learning_sessions' => _learningSessions(ownerId),
      'session_configurations' => _sessionConfigurations(ownerId),
      'learning_time_segments' => _learningTimeSegments(ownerId),
      'learning_goals' => _learningGoals(ownerId),
      'learner_preferences' => _learnerPreferences(ownerId),
      'answer_attempts' => _answerAttempts(ownerId),
      'srs_states' => _srsStates(ownerId),
      'reading_progress_entries' => _readingProgress(ownerId, documentAliases),
      'reading_events' => _readingEvents(ownerId, documentAliases),
      'points_ledger_entries' => _pointsLedger(ownerId),
      'reward_transactions' => _rewardTransactions(ownerId),
      'streak_states' => _streakState(ownerId),
      'learning_day_log' => _learningDays(ownerId),
      'ai_usage_events' => _aiUsage(ownerId),
      'runtime_flags' => _runtimeDiagnostics(nowUtc),
      'model_downloads' => _modelDownloads(),
      _ => _countRecord(descriptor, ownerId),
    };
  }

  Future<List<Map<String, Object?>>> _ownerRoot(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT account_state FROM local_owners WHERE id = ? LIMIT 1',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.localOwners},
        )
        .getSingleOrNull();
    if (row == null) return const [];
    return [
      {
        'recordCount': 1,
        'accountState': _accountState(row.read<String>('account_state')),
      },
    ];
  }

  Future<List<Map<String, Object?>>> _pointsLedger(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS record_count, '
          'COALESCE(SUM(amount), 0) AS net_points '
          'FROM points_ledger_entries WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.pointsLedgerEntries},
        )
        .getSingle();
    return [
      {
        'recordCount': row.read<int>('record_count'),
        'netPoints': row.read<int>('net_points'),
      },
    ];
  }

  Future<List<Map<String, Object?>>> _rewardTransactions(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS record_count, '
          'COALESCE(SUM(amount), 0) AS net_amount '
          'FROM reward_transactions WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.rewardTransactions},
        )
        .getSingle();
    return [
      {
        'recordCount': row.read<int>('record_count'),
        'netAmount': row.read<int>('net_amount'),
      },
    ];
  }

  Future<List<Map<String, Object?>>> _researchConsents(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT consent_version, consent_state, decided_at_utc_ms, '
          'withdrawn_at_utc_ms FROM research_consents WHERE owner_id = ? '
          'ORDER BY consent_version',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.researchConsents},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'consentVersion': row.read<int>('consent_version'),
          'consentState': _consentState(row.read<String>('consent_state')),
          'decidedAtUtc': _iso(row.read<int>('decided_at_utc_ms')),
          'withdrawnAtUtc': _nullableIso(
            row.readNullable<int>('withdrawn_at_utc_ms'),
          ),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _experimentAssignments(
    String ownerId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT experiment_id, experiment_version, cohort, protocol_version, '
          'assigned_at_utc_ms FROM experiment_assignments WHERE owner_id = ? '
          'ORDER BY experiment_id, experiment_version',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.experimentAssignments},
        )
        .get();
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'experimentId': row.read<String>('experiment_id'),
          'experimentVersion': row.read<int>('experiment_version'),
          'cohort': row.read<String>('cohort'),
          'protocolVersion': row.read<String>('protocol_version'),
          'assignedAtUtc': DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('assigned_at_utc_ms'),
            isUtc: true,
          ).toIso8601String(),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _assessmentRuns(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT id, learning_session_id, study_cycle_id, phase, state, '
          'protocol_id, protocol_version, experiment_id, experiment_version, '
          'assignment_id, cohort, consent_version, '
          'consent_decided_at_utc_ms, instrument_id, instrument_version, '
          'form_id, form_version, instrument_checksum_sha256, '
          'form_checksum_sha256, app_version, build_id, '
          'database_schema_version, content_revision, '
          'evidence_policy_version, feature_contract_revision, '
          'feature_contract_hash, started_at_utc_ms, completed_at_utc_ms, '
          'abandoned_at_utc_ms FROM assessment_runs WHERE owner_id = ? '
          'ORDER BY started_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.assessmentRuns},
        )
        .get();
    final records = <Map<String, Object?>>[
      {'recordCount': rows.length},
    ];
    for (final row in rows) {
      records.add({
        'studyCycleId': _safeLabel(row.read<String>('study_cycle_id')),
        'phase': _assessmentPhase(row.read<String>('phase')),
        'state': _assessmentState(row.read<String>('state')),
        'protocolId': _safeLabel(row.read<String>('protocol_id')),
        'protocolVersion': _safeLabel(row.read<String>('protocol_version')),
        'experimentId': _safeLabel(row.read<String>('experiment_id')),
        'experimentVersion': row.read<int>('experiment_version'),
        'cohort': _safeLabel(row.read<String>('cohort')),
        'consentVersion': row.read<int>('consent_version'),
        'consentDecidedAtUtc': _iso(row.read<int>('consent_decided_at_utc_ms')),
        'instrumentId': _safeLabel(row.read<String>('instrument_id')),
        'instrumentVersion': _safeLabel(row.read<String>('instrument_version')),
        'formId': _safeLabel(row.read<String>('form_id')),
        'formVersion': _safeLabel(row.read<String>('form_version')),
        'instrumentChecksumSha256': _safeLabel(
          row.read<String>('instrument_checksum_sha256'),
        ),
        'formChecksumSha256': _safeLabel(
          row.read<String>('form_checksum_sha256'),
        ),
        'appVersion': _safeLabel(row.read<String>('app_version')),
        'buildId': _safeLabel(row.read<String>('build_id')),
        'databaseSchemaVersion': row.read<int>('database_schema_version'),
        'contentRevision': _safeLabel(row.read<String>('content_revision')),
        'evidencePolicyVersion': _safeLabel(
          row.read<String>('evidence_policy_version'),
        ),
        'featureContractRevision': _safeLabel(
          row.read<String>('feature_contract_revision'),
        ),
        'featureContractHash': _safeLabel(
          row.read<String>('feature_contract_hash'),
        ),
        'startedAtUtc': _iso(row.read<int>('started_at_utc_ms')),
        'completedAtUtc': _nullableIso(
          row.readNullable<int>('completed_at_utc_ms'),
        ),
        'abandonedAtUtc': _nullableIso(
          row.readNullable<int>('abandoned_at_utc_ms'),
        ),
        'controlledResponses': await _controlledAssessmentResponses(
          ownerId: ownerId,
          run: row,
        ),
      });
    }
    return records;
  }

  Future<List<Map<String, Object?>>> _savedLearningItems(String ownerId) async {
    final rows = await DriftExportReader(
      database,
    ).loadSavedLearningItems(ownerId);
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'contentType': _safeLabel(row.contentType),
          'contentId': _safeLabel(row.contentId),
          'contentRevision': row.contentRevision,
          'savedAtUtc': row.savedAtUtc.toIso8601String(),
          'updatedAtUtc': row.updatedAtUtc.toIso8601String(),
          'isSaved': row.isSaved,
        },
    ];
  }

  Future<List<Map<String, Object?>>> _contentQualityReports(
    String ownerId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT content_type, content_id, content_revision, reason_code, '
          'comment, submitted_at_utc_ms FROM content_quality_reports '
          'WHERE owner_id = ? ORDER BY submitted_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.contentQualityReports},
        )
        .get();
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'contentType': _safeLabel(row.read<String>('content_type')),
          'contentId': _safeLabel(row.read<String>('content_id')),
          'contentRevision': row.read<int>('content_revision'),
          'reasonCode': _safeLabel(row.read<String>('reason_code')),
          'comment': switch (row.readNullable<String>('comment')) {
            final value? => redactContentReportSecrets(value),
            null => null,
          },
          'submittedAtUtc': _iso(row.read<int>('submitted_at_utc_ms')),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _controlledAssessmentResponses({
    required String ownerId,
    required QueryRow run,
  }) async {
    final attempts = await database
        .customSelect(
          'SELECT id, is_correct, response_time_ms, occurred_at_utc_ms, '
          'evidence_class, evidence_context_json FROM answer_attempts '
          'WHERE owner_id = ? AND session_id = ? '
          "AND evidence_class = 'assessment' "
          'ORDER BY occurred_at_utc_ms, id',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(run.read<String>('learning_session_id')),
          ],
          readsFrom: {database.answerAttempts},
        )
        .get();
    final records = <Map<String, Object?>>[];
    for (final attempt in attempts) {
      final persistedClass = attempt.read<String>('evidence_class');
      final encodedContext = attempt.read<String>('evidence_context_json');
      if (!LearningEvidenceContract.validEvidenceMetadata(
        evidenceClass: persistedClass,
        evidenceContextJson: encodedContext,
      )) {
        throw StateError('Assessment response has invalid evidence metadata.');
      }
      final context = EvidenceContext.fromJson(
        (jsonDecode(encodedContext) as Map).cast<String, Object?>(),
      );
      final occurredAtUtcMs = attempt.read<int>('occurred_at_utc_ms');
      final terminalAtUtcMs =
          run.readNullable<int>('completed_at_utc_ms') ??
          run.readNullable<int>('abandoned_at_utc_ms');
      final responseTimeMs = attempt.readNullable<int>('response_time_ms');
      if (context.evidenceClass != EvidenceClass.assessment ||
          context.assignmentId != run.read<String>('assignment_id') ||
          context.experimentId != run.read<String>('experiment_id') ||
          context.experimentVersion != run.read<int>('experiment_version') ||
          context.cohort != run.read<String>('cohort') ||
          context.researchConsentVersion != run.read<int>('consent_version') ||
          context.protocolId != run.read<String>('protocol_id') ||
          context.protocolVersion != run.read<String>('protocol_version') ||
          context.instrumentId != run.read<String>('instrument_id') ||
          context.instrumentVersion != run.read<String>('instrument_version') ||
          context.formId != run.read<String>('form_id') ||
          context.formVersion != run.read<String>('form_version') ||
          context.contentRevision != run.read<String>('content_revision') ||
          context.policyVersion !=
              run.read<String>('evidence_policy_version') ||
          context.featureContractRevision !=
              run.read<String>('feature_contract_revision') ||
          context.featureContractHash !=
              run.read<String>('feature_contract_hash') ||
          context.engagementAllowed ||
          context.assessmentItemId == null ||
          context.assessmentResponseCode == null ||
          context.scoringRuleVersion == null ||
          responseTimeMs == null ||
          responseTimeMs < 0 ||
          occurredAtUtcMs < run.read<int>('started_at_utc_ms') ||
          (terminalAtUtcMs != null && occurredAtUtcMs > terminalAtUtcMs)) {
        throw StateError('Assessment response does not match its run.');
      }
      records.add({
        'sourceEvidenceId': attempt.read<String>('id'),
        'itemId': context.assessmentItemId,
        'responseCode': context.assessmentResponseCode,
        'isCorrect': attempt.read<bool>('is_correct'),
        'responseTimeMs': responseTimeMs,
        'occurredAtUtc': _iso(occurredAtUtcMs),
        'scoringRuleVersion': context.scoringRuleVersion,
      });
    }
    return records;
  }

  Future<List<Map<String, Object?>>> _vocabularyCategories(
    String ownerId,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT name, sort_order FROM vocabulary_categories '
          'WHERE owner_id = ? AND is_deleted = 0 '
          'ORDER BY sort_order, name, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.vocabularyCategories},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'name': row.read<String>('name'),
          'sortOrder': row.read<int>('sort_order'),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _vocabularyWords(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT spelling, meaning, part_of_speech, cefr_level, source, '
          'content_revision, content_checksum_sha256, content_provenance, '
          'content_review_state, content_publication_state '
          'FROM vocabulary_words WHERE owner_id = ? AND is_deleted = 0 '
          'ORDER BY spelling, meaning, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.vocabularyWords},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'spelling': row.read<String>('spelling'),
          'meaning': row.read<String>('meaning'),
          'partOfSpeech': row.read<String>('part_of_speech'),
          'cefrLevel': row.readNullable<String>('cefr_level'),
          'source': _vocabularySource(row.read<String>('source')),
          'contentRevision': row.read<int>('content_revision'),
          'contentChecksumSha256': row.readNullable<String>(
            'content_checksum_sha256',
          ),
          'contentProvenance': _safeLabel(
            row.read<String>('content_provenance'),
          ),
          'contentReviewState': _safeLabel(
            row.read<String>('content_review_state'),
          ),
          'contentPublicationState': _safeLabel(
            row.read<String>('content_publication_state'),
          ),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _vocabularyImports(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT source_type, status, accepted_count, duplicate_count, '
          'rejected_count FROM vocabulary_imports WHERE owner_id = ? '
          'ORDER BY created_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.vocabularyImports},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'sourceType': _safeLabel(row.read<String>('source_type')),
          'status': _safeLabel(row.read<String>('status')),
          'acceptedCount': row.read<int>('accepted_count'),
          'duplicateCount': row.read<int>('duplicate_count'),
          'rejectedCount': row.read<int>('rejected_count'),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _learningSessions(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT activity_type, state, started_at_utc_ms, ended_at_utc_ms, '
          'correct_count, wrong_count, score, '
          'session_configuration_identity, session_configuration_json, '
          'configuration_active_effort_us FROM learning_sessions '
          'WHERE owner_id = ? ORDER BY started_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.learningSessions},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'activityType': _safeLabel(row.read<String>('activity_type')),
          'state': _safeLabel(row.read<String>('state')),
          'startedAtUtc': _iso(row.read<int>('started_at_utc_ms')),
          'endedAtUtc': _nullableIso(row.readNullable<int>('ended_at_utc_ms')),
          'correctCount': row.read<int>('correct_count'),
          'wrongCount': row.read<int>('wrong_count'),
          'score': row.readNullable<int>('score'),
          'sessionConfigurationIdentity': _nullableSafeLabel(
            row.readNullable<String>('session_configuration_identity'),
          ),
          'sessionConfiguration': _sessionConfigurationExport(
            identity: row.readNullable<String>(
              'session_configuration_identity',
            ),
            serialization: row.readNullable<String>(
              'session_configuration_json',
            ),
          ),
          'configurationActiveEffortUs': row.read<int>(
            'configuration_active_effort_us',
          ),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _sessionConfigurations(
    String ownerId,
  ) async {
    final rows =
        await (database.select(database.sessionConfigurations)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.mode)]))
            .get();
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'mode': _safeLabel(row.mode),
          'contentIdentity': _safeLabel(row.contentIdentity),
          'sessionConfiguration': _sessionConfigurationExport(
            identity: row.contentIdentity,
            serialization: row.stableSerialization,
          ),
          'updatedAtUtc': _iso(row.updatedAtUtcMs),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _learningTimeSegments(
    String ownerId,
  ) async {
    final rows = await DriftExportReader(
      database,
    ).loadLearningTimeSegments(ownerId);
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'sessionId': _safeLabel(row.sessionId),
          'activeStartOffsetMs': row.activeStartOffsetMs,
          'activeDurationMs': row.activeDurationMs,
          'startedAtUtc': row.startedAtUtc.toIso8601String(),
          'endedAtUtc': row.endedAtUtc.toIso8601String(),
          'timezoneId': _safeTimezoneId(
            row.timezoneId,
            utcOffsetMinutes: row.timezoneOffsetMinutes,
            occurredAtUtcMs: row.startedAtUtc.millisecondsSinceEpoch,
          ),
          'timezoneOffsetMinutes': row.timezoneOffsetMinutes,
          'captureSource': _safeLabel(row.captureSource),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _learningGoals(String ownerId) async {
    final rows = await DriftExportReader(database).loadLearningGoals(ownerId);
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'kind': _safeLabel(row.kind),
          'title': _safePersonalText(row.title, maximumLength: 120),
          'deadlineAtUtc': row.deadlineAtUtc.toIso8601String(),
          'timezoneId': _safeTimezoneId(
            row.timezoneId,
            utcOffsetMinutes: row.timezoneOffsetMinutes,
            occurredAtUtcMs: row.deadlineAtUtc.millisecondsSinceEpoch,
          ),
          'timezoneOffsetMinutes': row.timezoneOffsetMinutes,
          'status': _safeLabel(row.status),
          'createdAtUtc': row.createdAtUtc.toIso8601String(),
          'updatedAtUtc': row.updatedAtUtc.toIso8601String(),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _learnerPreferences(String ownerId) async {
    final rows = await DriftExportReader(
      database,
    ).loadLearnerPreferences(ownerId);
    return <Map<String, Object?>>[
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'preferenceVersion': row.preferenceVersion,
          'goal': _safeLabel(row.goal),
          'availableMinutesPerDay': row.availableMinutesPerDay,
          'activityPreference': _safeLabel(row.activityPreference),
          'updatedAtUtc': row.updatedAtUtc.toIso8601String(),
          'themeMode': _safeLabel(row.themeMode),
          'motionMode': _safeLabel(row.motionMode),
          'displayUpdatedAtUtc': row.displayUpdatedAtUtc.toIso8601String(),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _answerAttempts(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT prompt_mode, is_correct, response_time_ms, attempt_number, '
          'occurred_at_utc_ms, evidence_class, evidence_context_json '
          'FROM answer_attempts WHERE owner_id = ? '
          'ORDER BY occurred_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.answerAttempts},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'promptMode': _safeLabel(row.read<String>('prompt_mode')),
          'isCorrect': row.read<bool>('is_correct'),
          'responseTimeMs': row.readNullable<int>('response_time_ms'),
          'attemptNumber': row.read<int>('attempt_number'),
          'occurredAtUtc': _iso(row.read<int>('occurred_at_utc_ms')),
          'evidenceClass': row.read<String>('evidence_class'),
          'evidenceContext': _validatedEvidenceContext(
            evidenceClass: row.read<String>('evidence_class'),
            evidenceContextJson: row.read<String>('evidence_context_json'),
          ),
        },
    ];
  }

  Map<String, Object?> _validatedEvidenceContext({
    required String evidenceClass,
    required String evidenceContextJson,
  }) {
    if (!LearningEvidenceContract.validEvidenceMetadata(
      evidenceClass: evidenceClass,
      evidenceContextJson: evidenceContextJson,
    )) {
      throw StateError('Answer attempt has invalid evidence metadata.');
    }
    return EvidenceContext.fromJson(
      (jsonDecode(evidenceContextJson) as Map).cast<String, Object?>(),
    ).toJson();
  }

  Future<List<Map<String, Object?>>> _srsStates(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT stability, difficulty, interval_days, repetitions, lapses, '
          'last_review_at_utc_ms, due_at_utc_ms, algorithm_version '
          'FROM srs_states WHERE owner_id = ? ORDER BY due_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.srsStates},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'stability': row.read<double>('stability'),
          'difficulty': row.read<double>('difficulty'),
          'intervalDays': row.read<int>('interval_days'),
          'repetitions': row.read<int>('repetitions'),
          'lapses': row.read<int>('lapses'),
          'lastReviewAtUtc': _nullableIso(
            row.readNullable<int>('last_review_at_utc_ms'),
          ),
          'dueAtUtc': _iso(row.read<int>('due_at_utc_ms')),
          'algorithmVersion': row.read<int>('algorithm_version'),
        },
    ];
  }

  Future<Map<String, String>> _documentAliases(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT document_id FROM reading_progress_entries '
          'WHERE owner_id = ? UNION SELECT document_id FROM reading_events '
          'WHERE owner_id = ? ORDER BY document_id',
          variables: [Variable<String>(ownerId), Variable<String>(ownerId)],
          readsFrom: {database.readingProgressEntries, database.readingEvents},
        )
        .get();
    return {
      for (var index = 0; index < rows.length; index += 1)
        rows[index].read<String>('document_id'): 'document-${index + 1}',
    };
  }

  Future<List<Map<String, Object?>>> _readingProgress(
    String ownerId,
    Map<String, String> aliases,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT document_id, document_revision, last_position, '
          'is_completed, updated_at_utc_ms FROM reading_progress_entries '
          'WHERE owner_id = ? ORDER BY updated_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.readingProgressEntries},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'documentAlias': aliases[row.read<String>('document_id')],
          'documentRevision': row.read<int>('document_revision'),
          'lastPosition': row.read<int>('last_position'),
          'isCompleted': row.read<bool>('is_completed'),
          'updatedAtUtc': _iso(row.read<int>('updated_at_utc_ms')),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _readingEvents(
    String ownerId,
    Map<String, String> aliases,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT document_id, document_revision, event_type, position, '
          'occurred_at_utc_ms FROM reading_events WHERE owner_id = ? '
          'ORDER BY occurred_at_utc_ms, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.readingEvents},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'documentAlias': aliases[row.read<String>('document_id')],
          'documentRevision': row.read<int>('document_revision'),
          'eventType': _safeLabel(row.read<String>('event_type')),
          'position': row.read<int>('position'),
          'occurredAtUtc': _iso(row.read<int>('occurred_at_utc_ms')),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _streakState(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT current_streak_days, longest_streak_days, freeze_count, '
          'last_learned_at_utc_ms FROM streak_states WHERE owner_id = ? '
          'LIMIT 1',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.streakStates},
        )
        .getSingleOrNull();
    if (row == null) {
      return const [
        {'recordCount': 0},
      ];
    }
    return [
      {'recordCount': 1},
      {
        'currentStreakDays': row.read<int>('current_streak_days'),
        'longestStreakDays': row.read<int>('longest_streak_days'),
        'freezeCount': row.read<int>('freeze_count'),
        'lastLearnedAtUtc': _nullableIso(
          row.readNullable<int>('last_learned_at_utc_ms'),
        ),
      },
    ];
  }

  Future<List<Map<String, Object?>>> _learningDays(String ownerId) async {
    final rows = await database
        .customSelect(
          'SELECT learning_day, first_session_at_utc_ms '
          'FROM learning_day_log WHERE owner_id = ? ORDER BY learning_day, id',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.learningDayLog},
        )
        .get();
    return [
      {'recordCount': rows.length},
      for (final row in rows)
        {
          'learningDay': _safeLabel(row.read<String>('learning_day')),
          'firstSessionAtUtc': _iso(row.read<int>('first_session_at_utc_ms')),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _aiUsage(String ownerId) async {
    final rows = await database
        .customSelect(
          '''
          SELECT provider_id, model,
                 COUNT(*) AS request_count,
                 SUM(CASE WHEN outcome = 'success' THEN 1 ELSE 0 END)
                   AS success_count,
                 SUM(CASE WHEN outcome = 'failure' THEN 1 ELSE 0 END)
                   AS failure_count,
                 SUM(CASE WHEN outcome = 'indeterminate' THEN 1 ELSE 0 END)
                   AS indeterminate_count,
                 SUM(COALESCE(total_tokens, 0))
                   AS total_tokens,
                 SUM(latency_ms) AS total_latency_ms,
                 CASE
                   WHEN COUNT(provider_reported_cost_micros_usd) = COUNT(*)
                   THEN SUM(provider_reported_cost_micros_usd)
                   ELSE NULL
                 END AS provider_cost
          FROM ai_usage_events
          WHERE owner_id = ? AND outcome <> 'pending'
          GROUP BY provider_id, model
          ORDER BY provider_id, model
          ''',
          variables: [Variable<String>(ownerId)],
          readsFrom: {database.aiUsageEvents},
        )
        .get();
    return [
      for (final row in rows)
        {
          'recordCount': row.read<int>('request_count'),
          'providerId': _providerId(row.read<String>('provider_id')),
          'model': _safeLabel(row.read<String>('model')),
          'requestCount': row.read<int>('request_count'),
          'successCount': row.read<int>('success_count'),
          'failureCount': row.read<int>('failure_count'),
          'indeterminateCount': row.read<int>('indeterminate_count'),
          'totalTokens': row.read<int>('total_tokens'),
          'totalLatencyMs': row.read<int>('total_latency_ms'),
          'providerReportedCostMicrosUsd': row.readNullable<int>(
            'provider_cost',
          ),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _runtimeDiagnostics(
    DateTime nowUtc,
  ) async {
    final records = <Map<String, Object?>>[];
    final featurePrefix = _runtimeNamespace('featureOverrides').keyPattern;
    final featureUpperBound = RuntimeFlagNamespaces.prefixUpperBound(
      featurePrefix,
    );
    final featureRows = await database
        .customSelect(
          'SELECT "key", bool_value, expires_at_utc_ms FROM runtime_flags '
          'WHERE "key" >= ? AND "key" < ? ORDER BY "key"',
          variables: [
            Variable<String>(featurePrefix),
            Variable<String>(featureUpperBound),
          ],
          readsFrom: {database.runtimeFlags},
        )
        .get();
    const defaults = BuildFeatureRegistry.fieldDefaults();
    for (final row in featureRows) {
      final name = row.read<String>('key').substring(featurePrefix.length);
      final feature = Feature.values
          .where((value) => value.name == name)
          .firstOrNull;
      if (feature == null) continue;
      final expiry = row.readNullable<int>('expires_at_utc_ms');
      final active =
          row.read<bool>('bool_value') &&
          (expiry == null || nowUtc.millisecondsSinceEpoch < expiry);
      final record = <String, Object?>{
        'feature': feature.name,
        'effectiveState': active
            ? FeatureState.emergencyOff.name
            : defaults.stateOf(feature).name,
        'active': active,
      };
      validateRuntimeFlagDiagnosticFields(
        namespaceName: 'featureOverrides',
        record: record,
      );
      records.add(record);
    }
    final downloadPrefix = _runtimeNamespace('downloadCounters').keyPattern;
    final downloadUpperBound = RuntimeFlagNamespaces.prefixUpperBound(
      downloadPrefix,
    );
    final downloadRows = await database
        .customSelect(
          'SELECT "key" FROM runtime_flags WHERE "key" >= ? AND "key" < ? '
          'AND source = ? ORDER BY "key"',
          variables: [
            Variable<String>(downloadPrefix),
            Variable<String>(downloadUpperBound),
            const Variable<String>(RuntimeFlagNamespaces.downloadCounterSource),
          ],
          readsFrom: {database.runtimeFlags},
        )
        .get();
    final counts = <String, int>{};
    for (final row in downloadRows) {
      final parts = row.read<String>('key').split(':');
      if (parts.length < 3) continue;
      final version = _decodeVersion(parts[1]);
      if (version == null) continue;
      counts[version] = (counts[version] ?? 0) + 1;
    }
    for (final version in counts.keys.toList()..sort()) {
      final record = <String, Object?>{
        'modelVersion': version,
        'successfulDownloadCount': counts[version],
        'retentionLimit': DownloadCounter.defaultMaxRetainedEventsPerVersion,
        'countMayBeSaturated':
            counts[version]! >=
            DownloadCounter.defaultMaxRetainedEventsPerVersion,
        'countSemantics': DownloadCountSnapshot.boundedWindowSemantics,
      };
      validateRuntimeFlagDiagnosticFields(
        namespaceName: 'downloadCounters',
        record: record,
      );
      records.add(record);
    }
    final versionWindow = <String, Object?>{
      'trackedVersionLimit': DownloadCounter.defaultMaxTrackedVersions,
      'versionWindowMayHaveEvicted':
          counts.length >= DownloadCounter.defaultMaxTrackedVersions,
      'versionWindowSemantics': 'boundedTrackedVersionWindow',
    };
    validateRuntimeFlagDiagnosticFields(
      namespaceName: 'downloadCounters',
      record: versionWindow,
    );
    records.add(versionWindow);
    return records;
  }

  Future<List<Map<String, Object?>>> _modelDownloads() async {
    final rows = await database
        .customSelect(
          'SELECT model_version, state, expected_bytes, downloaded_bytes, '
          'retry_count FROM model_downloads ORDER BY model_version',
          readsFrom: {database.modelDownloads},
        )
        .get();
    return [
      for (final row in rows)
        {
          'modelVersion': _safeLabel(row.read<String>('model_version')),
          'state': _modelState(row.read<String>('state')),
          'expectedBytes': row.read<int>('expected_bytes'),
          'downloadedBytes': row.read<int>('downloaded_bytes'),
          'retryCount': row.read<int>('retry_count'),
        },
    ];
  }

  Future<List<Map<String, Object?>>> _countRecord(
    OwnerLifecycleTableDescriptor descriptor,
    String ownerId,
  ) async {
    if (!descriptor.allowedExportFields.contains('recordCount')) {
      return const [];
    }
    final count = switch (descriptor.authority) {
      OwnerLifecycleAuthority.root => 0,
      OwnerLifecycleAuthority.directOwner => await _directCount(
        descriptor.tableName,
        ownerId,
      ),
      OwnerLifecycleAuthority.transitiveOwner => await _transitiveCount(
        descriptor.tableName,
        ownerId,
      ),
      OwnerLifecycleAuthority.global ||
      OwnerLifecycleAuthority.packagedContent ||
      OwnerLifecycleAuthority.deviceLocal => 0,
    };
    return [
      {'recordCount': count},
    ];
  }

  Future<int> _directCount(String tableName, String ownerId) => database
      .customSelect(
        'SELECT COUNT(*) AS count FROM "$tableName" WHERE owner_id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .map((row) => row.read<int>('count'))
      .getSingle();

  Future<int> _transitiveCount(String tableName, String ownerId) {
    final sql = switch (tableName) {
      'vocabulary_import_rows' =>
        'SELECT COUNT(*) AS count FROM vocabulary_import_rows WHERE '
            'import_id IN (SELECT id FROM vocabulary_imports '
            'WHERE owner_id = ?)',
      'quest_objective_progress' =>
        'SELECT COUNT(*) AS count FROM quest_objective_progress WHERE '
            'instance_id IN (SELECT instance_id FROM quest_instances '
            'WHERE owner_id = ?)',
      _ => throw StateError('Unknown transitive lifecycle table: $tableName'),
    };
    return database
        .customSelect(sql, variables: [Variable<String>(ownerId)])
        .map((row) => row.read<int>('count'))
        .getSingle();
  }

  String _manifestSha256() {
    return ownerLifecycleManifestSha256();
  }
}

String ownerLifecycleManifestSha256({
  List<OwnerLifecycleTableDescriptor> tables = ownerLifecycleManifest,
  List<RuntimeFlagLifecycleNamespaceDescriptor> runtimeFlagNamespaces =
      runtimeFlagLifecycleNamespaces,
}) {
  final payload = {
    'tables': [
      for (final entry in tables)
        {
          'tableName': entry.tableName,
          'alias': entry.alias,
          'authority': entry.authority.name,
          'exportDisposition': entry.exportDisposition.name,
          'deletionDisposition': entry.deletionDisposition.name,
          'allowedExportFields': entry.allowedExportFields,
        },
    ],
    'runtimeFlagNamespaces': [
      for (final entry in runtimeFlagNamespaces)
        {
          'name': entry.name,
          'match': entry.match.name,
          'keyPattern': entry.keyPattern,
          'exportDisposition': entry.exportDisposition.name,
          'deletionDisposition': entry.deletionDisposition.name,
          'allowedDiagnosticFields': entry.allowedDiagnosticFields.toList()
            ..sort(),
        },
    ],
  };
  return crypto.sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}

RuntimeFlagLifecycleNamespaceDescriptor _runtimeNamespace(String name) =>
    runtimeFlagLifecycleNamespaces.singleWhere((entry) => entry.name == name);

void validateRuntimeFlagDiagnosticFields({
  required String namespaceName,
  required Map<String, Object?> record,
}) {
  final namespace = _runtimeNamespace(namespaceName);
  final forbidden = record.keys.where(
    (field) => !namespace.allowedDiagnosticFields.contains(field),
  );
  if (forbidden.isNotEmpty) {
    throw StateError(
      'Runtime diagnostic field is not allowlisted for $namespaceName: '
      '${forbidden.first}',
    );
  }
}

String _iso(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
  milliseconds,
  isUtc: true,
).toIso8601String();

String? _nullableIso(int? milliseconds) =>
    milliseconds == null ? null : _iso(milliseconds);

String _accountState(String value) => switch (value) {
  'localGuest' || 'firebaseBound' => value,
  _ when value.startsWith('mergedInto:') => 'merged',
  _ => 'unknown',
};

String _consentState(String value) => switch (value) {
  'accepted' || 'declined' || 'withdrawn' => value,
  _ => 'unknown',
};

String _assessmentPhase(String value) => switch (value) {
  'pre' || 'post' => value,
  _ => 'unknown',
};

String _assessmentState(String value) => switch (value) {
  'active' || 'completed' || 'abandoned' => value,
  _ => 'unknown',
};

String _vocabularySource(String value) => switch (value) {
  'manual' || 'import' || 'global' => value,
  _ => 'other',
};

String _providerId(String value) {
  final provider = AiProviderId.values
      .where((item) => item.name == value)
      .firstOrNull;
  return provider?.name ?? 'other';
}

String _safeLabel(String value) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 200) return 'redacted';
  if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(canonical)) return 'redacted';
  return canonical;
}

String? _nullableSafeLabel(String? value) =>
    value == null ? null : _safeLabel(value);

Map<String, Object?>? _sessionConfigurationExport({
  required String? identity,
  required String? serialization,
}) {
  if (identity == null && serialization == null) return null;
  if (identity == null || serialization == null) {
    throw StateError('incomplete durable session configuration binding');
  }
  try {
    final configuration = SessionConfiguration.fromStableSerialization(
      serialization,
    );
    if (configuration.contentIdentity != identity) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    final pack = configuration.packIdentity;
    return <String, Object?>{
      'schemaVersion': configuration.schemaVersion,
      'policyVersion': _configurationIdentifier(
        configuration.policyVersion,
        'policyVersion',
      ),
      'mode': configuration.mode.name,
      'itemCount': configuration.itemCount,
      'direction': configuration.direction.name,
      'difficulty': configuration.difficulty.name,
      'hintBudget': configuration.hintBudget,
      'timing': configuration.timing.toJson(),
      'packIdentity': pack == null
          ? null
          : <String, Object?>{
              'type': pack.type.name,
              'id': _configurationIdentifier(pack.id, 'packIdentity.id'),
              'revision': pack.revision,
            },
      'protocolId': _configurationIdentifier(
        configuration.protocolId,
        'protocolId',
      ),
      'protocolVersion': _configurationIdentifier(
        configuration.protocolVersion,
        'protocolVersion',
      ),
      'protocolLimitsIdentity': _configurationIdentifier(
        configuration.protocolLimitsIdentity,
        'protocolLimitsIdentity',
      ),
    };
  } on SessionConfigurationResetRequired catch (error) {
    throw StateError('invalid durable session configuration: $error');
  }
}

String _configurationIdentifier(String value, String field) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
    throw StateError('invalid durable session configuration $field');
  }
  return value;
}

String _safePersonalText(String value, {required int maximumLength}) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > maximumLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    return 'redacted';
  }
  return value;
}

String _safeTimezoneId(
  String value, {
  required int utcOffsetMinutes,
  required int occurredAtUtcMs,
}) {
  try {
    LearningTimeSegment.requireCanonicalTimezoneContext(
      timezoneId: value,
      utcOffsetMinutes: utcOffsetMinutes,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    return value;
  } on Object {
    return 'redacted';
  }
}

String _modelState(String value) =>
    ModelDownloadState.values
        .where((state) => state.name == value)
        .firstOrNull
        ?.name ??
    'degraded';

String? _decodeVersion(String encoded) {
  try {
    final padding = '=' * ((4 - encoded.length % 4) % 4);
    final value = utf8.decode(base64Url.decode('$encoded$padding')).trim();
    if (value.isEmpty) return null;
    return _safeLabel(value);
  } on Object {
    return null;
  }
}
