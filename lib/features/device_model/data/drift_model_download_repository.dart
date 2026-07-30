import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../application/model_download_manager.dart';
import '../domain/model_lifecycle.dart';

final class DriftModelDownloadRepository implements ModelDownloadRepository {
  const DriftModelDownloadRepository(this.database);

  final AppDatabase database;

  @override
  Future<ModelDownloadRecord?> find(String id) async {
    final row = await (database.select(
      database.modelDownloads,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> save(ModelDownloadRecord record) async {
    await database
        .into(database.modelDownloads)
        .insertOnConflictUpdate(_companion(record));
  }

  @override
  Future<void> activate(ModelDownloadRecord record) {
    return database.transaction(() async {
      await (database.update(database.modelDownloads)..where(
            (table) => table.state.equals(ModelDownloadState.active.name),
          ))
          .write(
            ModelDownloadsCompanion(
              state: Value(ModelDownloadState.ready.name),
              updatedAtUtcMs: Value(record.updatedAtUtc.millisecondsSinceEpoch),
            ),
          );
      await database
          .into(database.modelDownloads)
          .insertOnConflictUpdate(
            _companion(record.copyWith(state: ModelDownloadState.active)),
          );
    });
  }

  ModelDownloadsCompanion _companion(ModelDownloadRecord record) {
    if (!record.updatedAtUtc.isUtc) {
      throw ArgumentError.value(
        record.updatedAtUtc,
        'updatedAtUtc',
        'must be UTC',
      );
    }
    return ModelDownloadsCompanion(
      id: Value(record.id),
      modelVersion: Value(record.modelVersion),
      sourceUrl: Value(record.sourceUrl),
      expectedChecksum: Value(record.expectedChecksum),
      expectedBytes: Value(record.expectedBytes),
      downloadedBytes: Value(record.downloadedBytes),
      retryCount: Value(record.retryCount),
      state: Value(record.state.name),
      localPath: Value(record.localPath),
      failureCode: Value(record.failureCode?.name),
      updatedAtUtcMs: Value(record.updatedAtUtc.millisecondsSinceEpoch),
    );
  }

  ModelDownloadRecord _fromRow(ModelDownload row) {
    return ModelDownloadRecord(
      id: row.id,
      modelVersion: row.modelVersion,
      sourceUrl: row.sourceUrl,
      expectedChecksum: row.expectedChecksum,
      expectedBytes: row.expectedBytes,
      downloadedBytes: row.downloadedBytes,
      retryCount: row.retryCount,
      state: _parseEnum(
        ModelDownloadState.values,
        row.state,
        'model download state',
      ),
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtUtcMs,
        isUtc: true,
      ),
      localPath: row.localPath,
      failureCode: row.failureCode == null
          ? null
          : _parseEnum(
              ModelFailureCode.values,
              row.failureCode!,
              'model failure code',
            ),
    );
  }

  T _parseEnum<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw StateError('Unknown $field.');
  }
}
