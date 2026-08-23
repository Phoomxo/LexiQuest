import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_credential_version_index.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/runtime/download_counter.dart';

void main() {
  test(
    'current schema lifecycle manifest, export, and deletion cover v14 assignments exactly once',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customSelect('SELECT 1').getSingle();

      const exactCurrentSchemaTables = <String>{
        'local_owners',
        'research_consents',
        'experiment_assignments',
        'vocabulary_categories',
        'vocabulary_words',
        'vocabulary_imports',
        'vocabulary_import_rows',
        'learning_sessions',
        'answer_attempts',
        'srs_states',
        'reading_progress_entries',
        'reading_events',
        'points_ledger_entries',
        'achievement_unlocks',
        'reward_transactions',
        'owned_reward_items',
        'equipped_reward_items',
        'outbox_operations',
        'sync_checkpoints',
        'sync_conflicts',
        'runtime_flags',
        'model_downloads',
        'events_v2',
        'quest_definitions',
        'quest_instances',
        'quest_objective_progress',
        'streak_states',
        'learning_day_log',
        'association_records',
        'associative_memory_states',
        'ai_usage_events',
        'speech_evidence',
      };
      final liveTables = database.allTables
          .map((table) => table.actualTableName)
          .toSet();
      final manifestTables = ownerLifecycleManifest
          .map((entry) => entry.tableName)
          .toSet();

      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(liveTables, exactCurrentSchemaTables);
      expect(manifestTables, exactCurrentSchemaTables);
      expect(ownerLifecycleExportTableNames, exactCurrentSchemaTables);
      expect(ownerLifecycleDeletionTableNames, exactCurrentSchemaTables);
      expect(
        ownerLifecycleManifest.map((entry) => entry.alias).toSet(),
        hasLength(32),
      );
      expect(
        ownerLifecycleManifest.where(
          (entry) => entry.authority == OwnerLifecycleAuthority.root,
        ),
        hasLength(1),
      );
      expect(
        ownerLifecycleManifest.where(
          (entry) => entry.authority == OwnerLifecycleAuthority.directOwner,
        ),
        hasLength(26),
      );
      expect(ownerLifecycleDirectOwnerTableNames, ownerUpgradeInventory);
      expect(
        ownerLifecycleManifest.where(
          (entry) => entry.authority == OwnerLifecycleAuthority.transitiveOwner,
        ),
        hasLength(2),
      );
      expect(
        ownerLifecycleManifest.where(
          (entry) => entry.authority == OwnerLifecycleAuthority.global,
        ),
        hasLength(3),
      );

      final pragmaDirectOwnerTables = <String>{};
      for (final table in liveTables) {
        final columns = await database
            .customSelect('PRAGMA table_info("$table")')
            .get();
        if (columns.any((row) => row.read<String>('name') == 'owner_id')) {
          pragmaDirectOwnerTables.add(table);
        }
      }
      expect(pragmaDirectOwnerTables, ownerLifecycleDirectOwnerTableNames);

      expect(
        ownerLifecyclePhysicalDeletionOrder.indexOf('speech_evidence'),
        lessThan(
          ownerLifecyclePhysicalDeletionOrder.indexOf('learning_sessions'),
        ),
      );
      expect(
        ownerLifecyclePhysicalDeletionOrder.indexOf('vocabulary_import_rows'),
        lessThan(
          ownerLifecyclePhysicalDeletionOrder.indexOf('vocabulary_imports'),
        ),
      );
      expect(
        ownerLifecyclePhysicalDeletionOrder.indexOf('quest_objective_progress'),
        lessThan(
          ownerLifecyclePhysicalDeletionOrder.indexOf('quest_instances'),
        ),
      );
      expect(
        ownerLifecyclePhysicalDeletionOrder.indexOf('experiment_assignments'),
        lessThan(ownerLifecyclePhysicalDeletionOrder.indexOf('local_owners')),
      );
      expect(ownerLifecyclePhysicalDeletionOrder.last, 'local_owners');
      final experimentAssignments = ownerLifecycleManifest
          .where((entry) => entry.tableName == 'experiment_assignments')
          .toList(growable: false);
      expect(experimentAssignments, hasLength(1));
      expect(
        experimentAssignments.single.authority,
        OwnerLifecycleAuthority.directOwner,
      );
      expect(
        experimentAssignments.single.deletionDisposition,
        OwnerLifecycleDeletionDisposition.deleteDirect,
      );
      expect(experimentAssignments.single.allowedExportFields.toSet(), {
        'recordCount',
        'experimentId',
        'experimentVersion',
        'cohort',
        'protocolVersion',
        'assignedAtUtc',
      });
      final vocabularyImports = ownerLifecycleManifest.singleWhere(
        (entry) => entry.tableName == 'vocabulary_imports',
      );
      expect(
        vocabularyImports.allowedExportFields,
        isNot(contains('sourceName')),
        reason: 'an import source name may be an absolute local path',
      );
      expect(
        vocabularyImports.allowedExportFields.any(
          (field) => field.toLowerCase().contains('path'),
        ),
        isFalse,
      );
      final targetDeletedTables = ownerLifecycleManifest
          .where(
            (entry) =>
                entry.deletionDisposition !=
                OwnerLifecycleDeletionDisposition.preserveGlobal,
          )
          .map((entry) => entry.tableName)
          .toSet();
      expect(ownerLifecyclePhysicalDeletionOrder.toSet(), targetDeletedTables);
      expect(
        ownerLifecyclePhysicalDeletionOrder,
        hasLength(targetDeletedTables.length),
        reason: 'every target-delete action must occur exactly once',
      );

      expect(
        runtimeFlagLifecycleNamespaces.map((entry) => entry.name).toSet(),
        const {
          'ownerOperationGate',
          'cloudSyncEnabled',
          'featureOverrides',
          'downloadCounters',
          'aiCredentialPointers',
          'aiCredentialIntents',
          'unknown',
        },
      );
      final credentialNamespaces = runtimeFlagLifecycleNamespaces.where(
        (entry) => entry.name.startsWith('aiCredential'),
      );
      expect(
        credentialNamespaces.every(
          (entry) =>
              entry.exportDisposition ==
                  RuntimeFlagExportDisposition.omitSensitive &&
              entry.deletionDisposition ==
                  RuntimeFlagDeletionDisposition.deleteTargetOwner,
        ),
        isTrue,
      );
      final featureNamespace = runtimeFlagLifecycleNamespaces.singleWhere(
        (entry) => entry.name == 'featureOverrides',
      );
      expect(featureNamespace.allowedDiagnosticFields, {
        'feature',
        'effectiveState',
        'active',
      });
      final downloadNamespace = runtimeFlagLifecycleNamespaces.singleWhere(
        (entry) => entry.name == 'downloadCounters',
      );
      expect(downloadNamespace.allowedDiagnosticFields, {
        'modelVersion',
        'successfulDownloadCount',
        'retentionLimit',
        'countMayBeSaturated',
        'countSemantics',
        'trackedVersionLimit',
        'versionWindowMayHaveEvicted',
        'versionWindowSemantics',
      });
      expect(
        () => validateRuntimeFlagDiagnosticFields(
          namespaceName: 'featureOverrides',
          record: const {'feature': 'aiTutor', 'successfulDownloadCount': 1},
        ),
        throwsStateError,
      );
      final changedDownloadNamespace = RuntimeFlagLifecycleNamespaceDescriptor(
        name: downloadNamespace.name,
        match: downloadNamespace.match,
        keyPattern: '${downloadNamespace.keyPattern}changed:',
        exportDisposition: downloadNamespace.exportDisposition,
        deletionDisposition: downloadNamespace.deletionDisposition,
        allowedDiagnosticFields: downloadNamespace.allowedDiagnosticFields,
      );
      expect(
        ownerLifecycleManifestSha256(
          runtimeFlagNamespaces: [
            for (final namespace in runtimeFlagLifecycleNamespaces)
              if (namespace.name == downloadNamespace.name)
                changedDownloadNamespace
              else
                namespace,
          ],
        ),
        isNot(ownerLifecycleManifestSha256()),
      );
    },
  );

  test(
    'archive preserves every typed model state and degrades unknown',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, account_state, created_at_utc_ms, is_active) '
        "VALUES ('owner-a', 'localGuest', 1, 1)",
      );
      final exporter = OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => DateTime.utc(2026, 8, 11, 12),
      );
      for (final state in [
        ...ModelDownloadState.values.map((value) => value.name),
        'unknown',
      ]) {
        await database.customInsert(
          'INSERT OR REPLACE INTO model_downloads '
          '(id, model_version, source_url, expected_checksum, expected_bytes, '
          'state, updated_at_utc_ms) VALUES '
          "('model', 'model-v1', 'https://example.invalid/model', "
          "'checksum', 1, ?, 1)",
          variables: [Variable<String>(state)],
        );
        final artifact = await exporter.prepareActive();
        final envelope =
            jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
        final tables =
            (envelope['content'] as Map<String, dynamic>)['tables']
                as List<dynamic>;
        final record =
            (tables.cast<Map<String, dynamic>>().singleWhere(
                          (entry) => entry['alias'] == 'globalModelDownloads',
                        )['records']
                        as List<dynamic>)
                    .single
                as Map<String, dynamic>;
        expect(record['state'], state == 'unknown' ? 'degraded' : state);
      }
    },
  );

  test('archive never reports a partial provider cost as total cost', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customInsert(
      'INSERT INTO local_owners '
      '(id, account_state, created_at_utc_ms, is_active) '
      "VALUES ('owner-a', 'localGuest', 1, 1)",
    );
    await database.customInsert(
      'INSERT INTO ai_usage_events '
      '(event_id, owner_id, occurred_at_utc_ms, provider_id, model, '
      'request_type, outcome, latency_ms, total_tokens, '
      'provider_reported_cost_micros_usd) VALUES '
      "('known', 'owner-a', 1, 'openai', 'model-a', 'tutorReply', "
      "'success', 10, 7, 100), "
      "('unknown', 'owner-a', 2, 'openai', 'model-a', 'tutorReply', "
      "'success', 10, 7, NULL)",
    );

    final artifact = await OwnerLifecycleArchiveExporter(
      database: database,
      nowUtc: () => DateTime.utc(2026, 8, 11, 12),
    ).prepareActive();
    final envelope =
        jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
    final tables =
        (envelope['content'] as Map<String, dynamic>)['tables']
            as List<dynamic>;
    final aiRecord =
        (tables.cast<Map<String, dynamic>>().singleWhere(
                      (entry) => entry['alias'] == 'aiUsageDiagnostics',
                    )['records']
                    as List<dynamic>)
                .single
            as Map<String, dynamic>;

    expect(aiRecord['requestCount'], 2);
    expect(aiRecord['providerReportedCostMicrosUsd'], isNull);
  });

  test('archive discloses its bounded tracked-version window', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customInsert(
      'INSERT INTO local_owners '
      '(id, account_state, created_at_utc_ms, is_active) '
      "VALUES ('owner-a', 'localGuest', 1, 1)",
    );
    var event = 0;
    final counter = DownloadCounter(
      database,
      generateEventId: () => 'event-${event++}',
      nowUtc: () => DateTime.utc(2026, 8, 11, 12),
    );
    for (
      var version = 0;
      version < DownloadCounter.defaultMaxTrackedVersions + 1;
      version++
    ) {
      await counter.increment('model-$version');
    }

    final artifact = await OwnerLifecycleArchiveExporter(
      database: database,
      nowUtc: () => DateTime.utc(2026, 8, 11, 12),
    ).prepareActive();
    final envelope =
        jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
    final tables =
        (envelope['content'] as Map<String, dynamic>)['tables']
            as List<dynamic>;
    final runtimeRecords =
        (tables.cast<Map<String, dynamic>>().singleWhere(
                  (entry) => entry['alias'] == 'runtimeControlsAndMetadata',
                )['records']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
    final versionRows = runtimeRecords.where(
      (record) => record.containsKey('modelVersion'),
    );
    final window = runtimeRecords.singleWhere(
      (record) => record.containsKey('trackedVersionLimit'),
    );

    expect(versionRows, hasLength(DownloadCounter.defaultMaxTrackedVersions));
    expect(
      window['trackedVersionLimit'],
      DownloadCounter.defaultMaxTrackedVersions,
    );
    expect(window['versionWindowMayHaveEvicted'], isTrue);
    expect(window['versionWindowSemantics'], 'boundedTrackedVersionWindow');
  });

  test('archive rejects mismatched or noncanonical attempt evidence', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedCompleteOwnerA(database);
    final exporter = OwnerLifecycleArchiveExporter(
      database: database,
      nowUtc: () => DateTime.utc(2026, 8, 11, 12),
    );

    await database.customUpdate(
      'UPDATE answer_attempts SET evidence_class = ? WHERE id = ?',
      variables: const [
        Variable<String>('recognition'),
        Variable<String>('a:attempt'),
      ],
      updates: {database.answerAttempts},
    );
    await expectLater(exporter.prepareActive(), throwsStateError);

    final canonical = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'legacy-unspecified',
      hintLevel: 0,
      contentRevision: 'legacy-unknown',
      engagementAllowed: true,
    ).toJson();
    final reversed = Map<String, Object?>.fromEntries(
      canonical.entries.toList(growable: false).reversed,
    );
    await database.customUpdate(
      'UPDATE answer_attempts SET evidence_class = ?, '
      'evidence_context_json = ? WHERE id = ?',
      variables: [
        const Variable<String>('independentRecall'),
        Variable<String>(jsonEncode(reversed)),
        const Variable<String>('a:attempt'),
      ],
      updates: {database.answerAttempts},
    );
    await expectLater(exporter.prepareActive(), throwsStateError);
  });

  test(
    'manifest deletion removes one complete owner and preserves foreign and global rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-owner-lifecycle-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}owner-lifecycle.sqlite',
      );
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await _seedCompleteOwnerA(database);
      await _cloneOwnerAAsB(database);
      await database.customUpdate(
        "UPDATE research_consents SET consent_state = 'withdrawn', "
        'withdrawn_at_utc_ms = 1723377600000 WHERE owner_id = \'owner-a\'',
      );
      final now = DateTime.utc(2026, 8, 11, 12);
      final gate = DriftOwnerOperationGate(database);
      final index = DriftAiCredentialVersionIndex(database);
      final secureValues = <String, String>{
        'gemini_api_key': 'legacy-key-SENTINEL',
        'gemini_provider_consent': 'true',
        'gemini_learning_summary_consent': 'true',
      };
      final secureStorage = _MemorySecureValueStore(secureValues);
      final settings = SecureAiTutorSettingsStore(
        secureStorage,
        activeOwnerId: () async => 'owner-a',
        versionIndex: index,
      );
      await _replaceCredential(
        settings: settings,
        gate: gate,
        ownerId: 'owner-a',
        operationVersion: 'a-current',
        secret: 'secret-SENTINEL-A',
        now: now,
      );
      await _replaceCredential(
        settings: settings,
        gate: gate,
        ownerId: 'owner-b',
        operationVersion: 'b-current',
        secret: 'secret-SENTINEL-B',
        now: now,
      );
      await _preparePendingCredential(
        index: index,
        gate: gate,
        storage: secureStorage,
        ownerId: 'owner-a',
        operationVersion: 'a-pending',
        secret: 'pending-SENTINEL-A',
        now: now,
      );
      await _preparePendingCredential(
        index: index,
        gate: gate,
        storage: secureStorage,
        ownerId: 'owner-b',
        operationVersion: 'b-pending',
        secret: 'pending-SENTINEL-B',
        now: now,
      );
      _seedScopedLegacyCredentialValues(secureValues, 'owner-a', 'A');
      _seedScopedLegacyCredentialValues(secureValues, 'owner-b', 'B');
      expect(secureValues.keys, isNot(contains('gemini_api_key')));
      expect(secureValues.keys, isNot(contains('gemini_provider_consent')));
      expect(
        secureValues.keys,
        isNot(contains('gemini_learning_summary_consent')),
      );

      final archiveExporter = OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => now,
      );
      final firstArchive = await archiveExporter.prepareActive();
      final secondArchive = await archiveExporter.prepareActive();
      expect(secondArchive.bytes, firstArchive.bytes);
      expect(secondArchive.sha256, firstArchive.sha256);
      expect(secondArchive.contentSha256, firstArchive.contentSha256);
      expect(secondArchive.manifestSha256, firstArchive.manifestSha256);
      final archiveText = utf8.decode(firstArchive.bytes);
      final archiveEnvelope = jsonDecode(archiveText) as Map<String, dynamic>;
      expect(archiveEnvelope['contentSha256'], firstArchive.contentSha256);
      final archiveContent = archiveEnvelope['content'] as Map<String, dynamic>;
      expect(
        archiveContent['databaseSchemaVersion'],
        AppDatabase.currentSchemaVersion,
      );
      expect(archiveContent['participantAlias'], 'participant-1');
      final archiveTables = archiveContent['tables'] as List<dynamic>;
      expect(archiveTables, hasLength(32));
      expect(
        archiveTables
            .map((entry) => (entry as Map<String, dynamic>)['alias'] as String)
            .toSet(),
        ownerLifecycleManifest.map((entry) => entry.alias).toSet(),
      );
      for (final rawEntry in archiveTables) {
        final entry = rawEntry as Map<String, dynamic>;
        final descriptor = ownerLifecycleManifest.singleWhere(
          (item) => item.alias == entry['alias'],
        );
        expect(entry['authority'], descriptor.authority.name);
        expect(entry['exportDisposition'], descriptor.exportDisposition.name);
        expect(
          entry['deletionDisposition'],
          descriptor.deletionDisposition.name,
        );
        for (final rawRecord in entry['records'] as List<dynamic>) {
          final record = rawRecord as Map<String, dynamic>;
          expect(
            descriptor.allowedExportFields.toSet(),
            containsAll(record.keys),
            reason: '${descriptor.alias} emitted a non-allowlisted field',
          );
        }
      }
      for (final alias in const [
        'vocabularyImports',
        'answerAttempts',
        'srsStates',
        'streakState',
        'learningDays',
      ]) {
        final descriptor = ownerLifecycleManifest.singleWhere(
          (entry) => entry.alias == alias,
        );
        final table = archiveTables.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['alias'] == alias,
        );
        final records = (table['records'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(records, hasLength(2));
        expect(records.first, {'recordCount': 1});
        expect(
          records.last.keys.toSet(),
          descriptor.allowedExportFields
              .where((field) => field != 'recordCount')
              .toSet(),
          reason: '$alias must materialize its complete personal allowlist',
        );
      }
      final assignmentArchive = archiveTables
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['alias'] == 'experimentAssignments');
      expect(assignmentArchive['records'], [
        {'recordCount': 1},
        {
          'experimentId': 'research-assessment',
          'experimentVersion': 1,
          'cohort': 'treatment-a',
          'protocolVersion': '2026.08',
          'assignedAtUtc': '2026-08-11T12:00:00.000Z',
        },
      ]);
      final answerAttempts = archiveTables
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['alias'] == 'answerAttempts');
      final answerEvidence = (answerAttempts['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .last;
      expect(
        answerEvidence['evidenceClass'],
        EvidenceClass.independentRecall.name,
      );
      final evidenceContext = EvidenceContext.fromJson(
        (answerEvidence['evidenceContext'] as Map).cast<String, Object?>(),
      );
      expect(
        evidenceContext.toJson(),
        EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'legacy-unspecified',
          hintLevel: 0,
          contentRevision: 'legacy-unknown',
          engagementAllowed: true,
        ).toJson(),
      );
      expect(
        (archiveTables.cast<Map<String, dynamic>>().singleWhere(
                  (entry) => entry['alias'] == 'pointsLedger',
                )['records']
                as List<dynamic>)
            .single,
        {'recordCount': 1, 'netPoints': 200},
      );
      expect(
        (archiveTables.cast<Map<String, dynamic>>().singleWhere(
                  (entry) => entry['alias'] == 'rewardTransactions',
                )['records']
                as List<dynamic>)
            .single,
        {'recordCount': 1, 'netAmount': -80},
      );
      final aiDiagnostics = archiveTables
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['alias'] == 'aiUsageDiagnostics');
      expect(
        (aiDiagnostics['records'] as List<dynamic>).single,
        containsPair('providerId', 'other'),
      );
      expect(
        (aiDiagnostics['records'] as List<dynamic>).single,
        containsPair('model', 'typed-model'),
      );
      expect(
        (aiDiagnostics['records'] as List<dynamic>).single,
        containsPair('totalTokens', 99),
      );
      expect(
        (aiDiagnostics['records'] as List<dynamic>).single,
        containsPair('providerReportedCostMicrosUsd', null),
      );
      final runtimeDiagnostics = archiveTables
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (entry) => entry['alias'] == 'runtimeControlsAndMetadata',
          );
      expect(
        runtimeDiagnostics['records'],
        contains(containsPair('feature', 'aiTutor')),
      );
      expect(
        runtimeDiagnostics['records'],
        contains(containsPair('trackedVersionLimit', 20)),
      );
      expect(
        runtimeDiagnostics['records'],
        contains(containsPair('modelVersion', 'model-v1')),
      );
      final modelDiagnostics = archiveTables
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['alias'] == 'globalModelDownloads');
      expect(
        (modelDiagnostics['records'] as List<dynamic>).single,
        containsPair('retryCount', 1),
      );
      expect(
        (modelDiagnostics['records'] as List<dynamic>).single,
        containsPair('state', 'active'),
      );
      for (final forbidden in const [
        'owner-a',
        'firebase-owner-a',
        'provider-key-SENTINEL-A',
        'auth-SENTINEL-A',
        'raw-participant-SENTINEL-A',
        'opaque-SENTINEL-A',
        'secret-SENTINEL-A',
        'pending-SENTINEL-A',
        'secret-SENTINEL.example',
        'private-SENTINEL',
        'private-source.csv',
        'aiCredentialPointer:',
        'aiCredentialIntent:',
        'owner-b',
        'firebase-owner-b',
        'raw-participant-SENTINEL-B',
        'secret-SENTINEL-B',
        'pending-SENTINEL-B',
      ]) {
        expect(
          archiveText,
          isNot(contains(forbidden)),
          reason: 'archive must redact $forbidden',
        );
      }

      final ownerBBefore = await _ownerSnapshot(database, 'owner-b');
      final globalsBefore = await _preservedGlobalSnapshot(database);
      final ownerBToken = _ownerToken('owner-b');
      final ownerAMetadataBefore = await _credentialMetadataSnapshot(
        database,
        _ownerToken('owner-a'),
      );
      final ownerBMetadataBefore = await _credentialMetadataSnapshot(
        database,
        ownerBToken,
      );
      final ownerBSecureBefore = Map<String, String>.fromEntries(
        secureValues.entries.where((entry) => entry.key.contains(ownerBToken)),
      );
      expect(ownerAMetadataBefore, hasLength(2));
      expect(ownerBMetadataBefore, hasLength(2));
      final coordinator = OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => 'owner-a',
        nowUtc: () => now,
        generateToken: () => 'erase-owner-a',
        leaseDuration: const Duration(minutes: 2),
        heartbeatInterval: const Duration(seconds: 30),
      );

      final deleted = await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) => throw StateError('must use fenced erasure'),
        deleteOwnerSecretsFenced: (ownerId, leaseToken) =>
            settings.eraseOwnerCredentialsFenced(
              ownerId,
              leaseToken: leaseToken,
              leaseIsOwned: () => gate.isOwned(token: leaseToken, nowUtc: now),
              nowUtc: () => now,
            ),
        fenceOwnerOperation: (operationToken) =>
            gate.requireOwned(token: operationToken, nowUtc: now),
        coordinate: (ownerId, operation) => coordinator.run(AiCancellation(), (
          activeOwnerId,
        ) async {
          expect(activeOwnerId, ownerId);
          final operationToken = OwnerOperationCoordinator.currentLeaseToken;
          expect(operationToken, isNotNull);
          final result = await operation(operationToken!);
          coordinator.markCurrentOperationResultCommitted();
          return result;
        }),
      ).eraseAll(ownerId: 'owner-a');

      await database.close();
      database = AppDatabase(NativeDatabase(file));
      await database.customSelect('SELECT 1').getSingle();
      final reopenedSettings = SecureAiTutorSettingsStore(
        secureStorage,
        activeOwnerId: () async => 'owner-b',
        versionIndex: DriftAiCredentialVersionIndex(database),
      );

      expect(deleted, 29);
      expect(await _ownerPhysicalRowCount(database, 'owner-a'), 0);
      // v14 retains exactly one immutable owner-b experiment assignment after
      // owner-a is erased, in addition to the pre-existing canonical rows.
      expect(await _ownerPhysicalRowCount(database, 'owner-b'), 29);
      expect(await _experimentAssignmentOwnerCount(database, 'owner-a'), 0);
      expect(await _experimentAssignmentOwnerCount(database, 'owner-b'), 1);
      expect(await _ownerSnapshot(database, 'owner-b'), ownerBBefore);
      expect(await _preservedGlobalSnapshot(database), globalsBefore);
      expect(
        await _credentialMetadataSnapshot(database, _ownerToken('owner-a')),
        isEmpty,
      );
      expect(
        await _credentialMetadataSnapshot(database, ownerBToken),
        ownerBMetadataBefore,
      );
      expect(
        Map<String, String>.fromEntries(
          secureValues.entries.where(
            (entry) => entry.key.contains(ownerBToken),
          ),
        ),
        ownerBSecureBefore,
      );
      expect(
        secureValues.entries.where(
          (entry) => entry.key.contains(_ownerToken('owner-a')),
        ),
        isEmpty,
      );
      expect(secureValues.values.join('|'), isNot(contains('SENTINEL-A')));
      expect(await reopenedSettings.readCredentialForOwner('owner-a'), isNull);
      expect(
        (await reopenedSettings.readCredentialForOwner('owner-b'))?.key,
        'secret-SENTINEL-B',
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

Future<int> _experimentAssignmentOwnerCount(
  AppDatabase database,
  String ownerId,
) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM experiment_assignments WHERE owner_id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .getSingle();
  return row.read<int>('count');
}

