import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('TC-PMT-001 Pair Matching remains the hidden f10 learning boundary', () {
    final snapshot = _currentBoundary(database);

    expect(() => _validateBoundary(snapshot), returnsNormally);
    expect(snapshot.registration.isDeliverable, isFalse);
  });

  test('negative mutations reject f45, a main route, and a star table', () {
    final baseline = _currentBoundary(database);
    final mutations = <_PairBoundarySnapshot>[
      baseline.copyWith(featureIds: <String>[...baseline.featureIds, 'f45']),
      baseline.copyWith(
        appRoutes: <String>[...baseline.appRoutes, 'pairMatching'],
      ),
      baseline.copyWith(
        tableNames: <String>[...baseline.tableNames, 'pair_stars'],
      ),
    ];

    for (final mutation in mutations) {
      expect(() => _validateBoundary(mutation), throwsStateError);
    }
  });
}

_PairBoundarySnapshot _currentBoundary(AppDatabase database) {
  final f10 = allTcasIdeaIntegrationCatalog.records.singleWhere(
    (record) => record.id == FeatureContractId.f10,
  );
  final registration = buildLessonModeRegistry().find(LessonMode.matching)!;
  return _PairBoundarySnapshot(
    featureIds: FeatureContractId.values.map((id) => id.name).toList(),
    pairContractId: f10.id.name,
    pairContractName: f10.name,
    appRoutes: AppRoute.values.map((route) => route.name).toList(),
    tableNames: database.allTables
        .map((table) => table.actualTableName)
        .toList(),
    registration: registration,
  );
}

void _validateBoundary(_PairBoundarySnapshot snapshot) {
  if (snapshot.featureIds.length != 44 ||
      snapshot.featureIds.first != 'f01' ||
      snapshot.featureIds.last != 'f44' ||
      snapshot.featureIds.contains('f45')) {
    throw StateError('Pair Matching must not create f45.');
  }
  if (snapshot.pairContractId != 'f10' ||
      snapshot.pairContractName != 'Matching Mode' ||
      snapshot.registration.mode != LessonMode.matching ||
      snapshot.registration.feature != Feature.quiz ||
      snapshot.registration.productionEntryId != 'home/learn/quiz' ||
      snapshot.registration.routeName != 'learning/matching') {
    throw StateError('Pair launch must resolve through the existing f10 path.');
  }
  if (snapshot.appRoutes.length != 4 ||
      snapshot.appRoutes.join(',') != 'login,register,emailVerification,home') {
    throw StateError('Pair Matching must not create a main destination.');
  }
  if (snapshot.tableNames.length != 48 ||
      snapshot.tableNames.any(
        (name) => name.contains('pair_star') || name.contains('matching_star'),
      )) {
    throw StateError('Pair Matching must not create a star table.');
  }
}

final class _PairBoundarySnapshot {
  const _PairBoundarySnapshot({
    required this.featureIds,
    required this.pairContractId,
    required this.pairContractName,
    required this.appRoutes,
    required this.tableNames,
    required this.registration,
  });

  final List<String> featureIds;
  final String pairContractId;
  final String pairContractName;
  final List<String> appRoutes;
  final List<String> tableNames;
  final LessonModeRegistration registration;

  _PairBoundarySnapshot copyWith({
    List<String>? featureIds,
    List<String>? appRoutes,
    List<String>? tableNames,
  }) => _PairBoundarySnapshot(
    featureIds: featureIds ?? this.featureIds,
    pairContractId: pairContractId,
    pairContractName: pairContractName,
    appRoutes: appRoutes ?? this.appRoutes,
    tableNames: tableNames ?? this.tableNames,
    registration: registration,
  );
}
