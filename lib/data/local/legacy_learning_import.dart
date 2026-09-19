import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'app_database.dart';
import 'app_database_open_policy.dart';

// Pinned historical learning_database.dart at 7b8ac6cc, schema1.
const _columns = <String, List<String>>{
  'learning_commits': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'commit_id',
    'recorded_at_utc',
    'record_count',
    'content_fingerprint',
  ],
  'associations': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'association_id',
    'word_key',
    'cue_type',
    'cue_text',
    'origin',
    'strength',
    'success_count',
    'failure_count',
  ],
  'reading_sessions': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'session_id',
    'cefr_level',
    'target_word_keys_json',
    'mix_policy_version',
    'content_id',
    'content_version',
    'current_stage',
    'started_at_utc',
    'completed_at_utc',
    'abandoned_at_utc',
  ],
  'recall_attempts': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'attempt_id',
    'session_id',
    'word_key',
    'recall_mode',
    'cue_level',
    'correctness',
    'response_time_ms',
    'confidence',
    'context_id',
    'algorithm_version',
    'occurred_at_utc',
  ],
  'memory_states': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'word_key',
    'strength',
    'cue_dependency',
    'stability',
    'difficulty',
    'lapse_count',
    'last_reviewed_at_utc',
    'next_due_at_utc',
    'last_error_type',
    'algorithm_version',
  ],
  'learning_events': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'event_id',
    'occurred_at_utc',
    'activity',
    'content_id',
    'category_id',
    'cefr_level',
    'skill',
    'correct',
    'score',
    'response_time_ms',
    'attempt_number',
    'app_version',
    'build_id',
  ],
  'sync_outbox': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'outbox_id',
    'event_id',
    'operation',
    'payload_json',
    'acknowledged_at_utc',
    'attempt_count',
  ],
  'deletion_tombstones': [
    'owner_id',
    'schema_version',
    'created_at_utc',
    'updated_at_utc',
    'tombstone_id',
    'entity_type',
    'entity_id',
    'deleted_at_utc',
  ],
};

/// Versioned snapshot, not a conversion to current learning evidence.
final class LegacyLearningSnapshot {
  LegacyLearningSnapshot._(this.records, this.ownerId);
  final Map<String, List<Map<String, Object?>>> records;
  final String? ownerId;

