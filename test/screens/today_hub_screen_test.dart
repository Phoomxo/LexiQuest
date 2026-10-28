import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';

void main() {
  test(
    'f42 use cases bind owner time and timezone once without invoking actions',
    () async {
      final snapshot = _snapshot();
      final reader = _Reader(snapshot);
      var ownerCalls = 0;
      var clockCalls = 0;
      final useCases = TodayHubUseCases(
        activeOwnerId: () async {
          ownerCalls += 1;
          return _ownerId;
        },
        reader: reader,
        nowUtc: () {
          clockCalls += 1;
          return _now;
        },
        timezoneId: 'Asia/Bangkok',
      );

      final loaded = await useCases.load();

      expect(identical(loaded, snapshot), isTrue);
      expect(ownerCalls, 1);
      expect(clockCalls, 1);
      expect(reader.requests, hasLength(1));
      expect(reader.requests.single.ownerId, _ownerId);
      expect(reader.requests.single.evaluatedAtUtc, _now);
      expect(reader.requests.single.timezoneId, 'Asia/Bangkok');
      expect(
        () => loaded.sectionOrder.add(TodayHubSectionKind.resume),
        throwsUnsupportedError,
        reason: 'the application boundary returns the immutable read model',
      );
    },
  );

  testWidgets(
    'f42 screen renders priority cards and preserves merged review provenance',
    (tester) async {
      final review = _reviewWork(
        recommendation: _recommendedResult(contentId: 'word:station'),
      );
      final snapshot = _snapshot(
        resumableSession: _resumableSession(),
        reviewWork: <TodayHubReviewWorkItem>[review],
        recommendation: _freshRecommendation(contentId: 'word:airport'),
      );

      await tester.pumpWidget(_app(snapshot: snapshot));
      await tester.pumpAndSettle();

      final resume = find.byKey(const ValueKey('today-hub-resume'));
      final reviewCard = find.byKey(
        const ValueKey('today-hub-review:word:station'),
      );
      final recommendation = find.byKey(
        const ValueKey('today-hub-recommendation'),
      );
      expect(resume, findsOneWidget);
      expect(reviewCard, findsOneWidget);
      expect(recommendation, findsOneWidget);
      expect(
        tester.getTopLeft(resume).dy,
        lessThan(tester.getTopLeft(reviewCard).dy),
      );
      expect(
        tester.getTopLeft(reviewCard).dy,
        lessThan(tester.getTopLeft(recommendation).dy),
      );
      expect(find.text('ถึงกำหนด SRS'), findsOneWidget);
      expect(find.text('เคยตอบผิด'), findsOneWidget);
      expect(find.text('srs:station'), findsOneWidget);
      expect(find.text('attempt:station'), findsOneWidget);
      expect(find.text('หลักฐานยังไม่แข็งแรง'), findsNWidgets(2));
      expect(
        review.provenance.map((source) => source.reason),
        <ReviewQueueReason>[
          ReviewQueueReason.dueSrs,
          ReviewQueueReason.incorrectAnswer,
        ],
      );
    },
  );

  testWidgets(
    'Thai glossary actions retain their stable keys, icons, and delegates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final actions = _Actions();
        await tester.pumpWidget(
          _app(
            snapshot: _snapshot(
              resumableSession: _resumableSession(),
              assignedAssessment: _assignedAssessment(),
              reviewWork: <TodayHubReviewWorkItem>[_reviewWork()],
              recommendation: _freshRecommendation(contentId: 'word:airport'),
            ),
            actions: actions,
          ),
        );
        await tester.pumpAndSettle();

        const cases = <(String, String, IconData)>[
          ('today-hub-resume-action', 'เรียนต่อ', Icons.play_arrow),
          (
            'today-hub-start-recommendation',
            'เริ่มกิจกรรมที่แนะนำ',
            Icons.auto_awesome_outlined,
          ),
          (
            'today-hub-assessment-action',
            'เริ่มแบบประเมิน',
            Icons.assignment_outlined,
          ),
          (
            'today-hub-open-review',
            'เปิดศูนย์ทบทวน',
            Icons.fact_check_outlined,
          ),
          ('today-hub-open-history', 'ดูประวัติการเรียน', Icons.history),
        ];
        for (final (key, label, icon) in cases) {
          await _scrollToTodayHubAction(tester, key);
          final action = find.byKey(ValueKey<String>(key));
          expect(action, findsOneWidget);
          expect(
            find.descendant(of: action, matching: find.text(label)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: action, matching: find.byIcon(icon)),
            findsOneWidget,
          );
          _expectSingleThaiGlossaryAction(action: action, entryId: key);
        }

        await _scrollToTodayHubAction(tester, 'today-hub-resume-action');
        await tester.tap(
          find.byKey(const ValueKey<String>('today-hub-resume-action')),
        );
        await tester.pump();
        await _scrollToTodayHubAction(tester, 'today-hub-start-recommendation');
        await tester.tap(
          find.byKey(const ValueKey<String>('today-hub-start-recommendation')),
        );
        await tester.pump();
        await _scrollToTodayHubAction(tester, 'today-hub-assessment-action');
        await tester.tap(
          find.byKey(const ValueKey<String>('today-hub-assessment-action')),
        );
        await tester.pump();
        await _scrollToTodayHubAction(tester, 'today-hub-open-review');
        await tester.tap(
          find.byKey(const ValueKey<String>('today-hub-open-review')),
        );
        await tester.pump();
        await _scrollToTodayHubAction(tester, 'today-hub-open-history');
        await tester.tap(
          find.byKey(const ValueKey<String>('today-hub-open-history')),
        );
        await tester.pump();

        expect(actions.resumeCalls, 1);
        expect(actions.recommendationCalls, 1);
        expect(actions.assessmentCalls, 1);
        expect(actions.reviewCalls, 1);
        expect(actions.historyCalls, 1);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'f42 signoff exact merged recommendation renders one review card and no standalone action',
    (tester) async {
      final recommendation = _recommendedResult(contentId: 'word:station');
      final review = _reviewWork(recommendation: recommendation);
      final snapshot = _snapshot(
        reviewWork: <TodayHubReviewWorkItem>[review],
        recommendation: TodayHubRecommendation(
          result: recommendation,
          isAuthoritative: true,
          mergedInto: review.identity,
        ),
      );

      await tester.pumpWidget(_app(snapshot: snapshot));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('today-hub-review:word:station')),
        findsOneWidget,
      );
      expect(find.text('ถึงกำหนด SRS'), findsOneWidget);
      expect(find.text('เคยตอบผิด'), findsOneWidget);
      expect(find.text('srs:station'), findsOneWidget);
      expect(find.text('attempt:station'), findsOneWidget);
      expect(find.text('หลักฐานยังไม่แข็งแรง'), findsOneWidget);
      expect(
        review.provenance.map((source) => source.reason),
        <ReviewQueueReason>[
          ReviewQueueReason.dueSrs,
          ReviewQueueReason.incorrectAnswer,
        ],
      );
      expect(
        find.byKey(const ValueKey('today-hub-recommendation')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-hub-start-recommendation')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'f42 signoff every non-authoritative recommendation explains its exact reason without a start action',
    (tester) async {
      const cases = <RecommendationPanelReason, String>{
        RecommendationPanelReason.staleEvidence: 'ข้อมูลคำแนะนำล้าสมัย',
        RecommendationPanelReason.missingEvidence: 'ยังมีข้อมูลไม่เพียงพอ',
        RecommendationPanelReason.corruptEvidence:
            'ข้อมูลคำแนะนำไม่พร้อมใช้งาน',
        RecommendationPanelReason.modeUnavailable:
            'กิจกรรมนี้ยังไม่พร้อมใช้งาน',
        RecommendationPanelReason.protocolLocked: 'กิจกรรมถูกจำกัดตามโปรโตคอล',
        RecommendationPanelReason.canonicalAuthorityUnavailable:
            'ข้อมูลหลักยังไม่พร้อมใช้งาน',
        RecommendationPanelReason.noEligibleActivity:
            'ยังไม่มีกิจกรรมที่เหมาะสมในตอนนี้',
      };

      for (final entry in cases.entries) {
        final freshness = entry.key == RecommendationPanelReason.staleEvidence
            ? RecommendationEvidenceFreshness.stale
            : entry.key == RecommendationPanelReason.corruptEvidence
            ? RecommendationEvidenceFreshness.corrupt
            : RecommendationEvidenceFreshness.missing;
        final recommendation = TodayHubRecommendation(
          result: RecommendationPanelResult.unavailable(
            ownerId: _ownerId,
            reason: entry.key,
            freshness: freshness,
            protocolConstraint:
                entry.key == RecommendationPanelReason.protocolLocked
                ? RecommendationProtocolConstraint.constrained
                : RecommendationProtocolConstraint.open,
          ),
          isAuthoritative: false,
          mergedInto: null,
        );

        await tester.pumpWidget(
          _app(snapshot: _snapshot(recommendation: recommendation)),
        );
        await tester.pumpAndSettle();

        expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);
        expect(
          find.byKey(const ValueKey('today-hub-start-recommendation')),
          findsNothing,
          reason: '${entry.key.name} is not an invocation authority',
        );
      }
    },
  );

  testWidgets(
    'f42 screen exposes stale and unavailable states without authoritative start',
    (tester) async {
      final stale = TodayHubRecommendation(
        result: RecommendationPanelResult.recommended(
          ownerId: _ownerId,
          mode: LessonMode.typedRecall,
          reason: RecommendationPanelReason.staleEvidence,
          freshness: RecommendationEvidenceFreshness.stale,
          protocolConstraint: RecommendationProtocolConstraint.open,
          alternatives: const <LessonMode>[LessonMode.meaningQuiz],
          contentId: 'word:stale',
        ),
        isAuthoritative: false,
        mergedInto: null,
      );
      final snapshot = _snapshot(
        recommendation: stale,
        dependencyStates: _states(
          overrides: const <TodayHubDependency, TodayHubDependencyState>{
            TodayHubDependency.review: TodayHubDependencyState.unavailable,
            TodayHubDependency.recommendation: TodayHubDependencyState.stale,
          },
        ),
      );

      await tester.pumpWidget(_app(snapshot: snapshot));
      await tester.pumpAndSettle();

      expect(find.text('รายการทบทวนไม่พร้อมใช้งาน'), findsOneWidget);
      expect(find.text('ข้อมูลคำแนะนำล้าสมัย'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-hub-start-recommendation')),
        findsNothing,
        reason: 'stale recommendation evidence is not an invocation authority',
      );
    },
  );

  testWidgets(
    'f42 screen keeps gentle continuity supportive and non-competitive',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final snapshot = _snapshot(
          gentleStreak: const GentleStreakSnapshot(
            ownerId: _ownerId,
            currentStreakDays: 3,
            longestStreakDays: 8,
            freezeCount: 1,
            phase: GentleStreakPhase.recovery,
            policyVersion: StreakPolicy.version,
          ),
        );

        await tester.pumpWidget(_app(snapshot: snapshot));
        await tester.pumpAndSettle();

        expect(
          find.text('ต่อเนื่อง 3 วัน — พักได้เมื่อจำเป็น แล้วกลับมาเมื่อพร้อม'),
          findsOneWidget,
        );
        final forbidden = RegExp(
          r'leaderboard|rank|social|อันดับ|แข่งขัน|เปรียบเทียบกับ|สาธารณะ|เพื่อน',
          caseSensitive: false,
        );
        expect(find.textContaining(forbidden), findsNothing);
        expect(find.bySemanticsLabel(forbidden), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'f42 screen delegates review and history to typed child launchers once',
    (tester) async {
      final review = _reviewWork();
      final snapshot = _snapshot(reviewWork: <TodayHubReviewWorkItem>[review]);
      final actions = _Actions();

      await tester.pumpWidget(_app(snapshot: snapshot, actions: actions));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('today-hub-open-review')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('today-hub-open-history')));
      await tester.pump();

      expect(actions.reviewCalls, 1);
      expect(actions.historyCalls, 1);
      expect(actions.reviewWork, hasLength(1));
      expect(identical(actions.reviewWork.single, review), isTrue);
      expect(snapshot.reviewWork, hasLength(1));
      expect(snapshot.reviewWork.single.provenance, hasLength(2));
    },
  );

  testWidgets(
    'f42 screen single-flights resume and recommendation without Hub mutation',
    (tester) async {
      final snapshot = _snapshot(
        resumableSession: _resumableSession(),
        recommendation: _freshRecommendation(contentId: 'word:airport'),
      );
      final actions = _Actions(
        resumePending: Completer<void>(),
        recommendationPending: Completer<void>(),
      );

      await tester.pumpWidget(_app(snapshot: snapshot, actions: actions));
      await tester.pumpAndSettle();

      final resume = find.byKey(const ValueKey('today-hub-resume-action'));
      await tester.tap(resume);
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(resume).onPressed, isNull);
      await tester.tap(resume);
      await tester.pump();
      expect(actions.resumeCalls, 1);
      expect(actions.resumedSession?.id, 'session:resume');

      final recommendation = find.byKey(
        const ValueKey('today-hub-start-recommendation'),
      );
      await tester.tap(recommendation);
      await tester.pump();
      expect(
        tester.widget<ButtonStyleButton>(recommendation).onPressed,
        isNull,
      );
      await tester.tap(recommendation);
      await tester.pump();
      expect(actions.recommendationCalls, 1);
      expect(actions.startedRecommendation?.result.contentId, 'word:airport');
      expect(snapshot.resumableSession?.state, 'active');
      expect(snapshot.recommendation.isAuthoritative, isTrue);

      actions.resumePending!.complete();
      actions.recommendationPending!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'f42 screen gates exact active assessment with live researchAssessment state',
    (tester) async {
      final assessment = _assignedAssessment();
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      final actions = _Actions();

      await tester.pumpWidget(
        _app(
          snapshot: _snapshot(assignedAssessment: assessment),
          actions: actions,
          features: registry,
        ),
      );
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('today-hub-assessment-action'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pump();
      expect(actions.assessmentCalls, 1);
      expect(identical(actions.startedAssessment, assessment), isTrue);

      registry.emergencyOff(Feature.researchAssessment);
      await tester.pump();
      expect(action, findsNothing);

      await tester.pumpWidget(
        _app(
          snapshot: _snapshot(),
          actions: actions,
          features: const BuildFeatureRegistry.allEnabled(),
        ),
      );
      await tester.pumpAndSettle();
      expect(action, findsNothing);
    },
  );

  testWidgets('f42 screen load failure is explicit and retryable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final loader = _Loader(_snapshot())..failure = StateError('offline');
    try {
      await tester.pumpWidget(_app(loader: loader));
      await tester.pumpAndSettle();

      expect(find.text('ไม่สามารถโหลดรายการวันนี้ได้'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape('โหลดรายการวันนี้ไม่สำเร็จ')),
        ),
        findsOneWidget,
      );
      loader.failure = null;
      await tester.tap(find.byKey(const ValueKey('today-hub-retry')));
      await tester.pumpAndSettle();

      expect(loader.calls, 2);
      expect(find.text('วันนี้'), findsOneWidget);
      expect(find.text('ไม่สามารถโหลดรายการวันนี้ได้'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}

void _expectSingleThaiGlossaryAction({
  required Finder action,
  required String entryId,
}) {
  final entry = NavigationGlossary.require(entryId);
  final tooltip = find.ancestor(
    of: action,
    matching: find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == entry.tooltip,
    ),
  );
  expect(tooltip, findsOneWidget);
  expect(
    find.descendant(of: tooltip, matching: find.text(entry.fullThaiLabel)),
    findsOneWidget,
  );
  final semanticActions = find
      .ancestor(of: action, matching: find.byType(Semantics))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Semantics>()
      .where(
        (semantics) =>
            semantics.properties.label == entry.semanticsLabel &&
            semantics.properties.onTap != null &&
            semantics.excludeSemantics,
      )
      .toList(growable: false);
  expect(semanticActions, hasLength(1));
}

Widget _app({
  TodayHubSnapshot? snapshot,
  _Loader? loader,
  _Actions? actions,
  FeatureRegistry features = const BuildFeatureRegistry.allEnabled(),
  bool assessmentAvailable = true,
}) => MaterialApp(
  home: TodayHubScreen(
    useCases: loader ?? _Loader(snapshot ?? _snapshot()),
    actions: actions ?? _Actions(),
    features: features,
    assessmentAvailable: assessmentAvailable,
  ),
);

Future<void> _scrollToTodayHubAction(
  WidgetTester tester,
  String actionKey,
) async {
  final scrollable = find
      .descendant(
        of: find.byType(TodayHubScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  var position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();

  final action = find.byKey(ValueKey<String>(actionKey));
  for (var step = 0; step < 64 && action.evaluate().length != 1; step += 1) {
    position = tester.state<ScrollableState>(scrollable).position;
    final nextPixels = (position.pixels + 240)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextPixels == position.pixels) break;
    position.jumpTo(nextPixels);
    await tester.pump();
  }

  if (action.evaluate().length != 1) {
    position = tester.state<ScrollableState>(scrollable).position;
    fail(
      'Today Hub action $actionKey did not materialize exactly once; '
      'pixels=${position.pixels}, '
      'min=${position.minScrollExtent}, '
      'max=${position.maxScrollExtent}.',
    );
  }

  await tester.ensureVisible(action);
  await tester.pump();
}

const _ownerId = 'owner:today';
const _checksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _now = DateTime.utc(2026, 8, 31, 8);

TodayHubSnapshot _snapshot({
  LearningSessionSummary? resumableSession,
  TodayHubAssignedAssessment? assignedAssessment,
  List<TodayHubReviewWorkItem> reviewWork = const <TodayHubReviewWorkItem>[],
  TodayHubRecommendation? recommendation,
  GentleStreakSnapshot? gentleStreak,
  Map<TodayHubDependency, TodayHubDependencyState>? dependencyStates,
}) => TodayHubSnapshot(
  ownerId: _ownerId,
  evaluatedAtUtc: _now,
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: resumableSession,
  assignedAssessment: assignedAssessment,
  reviewWork: reviewWork,
  recommendation: recommendation ?? _unavailableRecommendation(),
  goals: const [],
  reminders: const [],
  quests: const [],
  gentleStreak: gentleStreak,
  dependencyStates: dependencyStates ?? _states(),
);

Map<TodayHubDependency, TodayHubDependencyState> _states({
  Map<TodayHubDependency, TodayHubDependencyState> overrides =
      const <TodayHubDependency, TodayHubDependencyState>{},
}) => <TodayHubDependency, TodayHubDependencyState>{
  for (final dependency in TodayHubDependency.values)
    dependency: overrides[dependency] ?? TodayHubDependencyState.ready,
};

LearningSessionSummary _resumableSession() => LearningSessionSummary(
  id: 'session:resume',
  ownerId: _ownerId,
  activityType: 'meaningQuiz',
  state: 'active',
  startedAtUtc: _now.subtract(const Duration(minutes: 8)),
  correctCount: 2,
  wrongCount: 1,
  score: 67,
);

TodayHubReviewWorkItem _reviewWork({
  RecommendationPanelResult? recommendation,
}) {
  const identity = ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: 'word:station',
    revision: 1,
  );
  return TodayHubReviewWorkItem(
    item: ReviewQueueItem(
      snapshot: ReviewedLexicalContentSnapshot(
        identity: identity,
        categoryId: 'category:travel',
        spelling: 'station',
        normalizedSpelling: 'station',
        meaning: 'สถานี',
        normalizedMeaning: 'สถานี',
        partOfSpeech: 'noun',
        cefrLevel: 'A1',
        source: 'pack',
        isGlobal: true,
        coreChecksumSha256: _checksum,
        provenance: ContentProvenance.packaged,
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        artifact: null,
      ),
      provenance: <ReviewReasonProvenance>[
        ReviewReasonProvenance.due(
          sourceId: 'srs:station',
          dueAtUtc: _now.subtract(const Duration(hours: 2)),
        ),
        ReviewReasonProvenance.incorrect(
          sourceId: 'attempt:station',
          occurredAtUtc: _now.subtract(const Duration(hours: 1)),
        ),
      ],
    ),
    recommendation: recommendation,
  );
}

RecommendationPanelResult _recommendedResult({required String contentId}) =>
    RecommendationPanelResult.recommended(
      ownerId: _ownerId,
      mode: LessonMode.typedRecall,
      reason: RecommendationPanelReason.weakEvidence,
      freshness: RecommendationEvidenceFreshness.current,
      protocolConstraint: RecommendationProtocolConstraint.open,
      alternatives: const <LessonMode>[LessonMode.meaningQuiz],
      contentId: contentId,
    );

TodayHubRecommendation _freshRecommendation({required String contentId}) =>
    TodayHubRecommendation(
      result: _recommendedResult(contentId: contentId),
      isAuthoritative: true,
      mergedInto: null,
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

TodayHubAssignedAssessment _assignedAssessment() => TodayHubAssignedAssessment(
  run: AssessmentRun(
    id: 'assessment:today',
    ownerId: _ownerId,
    learningSessionId: 'session:assessment',
    studyCycleId: 'cycle:2026',
    phase: AssessmentPhase.pre,
    state: AssessmentRunState.active,
    protocolId: 'protocol:assessment',
    protocolVersion: '1.0.0',
    experimentId: 'experiment:assessment',
    experimentVersion: 1,
    assignmentId: 'assignment:assessment',
    cohort: 'enforced',
    consentVersion: 1,
    consentDecidedAtUtc: _now.subtract(const Duration(days: 2)),
    instrumentId: 'instrument:assessment',
    instrumentVersion: '1.0.0',
    formId: 'form:pre',
    formVersion: '1.0.0',
    instrumentChecksumSha256: _checksum,
    formChecksumSha256: _checksum,
    appVersion: '1.0.0',
    buildId: 'f42',
    databaseSchemaVersion: 20,
    contentRevision: 'assessment-content-v1',
    evidencePolicyVersion: 'evidence-v2',
    featureContractRevision: '1.1.0',
    featureContractHash: _checksum,
    startedAtUtc: _now.subtract(const Duration(hours: 1)),
    completedAtUtc: null,
    abandonedAtUtc: null,
  ),
);

final class _Reader implements TodayHubReader {
  _Reader(this.snapshot);

  final TodayHubSnapshot snapshot;
  final List<TodayHubRequest> requests = <TodayHubRequest>[];

  @override
  Future<TodayHubSnapshot> compose(TodayHubRequest request) async {
    requests.add(request);
    return snapshot;
  }
}

final class _Loader implements TodayHubSnapshotLoader {
  _Loader(this.snapshot);

  final TodayHubSnapshot snapshot;
  Object? failure;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return snapshot;
  }
}

final class _Actions implements TodayHubActionDelegate {
  _Actions({this.resumePending, this.recommendationPending});

  final Completer<void>? resumePending;
  final Completer<void>? recommendationPending;
  int resumeCalls = 0;
  int recommendationCalls = 0;
  int reviewCalls = 0;
  int historyCalls = 0;
  int assessmentCalls = 0;
  LearningSessionSummary? resumedSession;
  TodayHubRecommendation? startedRecommendation;
  List<TodayHubReviewWorkItem> reviewWork = const <TodayHubReviewWorkItem>[];
  TodayHubAssignedAssessment? startedAssessment;

  @override
  Future<void> resume(LearningSessionSummary session) {
    resumeCalls += 1;
    resumedSession = session;
    return resumePending?.future ?? Future<void>.value();
  }

  @override
  Future<void> startRecommendation(TodayHubRecommendation recommendation) {
    recommendationCalls += 1;
    startedRecommendation = recommendation;
    return recommendationPending?.future ?? Future<void>.value();
  }

  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {
    reviewCalls += 1;
    reviewWork = List<TodayHubReviewWorkItem>.unmodifiable(work);
  }

  @override
  Future<void> openHistory() async {
    historyCalls += 1;
  }

  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {
    assessmentCalls += 1;
    startedAssessment = assessment;
  }
}
