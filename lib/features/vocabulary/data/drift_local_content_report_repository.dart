import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/local_content_report.dart';

final class DriftLocalContentReportRepository {
  const DriftLocalContentReportRepository(this.database);

  final db.AppDatabase database;

  Stream<bool> watchOwnerActive(String ownerId) =>
      (database.select(database.localOwners)
            ..where((row) => row.isActive.equals(true)))
          .watch()
          .map((rows) => rows.length == 1 && rows.single.id == ownerId)
          .distinct();

  Stream<List<LocalContentReportDraft>> watchReports(String ownerId) {
    _text(ownerId, 'ownerId', 256);
    final query = database.select(database.localContentReports)
      ..where((row) => row.ownerId.equals(ownerId))
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAtUtcMs),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.watch().map(
      (rows) => List.unmodifiable(
        rows.map(
          (row) => LocalContentReportDraft(
            id: row.id,
            sourceKind: row.sourceKind,
            sourceId: row.sourceId,
            sourceRevision: row.sourceRevision,
            spelling: row.spelling,
            meaning: row.meaning,
            sentence: row.sentence,
            reason: LocalContentReportReason.values.byName(row.reason),
            createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
              row.createdAtUtcMs,
              isUtc: true,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> queue({
    required String expectedOwnerId,
    required LocalContentReportDraft report,
  }) async {
    _text(expectedOwnerId, 'expectedOwnerId', 256);
    _text(report.id, 'id', 256);
    _text(report.sourceKind, 'sourceKind', 64);
    _text(report.sourceId, 'sourceId', 256);
    _text(report.spelling, 'spelling', 480);
    _text(report.meaning, 'meaning', 2000);
    if (report.sentence case final sentence?) _text(sentence, 'sentence', 4096);
    if (report.sourceRevision <= 0) {
      throw ArgumentError.value(report.sourceRevision, 'sourceRevision');
    }
    if (!report.createdAtUtc.isUtc ||
        report.createdAtUtc.microsecondsSinceEpoch < 0 ||
        report.createdAtUtc.microsecondsSinceEpoch % 1000 != 0) {
      throw ArgumentError.value(
        report.createdAtUtc,
        'createdAtUtc',
        'must be nonnegative UTC at millisecond precision',
      );
    }
    await database.transaction(() async {
      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).get();
      if (active.length != 1 || active.single.id != expectedOwnerId) {
        throw StateError('Report owner changed');
      }
      final existing = await (database.select(
        database.localContentReports,
      )..where((row) => row.id.equals(report.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.ownerId != expectedOwnerId ||
            existing.sourceKind != report.sourceKind ||
            existing.sourceId != report.sourceId ||
            existing.sourceRevision != report.sourceRevision ||
            existing.spelling != report.spelling ||
            existing.meaning != report.meaning ||
            existing.sentence != report.sentence ||
            existing.reason != report.reason.name ||
            existing.createdAtUtcMs !=
                report.createdAtUtc.millisecondsSinceEpoch) {
          throw StateError('Report ID already has different evidence');
        }
        return;
      }
      await database
          .into(database.localContentReports)
          .insert(
            db.LocalContentReportsCompanion.insert(
              id: report.id,
              ownerId: expectedOwnerId,
              sourceKind: report.sourceKind,
              sourceId: report.sourceId,
              sourceRevision: report.sourceRevision,
              spelling: report.spelling,
              meaning: report.meaning,
              sentence: Value(report.sentence),
              reason: report.reason.name,
              createdAtUtcMs: report.createdAtUtc.millisecondsSinceEpoch,
            ),
          );
    });
  }
}

void _text(String value, String field, int maxBytes) {
  if (value.trim().isEmpty || utf8.encode(value).length > maxBytes) {
    throw ArgumentError.value(
      value,
      field,
      'must be nonempty and at most $maxBytes UTF-8 bytes',
    );
  }
}
