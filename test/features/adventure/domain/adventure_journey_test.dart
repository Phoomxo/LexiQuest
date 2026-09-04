import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';

void main() {
  test('journey enums are closed and keep exact wire names', () {
    expect(AdventureNodeState.values.map((value) => value.name), <String>[
      'hidden',
      'locked',
      'available',
      'current',
      'completed',
      'unavailable',
    ]);
    expect(
      AdventureSnapshotFreshness.values.map((value) => value.name),
      <String>['current', 'stale', 'unavailable', 'corrupt'],
    );
    expect(
      AdventureJourneyAuthority.values.map((value) => value.name),
      <String>[
        'today',
        'quest',
        'streak',
        'achievement',
        'reward',
        'history',
        'packCompletion',
      ],
    );
  });

  test('snapshot and nested collections are immutable', () {
    final snapshot = AdventureJourneySnapshot(
      ownerId: 'owner-001',
      evaluatedAtUtc: DateTime.utc(2026, 9, 4),
      sourceEvaluatedAtUtc: DateTime.utc(2026, 9, 4),
      catalogId: 'catalog',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      freshness: AdventureSnapshotFreshness.current,
      dependencyStates:
          <AdventureJourneyAuthority, AdventureJourneyDependencyState>{
            for (final authority in AdventureJourneyAuthority.values)
              authority: AdventureJourneyDependencyState.ready,
          },
      nodes: const <AdventureNodeSnapshot>[],
      primaryMission: null,
      inputFingerprintSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(() => snapshot.dependencyStates.clear(), throwsUnsupportedError);
    expect(() => snapshot.nodes.clear(), throwsUnsupportedError);
  });
}
