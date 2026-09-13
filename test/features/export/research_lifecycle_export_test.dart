import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';

import '../identity/research_lifecycle_fixtures.dart';

void main() {
  late AppDatabase database;
  late OwnerLifecycleArchiveExporter exporter;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedLifecycleOwner(database, 'source', active: true);
    await seedLifecycleOwner(database, 'other');
    exporter = OwnerLifecycleArchiveExporter(
      database: database,
      nowUtc: () => DateTime.utc(2026, 9, 5),
    );
  });
  tearDown(() => database.close());

  test(
    'four research tables have exactly one personal owner lifecycle entry',
    () {
      expect(ownerLifecycleManifest, hasLength(50));
      expect(
        ownerLifecycleManifest.map((entry) => entry.alias).toSet(),
        hasLength(50),
      );
      for (final table in researchLifecycleTables) {
        final entries = ownerLifecycleManifest.where(
          (entry) => entry.tableName == table,
        );
        expect(entries, hasLength(1));
        final entry = entries.single;
        expect(entry.authority, OwnerLifecycleAuthority.directOwner);
        expect(
          entry.exportDisposition,
          OwnerLifecycleExportDisposition.allowlistedPersonal,
        );
        expect(
          entry.deletionDisposition,
          OwnerLifecycleDeletionDisposition.deleteDirect,
        );
        expect(
          entry.allowedExportFields,
          isNot(
            contains(
              anyOf([
                'signature',
                'payloadSha256',
                'issuerKeyId',
                'ownerId',
                'consentReceiptId',
                'guardianPermissionReceiptRef',
                'learnerAssentReceiptRef',
                'freeText',
              ]),
            ),
          ),
        );
      }
    },
  );

  test(
    'children precede all research, assignment, session and owner parents',
    () {
      for (final child in [
        'measurement_opportunities',
        'motivation_responses',
      ]) {
        final childIndex = ownerLifecyclePhysicalDeletionOrder.indexOf(child);
        expect(childIndex, greaterThanOrEqualTo(0));
        expect(
          ownerLifecyclePhysicalDeletionOrder.where((table) => table == child),
          hasLength(1),
        );
        for (final parent in [
          'motivation_measurement_runs',
          'research_participation_permits',
          'experiment_assignments',
          'learning_sessions',
          'local_owners',
        ]) {
          expect(
            childIndex,
            lessThan(ownerLifecyclePhysicalDeletionOrder.indexOf(parent)),
          );
        }
      }
      for (final table in [
        'motivation_measurement_runs',
        'research_participation_permits',
      ]) {
        for (final parent in [
          'experiment_assignments',
          'learning_sessions',
          'local_owners',
        ]) {
          expect(
            ownerLifecyclePhysicalDeletionOrder.indexOf(table),
            lessThan(ownerLifecyclePhysicalDeletionOrder.indexOf(parent)),
          );
        }
      }
    },
  );

  test(
    'personal archive exports coded motivation separately from engagement',
    () async {
      await seedLifecycleResearch(database, 'source');
      await seedLifecycleResearch(database, 'other');
      final snapshot = await lifecycleSnapshot(database, 'source');
      final artifact = await exporter.prepareActive();
      final text = utf8.decode(artifact.bytes);
      final tables = archiveTables(artifact);
      expect(tables, hasLength(50));
      final run = records(tables, 'motivationMeasurementRuns').last;
      final response = records(tables, 'motivationResponses').last;
      final permit = records(tables, 'researchParticipationPermits').last;
      final opportunity = records(tables, 'measurementOpportunities').last;
      expect(run['measurementAxis'], 'motivation');
      expect(run['state'], 'started');
      expect(response, {
        'measurementAxis': 'motivation',
        'runAlias': run['runAlias'],
        'itemId': 'baseline.interest',
        'itemCatalogVersion': '1',
        'responseCode': 'agree',
        'ordinalValue': 3,
        'answeredAtUtc': DateTime.fromMillisecondsSinceEpoch(
          2,
          isUtc: true,
        ).toIso8601String(),
        'isDeleted': false,
      });
      expect(permit['participantClass'], 'minor');
      expect(permit['ageBandCode'], 'adolescent');
      expect(opportunity['measurementAxis'], 'engagement');
      expect(opportunity['runAlias'], run['runAlias']);
      expect(opportunity['permitAlias'], permit['permitAlias']);
      expect(opportunity['assignedTreatment'], 'adventure');
      expect(opportunity['effectivePresentation'], 'standard');
      expect(opportunity['hasAcceptedSession'], isTrue);
      expect(opportunity['hasCompletionEvent'], isTrue);
      expect(opportunity['lastSwitchOrdinal'], 2);
      for (final alias in [
        'motivationMeasurementRuns',
        'motivationResponses',
        'researchParticipationPermits',
        'measurementOpportunities',
      ]) {
        expect(records(tables, alias), hasLength(2));
        expect(records(tables, alias).first, {'recordCount': 1});
        final descriptor = ownerLifecycleManifest.singleWhere(
          (entry) => entry.alias == alias,
        );
        expect(
          records(tables, alias).last.keys.toSet(),
          descriptor.allowedExportFields.toSet()..remove('recordCount'),
        );
      }
      for (final secret in [
        'private-signature',
        'private-consent',
        'private-guardian',
        'private-assent',
        'private-issuer',
        'a' * 64,
        'run:source',
        'permit:source',
        'opportunity:source',
        'response:source',
        'session:source',
        'run:other',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        response.keys,
        isNot(
          contains(
            anyOf('completionRate', 'retentionRate', 'score', 'learningScore'),
          ),
        ),
      );
      expect(
        opportunity.keys,
        isNot(
          contains(anyOf('motivationScore', 'retentionRate', 'learningScore')),
        ),
      );
      expect(await lifecycleSnapshot(database, 'source'), snapshot);
      expect((await exporter.prepareActive()).sha256, artifact.sha256);
    },
  );

  test(
    'withdrawn, revoked and tombstoned research remains personally exportable',
    () async {
      await seedLifecycleResearch(
        database,
        'source',
        withdrawn: true,
        deleted: true,
      );
      final tables = archiveTables(await exporter.prepareActive());
      expect(
        records(tables, 'motivationMeasurementRuns').last['state'],
        'withdrawn',
      );
      expect(
        records(tables, 'researchParticipationPermits').last['revokedAtUtc'],
        isNotNull,
      );
      for (final alias in [
        'motivationMeasurementRuns',
        'motivationResponses',
        'researchParticipationPermits',
        'measurementOpportunities',
      ]) {
        expect(records(tables, alias).last['isDeleted'], isTrue);
      }
    },
  );

  test('nonparticipant archive creates no research rows', () async {
    final tables = archiveTables(await exporter.prepareActive());
    for (final alias in [
      'motivationMeasurementRuns',
      'motivationResponses',
      'researchParticipationPermits',
      'measurementOpportunities',
    ]) {
      expect(records(tables, alias), [
        {'recordCount': 0},
      ]);
    }
    for (final table in researchLifecycleTables) {
      expect(await lifecycleRows(database, table, 'source'), isEmpty);
    }
  });

  test(
    'malformed response text is rejected instead of exported as a code',
    () async {
      await seedLifecycleResearch(database, 'source');
      await database.customStatement(
        "UPDATE motivation_responses SET response_code = 'private free text' WHERE owner_id = 'source'",
      );
      await expectLater(
        exporter.prepareActive(),
        throwsA(isA<ExportException>()),
      );
    },
  );

  for (final value in [
    ' agree',
    'agree ',
    'agree\n',
    'agree\u0000',
    'เห็นด้วย',
    'a' * 129,
  ]) {
    test('noncanonical response ${jsonEncode(value)} fails closed', () async {
      await seedLifecycleResearch(
        database,
        'source',
        withdrawn: true,
        deleted: true,
      );
      await database.customStatement(
        'UPDATE motivation_responses SET response_code = ? WHERE owner_id = ?',
        [value, 'source'],
      );
      await expectLater(
        exporter.prepareActive(),
        throwsA(isA<ExportException>()),
      );
    });
  }

  test('ordinal absence and unanswered opportunity stay absent', () async {
    await seedLifecycleResearch(database, 'source');
    await database.customStatement(
      "UPDATE motivation_responses SET ordinal_value = NULL WHERE owner_id = 'source'",
    );
    await database.customStatement('''
      UPDATE measurement_opportunities SET presented_event_id = NULL,
      learning_session_id = NULL, started_event_id = NULL,
      completed_event_id = NULL, last_switch_ordinal = 0,
      suppressed_switch_count = 0, closed_at_utc_ms = NULL
      WHERE owner_id = 'source'
    ''');
    final tables = archiveTables(await exporter.prepareActive());
    expect(records(tables, 'motivationResponses').last['ordinalValue'], isNull);
    final opportunity = records(tables, 'measurementOpportunities').last;
    for (final field in [
      'hasPresentationEvent',
      'hasAcceptedSession',
      'hasStartEvent',
      'hasCompletionEvent',
    ]) {
      expect(opportunity[field], isFalse);
    }
    expect(opportunity['closedAtUtc'], isNull);
    expect(opportunity['lastSwitchOrdinal'], 0);
    expect(opportunity['suppressedSwitchCount'], 0);
  });

  test(
    'malformed evidence owned by someone else cannot block personal export',
    () async {
      await seedLifecycleResearch(database, 'source');
      await seedLifecycleResearch(database, 'other');
      await database.customStatement(
        "UPDATE motivation_responses SET response_code = 'private other answer' WHERE owner_id = 'other'",
      );
      final artifact = await exporter.prepareActive();
      expect(
        records(
          archiveTables(artifact),
          'motivationResponses',
        ).last['responseCode'],
        'agree',
      );
      expect(
        utf8.decode(artifact.bytes),
        isNot(contains('private other answer')),
      );
    },
  );

  for (final field in ['item_id', 'item_catalog_version']) {
    test('malformed $field cannot carry personal text out as metadata', () async {
      await seedLifecycleResearch(database, 'source');
      await database.customStatement(
        "UPDATE motivation_responses SET $field = 'private personal text' WHERE owner_id = 'source'",
      );
      await expectLater(
        exporter.prepareActive(),
        throwsA(isA<ExportException>()),
      );
    });
  }

  test(
    'multiple runs and permits retain exact private alias linkage',
    () async {
      await seedLifecycleResearch(database, 'source');
      final run = (await lifecycleRows(
        database,
        'motivation_measurement_runs',
        'source',
      )).single;
      final permit = (await lifecycleRows(
        database,
        'research_participation_permits',
        'source',
      )).single;
      final response = (await lifecycleRows(
        database,
        'motivation_responses',
        'source',
      )).single;
      final opportunity = (await lifecycleRows(
        database,
        'measurement_opportunities',
        'source',
      )).single;
      await insertLifecycleRow(database, 'motivation_measurement_runs', {
        ...run,
        'id': 'private-second-run',
        'started_at_utc_ms': 2,
        'is_deleted': 1,
      });
      await insertLifecycleRow(database, 'research_participation_permits', {
        ...permit,
        'id': 'private-second-permit',
        'issued_at_utc_ms': 2,
        'is_deleted': 1,
      });
      await insertLifecycleRow(database, 'motivation_responses', {
        ...response,
        'id': 'private-second-response',
        'run_id': 'private-second-run',
        'item_id': 'post.interest',
        'response_code': 'disagree',
        'ordinal_value': 0,
      });
      await insertLifecycleRow(database, 'measurement_opportunities', {
        ...opportunity,
        'id': 'private-second-opportunity',
        'measurement_run_id': 'private-second-run',
        'permit_id': 'private-second-permit',
        'opened_at_utc_ms': 3,
      });
      final artifact = await exporter.prepareActive();
      final tables = archiveTables(artifact);
      final runs = records(
        tables,
        'motivationMeasurementRuns',
      ).skip(1).toList();
      final permits = records(
        tables,
        'researchParticipationPermits',
      ).skip(1).toList();
      final responses = records(tables, 'motivationResponses').skip(1).toList();
      final opportunities = records(
        tables,
        'measurementOpportunities',
      ).skip(1).toList();
      expect(runs.map((row) => row['runAlias']).toSet(), hasLength(2));
      expect(permits.map((row) => row['permitAlias']).toSet(), hasLength(2));
      for (var index = 0; index < 2; index++) {
        final itemId = index == 0 ? 'baseline.interest' : 'post.interest';
        expect(
          responses.singleWhere((row) => row['itemId'] == itemId)['runAlias'],
          runs[index]['runAlias'],
        );
        expect(opportunities[index]['runAlias'], runs[index]['runAlias']);
        expect(
          opportunities[index]['permitAlias'],
          permits[index]['permitAlias'],
        );
      }
      expect(
        responses.singleWhere(
          (row) => row['itemId'] == 'post.interest',
        )['ordinalValue'],
        0,
      );
      expect(utf8.decode(artifact.bytes), isNot(contains('private-second')));
      expect((await exporter.prepareActive()).sha256, artifact.sha256);
    },
  );

  test(
    'physical deletion erases linked research without orphans or cross-owner loss',
    () async {
      await seedLifecycleResearch(
        database,
        'source',
        withdrawn: true,
        deleted: true,
      );
      await seedLifecycleResearch(database, 'other');
      final other = await lifecycleSnapshot(database, 'other');
      await database.customStatement(
        "INSERT INTO runtime_flags (key, bool_value, updated_at_utc_ms, source) VALUES ('global:keep', 1, 1, 'fixture')",
      );
      final secrets = <String>[];
      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (owner) async => secrets.add(owner),
      ).eraseAll(ownerId: 'source');
      for (final table in [
        'local_owners',
        'research_consents',
        'experiment_assignments',
        'learning_sessions',
        ...researchLifecycleTables,
      ]) {
        expect(await lifecycleRows(database, table, 'source'), isEmpty);
      }
      expect(await lifecycleSnapshot(database, 'other'), other);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        await database
            .customSelect(
              "SELECT * FROM runtime_flags WHERE key = 'global:keep'",
            )
            .get(),
        hasLength(1),
      );
      expect(secrets, ['source']);
      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'source');
      expect(await lifecycleSnapshot(database, 'other'), other);
    },
  );

  test(
    'late deletion failure rolls back the complete research graph',
    () async {
      await seedLifecycleResearch(database, 'source');
      final before = await lifecycleSnapshot(database, 'source');
      await database.customStatement('''
      CREATE TRIGGER fail_late_owner_deletion BEFORE DELETE ON local_owners
      WHEN OLD.id = 'source' BEGIN SELECT RAISE(ABORT, 'injected late failure'); END
    ''');
      await expectLater(
        LocalDataDeletion(
          database,
          deleteOwnerSecrets: (_) async {},
        ).eraseAll(ownerId: 'source'),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('injected late failure'),
          ),
        ),
      );
      expect(await lifecycleSnapshot(database, 'source'), before);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

List<Map<String, Object?>> archiveTables(
  OwnerLifecycleArchiveArtifact artifact,
) {
  final document =
      jsonDecode(utf8.decode(artifact.bytes)) as Map<String, Object?>;
  final content = document['content'] as Map<String, Object?>;
  return (content['tables'] as List).cast<Map<String, Object?>>();
}

List<Map<String, Object?>> records(
  List<Map<String, Object?>> tables,
  String alias,
) => (tables.singleWhere((table) => table['alias'] == alias)['records'] as List)
    .cast<Map<String, Object?>>();
