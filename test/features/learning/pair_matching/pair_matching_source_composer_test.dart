import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';

PairLexicalItem fixture(
  int i, {
  String? spelling,
  String? meaning,
  Set<PairSourceReason>? reasons,
}) => PairLexicalItem(
  wordId: 'synthetic-$i',
  contentRevision: 1,
  checksum: ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'synthetic-category',
    spelling: spelling ?? 'word $i',
    normalizedSpelling: spelling ?? 'word $i',
    meaning: meaning ?? 'คำ $i',
    normalizedMeaning: meaning ?? 'คำ $i',
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
  ),
  spelling: spelling ?? 'word $i',
  meaning: meaning ?? 'คำ $i',
  sourceLocale: 'en',
  targetLocale: 'th',
  sourceReasons: reasons ?? {PairSourceReason.newContent},
);
PairMatchingLaunchIntent intent({
  PairDensity density = PairDensity.compact4,
  PairDirection direction = PairDirection.enToTh,
}) => PairMatchingLaunchIntent(
  ownerId: 'synthetic-owner',
  sourceSurface: PairSourceSurface.learn,
  sourceSnapshotRef: 'synthetic-snapshot',
  operationId: 'synthetic-operation',
  createdAtUtc: DateTime.utc(2026, 9, 5),
  requestedDensity: density,
  requestedDirection: direction,
);
PairPlanResolution compose(
  List<PairLexicalItem> items, {
  PairMatchingLaunchIntent? launch,
  List<PairLexicalItem>? allowlist,
}) =>
    PairMatchingSourceComposer(
      allowlist: PairCuratedAllowlist(
        version: 'synthetic-v1',
        items: allowlist ?? items,
      ),
    ).compose(
      launch: launch ?? intent(),
      source: PairSourceSnapshot.learn(
        ownerId: 'synthetic-owner',
        reference: 'synthetic-snapshot',
        items: items,
      ),
      preferences: const PairDensityPreferences(ownerId: 'synthetic-owner'),
      shuffleSeed: 42,
    );

