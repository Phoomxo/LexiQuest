import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart' as db;
import 'runtime_flag_namespaces.dart';

final class DownloadCountSnapshot {
  const DownloadCountSnapshot({
    required this.retainedCount,
    required this.retentionLimit,
  });

  final int retainedCount;
  final int retentionLimit;

  /// A full retained window may represent exactly [retentionLimit] successes
  /// or a saturated lifetime count. It must not be used for billing.
  bool get mayBeSaturated => retainedCount >= retentionLimit;

  static const boundedWindowSemantics = 'boundedRetainedWindow';

  String get semantics => boundedWindowSemantics;
}

/// Durable, bounded event window for completed model downloads.
///
/// Each retained completion is a separate row. [count] is deliberately a
/// capped diagnostic window, not a lifetime accounting or billing counter.
final class DownloadCounter {
  DownloadCounter(
    this._database, {
    required this.generateEventId,
    DateTime Function()? nowUtc,
    this.maxRetainedEventsPerVersion = defaultMaxRetainedEventsPerVersion,
    this.maxTrackedVersions = defaultMaxTrackedVersions,
  }) : _nowUtc = nowUtc ?? _systemNowUtc {
    if (maxRetainedEventsPerVersion <= 0) {
      throw ArgumentError.value(
        maxRetainedEventsPerVersion,
        'maxRetainedEventsPerVersion',
        'must be positive',
      );
    }
    if (maxTrackedVersions <= 0) {
      throw ArgumentError.value(
        maxTrackedVersions,
        'maxTrackedVersions',
        'must be positive',
      );
    }
  }

  final db.AppDatabase _database;
  final String Function() generateEventId;
  final DateTime Function() _nowUtc;
  final int maxRetainedEventsPerVersion;
  final int maxTrackedVersions;

  static const defaultMaxRetainedEventsPerVersion = 100;
  static const defaultMaxTrackedVersions = 20;

  Future<void> increment(String version) async {
    final eventId = generateEventId().trim();
    await _record(version: version, eventId: eventId, rejectDuplicate: true);
  }

  /// Records a deterministic verified-activation marker idempotently.
  ///
  /// The model manager retries this after validating an already-active file,
  /// so a crash or callback failure after activation can be repaired without
  /// counting cached opens as new downloads.
  Future<void> recordCompletion(String version, String completionId) {
    return _record(
      version: version,
      eventId: completionId.trim(),
      rejectDuplicate: false,
      replaceLegacyMarker: false,
    );
  }

  /// Establishes the stable marker for an already-verified cached artifact.
  ///
  /// Task 7 recorded successful transfers with random UUID markers. On the
  /// first Task 8 cached open, one such legacy marker is transactionally
  /// replaced by the stable marker so an upgrade cannot fabricate a second
  /// transfer. With no marker, this still repairs a callback/crash gap.
  Future<void> reconcileCompletion(String version, String completionId) {
    return _record(
      version: version,
      eventId: completionId.trim(),
      rejectDuplicate: false,
      replaceLegacyMarker: true,
    );
  }

  Future<void> _record({
    required String version,
    required String eventId,
    required bool rejectDuplicate,
    bool replaceLegacyMarker = false,
  }) async {
    final normalizedVersion = _normalizedVersion(version);
    if (eventId.isEmpty || eventId.length > 256) {
      throw StateError('Download event id must contain 1-256 characters.');
    }
    final prefix = _keyPrefix(normalizedVersion);
    final upperPrefix = _rangeUpperBound(prefix);
    final insertedKey = '$prefix$eventId';
    await _database.transaction(() async {
      final inserted = await _database.customUpdate(
        'INSERT OR IGNORE INTO runtime_flags '
        '("key", bool_value, source, updated_at_utc_ms) VALUES (?, 0, ?, ?)',
        variables: [
          Variable<String>(insertedKey),
          const Variable<String>(_source),
          Variable<int>(_nowUtc().toUtc().millisecondsSinceEpoch),
        ],
        updates: {_database.runtimeFlags},
      );
      if (inserted == 0) {
        if (rejectDuplicate) {
          throw StateError('Download completion event already exists.');
        }
        final existing = await _database
            .customSelect(
              'SELECT bool_value, source, expires_at_utc_ms '
              'FROM runtime_flags WHERE "key" = ?',
              variables: [Variable<String>(insertedKey)],
              readsFrom: {_database.runtimeFlags},
            )
            .getSingleOrNull();
        if (existing == null ||
            existing.read<String>('source') != _source ||
            existing.read<bool>('bool_value') ||
            existing.readNullable<int>('expires_at_utc_ms') != null) {
          throw StateError(
            'Download completion key collides with another runtime owner.',
          );
        }
        await _pruneTrackedVersions(
          protectedEncodedVersion: _encodedVersion(normalizedVersion),
          protectedKey: insertedKey,
        );
        return;
      }
      if (replaceLegacyMarker) {
        await _replaceOneLegacyMarker(
          prefix: prefix,
          upperPrefix: upperPrefix,
          stableKey: insertedKey,
        );
      }
      await _pruneTrackedVersions(
        protectedEncodedVersion: _encodedVersion(normalizedVersion),
        protectedKey: insertedKey,
      );
    });
  }

  Future<void> _replaceOneLegacyMarker({
    required String prefix,
    required String upperPrefix,
    required String stableKey,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT "key" FROM runtime_flags '
          'WHERE source = ? AND "key" >= ? AND "key" < ? AND "key" <> ? '
          'ORDER BY updated_at_utc_ms DESC, "key" DESC',
          variables: [
            const Variable<String>(_source),
            Variable<String>(prefix),
            Variable<String>(upperPrefix),
            Variable<String>(stableKey),
          ],
          readsFrom: {_database.runtimeFlags},
        )
        .get();
    String? legacyKey;
    for (final row in rows) {
      final key = row.read<String>('key');
      if (_legacyUuidPattern.hasMatch(key.substring(prefix.length))) {
        legacyKey = key;
        break;
      }
    }
    if (legacyKey == null) return;
    await _database.customUpdate(
      'DELETE FROM runtime_flags WHERE "key" = ? AND source = ?',
      variables: [Variable<String>(legacyKey), const Variable<String>(_source)],
      updates: {_database.runtimeFlags},
    );
  }

