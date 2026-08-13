import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_feature_override_store.dart';

void main() {
  test(
    'persisted emergency override survives registry reconstruction',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final now = DateTime.utc(2026, 8, 9, 12);
      addTearDown(database.close);

      await store.setEmergencyOff(
        Feature.aiTutor,
        updatedAtUtc: now,
        source: 'local-test',
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
        overrides: await store.load(nowUtc: now),
      );
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(registry.isVisible(Feature.aiTutor), isFalse);
      expect(registry.isEnabled(Feature.aiTutor), isFalse);
    },
  );

  test('TTL override is active strictly before its UTC expiry', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final store = RuntimeFeatureOverrideStore(database);
    final now = DateTime.utc(2026, 8, 9, 12);
    addTearDown(database.close);

    await store.setEmergencyOff(
      Feature.objectScanner,
      updatedAtUtc: now,
      expiresAtUtc: now.add(const Duration(hours: 1)),
    );
    expect(await store.load(nowUtc: now), {
      Feature.objectScanner: FeatureState.emergencyOff,
    });
    expect(await store.load(nowUtc: now.add(const Duration(minutes: 59))), {
      Feature.objectScanner: FeatureState.emergencyOff,
    });
    expect(
      await store.load(nowUtc: now.add(const Duration(hours: 1))),
      isEmpty,
    );
  });

  test(
    'controller applies and persists an emergency change atomically',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      final now = DateTime.utc(2026, 8, 9, 12);
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
      );
      addTearDown(database.close);

      await controls.emergencyOff(Feature.aiTutor, source: 'operator');
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(await store.load(nowUtc: now), {
        Feature.aiTutor: FeatureState.emergencyOff,
      });

      await controls.clear(Feature.aiTutor);
      expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
      expect(await store.load(nowUtc: now), isEmpty);
    },
  );

  test(
    'controller expiry callback restores the build default at exact UTC',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      var now = DateTime.utc(2026, 8, 9, 12);
      Duration? scheduledDelay;
      void Function()? scheduledCallback;
      var cancelledTimers = 0;
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
        scheduleExpiry: (delay, callback) {
          scheduledDelay = delay;
          scheduledCallback = callback;
          return () => cancelledTimers += 1;
        },
      );
      addTearDown(() async {
        controls.dispose();
        registry.dispose();
        await database.close();
      });

      await controls.initialize();
      await controls.emergencyOff(
        Feature.aiTutor,
        source: 'operator',
        expiresAtUtc: now.add(const Duration(hours: 1)),
      );
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(scheduledDelay, const Duration(hours: 1));

      now = now.add(const Duration(hours: 1));
      scheduledCallback!();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
      expect(cancelledTimers, greaterThanOrEqualTo(1));
    },
  );

  test(
    'cancelled TTL callbacks cannot replace permanent later TTL or clear state',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      var now = DateTime.utc(2026, 8, 9, 12);
      final scheduled = <_RecordedExpiry>[];
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
        scheduleExpiry: (delay, callback) {
          final expiry = _RecordedExpiry(delay, callback);
          scheduled.add(expiry);
          return expiry.cancel;
        },
      );
      addTearDown(() async {
        controls.dispose();
        registry.dispose();
        await database.close();
      });

      await controls.emergencyOff(
        Feature.aiTutor,
        expiresAtUtc: now.add(const Duration(hours: 1)),
      );
      final beforePermanent = scheduled.single;
      await controls.emergencyOff(Feature.aiTutor);
      expect(beforePermanent.cancelled, isTrue);
      beforePermanent.callback();
      await _flushRuntimeFeatureCallbacks();
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect((await store.loadSnapshot(nowUtc: now)).nextExpiryUtc, isNull);

      await controls.emergencyOff(
        Feature.aiTutor,
        expiresAtUtc: now.add(const Duration(hours: 2)),
      );
      final beforeLaterTtl = scheduled.last;
      await controls.emergencyOff(
        Feature.aiTutor,
        expiresAtUtc: now.add(const Duration(hours: 3)),
      );
      final laterTtl = scheduled.last;
      expect(beforeLaterTtl.cancelled, isTrue);
      beforeLaterTtl.callback();
      await _flushRuntimeFeatureCallbacks();
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(
        (await store.loadSnapshot(nowUtc: now)).nextExpiryUtc,
        now.add(const Duration(hours: 3)),
      );

      await controls.clear(Feature.aiTutor);
      expect(laterTtl.cancelled, isTrue);
      laterTtl.callback();
      await _flushRuntimeFeatureCallbacks();
      expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
      expect(await store.load(nowUtc: now), isEmpty);
    },
  );

  test(
    'an early TTL callback stays off and schedules only the remainder',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      var now = DateTime.utc(2026, 8, 9, 12);
      final scheduled = <_RecordedExpiry>[];
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
        scheduleExpiry: (delay, callback) {
          final expiry = _RecordedExpiry(delay, callback);
          scheduled.add(expiry);
          return expiry.cancel;
        },
      );
      addTearDown(() async {
        controls.dispose();
        registry.dispose();
        await database.close();
      });

      await controls.emergencyOff(
        Feature.aiTutor,
        expiresAtUtc: now.add(const Duration(hours: 1)),
      );
      final early = scheduled.single;
      now = now.add(const Duration(minutes: 15));
      early.callback();
      await _flushRuntimeFeatureCallbacks();

      expect(early.cancelled, isTrue);
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(scheduled, hasLength(2));
      expect(scheduled.last.delay, const Duration(minutes: 45));
    },
  );

  test('disposed controls fence a late durable snapshot load', () async {
    final store = _DelayedOverrideStore();
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final controls = RuntimeFeatureControls(
      store: store,
      registry: registry,
      nowUtc: () => DateTime.utc(2026, 8, 9, 12),
    );
    addTearDown(registry.dispose);

    final initialization = controls.initialize();
    controls.dispose();
    store.complete(
      const RuntimeFeatureOverrideSnapshot(
        overrides: {Feature.aiTutor: FeatureState.emergencyOff},
        nextExpiryUtc: null,
      ),
    );
    await initialization;

    expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
  });

  test(
    'later clear wins when an earlier durable write completes late',
    () async {
      final store = _DelayedMutationStore();
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      final now = DateTime.utc(2026, 8, 9, 12);
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
      );
      addTearDown(() {
        controls.dispose();
        registry.dispose();
      });

      final emergency = controls.emergencyOff(Feature.aiTutor);
      await store.setStarted.future;
      final clear = controls.clear(Feature.aiTutor);
      store.allowSet.complete();
      await Future.wait<void>([emergency, clear]);

      expect(await store.load(nowUtc: now), isEmpty);
      expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
    },
  );

  test('concurrent kills for different features are both accepted', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final store = RuntimeFeatureOverrideStore(database);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final now = DateTime.utc(2026, 8, 9, 12);
    final controls = RuntimeFeatureControls(
      store: store,
      registry: registry,
      nowUtc: () => now,
    );
    addTearDown(() async {
      controls.dispose();
      registry.dispose();
      await database.close();
    });

    final aiKill = controls.emergencyOff(Feature.aiTutor);
    final scannerKill = controls.emergencyOff(Feature.objectScanner);
    await Future.wait<void>([aiKill, scannerKill]);

    expect(await store.load(nowUtc: now), {
      Feature.aiTutor: FeatureState.emergencyOff,
      Feature.objectScanner: FeatureState.emergencyOff,
    });
    expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
    expect(registry.stateOf(Feature.objectScanner), FeatureState.emergencyOff);
  });

  test(
    'a committed kill is live before a later queued mutation completes',
    () async {
      final store = _BlockedSecondMutationStore();
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      final now = DateTime.utc(2026, 8, 9, 12);
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
      );
      addTearDown(() {
        if (!store.allowSecond.isCompleted) store.allowSecond.complete();
        controls.dispose();
        registry.dispose();
      });

      final committed = controls.emergencyOff(Feature.aiTutor);
      final blocked = controls.emergencyOff(Feature.objectScanner);
      await committed;
      await store.secondStarted.future;

      expect(
        registry.stateOf(Feature.aiTutor),
        FeatureState.emergencyOff,
        reason: 'a successful durable kill must not wait on later work',
      );

      store.allowSecond.complete();
      await blocked;
    },
  );

  test('later rejected mutation reloads an earlier accepted kill', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final store = RuntimeFeatureOverrideStore(database);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final now = DateTime.utc(2026, 8, 9, 12);
    final controls = RuntimeFeatureControls(
      store: store,
      registry: registry,
      nowUtc: () => now,
    );
    addTearDown(() async {
      controls.dispose();
      registry.dispose();
      await database.close();
    });

    final accepted = controls.emergencyOff(Feature.aiTutor);
    final rejected = controls.emergencyOff(Feature.objectScanner, source: ' ');
    await accepted;
    await expectLater(rejected, throwsArgumentError);

    expect(await store.load(nowUtc: now), {
      Feature.aiTutor: FeatureState.emergencyOff,
    });
    expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
    expect(registry.stateOf(Feature.objectScanner), FeatureState.limited);
  });

  test(
    'durable TTL stays fail-closed and scheduled when snapshot reload fails',
    () async {
      var now = DateTime.utc(2026, 8, 9, 12);
      final store = _WriteThenFailLoadStore(() => now);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      void Function()? expiryCallback;
      final controls = RuntimeFeatureControls(
        store: store,
        registry: registry,
        nowUtc: () => now,
        scheduleExpiry: (_, callback) {
          expiryCallback = callback;
          return () {};
        },
      );
      addTearDown(() {
        controls.dispose();
        registry.dispose();
      });

      await expectLater(
        controls.emergencyOff(
          Feature.aiTutor,
          expiresAtUtc: now.add(const Duration(hours: 1)),
        ),
        throwsStateError,
      );
      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(expiryCallback, isNotNull);

      now = now.add(const Duration(hours: 1));
      expiryCallback!();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(registry.stateOf(Feature.aiTutor), FeatureState.limited);
    },
  );
}

