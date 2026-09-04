import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_reader.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';

void main() {
  test(
    'JRN-001 fixed input composes byte/value-equivalent projection',
    () async {
      final reader = AdventureJourneyUseCases();
      final request = _request(today: _today());

      final first = await reader.compose(request);
      final second = await reader.compose(request);

      expect(second.toJson(), first.toJson());
      expect(second.inputFingerprintSha256, first.inputFingerprintSha256);
    },
  );

  test(
    'JRN-002 shuffled catalog and fact readers preserve canonical output',
    () async {
      final sourceCatalog = PackagedAdventureWorldCatalog.forLocale('th');
      final shuffledCatalog = sourceCatalog.copyWith(
        worlds: sourceCatalog.worlds
            .map(
              (world) => world.copyWith(nodes: world.nodes.reversed.toList()),
            )
            .toList()
            .reversed
            .toList(),
      );
      final readers = <AdventureJourneyFactReader>[
        _Facts(AdventureJourneyAuthority.reward),
        _Facts(AdventureJourneyAuthority.achievement),
        _Facts(AdventureJourneyAuthority.history),
        _Facts(AdventureJourneyAuthority.packCompletion),
      ];

      final canonical = await AdventureJourneyUseCases(
        factReaders: readers,
      ).compose(_request(today: _today(), catalog: sourceCatalog));
      final shuffled = await AdventureJourneyUseCases(
        factReaders: readers.reversed.toList(),
      ).compose(_request(today: _today(), catalog: shuffledCatalog));

      expect(shuffled.toJson(), canonical.toJson());
    },
  );

  test(
    'JRN-003 active accepted session makes resume the primary mission',
    () async {
      final result = await AdventureJourneyUseCases().compose(
        _request(today: _today(resumableSession: _session())),
      );

      expect(result.primaryMission?.kind, AdventureMissionKind.resume);
      expect(result.primaryMission?.sourceId, 'session-001');
      expect(result.nodes.first.state, AdventureNodeState.current);
      expect(
        result.nodes.where((node) => node.state == AdventureNodeState.current),
        hasLength(1),
      );
    },
  );

  test(
    'JRN-004 due review preserves priority over new recommendation',
    () async {
      final result = await AdventureJourneyUseCases().compose(
        _request(
          today: _today(
            reviewWork: <TodayHubReviewWorkItem>[
              _review('word-b'),
              _review('word-a'),
            ],
            recommendation: _recommended('word-new'),
          ),
        ),
      );

      expect(result.primaryMission?.kind, AdventureMissionKind.review);
      expect(result.primaryMission?.sourceId, 'word-a');
      expect(
        result.primaryMission?.content.map((identity) => identity.id),
        <String>['word-a', 'word-b'],
      );
    },
  );

  test(
    'JRN-005 generic history facts cannot assert Adventure node completion',
    () async {
      final result = await AdventureJourneyUseCases(
        factReaders: <AdventureJourneyFactReader>[
          _Facts(
            AdventureJourneyAuthority.history,
            completedNodeIds: const <String>{'resume-review'},
          ),
        ],
      ).compose(_request(today: _today()));

      expect(
        result.dependencyStates[AdventureJourneyAuthority.history],
        AdventureJourneyDependencyState.corrupt,
      );
      expect(
        result.nodes
            .singleWhere((node) => node.nodeId == 'resume-review')
            .state,
        AdventureNodeState.available,
      );
      expect(
        result.nodes.singleWhere((node) => node.nodeId == 'next-preview').state,
        AdventureNodeState.unavailable,
      );
    },
  );

  test(
    'JRN-006 stale source disables start and keeps bounded reason',
    () async {
      final staleAt = _now.subtract(const Duration(hours: 1));
      final result = await AdventureJourneyUseCases().compose(
        _request(
          today: _today(
            evaluatedAtUtc: staleAt,
            recommendation: _recommended('word-new'),
          ),
        ),
      );

      expect(result.freshness, AdventureSnapshotFreshness.stale);
      expect(result.primaryMission, isNull);
      expect(
        result.nodes
            .singleWhere((node) => node.nodeId == 'today-mission')
            .state,
        AdventureNodeState.unavailable,
      );
      expect(
        result.nodes
            .singleWhere((node) => node.nodeId == 'today-mission')
            .reasonCode,
        'source_stale',
      );
    },
  );

  test(
    'supplemental exceptions degrade only next preview and preserve Today primary',
    () async {
      final primaryCases =
          <({TodayHubSnapshot today, AdventureMissionKind expectedKind})>[
            (
              today: _today(resumableSession: _session()),
              expectedKind: AdventureMissionKind.resume,
            ),
            (
              today: _today(
                reviewWork: <TodayHubReviewWorkItem>[_review('word-a')],
              ),
              expectedKind: AdventureMissionKind.review,
            ),
            (
              today: _today(recommendation: _recommended('word-new')),
              expectedKind: AdventureMissionKind.recommendation,
            ),
          ];

      for (final failedAuthority in _supplementalAuthorities) {
        for (final primaryCase in primaryCases) {
          final result = await AdventureJourneyUseCases(
            factReaders: <AdventureJourneyFactReader>[
              for (final authority in _supplementalAuthorities)
                if (authority == failedAuthority)
                  _ThrowingFacts(authority)
                else
                  _Facts(authority),
            ],
          ).compose(_request(today: primaryCase.today));

          expect(
            result.dependencyStates[failedAuthority],
            AdventureJourneyDependencyState.unavailable,
            reason: failedAuthority.name,
          );
          expect(
            result.freshness,
            AdventureSnapshotFreshness.current,
            reason: failedAuthority.name,
          );
          expect(
            result.primaryMission?.kind,
            primaryCase.expectedKind,
            reason: failedAuthority.name,
          );
          expect(
            result.nodes
                .singleWhere(
                  (node) => node.nodeId == result.primaryMission!.nodeId,
                )
                .state,
            AdventureNodeState.current,
            reason: failedAuthority.name,
          );
          expect(
            result.nodes
                .singleWhere((node) => node.nodeId == 'next-preview')
                .state,
            AdventureNodeState.unavailable,
            reason: failedAuthority.name,
          );
          expect(
            result.nodes
                .singleWhere((node) => node.nodeId == 'next-preview')
                .reasonCode,
            'source_unavailable',
            reason: failedAuthority.name,
          );
          expect(result.inputFingerprintSha256, hasLength(64));
        }
      }
    },
  );

  test(
    'wrong returned supplemental authority is contained as corrupt',
    () async {
      final reader = AdventureJourneyUseCases(
        factReaders: <AdventureJourneyFactReader>[
          const _WrongAuthorityFacts(
            configured: AdventureJourneyAuthority.achievement,
            returned: AdventureJourneyAuthority.reward,
          ),
          const _Facts(AdventureJourneyAuthority.reward),
          const _Facts(AdventureJourneyAuthority.history),
          const _Facts(AdventureJourneyAuthority.packCompletion),
        ],
      );

      final first = await reader.compose(
        _request(today: _today(recommendation: _recommended('word-new'))),
      );
      final second = await reader.compose(
        _request(today: _today(recommendation: _recommended('word-new'))),
      );

      expect(
        first.dependencyStates[AdventureJourneyAuthority.achievement],
        AdventureJourneyDependencyState.corrupt,
      );
      expect(first.freshness, AdventureSnapshotFreshness.current);
      expect(first.primaryMission?.kind, AdventureMissionKind.recommendation);
      expect(
        first.nodes.singleWhere((node) => node.nodeId == 'next-preview').state,
        AdventureNodeState.unavailable,
      );
      expect(
        first.nodes
            .singleWhere((node) => node.nodeId == 'next-preview')
            .reasonCode,
        'source_corrupt',
      );
      expect(second.inputFingerprintSha256, first.inputFingerprintSha256);
    },
  );

  test('corrupt supplemental facts cannot fabricate completed nodes', () async {
    final result = await AdventureJourneyUseCases(
      factReaders: const <AdventureJourneyFactReader>[
        _CorruptFactsWithCompletion(AdventureJourneyAuthority.achievement),
      ],
    ).compose(_request(today: _today()));

    expect(
      result.dependencyStates[AdventureJourneyAuthority.achievement],
      AdventureJourneyDependencyState.corrupt,
    );
    expect(
      result.nodes.singleWhere((node) => node.nodeId == 'today-mission').state,
      AdventureNodeState.available,
    );
    expect(
      result.nodes.singleWhere((node) => node.nodeId == 'next-preview').state,
      AdventureNodeState.unavailable,
    );
  });

  test('corrupt required Today dependency still blocks its mission', () async {
    final result = await AdventureJourneyUseCases().compose(
      _request(
        today: _today(
          recommendation: _recommended('word-new'),
          dependencyStates: <TodayHubDependency, TodayHubDependencyState>{
            for (final dependency in TodayHubDependency.values)
              dependency: dependency == TodayHubDependency.recommendation
                  ? TodayHubDependencyState.corrupt
                  : TodayHubDependencyState.ready,
          },
        ),
      ),
    );

    expect(result.freshness, AdventureSnapshotFreshness.corrupt);
    expect(result.primaryMission, isNull);
    expect(
      result.nodes.singleWhere((node) => node.nodeId == 'today-mission').state,
      AdventureNodeState.unavailable,
    );
    expect(
      result.nodes
          .singleWhere((node) => node.nodeId == 'today-mission')
          .reasonCode,
      'source_corrupt',
    );
  });

  test('configured supplemental authority view is canonical and immutable', () {
    final authorities = AdventureJourneyUseCases(
      factReaders: _supplementalAuthorities.reversed
          .map<AdventureJourneyFactReader>(_Facts.new)
          .toList(),
    ).configuredAuthorities;

    expect(authorities.toList(), _supplementalAuthorities);
    expect(
      () => authorities.remove(AdventureJourneyAuthority.achievement),
      throwsUnsupportedError,
    );
  });

  test(
    'Adventure journey source has no Drift row or progress store imports',
    () {
      final source = <String>[
        'lib/features/adventure/domain/adventure_journey.dart',
        'lib/features/adventure/application/adventure_journey_reader.dart',
        'lib/features/adventure/application/adventure_journey_fact_readers.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      expect(source, isNot(contains('app_database')));
      expect(source, isNot(contains('drift')));
      expect(source, isNot(contains('adventure_progress')));
    },
  );
}

AdventureJourneyRequest _request({
  required TodayHubSnapshot today,
  AdventureWorldCatalog? catalog,
}) => AdventureJourneyRequest(
  ownerId: _ownerId,
  evaluatedAtUtc: _now,
  catalog: catalog ?? PackagedAdventureWorldCatalog.forLocale('th'),
  today: today,
);

TodayHubSnapshot _today({
  DateTime? evaluatedAtUtc,
  LearningSessionSummary? resumableSession,
  List<TodayHubReviewWorkItem> reviewWork = const <TodayHubReviewWorkItem>[],
  TodayHubRecommendation? recommendation,
  Map<TodayHubDependency, TodayHubDependencyState>? dependencyStates,
}) => TodayHubSnapshot(
  ownerId: _ownerId,
  evaluatedAtUtc: evaluatedAtUtc ?? _now,
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: resumableSession,
  assignedAssessment: null,
  reviewWork: reviewWork,
  recommendation: recommendation ?? _unavailableRecommendation(),
  goals: const [],
  reminders: const [],
  quests: const [],
  gentleStreak: null,
  dependencyStates:
      dependencyStates ??
      <TodayHubDependency, TodayHubDependencyState>{
        for (final dependency in TodayHubDependency.values)
          dependency: TodayHubDependencyState.ready,
      },
);

LearningSessionSummary _session() => LearningSessionSummary(
  id: 'session-001',
  ownerId: _ownerId,
  activityType: 'meaningQuiz',
  state: 'active',
  startedAtUtc: _now.subtract(const Duration(minutes: 5)),
  correctCount: 2,
  wrongCount: 1,
  score: 67,
);

TodayHubReviewWorkItem _review(String id) => TodayHubReviewWorkItem(
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
      coreChecksumSha256: ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category-001',
        spelling: id,
        normalizedSpelling: id,
        meaning: 'meaning-$id',
        normalizedMeaning: 'meaning-$id',
        partOfSpeech: 'noun',
        cefrLevel: 'A1',
        source: 'pack',
        isGlobal: true,
      ),
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

TodayHubRecommendation _recommended(String contentId) => TodayHubRecommendation(
  result: RecommendationPanelResult.recommended(
    ownerId: _ownerId,
    mode: LessonMode.typedRecall,
    reason: RecommendationPanelReason.weakEvidence,
    freshness: RecommendationEvidenceFreshness.current,
    protocolConstraint: RecommendationProtocolConstraint.open,
    alternatives: const <LessonMode>[LessonMode.meaningQuiz],
    contentId: contentId,
  ),
  isAuthoritative: true,
  mergedInto: ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: contentId,
    revision: 1,
  ),
);