  Future<int> count(String version) async {
    final prefix = _keyPrefix(_normalizedVersion(version));
    final upperPrefix = _rangeUpperBound(prefix);
    return _database
        .customSelect(
          'SELECT COUNT(*) AS count FROM runtime_flags '
          'WHERE source = ? AND "key" >= ? AND "key" < ?',
          variables: [
            const Variable<String>(_source),
            Variable<String>(prefix),
            Variable<String>(upperPrefix),
          ],
          readsFrom: {_database.runtimeFlags},
        )
        .map((row) => row.read<int>('count'))
        .getSingle();
  }

  Future<DownloadCountSnapshot> snapshot(String version) async {
    return DownloadCountSnapshot(
      retainedCount: await count(version),
      retentionLimit: maxRetainedEventsPerVersion,
    );
  }

  Future<void> _pruneTrackedVersions({
    required String protectedEncodedVersion,
    required String protectedKey,
  }) async {
    final rootUpperBound = _rangeUpperBound(_rootPrefix);
    final rows = await _database
        .customSelect(
          'SELECT "key", updated_at_utc_ms FROM runtime_flags '
          'WHERE source = ? AND "key" >= ? AND "key" < ?',
          variables: [
            const Variable<String>(_source),
            const Variable<String>(_rootPrefix),
            Variable<String>(rootUpperBound),
          ],
          readsFrom: {_database.runtimeFlags},
        )
        .get();
    final markersByVersion = <String, List<({String key, int updatedAt})>>{};
    for (final row in rows) {
      final key = row.read<String>('key');
      final encodedVersion = _encodedVersionFromKey(key);
      if (encodedVersion == null) {
        await _deleteOwnedMarker(key);
        continue;
      }
      (markersByVersion[encodedVersion] ??= []).add((
        key: key,
        updatedAt: row.read<int>('updated_at_utc_ms'),
      ));
    }
    final newestByVersion = <String, int>{};
    for (final entry in markersByVersion.entries) {
      final markers = entry.value
        ..sort((left, right) {
          final timestamp = right.updatedAt.compareTo(left.updatedAt);
          return timestamp != 0 ? timestamp : right.key.compareTo(left.key);
        });
      final retainedKeys = <String>{};
      if (entry.key == protectedEncodedVersion &&
          markers.any((marker) => marker.key == protectedKey)) {
        retainedKeys.add(protectedKey);
      }
      for (final marker in markers) {
        if (retainedKeys.length >= maxRetainedEventsPerVersion) break;
        retainedKeys.add(marker.key);
      }
      int? newest;
      for (final marker in markers) {
        if (!retainedKeys.contains(marker.key)) {
          await _deleteOwnedMarker(marker.key);
          continue;
        }
        if (newest == null || marker.updatedAt > newest) {
          newest = marker.updatedAt;
        }
      }
      if (newest != null) newestByVersion[entry.key] = newest;
    }
    if (newestByVersion.length <= maxTrackedVersions) return;
    final oldest =
        newestByVersion.entries
            .where((entry) => entry.key != protectedEncodedVersion)
            .toList()
          ..sort((left, right) {
            final timestamp = left.value.compareTo(right.value);
            return timestamp != 0 ? timestamp : left.key.compareTo(right.key);
          });
    final requiredRemoval = newestByVersion.length - maxTrackedVersions;
    for (final entry in oldest.take(requiredRemoval)) {
      final prefix = '$_rootPrefix${entry.key}:';
      await _database.customUpdate(
        'DELETE FROM runtime_flags WHERE source = ? '
        'AND "key" >= ? AND "key" < ?',
        variables: [
          const Variable<String>(_source),
          Variable<String>(prefix),
          Variable<String>(_rangeUpperBound(prefix)),
        ],
        updates: {_database.runtimeFlags},
      );
    }
  }

  Future<void> _deleteOwnedMarker(String key) {
    return _database.customUpdate(
      'DELETE FROM runtime_flags WHERE "key" = ? AND source = ?',
      variables: [Variable<String>(key), const Variable<String>(_source)],
      updates: {_database.runtimeFlags},
    );
  }

  static String _keyPrefix(String version) {
    return '$_rootPrefix${_encodedVersion(version)}:';
  }

  static String _encodedVersion(String version) =>
      base64Url.encode(utf8.encode(version)).replaceAll('=', '');

  static String _normalizedVersion(String version) {
    final normalized = version.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError.value(
        version,
        'version',
        'must contain 1-200 characters',
      );
    }
    return normalized;
  }

  static String? _encodedVersionFromKey(String key) {
    if (!key.startsWith(_rootPrefix)) return null;
    final suffix = key.substring(_rootPrefix.length);
    final separator = suffix.indexOf(':');
    if (separator <= 0 || separator == suffix.length - 1) return null;
    return suffix.substring(0, separator);
  }

  static String _rangeUpperBound(String prefix) {
    return RuntimeFlagNamespaces.prefixUpperBound(prefix);
  }

  static const _source = RuntimeFlagNamespaces.downloadCounterSource;
  static const _rootPrefix = RuntimeFlagNamespaces.downloadCountPrefix;
  static final _legacyUuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
    r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static DateTime _systemNowUtc() => DateTime.now().toUtc();
}