Future<void> _seedCompleteOwnerA(AppDatabase database) async {
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'owner-a',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('owner-a', 'firebase-owner-a', 'firebaseBound', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'owner-a', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1786449600000)",
    variables: [Variable<String>(assignmentId)],
  );
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('a:consent', 'owner-a', 1, 'accepted', 10, NULL)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('a:category', 'owner-a', 'Travel', 'travel', 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('a:word', 'owner-a', 'a:category', 'station', 'station', 'station', "
    "'station', 'noun', 'manual', 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_imports '
    '(id, owner_id, category_id, source_type, source_name, source_hash, '
    'status, created_at_utc_ms) VALUES '
    "('a:import', 'owner-a', 'a:category', 'csv', 'private-source.csv', "
    "'a:source-hash', 'complete', 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_import_rows VALUES "
    "('a:import-row', 'a:import', 1, 'a:payload-hash', 'accepted', NULL, "
    "'a:word')",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES "
    "('a:session', 'owner-a', 'quiz', 'completed', 10, 20, 1, 0, 100, "
    "'1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('a:attempt', 'owner-a', 'a:session', 'a:word', 'meaning', 1, 100, "
    "1, 15, 'provider-key-SENTINEL-A')",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES "
    "('a:srs', 'owner-a', 'a:word', 1, 1, 1, 1, 0, 15, 30, 1)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES "
    "('a:reading-progress', 'owner-a', 'raw-document-owner-a', 1, 5, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES "
    "('a:reading-event', 'owner-a', 'raw-document-owner-a', 1, "
    "'position', 5, 20)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES "
    "('a:points', 'owner-a', 'a:points-key', 'quiz', 200, 'a:attempt', 20)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES "
    "('a:achievement', 'owner-a', 'first-answer', 1, 'a:attempt', 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES "
    "('a:reward', 'owner-a', 'a:reward-key', 'purchase', -80, "
    "'theme_ocean', 1, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO owned_reward_items VALUES "
    "('a:owned', 'owner-a', 'theme_ocean', 1, 'a:reward', 20)",
  );
  await database.customInsert(
    "INSERT INTO equipped_reward_items VALUES "
    "('a:equipped', 'owner-a', 'theme', 'theme_ocean', 20)",
  );
  await database.customInsert(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
    'created_at_utc_ms) VALUES '
    "('a:operation', 'owner-a', 'word', 'a:word', 'upsert', 20)",
  );
  await database.customInsert(
    'INSERT INTO sync_checkpoints '
    '(id, owner_id, collection_name, server_cursor, last_success_at_utc_ms) '
    "VALUES ('a:checkpoint', 'owner-a', 'words', "
    "'{\"token\":\"auth-SENTINEL-A\"}', 20)",
  );
  await database.customInsert(
    'INSERT INTO sync_conflicts '
    '(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, '
    'resolution_policy, outcome, resolved_at_utc_ms) VALUES '
    "('a:conflict', 'owner-a', 'word', 'a:word', 1, 2, 'cloudWins', "
    "'cloudApplied', 20)",
  );
  await database.customInsert(
    'INSERT INTO events_v2 '
    '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, '
    'actor_identity, owner_id, aggregate_type, aggregate_id, '
    'idempotency_key, consent_context_json, app_version, build_id, '
    'privacy_classification, payload_json) VALUES '
    "('a:event', 'QuizCompleted', 1, 20, 21, 'raw-participant-SENTINEL-A', "
    "'owner-a', 'LearningSession', 'a:session', 'a:event-key', '{}', "
    "'1.0.0', 'task-8', 'personal', "
    "'{\"token\":\"opaque-SENTINEL-A\"}')",
  );
  await database.customInsert(
    'INSERT INTO quest_definitions '
    '(quest_id, catalog_version, title, description, type, objectives_json, '
    'reward_json) VALUES '
    "('global:quest', 1, 'Seed Quest', 'Seed', 'daily', '[]', '{}')",
  );
  await database.customInsert(
    'INSERT INTO quest_instances '
    '(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, '
    "state) VALUES ('a:quest-instance', 'global:quest', 'owner-a', 1, 20, "
    "'active')",
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    "source_event_ids_json) VALUES ('a:objective', 'a:quest-instance', "
    "'answer-once', 1, 1, '[\"a:event\"]')",
  );
  await database.customInsert(
    'INSERT INTO streak_states '
    '(owner_id, current_streak_days, longest_streak_days, freeze_count, '
    "updated_at_utc_ms) VALUES ('owner-a', 1, 1, 0, 20)",
  );
  await database.customInsert(
    'INSERT INTO learning_day_log '
    '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
    "('a:day', 'owner-a', '2026-08-09', 20)",
  );
  await database.customInsert(
    'INSERT INTO association_records '
    '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
    "('a:association', 'owner-a', 'station', 'keyword', 'train stop', 20)",
  );
  await database.customInsert(
    'INSERT INTO associative_memory_states '
    '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
    'lapse_count, next_due_at_utc_ms, algorithm_version) VALUES '
    "('a:memory', 'owner-a', 'station', 1, 5, 0, 0, 30, 'v1')",
  );
  await database.customInsert(
    'INSERT INTO ai_usage_events '
    '(event_id, owner_id, occurred_at_utc_ms, provider_id, model, '
    'request_type, outcome, latency_ms, input_tokens, output_tokens, '
    'total_tokens, provider_reported_cost_micros_usd) VALUES '
    "('a:usage', 'owner-a', 20, 'typed-provider', 'typed-model', "
    "'tutorReply', 'success', 10, 2, 3, 99, NULL)",
  );
  await database.customInsert(
    'INSERT INTO speech_evidence '
    '(id, owner_id, session_id, word_id, prompt_mode, target_content, '
    'recognized_transcript, locale, stt_engine, similarity_algorithm, '
    'similarity_score, is_exact_match, recognition_confidence, sample_size, '
    'occurred_at_utc_ms, duration_ms) VALUES '
    "('a:speech', 'owner-a', 'a:session', 'a:word', 'meaning', 'station', "
    "'raw-participant-SENTINEL-A', 'en-US', 'fake-stt', 'levenshtein', "
    '100, 1, 0.95, 1, 20, 500)',
  );
  await database.customInsert(
    'INSERT INTO runtime_flags '
    '(key, bool_value, source, updated_at_utc_ms) VALUES '
    "('cloudSyncEnabled', 1, 'cloud_cache', 20), "
    "('feature_emergency_off:aiTutor', 1, 'operator', 20), "
    "('download_count:bW9kZWwtdjE:event-1', 1, 'download_counter', 20), "
    "('unrelated-global-flag', 1, 'operator', 20)",
  );
  await database.customInsert(
    'INSERT INTO model_downloads '
    '(id, model_version, source_url, expected_checksum, expected_bytes, '
    'downloaded_bytes, retry_count, state, local_path, updated_at_utc_ms) '
    "VALUES ('global:model', 'model-v1', "
    "'https://secret-SENTINEL.example/model', 'checksum', 100, 100, 1, "
    "'active', 'C:/private-SENTINEL/model.bin', 20)",
  );
}