  static LegacyLearningSnapshot read(
    File file, {
    Database Function(String path)? openReadOnly,
  }) {
    const maxBytes = 64 * 1024 * 1024;
    if (file.lengthSync() > maxBytes) _reject();
    final source =
        openReadOnly?.call(file.path) ??
        sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      source.execute('BEGIN');
      if (source.select('PRAGMA user_version').single.values.single != 1 ||
          source.select('PRAGMA quick_check').single.values.single != 'ok')
        _reject();
      final tables = source
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'])
          .toSet();
      if (tables.length != _columns.length ||
          !tables.containsAll(_columns.keys))
        _reject();
      // Admit the entire read-only transaction before transferring payloads
      // into Dart. Include WAL rows; file length alone is not a snapshot bound.
      // Six bytes per input byte bounds JSON escaping. Column names, scalar
      // text and punctuation are charged conservatively as well.
      var admittedBytes = 0;
      var admittedRows = 0;
      for (final entry in _columns.entries) {
        final columns = source
            .select('PRAGMA table_info(${entry.key})')
            .map((row) => row['name'])
            .toSet();
        if (columns.length != entry.value.length ||
            !columns.containsAll(entry.value)) {
          _reject();
        }
        final costs = entry.value
            .map(
              (column) =>
                  "(CASE WHEN typeof($column) IN ('text','blob') "
                  "THEN 6 * length(CAST($column AS BLOB)) ELSE 32 END)"
                  " + ${column.length + 6}",
            )
            .join(' + ');
        final budget = source
            .select(
              'SELECT count(*) AS n, coalesce(sum(cost), 0) AS bytes FROM '
              '(SELECT 2 + $costs AS cost FROM ${entry.key} LIMIT 100001)',
            )
            .single;
        admittedRows += budget['n'] as int;
        admittedBytes += budget['bytes'] as int;
        if (admittedRows > 100000 || admittedBytes > maxBytes) _reject();
      }
      final records = <String, List<Map<String, Object?>>>{};
      final owners = <String>{};
      var bytes = 0;
      var count = 0;
      for (final entry in _columns.entries) {
        final columns = source
            .select('PRAGMA table_info(${entry.key})')
            .map((r) => r['name'])
            .toSet();
        if (columns.length != entry.value.length ||
            !columns.containsAll(entry.value))
          _reject();
        final rows = source.select('SELECT * FROM ${entry.key} LIMIT 100001');
        count += rows.length;
        if (count > 100000) _reject();
        records[entry.key] = rows.map((row) {
          final values = <String, Object?>{
            for (final column in entry.value) column: row[column],
          };
          final owner = values['owner_id'];
          if (owner is! String ||
              owner.isEmpty ||
              owner.trim() != owner ||
              owner.length > 200 ||
              values['schema_version'] != 1)
            _reject();
          owners.add(owner as String);
          for (final value in values.values) {
            if (value != null && value is! String && value is! num) _reject();
            if (value is double && !value.isFinite) _reject();
          }
          for (final field in ['created_at_utc', 'updated_at_utc']) {
            if (values[field] is! int || (values[field] as int) < 0) _reject();
          }
          bytes += utf8.encode(jsonEncode(values)).length;
          if (bytes > maxBytes) _reject();
          return values;
        }).toList();
      }
      // The old store has no authoritative active-owner mapping. Never infer
      // an account identity from row order or combine multiple people's data.
      if (owners.length > 1) _reject();
      return LegacyLearningSnapshot._(records, owners.firstOrNull);
    } finally {
      source.close();
    }
  }

  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(records))).toString();

  /// All rows and their owner are committed together, or none are written.
  Future<void> importInto(AppDatabase target) async {
    await target.transaction(() async {
      if ((await target.select(target.localOwners).get()).isNotEmpty) _reject();
      if (ownerId == null) return;
      await target
          .into(target.localOwners)
          .insert(LocalOwnersCompanion.insert(id: ownerId!, createdAtUtcMs: 0));
      for (final entry in records.entries) {
        for (final row in entry.value) {
          final payload = jsonEncode(row);
          final id = sha256
              .convert(utf8.encode('${entry.key}:$payload'))
              .toString();
          await target.customInsert(
            'INSERT INTO legacy_learning_records(id,owner_id,source_table,payload_json) VALUES(?,?,?,?)',
            variables: [
              Variable<String>(id),
              Variable<String>(ownerId!),
              Variable<String>(entry.key),
              Variable<String>(payload),
            ],
            updates: {target.legacyLearningRecords},
          );
        }
      }
    });
  }
}

/// Source stays read-only. Destination appears only after complete import.
Future<void> importLegacyLearningFiles(
  List<File> sources,
  File destination,
) async {
  final lock = File(
    '${destination.path}.import.lock',
  ).openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
    if (destination.existsSync()) return;
    final snapshots = sources.map(LegacyLearningSnapshot.read).toList();
    if (snapshots.isEmpty) return;
    if (snapshots.any((s) => s.fingerprint != snapshots.first.fingerprint))
      _reject();
    final temporaryDirectory = await destination.parent.createTemp(
      '.legacy-import-',
    );
    final temporary = File('${temporaryDirectory.path}/lexiquest.sqlite');
    final database = AppDatabase(NativeDatabase(temporary));
    try {
      await snapshots.first.importInto(database);
      final foreignKeys = await database
          .customSelect('PRAGMA foreign_key_check')
          .get();
      if (foreignKeys.isNotEmpty) _reject();
      await database.close();
      // Same-directory volume, complete SQLite in DELETE journal mode.
      if (destination.existsSync()) _reject();
      await temporary.rename(destination.path);
    } finally {
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    }
  } on AppDatabaseOpenException {
    rethrow;
  } catch (_) {
    throw const AppDatabaseOpenException(
      AppDatabaseOpenError.legacyImportRequired,
    );
  } finally {
    lock.closeSync();
  }
}

Never _reject() => throw const AppDatabaseOpenException(
  AppDatabaseOpenError.legacyImportRequired,
);
