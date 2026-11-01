import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/study_reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary;
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/configured_quiz_harness.dart';
import 'content_report_test_support.dart';

void main() {
  late ConfiguredQuizHarness h;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    h.now = DateTime.utc(2026, 11, 1, 12);
  });
  tearDown(() => h.close());

  test(
    'file reopen preserves unknown delivery and the exact received receipt',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-report-lifecycle-',
      );
      h = await ConfiguredQuizHarness.open(
        file: File('${directory.path}/synthetic.sqlite'),
      );
      h.now = DateTime.utc(2026, 11, 1, 12);
      addTearDown(() async {
        await h.close();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$root${Platform.pathSeparator}lexiquest-report-lifecycle-',
          ),
        );
        for (final entity in directory.listSync(followLinks: false)) {
          expect(entity, isA<File>());
          expect(entity.parent.absolute.path, directory.absolute.path);
          await entity.delete();
        }
        await directory.delete();
      });
      final payload = syntheticReport(id: 'content-report:synthetic-reopen');
      var queue = _queue(h);
      await queue.put(expectedOwnerId: configuredOwnerId, payload: payload);
      await queue.markUnconfirmed(
        expectedOwnerId: configuredOwnerId,
        reportId: payload.reportId,
        expectedReportSha256: payload.reportSha256,
      );
      h = await h.reopen();
      queue = _queue(h);
      final beforeRead = await h.snapshot();
      final pending = (await queue.read(
        expectedOwnerId: configuredOwnerId,
        reportId: payload.reportId,
      ))!;
      expect(pending.delivery, ContentReportDelivery.unconfirmed);
      expect(pending.payload.reportJson, payload.reportJson);
      expect(pending.payload.reportSha256, payload.reportSha256);
      expect(pending.localRevision, 2);
      expect(await h.snapshot(), beforeRead);

      final acknowledged = await queue.acknowledge(
        expectedOwnerId: configuredOwnerId,
        expectedFirebaseUid: configuredFirebaseUid,
        expectedReportSha256: payload.reportSha256,
        acknowledgement: _ack(payload, configuredFirebaseUid),
      );
      h = await h.reopen();
      queue = _queue(h);
      final received = (await queue.read(
        expectedOwnerId: configuredOwnerId,
        reportId: payload.reportId,
      ))!;
      expect(received.delivery, ContentReportDelivery.received);
      expect(received.acknowledgedFirebaseUid, configuredFirebaseUid);
      expect(
        received.acknowledgement!.toJson(),
        acknowledged.acknowledgement!.toJson(),
      );
      expect(received.payload.reportJson, payload.reportJson);
      final resolved = _ack(payload, configuredFirebaseUid, resolved: true);
      await queue.acknowledge(
        expectedOwnerId: configuredOwnerId,
        expectedFirebaseUid: configuredFirebaseUid,
        expectedReportSha256: payload.reportSha256,
        acknowledgement: resolved,
      );
      final beforeReplay = await h.snapshot();
      await queue.acknowledge(
        expectedOwnerId: configuredOwnerId,
        expectedFirebaseUid: configuredFirebaseUid,
        expectedReportSha256: payload.reportSha256,
        acknowledgement: resolved,
      );
      await expectLater(
        queue.acknowledge(
          expectedOwnerId: configuredOwnerId,
          expectedFirebaseUid: configuredFirebaseUid,
          expectedReportSha256: payload.reportSha256,
          acknowledgement: _ack(payload, configuredFirebaseUid),
        ),
        throwsA(isA<ContentReportException>()),
      );
      expect(await h.snapshot(), beforeReplay);
    },
  );

  for (final targetHasPreference in [false, true]) {
    test(
      'merge retains unknown report facts and never enables the target reminder (targetPref=$targetHasPreference)',
      () async {
        if (targetHasPreference) {
          await _activate(h, configuredOtherOwnerId);
          await _reminder(
            h,
            configuredOtherOwnerId,
            enabled: false,
            minute: 7 * 60,
          );
          await _activate(h, configuredOwnerId);
        }
        await h.database.customUpdate(
          "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = ?",
          variables: [const drift.Variable(configuredOwnerId)],
          updates: {h.database.localOwners},
        );
        await _reminder(h, configuredOwnerId, enabled: true, minute: 19 * 60);
        final payload = syntheticReport(id: 'content-report:synthetic-merge');
        final queue = _queue(h);
        await queue.put(expectedOwnerId: configuredOwnerId, payload: payload);
        final prior = await queue.markUnconfirmed(
          expectedOwnerId: configuredOwnerId,
          reportId: payload.reportId,
          expectedReportSha256: payload.reportSha256,
        );
        final targetPreference = await _preferenceRows(
          h.database,
          configuredOtherOwnerId,
        );
        final result = await _upgrade(h).upgrade(
          activeOwnerId: configuredOwnerId,
          firebaseUid: 'synthetic-configured-uid-b',
        );
        expect(result.targetOwnerId, configuredOtherOwnerId);
        final moved = (await queue.read(
          expectedOwnerId: configuredOtherOwnerId,
          reportId: payload.reportId,
        ))!;
        expect(moved.payload.reportJson, payload.reportJson);
        expect(moved.payload.reportSha256, payload.reportSha256);
        expect(moved.payload.queuedAtUtc, payload.queuedAtUtc);
        expect(moved.delivery, prior.delivery);
        expect(moved.localRevision, prior.localRevision);
        expect(moved.acknowledgement, isNull);
        expect(await _preferenceRows(h.database, configuredOwnerId), isEmpty);
        expect(
          await _preferenceRows(h.database, configuredOtherOwnerId),
          targetPreference,
        );
        final beforeDeniedWrite = await h.snapshot();
        await expectLater(
          queue.put(
            expectedOwnerId: configuredOwnerId,
            payload: syntheticReport(id: 'content-report:retired-owner'),
          ),
          throwsA(isA<ContentReportException>()),
        );
        expect(await h.snapshot(), beforeDeniedWrite);
        expect(await h.count('content_reports'), 1);
      },
    );
  }

  test(
    'a received report retains its original UID after merge and is unavailable offline to the new account',
    () async {
      final payload = syntheticReport(
        id: 'content-report:synthetic-received-merge',
      );
      final queue = _queue(h);
      await queue.put(expectedOwnerId: configuredOwnerId, payload: payload);
      final acknowledged = await queue.acknowledge(
        expectedOwnerId: configuredOwnerId,
        expectedFirebaseUid: configuredFirebaseUid,
        expectedReportSha256: payload.reportSha256,
        acknowledgement: _ack(payload, configuredFirebaseUid),
      );
      await _upgrade(h).upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      final beforeRead = await h.snapshot();
      await expectLater(
        queue.read(
          expectedOwnerId: configuredOtherOwnerId,
          reportId: payload.reportId,
        ),
        throwsA(isA<ContentReportException>()),
      );
      await expectLater(
        queue.watchOwner(configuredOtherOwnerId).first,
        throwsA(isA<ContentReportException>()),
      );
      final exported = await _export(h, configuredOtherOwnerId);
      final row = (exported['content_reports'] as List).single as Map;
      expect(row['report_json'], payload.reportJson);
      expect(row['acknowledged_firebase_uid'], configuredFirebaseUid);
      expect(
        jsonDecode(row['acknowledgement_json'] as String),
        acknowledged.acknowledgement!.toJson(),
      );
      expect(await h.snapshot(), beforeRead);
    },
  );

  test(
    'personal export and local deletion cover both new tables while retaining the other owner exactly',
    () async {
      final a = syntheticReport(id: 'content-report:synthetic-delete-a');
      final b = syntheticReport(id: 'content-report:synthetic-retain-b');
      await _queue(h).put(expectedOwnerId: configuredOwnerId, payload: a);
      await _reminder(h, configuredOwnerId, enabled: true, minute: 20 * 60);
      await _activate(h, configuredOtherOwnerId);
      await _queue(h).put(expectedOwnerId: configuredOtherOwnerId, payload: b);
      await _reminder(
        h,
        configuredOtherOwnerId,
        enabled: false,
        minute: 8 * 60,
      );
      await _activate(h, configuredOwnerId);
      final otherBefore = await _export(h, configuredOtherOwnerId);
      final beforeExport = await h.snapshot();
      final exported = await _export(h, configuredOwnerId);
      expect(
        (exported['content_reports'] as List).single['report_json'],
        a.reportJson,
      );
      expect(
        (exported['study_reminder_preferences'] as List).single['enabled'],
        1,
      );
      expect(await h.snapshot(), beforeExport);
      final secretPurges = <(String, String)>[];
      final gateway = DriftLocalAccountDeletionGateway(
        h.database,
        nowUtc: () => h.now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          secretPurges.add((ownerId, firebaseUid));
        },
      );
      final cloud = CloudDeletionReceipt(
        receiptId: 'synthetic-content-report-delete',
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-content-report-delete-operation',
        completedAtUtc: h.now,
      );
      final deleted = await gateway.deleteAfterCloud(
        ownerId: configuredOwnerId,
        cloudReceipt: cloud,
      );
      expect(secretPurges, [(configuredOwnerId, configuredFirebaseUid)]);
      expect(await _export(h, configuredOtherOwnerId), otherBefore);
      expect(
        (await _export(h, deleted.newGuestOwnerId))['content_reports'],
        isEmpty,
      );
      expect(await _preferenceRows(h.database, configuredOwnerId), isEmpty);
      expect(await h.count('content_reports'), 1);
      expect(await h.count('study_reminder_preferences'), 1);
      final afterDelete = await h.snapshot();
      final replay = await gateway.deleteAfterCloud(
        ownerId: configuredOwnerId,
        cloudReceipt: cloud,
      );
      expect(replay.newGuestOwnerId, deleted.newGuestOwnerId);
      expect(await h.snapshot(), afterDelete);
    },
  );

  test(
    'the original word writer mirrors the same nine-field snapshot and replays without extra facts',
    () async {
      final queue = _queue(h);
      final writer = DriftWordReportRepository(
        database: h.database,
        ownerWriteCoordinator: h.ownerWrites,
        contentReports: queue,
      );
      final command = await _wordCommand(h);
      final saved = await writer.submit(command);
      final queued = (await queue.read(
        expectedOwnerId: configuredOwnerId,
        reportId: command.id,
      ))!;
      final expectedSnapshot = jsonEncode({
        'version': 'owned-word-report-v1',
        'wordId': configuredWordIds.first,
        'categoryId': configuredCategoryId,
        'wordRevision': 1,
        'spelling': 'station',
        'meaning': 'สถานี',
        'partOfSpeech': 'noun',
        'source': 'manual',
        'cefrLevel': null,
      });
      expect(saved.report.target.snapshotJson, expectedSnapshot);
      expect(queued.payload.target.snapshotJson, expectedSnapshot);
      expect(queued.payload.reportId, command.id);
      expect(queued.payload.queuedAtUtc, command.queuedAtUtc);
      expect(
        queued.payload.target.snapshotSha256,
        saved.report.target.snapshotSha256,
      );
      expect((jsonDecode(queued.payload.target.snapshotJson) as Map).length, 9);
      final afterSave = await h.snapshot();
      expect((await writer.submit(command)).status, SubmitStatus.replayed);
      expect(await h.snapshot(), afterSave);
      expect(await h.count('word_reports'), 1);
      expect(await h.count('content_reports'), 1);
      expect(await h.count('outbox_operations'), 0);
    },
  );

  test(
    'a source guard rejected after both report inserts rolls back every table',
    () async {
      final queue = _queue(h);
      final writer = DriftWordReportRepository(
        database: h.database,
        ownerWriteCoordinator: h.ownerWrites,
        contentReports: queue,
      );
      var observedBothWrites = false;
      final command = await _wordCommand(
        h,
        revalidate: () async {
          if (await h.count('word_reports') == 1 &&
              await h.count('content_reports') == 1) {
            observedBothWrites = true;
            throw StateError('Synthetic source lease retired after collection');
          }
        },
      );
      final before = await h.snapshot();
      await expectLater(writer.submit(command), throwsStateError);
      expect(observedBothWrites, isTrue);
      expect(await h.snapshot(), before);
      final retried = await writer.submit(await _wordCommand(h));
      expect(retried.report.id, command.id);
      expect(await h.count('word_reports'), 1);
      expect(await h.count('content_reports'), 1);
    },
  );
}

