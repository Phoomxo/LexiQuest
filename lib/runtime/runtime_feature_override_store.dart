import 'dart:async';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart' as db;
import 'registries/feature_registry.dart';
import 'runtime_flag_namespaces.dart';

/// Persists local emergency feature controls in the existing runtime table.
///
/// This store deliberately makes no remote-source claim. A future remote
/// refresh may write the same contract after its own authenticity checks.
abstract interface class RuntimeFeatureOverrideRepository {
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc});

  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  });

  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  });

  Future<void> clear(Feature feature, {required DateTime updatedAtUtc});
}

final class RuntimeFeatureOverrideStore
    implements RuntimeFeatureOverrideRepository {
  const RuntimeFeatureOverrideStore(this._database);

  static const String _keyPrefix =
      RuntimeFlagNamespaces.featureEmergencyOffPrefix;

  final db.AppDatabase _database;

  @override
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async {
    return (await loadSnapshot(nowUtc: nowUtc)).overrides;
  }

  @override
  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc, 'nowUtc');
    final rows = await _database.select(_database.runtimeFlags).get();
    final overrides = <Feature, FeatureState>{};
    DateTime? nextExpiryUtc;
    for (final row in rows) {
      if (!row.key.startsWith(_keyPrefix) || !row.boolValue) continue;
      final expiresAtUtcMs = row.expiresAtUtcMs;
      if (expiresAtUtcMs != null &&
          nowUtc.millisecondsSinceEpoch >= expiresAtUtcMs) {
        continue;
      }
      final feature = _featureNamed(row.key.substring(_keyPrefix.length));
      if (feature != null) {
        overrides[feature] = FeatureState.emergencyOff;
        if (expiresAtUtcMs != null) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(
            expiresAtUtcMs,
            isUtc: true,
          );
          if (nextExpiryUtc == null || expiry.isBefore(nextExpiryUtc)) {
            nextExpiryUtc = expiry;
          }
        }
      }
    }
    return RuntimeFeatureOverrideSnapshot(
      overrides: Map<Feature, FeatureState>.unmodifiable(overrides),
      nextExpiryUtc: nextExpiryUtc,
    );
  }

  Future<RuntimeFeatureDurableDecision> loadDecision(
    Feature feature, {
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc, 'nowUtc');
    final row =
        await (_database.select(_database.runtimeFlags)..where(
              (candidate) => candidate.key.equals('$_keyPrefix${feature.name}'),
            ))
            .getSingleOrNull();
    if (row == null) return const RuntimeFeatureDurableDecision.missing();
    final source = row.source;
    final expiresAtUtcMs = row.expiresAtUtcMs;
    if (source.isEmpty ||
        source != source.trim() ||
        row.updatedAtUtcMs < 0 ||
        (expiresAtUtcMs != null && expiresAtUtcMs <= row.updatedAtUtcMs)) {
      throw StateError('corrupt durable runtime feature override');
    }
    return RuntimeFeatureDurableDecision(
      emergencyOff:
          row.boolValue &&
          (expiresAtUtcMs == null ||
              nowUtc.millisecondsSinceEpoch < expiresAtUtcMs),
      epoch: (
        present: true,
        storedEmergencyOff: row.boolValue,
        source: source,
        updatedAtUtcMs: row.updatedAtUtcMs,
        expiresAtUtcMs: expiresAtUtcMs,
      ),
    );
  }

  @override
  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) {
    _requireUtc(updatedAtUtc, 'updatedAtUtc');
    if (expiresAtUtc != null) {
      _requireUtc(expiresAtUtc, 'expiresAtUtc');
      if (!expiresAtUtc.isAfter(updatedAtUtc)) {
        throw ArgumentError.value(
          expiresAtUtc,
          'expiresAtUtc',
          'must be later than updatedAtUtc',
        );
      }
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

  @override
  Future<void> clear(Feature feature, {required DateTime updatedAtUtc}) {
    _requireUtc(updatedAtUtc, 'updatedAtUtc');
    return _database
        .into(_database.runtimeFlags)
        .insert(
          db.RuntimeFlagsCompanion.insert(
            key: '$_keyPrefix${feature.name}',
            boolValue: false,
            source: const Value('local-clear'),
            updatedAtUtcMs: updatedAtUtc.millisecondsSinceEpoch,
            expiresAtUtcMs: const Value(null),
          ),
          mode: InsertMode.insertOrReplace,
        );
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

final class RuntimeFeatureOverrideSnapshot {
  const RuntimeFeatureOverrideSnapshot({
    required this.overrides,
    required this.nextExpiryUtc,
  });

  final Map<Feature, FeatureState> overrides;
  final DateTime? nextExpiryUtc;
}

typedef RuntimeFeatureDecisionEpoch = ({
  bool present,
  bool storedEmergencyOff,
  String source,
  int? updatedAtUtcMs,
  int? expiresAtUtcMs,
});

final class RuntimeFeatureDurableDecision {
  const RuntimeFeatureDurableDecision({
    required this.emergencyOff,
    required this.epoch,
  });

  const RuntimeFeatureDurableDecision.missing()
    : emergencyOff = false,
      epoch = const (
        present: false,
        storedEmergencyOff: false,
        source: '',
        updatedAtUtcMs: null,
        expiresAtUtcMs: null,
      );

  final bool emergencyOff;
  final RuntimeFeatureDecisionEpoch epoch;
}

typedef RuntimeFeatureTimerCancellation = void Function();
typedef RuntimeFeatureExpiryScheduler =
    RuntimeFeatureTimerCancellation Function(
      Duration delay,
      void Function() callback,
    );

RuntimeFeatureTimerCancellation _scheduleRuntimeFeatureExpiry(
  Duration delay,
  void Function() callback,
) {
  final timer = Timer(delay, callback);
  return timer.cancel;
}

/// Applies emergency controls to the live registry and durable store.
final class RuntimeFeatureControls {
  RuntimeFeatureControls({
    required this.store,
    required this.registry,
    required this.nowUtc,
    this.scheduleExpiry,
  });

  final RuntimeFeatureOverrideRepository store;
  final RuntimeFeatureRegistry registry;
  final DateTime Function() nowUtc;
  final RuntimeFeatureExpiryScheduler? scheduleExpiry;
  static const _unavailableAfterDispose =
      'Runtime feature controls are disposed.';

  int _generation = 0;
  bool _disposed = false;
  RuntimeFeatureTimerCancellation? _cancelExpiryTimer;
  Future<void> _operationTail = Future<void>.value();

  Future<void> initialize() => reload();

  Future<void> reload() {
    _requireActive();
    final generation = _beginGeneration();
    return _enqueue(() => _loadAndApply(generation));
  }

  Future<void> emergencyOff(
    Feature feature, {
    String source = 'local',
    DateTime? expiresAtUtc,
  }) async {
    _requireActive();
    final generation = _beginGeneration();
    return _enqueue(() async {
      try {
        await store.setEmergencyOff(
          feature,
          updatedAtUtc: nowUtc(),
          source: source,
          expiresAtUtc: expiresAtUtc,
        );
      } catch (error, stackTrace) {
        await _reloadAfterRejectedMutation(generation);
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (_disposed) return;
      registry.emergencyOff(feature);
      if (!_isCurrent(generation)) return;
      try {
        await _loadAndApply(generation);
      } catch (error, stackTrace) {
        final expiry = expiresAtUtc;
        if (expiry != null && _isCurrent(generation)) {
          _scheduleExpiryAt(generation, expiry);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> clear(Feature feature) async {
    _requireActive();
    final generation = _beginGeneration();
    return _enqueue(() async {
      try {
        await store.clear(feature, updatedAtUtc: nowUtc());
      } catch (error, stackTrace) {
        await _reloadAfterRejectedMutation(generation);
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (_disposed) return;
      registry.clearOverride(feature);
      if (!_isCurrent(generation)) return;
      await _loadAndApply(generation);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _cancelTimer();
  }

  int _beginGeneration() {
    _generation += 1;
    _cancelTimer();
    return _generation;
  }

  Future<void> _loadAndApply(int generation) async {
    final snapshot = await store.loadSnapshot(nowUtc: nowUtc());
    if (!_isCurrent(generation)) return;
    for (final feature in Feature.values) {
      final override = snapshot.overrides[feature];
      if (override == null) {
        registry.clearOverride(feature);
      } else {
        registry.setOverride(feature, override);
      }
    }
    if (!_isCurrent(generation)) return;
    final expiry = snapshot.nextExpiryUtc;
    if (expiry == null) return;
    _scheduleExpiryAt(generation, expiry);
  }

  void _scheduleExpiryAt(int generation, DateTime expiry) {
    final delay = expiry.difference(nowUtc());
    final scheduler = scheduleExpiry ?? _scheduleRuntimeFeatureExpiry;
    _cancelExpiryTimer = scheduler(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!_isCurrent(generation)) return;
        unawaited(reload().onError((_, _) {}));
      },
    );
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  void _cancelTimer() {
    _cancelExpiryTimer?.call();
    _cancelExpiryTimer = null;
  }

  void _requireActive() {
    if (_disposed) throw StateError(_unavailableAfterDispose);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _reloadAfterRejectedMutation(int generation) async {
    if (!_isCurrent(generation)) return;
    try {
      await _loadAndApply(generation);
    } on Object {
      // Preserve the mutation failure as the primary error. A later explicit
      // reload can recover if the durable reader itself is unavailable.
    }
  }
}