Future<void> _cloneOwnerAAsB(AppDatabase database) async {
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'owner-b',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('owner-b', 'firebase-owner-b', 'firebaseBound', 2, 0)",
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'owner-b', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1786449600000)",
    variables: [Variable<String>(assignmentId)],
  );
  for (final table in ownerLifecycleDirectOwnerTableNames.where(
    (table) => table != 'experiment_assignments',
  )) {
    final schema = await database
        .customSelect('PRAGMA table_info("$table")')
        .get();
    final columns = schema.map((row) => row.read<String>('name')).toList();
    final quotedColumns = columns.map((column) => '"$column"').join(', ');
    final projections = columns
        .map((column) {
          final quoted = '"$column"';
          if (column == 'owner_id') return "'owner-b'";
          if (column == 'actor_identity') return "'raw-participant-SENTINEL-B'";
          if (column == 'quest_id') return quoted;
          if (column == 'idempotency_key') return "'b:' || $quoted";
          if (column == 'id' || column.endsWith('_id')) {
            return 'CASE WHEN $quoted IS NULL THEN NULL '
                "ELSE 'b:' || $quoted END";
          }
          return quoted;
        })
        .join(', ');
    await database.customInsert(
      'INSERT INTO "$table" ($quotedColumns) '
      'SELECT $projections FROM "$table" WHERE owner_id = ?',
      variables: [const Variable<String>('owner-a')],
    );
  }
  await database.customInsert(
    'INSERT INTO vocabulary_import_rows '
    '(id, import_id, row_number, payload_hash, status, failure_code, word_id) '
    "SELECT 'b:' || id, 'b:' || import_id, row_number, payload_hash, status, "
    "failure_code, CASE WHEN word_id IS NULL THEN NULL ELSE 'b:' || word_id END "
    'FROM vocabulary_import_rows WHERE import_id = ?',
    variables: [const Variable<String>('a:import')],
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    'source_event_ids_json) '
    "SELECT 'b:' || id, 'b:' || instance_id, objective_id, current_count, "
    'target_count, source_event_ids_json FROM quest_objective_progress '
    'WHERE instance_id = ?',
    variables: [const Variable<String>('a:quest-instance')],
  );
}

