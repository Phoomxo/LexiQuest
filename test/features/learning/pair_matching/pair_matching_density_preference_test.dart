import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';

SessionConfiguration baseline() => SessionConfiguration.validated(
  schemaVersion: 1,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'synthetic-owner',
  mode: LessonMode.matching,
  itemCount: 4,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 2,
  timing: const SessionTiming.timed(Duration(seconds: 120)),
  packIdentity: null,
  protocolId: 'protocol:local-standard',
  protocolVersion: '1',
  protocolLimitsIdentity: 'synthetic-limits',
);
void main() {
  test('fallback six is rejected before constructing a usable preference', () {
    expect(
      () => PairDensityPreference(
        density: PairDensity.standard6,
        provenance: PairDensityProvenance.fallback,
      ),
      throwsArgumentError,
    );
    expect(
      () => baseline().withPairDensityPreference(
        PairDensityPreference(
          density: PairDensity.standard6,
          provenance: PairDensityProvenance.fallback,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => PairDensityPreference.fromJson({
        'schemaVersion': 1,
        'density': 'standard6',
        'provenance': 'fallback',
      }),
      throwsFormatException,
    );
    for (final provenance in PairDensityProvenance.values) {
      for (final density in PairDensity.values) {
        if (provenance == PairDensityProvenance.fallback &&
            density == PairDensity.standard6) {
          continue;
        }
        final preference = PairDensityPreference(
          density: density,
          provenance: provenance,
        );
        final configuration = baseline().withPairDensityPreference(preference);
        expect(
          SessionConfiguration.fromStableSerialization(
            configuration.stableSerialization,
          ),
          configuration,
        );
      }
    }
  });
  test(
    'v1 remains byte identical; optional Pair density uses exact v2 roundtrip',
    () {
      final v1 = baseline();
      final old = v1.stableSerialization;
      expect(
        SessionConfiguration.fromStableSerialization(old).stableSerialization,
        old,
      );
      final v2 = v1.withPairDensityPreference(
        PairDensityPreference(
          density: PairDensity.standard6,
          provenance: PairDensityProvenance.accessibility,
        ),
      );
      expect(v2.schemaVersion, 2);
      expect(v1.stableSerialization, old);
      final decoded = SessionConfiguration.fromStableSerialization(
        v2.stableSerialization,
      );
      expect(decoded.pairDensityPreference!.density, PairDensity.standard6);
      expect(
        decoded.pairDensityPreference!.provenance,
        PairDensityProvenance.accessibility,
      );
      final j = jsonDecode(v2.stableSerialization) as Map;
      (j['configuration'] as Map)['extra'] = true;
      expect(
        () => SessionConfiguration.fromStableSerialization(jsonEncode(j)),
        throwsA(isA<SessionConfigurationResetRequired>()),
      );
    },
  );
  test(
    'fallback persists one-time handled state through existing owner matching store',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'synthetic-owner',
              createdAtUtcMs: 1,
            ),
          );
      final v2 = baseline().withPairDensityPreference(
        PairDensityPreference(
          density: PairDensity.compact4,
          provenance: PairDensityProvenance.fallback,
        ),
      );
      await DriftSessionConfigurationStore(
        db,
      ).saveForActiveOwner(v2, updatedAtUtc: DateTime.utc(2026, 9, 5));
      final recovered = await DriftSessionConfigurationStore(
        db,
      ).read(ownerId: 'synthetic-owner', mode: LessonMode.matching);
      expect(
        recovered!.pairDensityInputs.resolve(canPrompt: true),
        PairDensity.compact4,
      );
      expect(
        await DriftSessionConfigurationStore(
          db,
        ).read(ownerId: 'another-synthetic-owner', mode: LessonMode.matching),
        isNull,
      );
      expect(await db.select(db.sessionConfigurations).get(), hasLength(1));
      expect(await db.select(db.learningSessions).get(), isEmpty);
      final artifact = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => DateTime.utc(2026, 9, 5),
      ).prepareActive();
      final envelope = jsonDecode(utf8.decode(artifact.bytes)) as Map;
      final tables = (envelope['content'] as Map)['tables'] as List;
      final table = tables.cast<Map>().singleWhere(
        (t) => t['alias'] == 'sessionConfigurations',
      );
      final record = (table['records'] as List).cast<Map>().singleWhere(
        (r) => !r.containsKey('recordCount'),
      );
      expect(
        (record['sessionConfiguration'] as Map)['pairDensityPreference'],
        v2.pairDensityPreference!.toJson(),
      );
      await DriftSessionConfigurationStore(
        db,
      ).clear(ownerId: 'synthetic-owner', mode: LessonMode.matching);
      expect(await db.select(db.sessionConfigurations).get(), isEmpty);
    },
  );
}