TodayHubRecommendation _unavailableRecommendation() => TodayHubRecommendation(
  result: RecommendationPanelResult.unavailable(
    ownerId: _ownerId,
    reason: RecommendationPanelReason.noEligibleActivity,
    freshness: RecommendationEvidenceFreshness.missing,
    protocolConstraint: RecommendationProtocolConstraint.open,
  ),
  isAuthoritative: false,
  mergedInto: null,
);

final class _Facts implements AdventureJourneyFactReader {
  const _Facts(this.authority, {this.completedNodeIds = const <String>{}});

  @override
  final AdventureJourneyAuthority authority;
  final Set<String> completedNodeIds;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => AdventureJourneyFacts(
    authority: authority,
    state: AdventureJourneyDependencyState.ready,
    completedNodeIds: completedNodeIds,
    fingerprintPart: '${authority.name}:ready',
  );
}

final class _ThrowingFacts implements AdventureJourneyFactReader {
  const _ThrowingFacts(this.authority);

  @override
  final AdventureJourneyAuthority authority;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) => throw StateError('sensitive source failure that must stay contained');
}

final class _WrongAuthorityFacts implements AdventureJourneyFactReader {
  const _WrongAuthorityFacts({
    required this.configured,
    required this.returned,
  });

  final AdventureJourneyAuthority configured;
  final AdventureJourneyAuthority returned;

  @override
  AdventureJourneyAuthority get authority => configured;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => AdventureJourneyFacts(
    authority: returned,
    state: AdventureJourneyDependencyState.ready,
    completedNodeIds: const <String>{},
    fingerprintPart: 'malformed-authority',
  );
}

final class _CorruptFactsWithCompletion implements AdventureJourneyFactReader {
  const _CorruptFactsWithCompletion(this.authority);

  @override
  final AdventureJourneyAuthority authority;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => AdventureJourneyFacts(
    authority: authority,
    state: AdventureJourneyDependencyState.corrupt,
    completedNodeIds: const <String>{'today-mission'},
    fingerprintPart: 'corrupt-with-fabricated-completion',
  );
}

const _supplementalAuthorities = <AdventureJourneyAuthority>[
  AdventureJourneyAuthority.achievement,
  AdventureJourneyAuthority.reward,
  AdventureJourneyAuthority.history,
  AdventureJourneyAuthority.packCompletion,
];

const _ownerId = 'owner-001';
final _now = DateTime.utc(2026, 9, 4, 10);