DriftContentReportQueue _queue(ConfiguredQuizHarness h) =>
    DriftContentReportQueue(database: h.database, ownerWrites: h.ownerWrites);

Future<void> _activate(ConfiguredQuizHarness h, String owner) => h.database
    .customUpdate(
      'UPDATE local_owners SET is_active = (id = ?)',
      variables: [drift.Variable(owner)],
      updates: {h.database.localOwners},
    )
    .then((_) {});

DriftOwnerUpgradeRepository _upgrade(ConfiguredQuizHarness h) {
  var ids = 0;
  return DriftOwnerUpgradeRepository(
    h.database,
    nowUtc: () => h.now,
    generateConflictId: () => 'synthetic-report-rehome-${++ids}',
    generateOwnerId: () => 'synthetic-report-new-guest',
  );
}

Future<void> _reminder(
  ConfiguredQuizHarness h,
  String owner, {
  required bool enabled,
  required int minute,
}) async {
  await DriftStudyReminderRepository(h.database, h.ownerWrites).writeForOwner(
    ownerId: owner,
    baseRevision: 0,
    choice: StudyReminderChoice(
      enabled: enabled,
      minuteOfDay: minute,
      timezoneId: 'Asia/Bangkok',
    ),
    updatedAtUtc: h.now,
    stillCurrent: () => true,
  );
}

