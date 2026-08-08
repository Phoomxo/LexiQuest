import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
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
      final legacy = FeatureRegistryFieldAdapter(registry);

      expect(registry.stateOf(Feature.aiTutor), FeatureState.emergencyOff);
      expect(legacy.stateOf(FieldFeature.aiTutor), FieldFeatureState.hidden);
      expect(legacy.isVisible(FieldFeature.aiTutor), isFalse);
    },
  );

  test(
    'TTL override is rejected until a live expiry scheduler exists',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final store = RuntimeFeatureOverrideStore(database);
      final now = DateTime.utc(2026, 8, 9, 12);
      addTearDown(database.close);

    expect(
      () => store.setEmergencyOff(
        Feature.objectScanner,
        updatedAtUtc: now,
        expiresAtUtc: now.add(const Duration(hours: 1)),
      ),
      throwsUnsupportedError,
      );
      expect(await store.load(nowUtc: now), isEmpty);

      await store.clear(Feature.objectScanner);
      expect(await store.load(nowUtc: now), isEmpty);
    },
  );

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
}
