import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_session_composer.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';

void main() {
  test('FR-034 composer uses only canonical Today work', () async {
    final fixture = await _fixture();
    final plan = await const CanonicalAdventureSessionComposer().compose(
      mission: fixture.mission,
      today: fixture.today,
      requestedConfiguration: fixture.configuration,
      entry: _entry(),
    );

    expect(plan.content.map((identity) => identity.id), <String>[
      'word-a',
      'word-b',
    ]);
    expect(plan.contentChecksumsSha256.keys, <String>['word-a', 'word-b']);
    final source = File(
      'lib/features/adventure/application/adventure_session_composer.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('VocabularyUseCases')));
    expect(source, isNot(contains('vocabulary_repository')));
    expect(source, isNot(contains('app_database')));
  });

  test('FR-035 due work order remains ahead of new work', () async {
    final fixture = await _fixture();
    final plan = await const CanonicalAdventureSessionComposer().compose(
      mission: fixture.mission,
      today: fixture.today,
      requestedConfiguration: fixture.configuration,
      entry: _entry(),
    );

    expect(plan.sourceReasonCode, 'due_review');
    expect(plan.content.first.id, 'word-a');
  });

  test(
    'FR-036/037 reason and learner override semantics are preserved',
    () async {
      final fixture = await _fixture();
      final mission = fixture.mission.copyWith(
        reasonCode: 'learnerOverride',
        learnerOverrideApplied: true,
      );
      final plan = await const CanonicalAdventureSessionComposer().compose(
        mission: mission,
        today: fixture.today,
        requestedConfiguration: fixture.configuration,
        entry: _entry(),
      );

      expect(plan.sourceReasonCode, 'learnerOverride');
      expect(plan.learnerOverrideApplied, isTrue);
      expect(plan.sourceReasonCode, isNot('weakness'));
    },
  );

  test(
    'FR-038 keeps the policy-validated duration configuration exact',
    () async {
      final fixture = await _fixture();
      final plan = await const CanonicalAdventureSessionComposer().compose(
        mission: fixture.mission,
        today: fixture.today,
        requestedConfiguration: fixture.configuration,
        entry: _entry(),
      );

      expect(plan.configuration, same(fixture.configuration));
      expect(plan.configuration.timing.timedLimit, const Duration(minutes: 10));
      expect(
        plan.configuration.contentIdentity,
        fixture.configuration.contentIdentity,
      );
    },
  );

  test(
    'FR-039 pins owner, source, content, policy, catalog and treatment',
    () async {
      final fixture = await _fixture();
      final plan = await const CanonicalAdventureSessionComposer().compose(
        mission: fixture.mission,
        today: fixture.today,
        requestedConfiguration: fixture.configuration,
        entry: _entry(assignmentId: 'assignment-001', permitId: 'permit-001'),
      );

      expect(plan.ownerId, _ownerId);
      expect(plan.sourceEvaluatedAtUtc, fixture.today.evaluatedAtUtc);
      expect(plan.content.every((identity) => identity.revision == 1), isTrue);
      expect(plan.contentChecksumsSha256.values.every(_isSha256), isTrue);
      expect(plan.recommendationPolicyVersion, 'f14-v1');
      expect(plan.origin.catalogId, PackagedAdventureWorldCatalog.catalogId);
      expect(
        plan.origin.catalogVersion,
        PackagedAdventureWorldCatalog.catalogVersion,
      );
      expect(plan.origin.catalogSchemaVersion, 1);
      expect(plan.assignmentId, 'assignment-001');
      expect(plan.treatment, 'adventure');
    },
  );

  group('FR-040 rejects incompatible source before launch', () {
    test('mixed owner', () async {
      final fixture = await _fixture();
      await expectLater(
        const CanonicalAdventureSessionComposer().compose(
          mission: fixture.mission.copyWith(ownerId: 'owner-002'),
          today: fixture.today,
          requestedConfiguration: fixture.configuration,
          entry: _entry(),
        ),
        throwsA(
          isA<AdventureSessionPlanException>().having(
            (error) => error.reason,
            'reason',
            AdventureSessionPlanFailure.ownerMismatch,
          ),
        ),
      );
    });

    test('stale source instant', () async {
      final fixture = await _fixture();
      await expectLater(
        const CanonicalAdventureSessionComposer().compose(
          mission: fixture.mission.copyWith(
            sourceEvaluatedAtUtc: _now.subtract(const Duration(minutes: 1)),
          ),
          today: fixture.today,
          requestedConfiguration: fixture.configuration,
          entry: _entry(),
        ),
        throwsA(
          isA<AdventureSessionPlanException>().having(
            (error) => error.reason,
            'reason',
            AdventureSessionPlanFailure.staleSource,
          ),
        ),
      );
    });

    test('unresolved content', () async {
      final fixture = await _fixture();
      final missing = const ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: 'word-missing',
        revision: 1,
      );
      await expectLater(
        const CanonicalAdventureSessionComposer().compose(
          mission: fixture.mission.copyWith(
            content: <ContentIdentity>[missing, fixture.mission.content.last],
          ),
          today: fixture.today,
          requestedConfiguration: fixture.configuration,
          entry: _entry(),
        ),
        throwsA(
          isA<AdventureSessionPlanException>().having(
            (error) => error.reason,
            'reason',
            AdventureSessionPlanFailure.unresolvedContent,
          ),
        ),
      );
    });
  });

  test(
    'FR-041 identical request deterministically returns one plan identity',
    () async {
      final fixture = await _fixture();
      final composer = const CanonicalAdventureSessionComposer();

      final first = await composer.compose(
        mission: fixture.mission,
        today: fixture.today,
        requestedConfiguration: fixture.configuration,
        entry: _entry(),
      );
      final retry = await composer.compose(
        mission: fixture.mission,
        today: fixture.today,
        requestedConfiguration: fixture.configuration,
        entry: _entry(),
      );

      expect(retry.planId, first.planId);
      expect(retry.toJson(), first.toJson());
    },
  );
}