Future<int> _ownerPhysicalRowCount(AppDatabase database, String ownerId) async {
  var count = await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM local_owners WHERE id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .map((row) => row.read<int>('count'))
      .getSingle();
  for (final table in ownerLifecycleDirectOwnerTableNames) {
    count += await database
        .customSelect(
          'SELECT COUNT(*) AS count FROM "$table" WHERE owner_id = ?',
          variables: [Variable<String>(ownerId)],
        )
        .map((row) => row.read<int>('count'))
        .getSingle();
  }
  count += await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM vocabulary_import_rows WHERE import_id '
        'IN (SELECT id FROM vocabulary_imports WHERE owner_id = ?)',
        variables: [Variable<String>(ownerId)],
      )
      .map((row) => row.read<int>('count'))
      .getSingle();
  count += await database
      .customSelect(
        'SELECT COUNT(*) AS count FROM quest_objective_progress WHERE '
        'instance_id IN (SELECT instance_id FROM quest_instances '
        'WHERE owner_id = ?)',
        variables: [Variable<String>(ownerId)],
      )
      .map((row) => row.read<int>('count'))
      .getSingle();
  return count;
}

Future<Map<String, List<String>>> _ownerSnapshot(
  AppDatabase database,
  String ownerId,
) async {
  final snapshot = <String, List<String>>{};
  snapshot['local_owners'] =
      (await database
              .customSelect(
                'SELECT * FROM local_owners WHERE id = ?',
                variables: [Variable<String>(ownerId)],
              )
              .get())
          .map((row) => row.data.toString())
          .toList();
  for (final table in ownerLifecycleDirectOwnerTableNames) {
    snapshot[table] =
        (await database
                .customSelect(
                  'SELECT * FROM "$table" WHERE owner_id = ?',
                  variables: [Variable<String>(ownerId)],
                )
                .get())
            .map((row) => row.data.toString())
            .toList();
  }
  snapshot['vocabulary_import_rows'] =
      (await database
              .customSelect(
                'SELECT * FROM vocabulary_import_rows WHERE import_id IN '
                '(SELECT id FROM vocabulary_imports WHERE owner_id = ?)',
                variables: [Variable<String>(ownerId)],
              )
              .get())
          .map((row) => row.data.toString())
          .toList();
  snapshot['quest_objective_progress'] =
      (await database
              .customSelect(
                'SELECT * FROM quest_objective_progress WHERE instance_id IN '
                '(SELECT instance_id FROM quest_instances WHERE owner_id = ?)',
                variables: [Variable<String>(ownerId)],
              )
              .get())
          .map((row) => row.data.toString())
          .toList();
  return snapshot;
}

