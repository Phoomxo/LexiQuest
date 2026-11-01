import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';

import 'content_report_test_support.dart';

void main() {
  late AppDatabase database;
  late DriftOwnerWriteCoordinator owners;
  late DriftContentReportQueue queue;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement(
      "INSERT INTO local_owners (id,firebase_uid,account_state,created_at_utc_ms,is_active) "
      "VALUES ('owner-a','uid-a','firebaseBound',1,1),('owner-b','uid-b','firebaseBound',2,0)",
    );
    owners = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => DateTime.utc(2026, 11, 1),
      nonceGenerator: () => 'synthetic-report-deletion',
    );
    queue = DriftContentReportQueue(database: database, ownerWrites: owners);
  });
  tearDown(() => database.close());

  test('absent queue reads and watches are pure across all tables', () async {
    final before = await _rows(database);
    expect(
      await queue.read(expectedOwnerId: 'owner-a', reportId: 'none'),
      isNull,
    );
    expect(await queue.watchOwner('owner-a').first, isEmpty);
    expect(await _rows(database), before);
  });

  test(
    'ordinary reporting guard excludes actual controlled relations without writes',
    () async {
      await database.customStatement(
        "INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) "
        "VALUES ('synthetic-ordinary','owner-a','quiz','active',1,'synthetic','synthetic')",
      );
      final before = await _rows(database);
      await queue.requireOrdinarySession(
        expectedOwnerId: 'owner-a',
        sessionId: 'synthetic-ordinary',
        stillCurrent: () => true,
      );
      await expectLater(
        queue.requireOrdinarySession(
          expectedOwnerId: 'owner-b',
          sessionId: 'synthetic-ordinary',
          stillCurrent: () => true,
        ),
        throwsA(isA<ContentReportException>()),
      );
      await expectLater(
        queue.requireOrdinarySession(
          expectedOwnerId: 'owner-a',
          sessionId: 'synthetic-ordinary',
          stillCurrent: () => false,
        ),
        throwsA(isA<ContentReportException>()),
      );
      expect(await _rows(database), before);

      final controlledDatabase = AppDatabase(NativeDatabase.memory());
      try {
        final capture =
            jsonDecode(
                  File(
                    'test/fixtures/populated_schema_v24.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final rows = capture['rows'] as Map<String, dynamic>;
        await controlledDatabase.transaction(() async {
          await controlledDatabase.customStatement(
            'PRAGMA defer_foreign_keys = ON',
          );
          for (final table in rows.entries) {
            for (final raw in table.value as List) {
              final row = raw as Map<String, dynamic>;
              if (table.key == 'runtime_flags' &&
                  row['key'] == 'accountDeletion.ownerWriteIntent') {
                continue;
              }
              await controlledDatabase.customStatement(
                'INSERT INTO "${table.key}" (${row.keys.join(',')}) '
                'VALUES (${List.filled(row.length, '?').join(',')})',
                row.values
                    .map(
                      (value) => value is List
                          ? Uint8List.fromList(value.cast<int>())
                          : value,
                    )
                    .toList(),
              );
            }
          }
        });
        final controlledQueue = DriftContentReportQueue(
          database: controlledDatabase,
          ownerWrites: DriftOwnerWriteCoordinator(
            controlledDatabase,
            nowUtc: () => DateTime.utc(2026, 11, 1),
          ),
        );
        final controlledBefore = await _rows(controlledDatabase);
        final sessions = await controlledDatabase
            .customSelect(
              'SELECT learning_session_id FROM assessment_runs '
              'UNION SELECT learning_session_id FROM measurement_opportunities '
              'WHERE learning_session_id IS NOT NULL',
            )
            .get();
        expect(sessions, isNotEmpty);
        for (final row in sessions) {
          await expectLater(
            controlledQueue.requireOrdinarySession(
              expectedOwnerId: 'owner-a',
              sessionId: row.read<String>('learning_session_id'),
              stillCurrent: () => true,
            ),
            throwsA(isA<ContentReportException>()),
          );
        }
        expect(await _rows(controlledDatabase), controlledBefore);
      } finally {
        await controlledDatabase.close();
      }
    },
  );

  test(
    'same payload replays and conflicting payload cannot replace original',
    () async {
      final payload = syntheticReport();
      await queue.put(expectedOwnerId: 'owner-a', payload: payload);
      final replay = await queue.put(
        expectedOwnerId: 'owner-a',
        payload: payload,
      );
      expect(replay.localRevision, 1);
      expect(replay.payload.reportJson, payload.reportJson);
      final json = jsonDecode(payload.reportJson) as Map<String, dynamic>;
      json['reason'] = 'incorrectMeaning';
      final changed = jsonEncode(json);
      final other = ContentReportPayload.fromStorage(
        reportJson: changed,
        reportSha256: contentReportDigest(changed),
      );
      await expectLater(
        queue.put(expectedOwnerId: 'owner-a', payload: other),
        throwsA(isA<ContentReportException>()),
      );
      expect(
        (await queue.read(
          expectedOwnerId: 'owner-a',
          reportId: payload.reportId,
        ))!.payload.reportJson,
        payload.reportJson,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'unconfirmed delivery persists and receipts advance once without downgrade',
    () async {
      final payload = syntheticReport();
      await queue.put(expectedOwnerId: 'owner-a', payload: payload);
      final first = await queue.markUnconfirmed(
        expectedOwnerId: 'owner-a',
        reportId: payload.reportId,
        expectedReportSha256: payload.reportSha256,
      );
      expect(first.delivery, ContentReportDelivery.unconfirmed);
      expect(
        (await queue.markUnconfirmed(
          expectedOwnerId: 'owner-a',
          reportId: payload.reportId,
          expectedReportSha256: payload.reportSha256,
        )).localRevision,
        first.localRevision,
      );
      final received = _ack(payload);
      final stored = await queue.acknowledge(
        expectedOwnerId: 'owner-a',
        expectedFirebaseUid: 'uid-a',
        expectedReportSha256: payload.reportSha256,
        acknowledgement: received,
      );
      expect(stored.delivery, ContentReportDelivery.received);
      expect(stored.acknowledgedFirebaseUid, 'uid-a');
      expect(
        (await queue.acknowledge(
          expectedOwnerId: 'owner-a',
          expectedFirebaseUid: 'uid-a',
          expectedReportSha256: payload.reportSha256,
          acknowledgement: received,
        )).localRevision,
        stored.localRevision,
      );
      final resolved = _ack(payload, resolved: true);
      await queue.acknowledge(
        expectedOwnerId: 'owner-a',
        expectedFirebaseUid: 'uid-a',
        expectedReportSha256: payload.reportSha256,
        acknowledgement: resolved,
      );
      await expectLater(
        queue.acknowledge(
          expectedOwnerId: 'owner-a',
          expectedFirebaseUid: 'uid-a',
          expectedReportSha256: payload.reportSha256,
          acknowledgement: received,
        ),
        throwsA(isA<ContentReportException>()),
      );
    },
  );

  test('wrong UID receipt and deletion fence cannot mutate reports', () async {
    final payload = syntheticReport();
    await queue.put(expectedOwnerId: 'owner-a', payload: payload);
    final before = await _rows(database);
    await expectLater(
      queue.acknowledge(
        expectedOwnerId: 'owner-a',
        expectedFirebaseUid: 'uid-b',
        expectedReportSha256: payload.reportSha256,
        acknowledgement: _ack(payload),
      ),
      throwsA(isA<ContentReportException>()),
    );
    expect(await _rows(database), before);
    await owners.beginDeletion(
      ownerId: 'owner-a',
      firebaseUid: 'uid-a',
      idempotencyKey: 'synthetic-report-delete',
    );
    final fenced = await _rows(database);
    await expectLater(
      queue.put(
        expectedOwnerId: 'owner-a',
        payload: syntheticReport(id: 'content-report:other'),
      ),
      throwsA(isA<ContentReportException>()),
    );
    await expectLater(
      queue.read(expectedOwnerId: 'owner-a', reportId: payload.reportId),
      throwsA(isA<ContentReportException>()),
    );
    expect(await _rows(database), fenced);
  });

  test(
    'offline receipt from another account is hidden by read and watch',
    () async {
      final payload = syntheticReport();
      await queue.put(expectedOwnerId: 'owner-a', payload: payload);
      await queue.acknowledge(
        expectedOwnerId: 'owner-a',
        expectedFirebaseUid: 'uid-a',
        expectedReportSha256: payload.reportSha256,
        acknowledgement: _ack(payload),
      );
      await database.customUpdate(
        "UPDATE local_owners SET firebase_uid = 'uid-c' WHERE id = 'owner-a'",
        updates: {database.localOwners},
      );
      await expectLater(
        queue.read(expectedOwnerId: 'owner-a', reportId: payload.reportId),
        throwsA(isA<ContentReportException>()),
      );
      await expectLater(
        queue.watchOwner('owner-a').first,
        throwsA(isA<ContentReportException>()),
      );
    },
  );

  test(
    'owner invalidation wakes an idle watch and remains retired after ABA',
    () async {
      final errors = <Object>[];
      final initial = Completer<void>();
      final sub = queue.watchOwner('owner-a').listen((_) {
        if (!initial.isCompleted) initial.complete();
      }, onError: (Object error) => errors.add(error));
      await initial.future;
      await database.customUpdate(
        "UPDATE local_owners SET is_active = 1 - is_active",
        updates: {database.localOwners},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(errors, isNotEmpty);
      await database.customUpdate(
        "UPDATE local_owners SET is_active = 1 - is_active",
        updates: {database.localOwners},
      );
      await sub.cancel();
    },
  );

  test(
    'full personal export includes local report bytes and received UID',
    () async {
      final payload = syntheticReport();
      await queue.put(expectedOwnerId: 'owner-a', payload: payload);
      final export = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
      ).build(ownerId: 'owner-a');
      final data =
          jsonDecode(utf8.decode(export.bytes)) as Map<String, dynamic>;
      final row =
          ((data['data'] as Map)['content_reports'] as List).single as Map;
      expect(row['report_json'], payload.reportJson);
      expect(row['report_sha256'], payload.reportSha256);
      expect(data['coveredScopes'], contains('study_reminder_preferences'));
    },
  );
}

ContentReportAcknowledgement _ack(
  ContentReportPayload payload, {
  bool resolved = false,
}) {
  final value = syntheticAcknowledgement(payload).toJson();
  (value['receipt'] as Map)['receiptId'] =
      'content-report-receipt:'
      '${contentReportDigest(jsonEncode(['uid-a', payload.reportId]))}';
  if (resolved) {
    value['moderation'] = {
      'revision': 2,
      'status': 'resolved',
      'decisionId': 'synthetic-decision',
      'publicNote': 'Synthetic correction reviewed',
      'decidedAtUtc': '2026-11-01T01:00:00.000Z',
    };
  }
  return ContentReportAcknowledgement.fromJson(value);
}

Future<Map<String, Object?>> _rows(AppDatabase database) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect(
                  'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
                )
                .get())
            .map((row) => row.data)
            .toList(),
};