final class _DelayedOverrideStore implements RuntimeFeatureOverrideRepository {
  final Completer<RuntimeFeatureOverrideSnapshot> _load =
      Completer<RuntimeFeatureOverrideSnapshot>();

  void complete(RuntimeFeatureOverrideSnapshot snapshot) {
    _load.complete(snapshot);
  }

  @override
  Future<void> clear(Feature feature) async {}

  @override
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async =>
      (await _load.future).overrides;

  @override
  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  }) => _load.future;

  @override
  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) async {}
}

Future<void> _flushRuntimeFeatureCallbacks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _RecordedExpiry {
  _RecordedExpiry(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
  }
}

final class _DelayedMutationStore implements RuntimeFeatureOverrideRepository {
  final Completer<void> setStarted = Completer<void>();
  final Completer<void> allowSet = Completer<void>();
  final Map<Feature, FeatureState> _overrides = <Feature, FeatureState>{};

  @override
  Future<void> clear(Feature feature) async {
    _overrides.remove(feature);
  }

  @override
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async =>
      Map<Feature, FeatureState>.unmodifiable(_overrides);

  @override
  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  }) async => RuntimeFeatureOverrideSnapshot(
    overrides: Map<Feature, FeatureState>.unmodifiable(_overrides),
    nextExpiryUtc: null,
  );

  @override
  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) async {
    setStarted.complete();
    await allowSet.future;
    _overrides[feature] = FeatureState.emergencyOff;
  }
}

