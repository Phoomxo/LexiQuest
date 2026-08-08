import 'package:drift/drift.dart';

import '../data/local/app_database.dart' as db;
import 'registries/feature_registry.dart';

/// Persists local emergency feature controls in the existing runtime table.
///
/// This store deliberately makes no remote-source claim. A future remote
/// refresh may write the same contract after its own authenticity checks.
final class RuntimeFeatureOverrideStore {
  const RuntimeFeatureOverrideStore(this._database);

  static const String _keyPrefix = 'feature_emergency_off:';

  final db.AppDatabase _database;

  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async {
    _requireUtc(nowUtc, 'nowUtc');
    final rows = await _database.select(_database.runtimeFlags).get();
    final overrides = <Feature, FeatureState>{};
    for (final row in rows) {
      if (!row.key.startsWith(_keyPrefix) || !row.boolValue) continue;
      // TTL controls are deliberately unsupported until a live expiry
      // scheduler exists; ignore externally written TTL rows as well.
      if (row.expiresAtUtcMs != null) continue;
      final feature = _featureNamed(row.key.substring(_keyPrefix.length));
      if (feature != null) {
        overrides[feature] = FeatureState.emergencyOff;
      }
    }
    return overrides;
  }

  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) {
    _requireUtc(updatedAtUtc, 'updatedAtUtc');
    if (expiresAtUtc != null) {
      throw UnsupportedError(
        'TTL feature controls require a live expiry scheduler.',
      );
    }
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty) {
      throw ArgumentError.value(source, 'source', 'must not be empty');
    }
    return _database
        .into(_database.runtimeFlags)
        .insert(
          db.RuntimeFlagsCompanion.insert(
            key: '$_keyPrefix${feature.name}',
            boolValue: true,
            source: Value(normalizedSource),
            updatedAtUtcMs: updatedAtUtc.millisecondsSinceEpoch,
            expiresAtUtcMs: Value(expiresAtUtc?.millisecondsSinceEpoch),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> clear(Feature feature) {
    return (_database.delete(
      _database.runtimeFlags,
    )..where((row) => row.key.equals('$_keyPrefix${feature.name}'))).go();
  }

  static Feature? _featureNamed(String name) {
    for (final feature in Feature.values) {
      if (feature.name == name) return feature;
    }
    return null;
  }

  static void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, name, 'must be UTC');
    }
  }
}

/// Applies emergency controls to the live registry and durable store.
final class RuntimeFeatureControls {
  const RuntimeFeatureControls({
    required this.store,
    required this.registry,
    required this.nowUtc,
  });

  final RuntimeFeatureOverrideStore store;
  final RuntimeFeatureRegistry registry;
  final DateTime Function() nowUtc;

  Future<void> emergencyOff(Feature feature, {String source = 'local'}) async {
    await store.setEmergencyOff(
      feature,
      updatedAtUtc: nowUtc(),
      source: source,
    );
    registry.emergencyOff(feature);
  }

  Future<void> clear(Feature feature) async {
    await store.clear(feature);
    registry.clearOverride(feature);
  }
}