Future<Map<String, List<String>>> _preservedGlobalSnapshot(
  AppDatabase database,
) async {
  final snapshot = <String, List<String>>{};
  snapshot['runtime_flags'] =
      (await database
              .customSelect(
                'SELECT * FROM runtime_flags WHERE "key" <> ? '
                'AND instr("key", ?) <> 1 AND instr("key", ?) <> 1 ORDER BY "key"',
                variables: const [
                  Variable<String>('ownerOperationGate'),
                  Variable<String>('aiCredentialPointer:'),
                  Variable<String>('aiCredentialIntent:'),
                ],
              )
              .get())
          .map((row) => row.data.toString())
          .toList();
  for (final table in const ['model_downloads', 'quest_definitions']) {
    snapshot[table] =
        (await database
                .customSelect('SELECT * FROM "$table" ORDER BY rowid')
                .get())
            .map((row) => row.data.toString())
            .toList();
  }
  return snapshot;
}

Future<List<String>> _credentialMetadataSnapshot(
  AppDatabase database,
  String ownerToken,
) async =>
    (await database
            .customSelect(
              'SELECT * FROM runtime_flags WHERE "key" = ? OR instr("key", ?) = 1 '
              'ORDER BY "key"',
              variables: [
                Variable<String>('aiCredentialPointer:$ownerToken'),
                Variable<String>('aiCredentialIntent:$ownerToken:'),
              ],
            )
            .get())
        .map((row) => row.data.toString())
        .toList();