final class _WriteThenFailLoadStore
    implements RuntimeFeatureOverrideRepository {
  _WriteThenFailLoadStore(this.nowUtc);

  final DateTime Function() nowUtc;
  DateTime? _expiry;
  var _remainingLoadFailures = 1;

  @override
  Future<void> clear(Feature feature) async {
    _expiry = null;
  }

  @override
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async =>
      (await loadSnapshot(nowUtc: nowUtc)).overrides;

  @override
  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  }) async {
    if (_remainingLoadFailures > 0) {
      _remainingLoadFailures -= 1;
      throw StateError('injected snapshot failure');
    }
    final expiry = _expiry;
    final active = expiry != null && nowUtc.isBefore(expiry);
    return RuntimeFeatureOverrideSnapshot(
      overrides: active
          ? const {Feature.aiTutor: FeatureState.emergencyOff}
          : const {},
      nextExpiryUtc: active ? expiry : null,
    );
  }

  @override
  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) async {
    _expiry = expiresAtUtc;
  }
}

final class _BlockedSecondMutationStore
    implements RuntimeFeatureOverrideRepository {
  final Completer<void> secondStarted = Completer<void>();
  final Completer<void> allowSecond = Completer<void>();
  final Map<Feature, FeatureState> _overrides = <Feature, FeatureState>{};

  @override
  Future<void> clear(Feature feature) async {
    _overrides.remove(feature);
  }

  @override
  Future<Map<Feature, FeatureState>> load({required DateTime nowUtc}) async =>
      Map<Feature, FeatureState>.unmodifiable(_overrides);

  @override
  Future<RuntimeFeatureOverrideSnapshot> loadSnapshot({
    required DateTime nowUtc,
  }) async => RuntimeFeatureOverrideSnapshot(
    overrides: Map<Feature, FeatureState>.unmodifiable(_overrides),
    nextExpiryUtc: null,
  );

  @override
  Future<void> setEmergencyOff(
    Feature feature, {
    required DateTime updatedAtUtc,
    DateTime? expiresAtUtc,
    String source = 'local',
  }) async {
    if (feature == Feature.objectScanner) {
      secondStarted.complete();
      await allowSecond.future;
    }
    _overrides[feature] = FeatureState.emergencyOff;
  }
}