Future<List<Map<String, Object?>>> _preferenceRows(
  AppDatabase database,
  String owner,
) async =>
    (await database
            .customSelect(
              'SELECT * FROM study_reminder_preferences WHERE owner_id = ?',
              variables: [drift.Variable(owner)],
            )
            .get())
        .map((row) => row.data)
        .toList();

Future<Map<String, dynamic>> _export(
  ConfiguredQuizHarness h,
  String owner,
) async {
  final result = await DriftAccountSnapshotBuilder(
    h.database,
    nowUtc: () => h.now,
  ).build(ownerId: owner);
  expect(
    result.coveredScopes,
    containsAll(['content_reports', 'study_reminder_preferences']),
  );
  return (jsonDecode(utf8.decode(result.bytes)) as Map<String, dynamic>)['data']
      as Map<String, dynamic>;
}

ContentReportAcknowledgement _ack(
  ContentReportPayload payload,
  String uid, {
  bool resolved = false,
}) {
  final value = syntheticAcknowledgement(payload).toJson();
  (value['receipt'] as Map)['receiptId'] =
      'content-report-receipt:'
      '${contentReportDigest(jsonEncode([uid, payload.reportId]))}';
  if (resolved) {
    value['moderation'] = {
      'revision': 2,
      'status': 'resolved',
      'decisionId': 'synthetic-lifecycle-decision',
      'publicNote': 'Synthetic content corrected',
      'decidedAtUtc': '2026-11-01T01:00:00.000Z',
    };
  }
  return ContentReportAcknowledgement.fromJson(value);
}

