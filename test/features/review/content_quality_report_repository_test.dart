import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/data/drift_content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late String ownerId;
  late int notifications;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'report-owner',
      nowUtc: () => DateTime.utc(2026, 8, 24, 12),
    );
    ownerId = (await owners.getOrCreateActiveOwner()).id;
    notifications = 0;
  });

  tearDown(() => database.close());

  test('default-off persists locally without creating upload work', () async {
    final repository = DriftContentQualityReportRepository(
      database,
      owners: owners,
      onLocalMutation: () async => notifications += 1,
    );
    final before = await _protectedCounts(database);

    await repository.submit(_report(id: 'report:local-only'));

    final rows = await database.select(database.contentQualityReports).get();
    expect(database.schemaVersion, 17);
    expect(rows, hasLength(1));
    expect(rows.single.ownerId, ownerId);
    expect(rows.single.contentType, ContentType.lexicalMetadata.name);
    expect(rows.single.contentId, 'word:station');
    expect(rows.single.contentRevision, 4);
    expect(rows.single.reasonCode, ContentReportReason.text.name);
    expect(rows.single.comment, isNull);
    expect(await _reportOutbox(database), isEmpty);
    expect(await _protectedCounts(database), before);
    expect(notifications, 0, reason: 'no upload work was queued');
  });

  test(
    'explicit rollout and granted consent atomically enqueue v1 upload',
    () async {
      await _decideConsent(database, ownerId: ownerId, accepted: true);
      final repository = _uploadingRepository(
        database,
        owners: owners,
        onLocalMutation: () async => notifications += 1,
      );

      await repository.submit(_report(id: 'report:upload'));

      final rows = await database.select(database.contentQualityReports).get();
      final outbox = await _reportOutbox(database);
      expect(rows, hasLength(1));
      expect(outbox, hasLength(1));
      expect(outbox.single.read<String>('entity_id'), 'report:upload');
      expect(outbox.single.read<String>('operation_kind'), 'upsert');
      expect(outbox.single.read<int>('payload_version'), 1);
      expect(outbox.single.read<int>('base_revision'), 0);
      expect(notifications, 1);
    },
  );

  test(
    'withdrawal blocks upload but retains the local lifecycle row',
    () async {
      await _decideConsent(database, ownerId: ownerId, accepted: false);
      final repository = _uploadingRepository(
        database,
        owners: owners,
        onLocalMutation: () async => notifications += 1,
      );

      await repository.submit(_report(id: 'report:withdrawn'));

      expect(
        await database.select(database.contentQualityReports).get(),
        hasLength(1),
      );
      expect(await _reportOutbox(database), isEmpty);
      expect(notifications, 0);
    },
  );

  test(
    'identical retry and repository restart remain one durable report',
    () async {
      await _decideConsent(database, ownerId: ownerId, accepted: true);
      final first = _uploadingRepository(database, owners: owners);
      final command = _report(id: 'report:stable');

      await first.submit(command);
      await first.submit(command);
      final reopened = _uploadingRepository(database, owners: owners);
      await reopened.submit(command);

      expect(
        await database.select(database.contentQualityReports).get(),
        hasLength(1),
      );
      expect(await _reportOutbox(database), hasLength(1));
      await expectLater(
        reopened.submit(
          _report(id: 'report:stable', reason: ContentReportReason.answer),
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.contentQualityReports).get(),
        hasLength(1),
      );
      expect(await _reportOutbox(database), hasLength(1));
    },
  );

  test(
    'semantic retry after restart deduplicates fresh command id and clock',
    () async {
      await _decideConsent(database, ownerId: ownerId, accepted: true);
      final first = _uploadingRepository(database, owners: owners);

      await first.submit(_report(id: 'report:first-attempt'));
      final reopened = _uploadingRepository(database, owners: owners);
      await reopened.submit(
        _report(
          id: 'report:fresh-retry-id',
          submittedAtUtc: DateTime.utc(2026, 8, 24, 12, 5),
        ),
      );

      final reports = await database
          .select(database.contentQualityReports)
          .get();
      expect(reports, hasLength(1));
      expect(reports.single.id, 'report:first-attempt');
      expect(
        reports.single.submittedAtUtcMs,
        DateTime.utc(2026, 8, 24, 12).millisecondsSinceEpoch,
      );
      expect(await _reportOutbox(database), hasLength(1));
    },
  );

  test(
    'outbox conflict rolls back the allowed local report transaction',
    () async {
      await _decideConsent(database, ownerId: ownerId, accepted: true);
      await database.customInsert(
        '''
      INSERT INTO outbox_operations(
        operation_id, owner_id, entity_type, entity_id, operation_kind,
        payload_version, base_revision, state, attempt_count,
        created_at_utc_ms
      ) VALUES (?, ?, 'contentQualityReport', 'different-report', 'upsert',
                1, 0, 'pending', 0, 1)
      ''',
        variables: <Variable<Object>>[
          const Variable<String>('contentQualityReport:report:collision:1'),
          Variable<String>(ownerId),
        ],
      );
      final repository = _uploadingRepository(database, owners: owners);

      await expectLater(
        repository.submit(_report(id: 'report:collision')),
        throwsStateError,
      );

      expect(
        await database.select(database.contentQualityReports).get(),
        isEmpty,
      );
    },
  );

  test(
    'active-owner archive and deletion retain no provider or device secret',
    () async {
      await database.customInsert(
        '''
      INSERT INTO content_quality_reports(
        id, owner_id, content_type, content_id, content_revision,
        reason_code, comment, submitted_at_utc_ms
      ) VALUES (?, ?, 'lexicalMetadata', 'word:station', 4, 'audio', ?, 1)
      ''',
        variables: <Variable<Object>>[
          const Variable<String>('report:legacy-sensitive'),
          Variable<String>(ownerId),
          const Variable<String>(
            'providerToken=provider-secret-SENTINEL; '
            'deviceId=device-secret-SENTINEL',
          ),
        ],
      );

      final artifact = await OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => DateTime.utc(2026, 8, 24, 13),
      ).prepareActive();
      final archive = utf8.decode(artifact.bytes);
      expect(archive, contains('contentQualityReports'));
      expect(archive, isNot(contains('provider-secret-SENTINEL')));
      expect(archive, isNot(contains('device-secret-SENTINEL')));

      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: ownerId);
      expect(
        await database.select(database.contentQualityReports).get(),
        isEmpty,
      );
    },
  );
}

