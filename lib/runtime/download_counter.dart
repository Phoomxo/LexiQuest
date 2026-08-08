import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart' as db;

/// Durable event counter for completed model downloads.
///
/// Each completion is a separate row so repeated downloads are observable
/// without adding a release-blocking schema migration.
final class DownloadCounter {
  DownloadCounter(
    this._database, {
    required this.generateEventId,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? _systemNowUtc;

  final db.AppDatabase _database;
  final String Function() generateEventId;
  final DateTime Function() _nowUtc;

  Future<void> increment(String version) async {
    final normalizedVersion = version.trim();
    if (normalizedVersion.isEmpty) {
      throw ArgumentError.value(version, 'version', 'must not be empty');
    }
    final eventId = generateEventId().trim();
    if (eventId.isEmpty) {
      throw StateError('Download event id must not be empty.');
    }
    final prefix = _keyPrefix(normalizedVersion);
    await _database
        .into(_database.runtimeFlags)
        .insert(
          db.RuntimeFlagsCompanion.insert(
            key: '$prefix$eventId',
            boolValue: false,
            source: const Value('download_counter'),
            updatedAtUtcMs: _nowUtc().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<int> count(String version) async {
    final prefix = _keyPrefix(version.trim());
    final rows = await _database.select(_database.runtimeFlags).get();
    return rows.where((row) => row.key.startsWith(prefix)).length;
  }

  static String _keyPrefix(String version) {
    final encoded = base64Url.encode(utf8.encode(version)).replaceAll('=', '');
    return 'download_count:$encoded:';
  }

  static DateTime _systemNowUtc() => DateTime.now().toUtc();
}