void main() {
  test(
    'exact six and explicitly accepted compact fallback preserve plan pins',
    () {
      final six =
          (compose(
                    List.generate(6, fixture),
                    launch: intent(density: PairDensity.standard6),
                  )
                  as PairPlanReady)
              .plan;
      expect(six.orderedLexicalItems, hasLength(6));
      final items = List.generate(4, fixture);
      final result =
          PairMatchingSourceComposer(
                allowlist: PairCuratedAllowlist(
                  version: 'synthetic-v1',
                  items: items,
                ),
              ).compose(
                launch: intent(density: PairDensity.standard6),
                source: PairSourceSnapshot.learn(
                  ownerId: 'synthetic-owner',
                  reference: 'synthetic-snapshot',
                  items: items,
                ),
                preferences: const PairDensityPreferences(
                  ownerId: 'synthetic-owner',
                ),
                shuffleSeed: 42,
                acceptCompactFallback: true,
              )
              as PairPlanReady;
      expect(result.plan.density, PairDensity.compact4);
      expect(result.plan.orderedLexicalItems, hasLength(4));
      expect(six.density, PairDensity.standard6);
    },
  );
  test('Review exact selection cannot shrink through filtering or density', () {
    final items = List.generate(6, fixture);
    ReviewQueueItem selected(PairLexicalItem i) => ReviewQueueItem(
      snapshot: ReviewedLexicalContentSnapshot(
        identity: ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: i.wordId,
          revision: 1,
        ),
        categoryId: 'synthetic-category',
        spelling: i.spelling,
        normalizedSpelling: i.spelling,
        meaning: i.meaning,
        normalizedMeaning: i.meaning,
        partOfSpeech: 'noun',
        cefrLevel: null,
        source: 'manual',
        isGlobal: false,
        coreChecksumSha256: i.checksum,
        provenance: ContentProvenance.userAuthored,
        reviewState: ContentReviewState.unreviewed,
        publicationState: ContentPublicationState.private,
        artifact: null,
      ),
      provenance: [
        ReviewReasonProvenance.saved(
          sourceId: 'synthetic-${i.wordId}',
          occurredAtUtc: DateTime.utc(2026, 9, 5),
        ),
      ],
    );
    for (final allowedCount in [6, 5]) {
      final allow = PairCuratedAllowlist(
        version: 'synthetic-v1',
        items: items.take(allowedCount),
      );
      final source = PairSourceSnapshot.review(
        ownerId: 'synthetic-owner',
        reference: 'synthetic-review',
        selection: items.map(selected).toList(),
        allowlist: allow,
      );
      final result = PairMatchingSourceComposer(allowlist: allow).compose(
        launch: PairMatchingLaunchIntent(
          ownerId: source.ownerId,
          sourceSurface: source.surface,
          sourceSnapshotRef: source.reference,
          operationId: 'synthetic-operation',
          createdAtUtc: DateTime.utc(2026, 9, 5),
          requestedDensity: PairDensity.compact4,
        ),
        source: source,
        preferences: const PairDensityPreferences(ownerId: 'synthetic-owner'),
        shuffleSeed: 42,
        acceptCompactFallback: true,
      );
      expect(result, isA<PairPlanUnavailable>());
    }
  });
  test(
    'TC-PMT-012 Thai SARA AM compatibility forms collide without stripping tone',
    () {
      expect(
        compose([
          fixture(0, meaning: 'น้ำ'),
          fixture(1, meaning: 'น้ํา'),
          fixture(2),
          fixture(3),
          fixture(4),
        ]),
        isA<PairPlanUnavailable>(),
      );
      expect(pairVisibleKey('น้ำ', 'th'), pairVisibleKey('นํ้า', 'th'));
      expect(pairVisibleKey('น้ำ', 'th'), isNot(pairVisibleKey('นำ', 'th')));
    },
  );
  test(
    'TC-PMT-002/003 captured Today and Review preserve selection order without loader',
    () {
      final items = [fixture(3), fixture(1), fixture(0), fixture(2)];
      final allowlist = PairCuratedAllowlist(
        version: 'synthetic-v1',
        items: items,
      );
      final selected = items
          .map(
            (i) => ReviewQueueItem(
              snapshot: ReviewedLexicalContentSnapshot(
                identity: ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: i.wordId,
                  revision: 1,
                ),
                categoryId: 'synthetic-category',
                spelling: i.spelling,
                normalizedSpelling: i.spelling,
                meaning: i.meaning,
                normalizedMeaning: i.meaning,
                partOfSpeech: 'noun',
                cefrLevel: null,
                source: 'manual',
                isGlobal: false,
                coreChecksumSha256: i.checksum,
                provenance: ContentProvenance.userAuthored,
                reviewState: ContentReviewState.unreviewed,
                publicationState: ContentPublicationState.private,
                artifact: null,
              ),
              provenance: [
                ReviewReasonProvenance.saved(
                  sourceId: 'synthetic-save-${i.wordId}',
                  occurredAtUtc: DateTime.utc(2026, 9, 5),
                ),
              ],
            ),
          )
          .toList();
      final today = TodayHubSnapshot(
        ownerId: 'synthetic-owner',
        evaluatedAtUtc: DateTime.utc(2026, 9, 5),
        sectionOrder: const [],
        resumableSession: null,
        assignedAssessment: null,
        reviewWork: selected.map(
          (i) => TodayHubReviewWorkItem(item: i, recommendation: null),
        ),
        recommendation: TodayHubRecommendation(
          result: RecommendationPanelResult.unavailable(
            ownerId: 'synthetic-owner',
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
        dependencyStates: {
          for (final d in TodayHubDependency.values)
            d: TodayHubDependencyState.ready,
        },
      );
      for (final source in [
        PairSourceSnapshot.review(
          ownerId: 'synthetic-owner',
          reference: 'synthetic-review',
          selection: selected,
          allowlist: allowlist,
        ),
        PairSourceSnapshot.today(snapshot: today, allowlist: allowlist),
      ]) {
        final result =
            PairMatchingSourceComposer(allowlist: allowlist).compose(
                  launch: PairMatchingLaunchIntent(
                    ownerId: source.ownerId,
                    sourceSurface: source.surface,
                    sourceSnapshotRef: source.reference,
                    operationId: 'synthetic-operation',
                    createdAtUtc: DateTime.utc(2026, 9, 5),
                    requestedDensity: PairDensity.compact4,
                  ),
                  source: source,
                  preferences: const PairDensityPreferences(
                    ownerId: 'synthetic-owner',
                  ),
                  shuffleSeed: 42,
                )
                as PairPlanReady;
        expect(
          result.plan.orderedLexicalItems.map((i) => i.wordId),
          items.map((i) => i.wordId),
        );
        expect(
          result.plan.orderedLexicalItems.every(
            (i) => i.sourceReasons.contains(PairSourceReason.saved),
          ),
          isTrue,
        );
        final pass =
            PairMatchingSourceComposer(
                  allowlist: PairCuratedAllowlist.disabled(),
                ).adventure(
                  ownerId: 'synthetic-owner',
                  acceptedPlan: result.plan,
                )
                as PairPlanReady;
        expect(identical(pass.plan, result.plan), isTrue);
      }
    },
  );
  test('TC-PMT-004/005 merge all reasons before deterministic Learn rank', () {
    final items = List.generate(6, fixture);
    items.add(
      fixture(
        5,
        reasons: {PairSourceReason.dueSrs, PairSourceReason.incorrectAnswer},
      ),
    );
    final a = (compose(items) as PairPlanReady).plan;
    final b = (compose(items.reversed.toList()) as PairPlanReady).plan;
    expect(a.orderedLexicalItems.first.wordId, 'synthetic-5');
    expect(
      a.orderedLexicalItems.first.sourceReasons,
      containsAll(
        PairSourceReason.values.where(
          (r) =>
              r != PairSourceReason.weakness &&
              r != PairSourceReason.saved &&
              r != PairSourceReason.reported,
        ),
      ),
    );
    expect(a.planFingerprint, b.planFingerprint);
  });
  test('TC-PMT-007 exact 6 to 4 requires explicit acceptance', () {
    expect(
      compose(
        List.generate(4, fixture),
        launch: intent(density: PairDensity.standard6),
      ),
      isA<PairPlanNeedsDensityConfirmation>(),
    );
    expect(compose(List.generate(3, fixture)), isA<PairPlanUnavailable>());
  });
  test('TC-PMT-009 rejects checksum not curated', () {
    expect(
      compose(List.generate(4, fixture), allowlist: List.generate(3, fixture)),
      isA<PairPlanUnavailable>(),
    );
  });
  test(
    'TC-PMT-012 reject all colliding labels including canonical accents',
    () {
      final items = [
        fixture(0, spelling: 'café'),
        fixture(1, spelling: 'cafe\u0301'),
        fixture(2),
        fixture(3),
        fixture(4),
      ];
      expect(compose(items), isA<PairPlanUnavailable>());
    },
  );
  test('TC-PMT-010 Thai tone marks remain distinct and reverse is pinned', () {
    final p =
        (compose([
                  fixture(0, meaning: 'ปา'),
                  fixture(1, meaning: 'ป่า'),
                  fixture(2),
                  fixture(3),
                ], launch: intent(direction: PairDirection.thToEn))
                as PairPlanReady)
            .plan;
    expect(p.promptLocale, 'th');
    expect(p.targetLocale, 'en');
    expect(p.timerPreset, PairTimerPreset.off);
  });
  test(
    'guardian precedes learner and unknown asks once then fallback four',
    () {
      const p = PairDensityPreferences(
        ownerId: 'synthetic-owner',
        guardianOverride: PairDensity.compact4,
        learnerPreference: PairDensity.standard6,
      );
      expect(
        p.resolve(requested: PairDensity.standard6, canPrompt: true),
        PairDensity.compact4,
      );
      expect(
        const PairDensityPreferences(
          ownerId: 'synthetic-owner',
        ).resolve(canPrompt: true),
        isNull,
      );
      expect(
        const PairDensityPreferences(
          ownerId: 'synthetic-owner',
          choiceHandled: true,
        ).resolve(canPrompt: true),
        PairDensity.compact4,
      );
    },
  );
}