DriftContentQualityReportRepository _uploadingRepository(
  AppDatabase database, {
  required DriftLocalOwnerRepository owners,
  Future<void> Function()? onLocalMutation,
}) => DriftContentQualityReportRepository(
  database,
  owners: owners,
  consentRegistry: DriftConsentRegistry(database),
  uploadPolicy: const ContentReportUploadPolicy.v1(
    deployedRulesRevision: contentQualityReportV1RulesRevision,
    consentVersion: 1,
  ),
  onLocalMutation: onLocalMutation,
);

Future<void> _decideConsent(
  AppDatabase database, {
  required String ownerId,
  required bool accepted,
}) => DriftResearchConsentRepository(database).decide(
  ownerId: ownerId,
  version: 1,
  accepted: accepted,
  decidedAtUtc: DateTime.utc(2026, 8, 24, 11),
);

ContentQualityReport _report({
  required String id,
  ContentReportReason reason = ContentReportReason.text,
  String? comment,
  DateTime? submittedAtUtc,
}) => ContentQualityReport(
  id: id,
  contentIdentity: const ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: 'word:station',
    revision: 4,
  ),
  reason: reason,
  comment: comment,
  submittedAtUtc: submittedAtUtc ?? DateTime.utc(2026, 8, 24, 12),
);

Future<List<QueryRow>> _reportOutbox(AppDatabase database) =>
    database.customSelect('''
      SELECT entity_id, operation_kind, payload_version, base_revision
      FROM outbox_operations
      WHERE entity_type = 'contentQualityReport'
      ORDER BY operation_id
    ''').get();

Future<Map<String, int>> _protectedCounts(AppDatabase database) async =>
    <String, int>{
      'content': await _count(database, 'content_manifests'),
      'words': await _count(database, 'vocabulary_words'),
      'attempts': await _count(database, 'answer_attempts'),
      'srs': await _count(database, 'srs_states'),
    };

Future<int> _count(AppDatabase database, String table) => database
    .customSelect('SELECT COUNT(*) AS count FROM $table')
    .map((row) => row.read<int>('count'))
    .getSingle();
