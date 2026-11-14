import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_local_content_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/local_content_report.dart';

LocalContentReportDraft report({
  String id = 'report-1',
  String spelling = 'station',
  LocalContentReportReason reason =
      LocalContentReportReason.translationMismatch,
  String? sentence,
  int revision = 7,
}) => LocalContentReportDraft(
  id: id,
  sourceKind: 'localSource',
  sourceId: 'local-source:synthetic',
  sourceRevision: revision,
  spelling: spelling,
  meaning: 'สถานี',
  sentence: sentence,
  reason: reason,
  createdAtUtc: DateTime.utc(2026, 11, 14),
);

void main() {
  late AppDatabase db;
  late DriftLocalContentReportRepository repository;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftLocalContentReportRepository(db);
    await db.customStatement(
      "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1),('owner-b','localGuest',1,0)",
    );
  });
  tearDown(() => db.close());

  test(
    'queue stores only explicit source snapshot and exact retry is a no-op',
    () async {
      final draft = report(sentence: 'Meet me at the station.');
      await repository.queue(expectedOwnerId: 'owner-a', report: draft);
      final before = await db.select(db.localContentReports).getSingle();
      expect(
        (
          before.id,
          before.ownerId,
          before.sourceKind,
          before.sourceId,
          before.sourceRevision,
          before.spelling,
          before.meaning,
          before.sentence,
          before.reason,
          before.createdAtUtcMs,
        ),
        (
          'report-1',
          'owner-a',
          'localSource',
          'local-source:synthetic',
          7,
          'station',
          'สถานี',
          'Meet me at the station.',
          'translationMismatch',
          DateTime.utc(2026, 11, 14).millisecondsSinceEpoch,
        ),
      );
      await repository.queue(expectedOwnerId: 'owner-a', report: draft);
      expect(await db.select(db.localContentReports).get(), [before]);
      expect(
        (await repository.watchReports('owner-a').first).map((row) => row.id),
        ['report-1'],
      );
      expect(await repository.watchReports('owner-b').first, isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
      expect(await db.select(db.researchConsents).get(), isEmpty);
      expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
    },
  );

  test(
    'same ID with changed evidence is rejected without replacing it',
    () async {
      await repository.queue(expectedOwnerId: 'owner-a', report: report());
      final before = await db.select(db.localContentReports).getSingle();
      await expectLater(
        repository.queue(
          expectedOwnerId: 'owner-a',
          report: report(reason: LocalContentReportReason.exampleSpellingError),
        ),
        throwsStateError,
      );
      expect(await db.select(db.localContentReports).get(), [before]);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );

  test('inactive or changed owner cannot queue a local report', () async {
    await expectLater(
      repository.queue(expectedOwnerId: 'owner-b', report: report()),
      throwsStateError,
    );
    await db.customStatement(
      "UPDATE local_owners SET is_active=CASE WHEN id='owner-b' THEN 1 ELSE 0 END",
    );
    await expectLater(
      repository.queue(expectedOwnerId: 'owner-a', report: report()),
      throwsStateError,
    );
    expect(await db.select(db.localContentReports).get(), isEmpty);
    expect(await db.select(db.outboxOperations).get(), isEmpty);
  });

  test(
    'empty, excessive and invalid revision inputs fail before insert',
    () async {
      for (final invalid in [
        report(id: ''),
        report(spelling: ' '),
        report(revision: 0),
        report(spelling: 'x' * 10000),
        report(sentence: 'x' * 10000),
      ]) {
        await expectLater(
          repository.queue(expectedOwnerId: 'owner-a', report: invalid),
          throwsArgumentError,
        );
      }
      expect(await db.select(db.localContentReports).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );

  test('queued source snapshot survives file reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-local-report-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}synthetic.sqlite',
    );
    var local = AppDatabase(NativeDatabase(file));
    try {
      await local.customStatement(
        "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1)",
      );
      await DriftLocalContentReportRepository(
        local,
      ).queue(expectedOwnerId: 'owner-a', report: report());
      await local.close();
      local = AppDatabase(NativeDatabase(file));
      final rows = await DriftLocalContentReportRepository(
        local,
      ).watchReports('owner-a').first;
      expect(rows.map((r) => r.id), ['report-1']);
      expect(await local.select(local.outboxOperations).get(), isEmpty);
    } finally {
      await local.close();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      expect(
        actual.startsWith(
          '$temp${Platform.pathSeparator}lexiquest-local-report-',
        ),
        isTrue,
      );
      await directory.delete(recursive: true);
    }
  });
}