Future<
  ({
    AdventureMissionRef mission,
    TodayHubSnapshot today,
    SessionConfiguration configuration,
  })
>
_fixture() async {
  final today = _today(<TodayHubReviewWorkItem>[
    _review('word-b'),
    _review('word-a'),
  ]);
  final journey = await AdventureJourneyUseCases().compose(
    AdventureJourneyRequest(
      ownerId: _ownerId,
      evaluatedAtUtc: _now,
      catalog: PackagedAdventureWorldCatalog.forLocale('th'),
      today: today,
    ),
  );
  return (
    mission: journey.primaryMission!,
    today: today,
    configuration: _configuration(),
  );
}

AdventureProductEntryDecision _entry({
  String? assignmentId,
  String? permitId,
}) => AdventureProductEntryDecision(
  entryAttemptId: '018f1f90-7b2d-4d58-8d7d-6d97039ad003',
  availability: AdventureAvailability.available,
  destination: AdventureEntryDestination.adventure,
  fallbackReason: AdventureFallbackReason.none,
  catalogId: PackagedAdventureWorldCatalog.catalogId,
  catalogVersion: PackagedAdventureWorldCatalog.catalogVersion,
  catalogSchemaVersion: 1,
  permitId: permitId,
  assignmentId: assignmentId,
  treatment: 'adventure',
);

SessionConfiguration _configuration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: _ownerId,
  mode: LessonMode.typedRecall,
  itemCount: 2,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 1,
  timing: const SessionTiming.timed(Duration(minutes: 10)),
  packIdentity: null,
  protocolId: 'protocol-local',
  protocolVersion: '1.0.0',
  protocolLimitsIdentity: 'limits-001',
);

TodayHubSnapshot _today(List<TodayHubReviewWorkItem> reviewWork) =>
    TodayHubSnapshot(
      ownerId: _ownerId,
      evaluatedAtUtc: _now,
      sectionOrder: TodayHubSectionKind.values,
      resumableSession: null,
      assignedAssessment: null,
      reviewWork: reviewWork,
      recommendation: TodayHubRecommendation(
        result: RecommendationPanelResult.unavailable(
          ownerId: _ownerId,
          reason: RecommendationPanelReason.noEligibleActivity,
          freshness: RecommendationEvidenceFreshness.missing,
          protocolConstraint: RecommendationProtocolConstraint.open,
        ),
        isAuthoritative: false,
        mergedInto: null,
      ),
      goals: const [],
      reminders: const [],
      quests: const [],
      gentleStreak: null,
      dependencyStates: <TodayHubDependency, TodayHubDependencyState>{
        for (final dependency in TodayHubDependency.values)
          dependency: TodayHubDependencyState.ready,
      },
    );

TodayHubReviewWorkItem _review(String id) {
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category-001',
    spelling: id,
    normalizedSpelling: id,
    meaning: 'meaning-$id',
    normalizedMeaning: 'meaning-$id',
    partOfSpeech: 'noun',
    cefrLevel: 'A1',
    source: 'pack',
    isGlobal: true,
  );
  return TodayHubReviewWorkItem(
    item: ReviewQueueItem(
      snapshot: ReviewedLexicalContentSnapshot(
        identity: ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: id,
          revision: 1,
        ),
        categoryId: 'category-001',
        spelling: id,
        normalizedSpelling: id,
        meaning: 'meaning-$id',
        normalizedMeaning: 'meaning-$id',
        partOfSpeech: 'noun',
        cefrLevel: 'A1',
        source: 'pack',
        isGlobal: true,
        coreChecksumSha256: checksum,
        provenance: ContentProvenance.packaged,
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        artifact: null,
      ),
      provenance: <ReviewReasonProvenance>[
        ReviewReasonProvenance.due(sourceId: 'srs-$id', dueAtUtc: _now),
      ],
    ),
    recommendation: null,
  );
}

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

const _ownerId = 'owner-001';
final _now = DateTime.utc(2026, 9, 4, 10);