Future<WordReportCommand> _wordCommand(
  ConfiguredQuizHarness h, {
  Future<void> Function()? revalidate,
}) async {
  final row = await (h.database.select(
    h.database.vocabularyWords,
  )..where((word) => word.id.equals(configuredWordIds.first))).getSingle();
  final word = vocabulary.VocabularyWord(
    id: row.id,
    ownerId: row.ownerId,
    categoryId: row.categoryId,
    spelling: row.spelling,
    normalizedSpelling: row.normalizedSpelling,
    meaning: row.meaning,
    normalizedMeaning: row.normalizedMeaning,
    partOfSpeech: row.partOfSpeech,
    cefrLevel: row.cefrLevel,
    source: row.source,
    isGlobal: row.isGlobal,
    localRevision: row.localRevision,
    isDeleted: row.isDeleted,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.createdAtUtcMs,
      isUtc: true,
    ),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.updatedAtUtcMs,
      isUtc: true,
    ),
  );
  return WordReportCommand(
    id: 'word-report:synthetic-lifecycle',
    expectedOwnerId: configuredOwnerId,
    target: WordReportTarget.fromWord(word),
    reason: ReportReason.spelling,
    comment: 'Synthetic selected content review',
    queuedAtUtc: h.now,
    revalidate: revalidate,
  );
}
