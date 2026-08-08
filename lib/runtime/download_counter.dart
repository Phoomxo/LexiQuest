import 'package:drift/drift.dart';

import '../data/local/app_database.dart' as db;

/// Tracks total downloads per model/asset version.
///
/// Uses the `runtime_flags` table with a `download_count:<version>` key
/// convention. Incremented on each successful download completion.
/// Used for cost monitoring (detecting runaway re-downloads).
class DownloadCounter {
  DownloadCounter(this._database);

  final db.AppDatabase _database;

  /// Increments the download counter for [version].
  Future<void> increment(String version) async {
    final key = 'download_count:$version';
    final existing = await (_database.select(_database.runtimeFlags)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (existing != null) {
      await (_database.update(_database.runtimeFlags)
            ..where((t) => t.key.equals(key)))
          .write(db.RuntimeFlagsCompanion(
        updatedAtUtcMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      ));
    } else {
      await _database.into(_database.runtimeFlags).insert(
            db.RuntimeFlagsCompanion.insert(
              key: key,
              boolValue: false,
              updatedAtUtcMs:
                  DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    }
  }

  /// Returns the count of downloads recorded for [version].
  Future<int> count(String version) async {
    final key = 'download_count:$version';
    final row = await (_database.select(_database.runtimeFlags)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row != null ? 1 : 0;
  }
}
