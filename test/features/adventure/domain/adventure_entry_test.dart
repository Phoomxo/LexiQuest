import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';

void main() {
  test('entry wire codecs are exhaustive and preserve their exact names', () {
    expect(
      TodayExperiencePresentation.values.map((value) => value.wireName),
      <String>['standard', 'adventure'],
    );
    expect(
      AdventureEntryDestination.values.map((value) => value.wireName),
      <String>['learn', 'standardToday', 'adventure'],
    );
    expect(
      AdventureAvailability.values.map((value) => value.wireName),
      <String>[
        'available',
        'hidden',
        'disabled',
        'emergencyOff',
        'missingDependency',
        'invalidCatalog',
        'contentUnavailable',
        'assignmentConflict',
      ],
    );
    expect(
      AdventureFallbackReason.values.map((value) => value.wireName),
      <String>[
        'none',
        'learnerChoseStandard',
        'featureUnavailable',
        'dependencyUnavailable',
        'catalogUnavailable',
        'contentUnavailable',
        'assignmentUnavailable',
        'emergencyOff',
      ],
    );

    for (final value in TodayExperiencePresentation.values) {
      expect(TodayExperiencePresentationCodec.tryDecode(value.wireName), value);
    }
  });

  test('unknown presentation wire values fail closed to no permit', () {
    expect(TodayExperiencePresentationCodec.tryDecode('future'), isNull);
    expect(TodayExperiencePresentationCodec.tryDecode(null), isNull);
    expect(
      () => TodayExperiencePresentationCodec.decode('future'),
      throwsFormatException,
    );
  });

  test('entry request and decision keep immutable version pins', () {
    final occurredAtUtc = DateTime.utc(2026, 9, 4, 9);
    final permit = ActivePresentationPermit(
      permitId: 'permit-001',
      ownerId: 'owner-001',
      assignedPresentation: TodayExperiencePresentation.adventure,
      protocolId: 'amm-pilot',
      protocolVersion: '1.0.0',
      assignmentId: 'assignment-001',
      expiresAtUtc: _expiry,
    );
    final request = AdventureEntryRequest(
      ownerId: 'owner-001',
      entryAttemptId: '018f1f90-7b2d-4d58-8d7d-6d97039ad003',
      occurredAtUtc: occurredAtUtc,
      activePresentationPermit: permit,
    );
    const decision = AdventureProductEntryDecision(
      entryAttemptId: '018f1f90-7b2d-4d58-8d7d-6d97039ad003',
      availability: AdventureAvailability.available,
      destination: AdventureEntryDestination.adventure,
      fallbackReason: AdventureFallbackReason.none,
      catalogId: 'lexiquest.adventure.world',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      permitId: 'permit-001',
      assignmentId: 'assignment-001',
      treatment: 'adventure',
    );

    expect(request.occurredAtUtc, same(occurredAtUtc));
    expect(request.activePresentationPermit, same(permit));
    expect(decision.catalogId, 'lexiquest.adventure.world');
    expect(decision.catalogVersion, '1.0.0');
    expect(decision.catalogSchemaVersion, 1);
  });
}

final _expiry = DateTime.utc(2026, 12, 31);