Future<void> _replaceCredential({
  required SecureAiTutorSettingsStore settings,
  required DriftOwnerOperationGate gate,
  required String ownerId,
  required String operationVersion,
  required String secret,
  required DateTime now,
}) async {
  expect(
    await gate.tryAcquire(
      token: operationVersion,
      nowUtc: now,
      leaseDuration: const Duration(minutes: 2),
    ),
    isTrue,
  );
  try {
    await settings.replaceCredentialForOwnerFenced(
      ownerId,
      AiTutorCredential(
        key: secret,
        providerId: AiProviderId.gemini,
        model: 'typed-model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
      operationVersion: operationVersion,
      leaseIsOwned: () => gate.isOwned(token: operationVersion, nowUtc: now),
      nowUtc: () => now,
    );
  } finally {
    await gate.release(token: operationVersion);
  }
}

Future<void> _preparePendingCredential({
  required DriftAiCredentialVersionIndex index,
  required DriftOwnerOperationGate gate,
  required SecureValueStore storage,
  required String ownerId,
  required String operationVersion,
  required String secret,
  required DateTime now,
}) async {
  expect(
    await gate.tryAcquire(
      token: operationVersion,
      nowUtc: now,
      leaseDuration: const Duration(minutes: 2),
    ),
    isTrue,
  );
  final ownerToken = _ownerToken(ownerId);
  try {
    await index.prepareMutation(
      ownerToken: ownerToken,
      operationVersion: operationVersion,
      kind: AiCredentialMutationKind.replace,
      legacyBlobExists: false,
      leaseToken: operationVersion,
      nowUtc: now,
    );
    await storage.write(
      'ai_active_profile_v2:$ownerToken:version:$operationVersion',
      jsonEncode({
        'version': 1,
        'key': secret,
        'providerId': 'gemini',
        'model': 'pending-model',
        'providerConsent': true,
        'shareLearningSummary': false,
      }),
    );
  } finally {
    await gate.release(token: operationVersion);
  }
}

void _seedScopedLegacyCredentialValues(
  Map<String, String> values,
  String ownerId,
  String sentinel,
) {
  final ownerToken = _ownerToken(ownerId);
  for (final baseKey in const [
    'ai_active_profile_v2',
    'ai_api_key_v2',
    'ai_provider_consent_v2',
    'ai_learning_summary_consent_v2',
    'ai_provider_id_v2',
    'ai_model_v2',
    'ai_custom_base_url_v2',
  ]) {
    values['$baseKey:$ownerToken'] = 'legacy-SENTINEL-$sentinel';
  }
}

String _ownerToken(String ownerId) =>
    base64Url.encode(utf8.encode(ownerId)).replaceAll('=', '');

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
