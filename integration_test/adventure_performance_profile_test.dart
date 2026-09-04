import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_learning_bridge.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_reaction_selector.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_session_composer.dart';
import 'package:vocab_learning_app/features/adventure/data/adventure_world_catalog_validator.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_reaction.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_hub_screen.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

const _profileId = 'adventure-performance-v1';
const _sampleCount = 20;
const _warmupCount = 3;
const _entryBudgetUs = 50 * Duration.microsecondsPerMillisecond;
const _journeyBudgetUs = 100 * Duration.microsecondsPerMillisecond;
const _renderBudgetUs = 1500 * Duration.microsecondsPerMillisecond;
const _sessionOverheadBudgetUs = 150 * Duration.microsecondsPerMillisecond;
const _frameBudgetUs = 16700;
const _longFrameOrTaskBudgetUs = 100 * Duration.microsecondsPerMillisecond;
const _learnerPauseBoundaryMargin = Duration(seconds: 1);
const _untimedIdleCutoff = Duration(minutes: 5);
const _performanceTimeoutPolicy = Timeout.none;
const _frameReportKey = 'adventureMapListFrameTiming';
const _timelineTaskName = 'LexiQuestAdventureMapListTransition';
const _timelineTaskFilterKey = 'lexiquest.adventure.map-list-transition';
const _maximumTimelineSourceEvents = 100000;

final _now = DateTime.utc(2026, 9, 4, 10);
const _ownerId = 'owner-001';
var _benchmarkSink = 0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Adventure production profile stays within approved Android budgets',
    (tester) async {
      final physicalSize = tester.view.physicalSize;
      final devicePixelRatio = tester.view.devicePixelRatio;
      final logicalSize = physicalSize / devicePixelRatio;
      final deviceViewportCaptured =
          physicalSize.width > 0 &&
          physicalSize.height > 0 &&
          logicalSize.width > 0 &&
          logicalSize.height > 0 &&
          devicePixelRatio > 0;

      const validator = AdventureWorldCatalogValidator();
      final catalog = PackagedAdventureWorldCatalog.forLocale('th');
      final catalogValidation = validator.validate(
        catalog,
        packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
      );
      final today = _today();
      final configuration = _configuration();
      final entry = _entryUseCases(
        catalog: catalog,
        todayIdentity: today,
        learningIdentity: configuration,
      );

      final entryRun = await _measureAsync<AdventureProductEntryDecision>(
        warmups: _warmupCount,
        samples: _sampleCount,
        action: (index) => entry.resolve(
          AdventureEntryRequest(
            ownerId: _ownerId,
            entryAttemptId: _uuidFor(index),
            occurredAtUtc: _now,
            sessionChoice: TodayExperiencePresentation.adventure,
          ),
        ),
        consume: _consumeEntry,
      );
      final entryP95Us = _p95(entryRun.samples);

      final journeyReader = AdventureJourneyUseCases();
      final journeyRequest = AdventureJourneyRequest(
        ownerId: _ownerId,
        evaluatedAtUtc: _now,
        catalog: catalog,
        today: today,
      );
      final journeyRun = await _measureAsync<AdventureJourneySnapshot>(
        warmups: _warmupCount,
        samples: _sampleCount,
        action: (_) => journeyReader.compose(journeyRequest),
        consume: _consumeJourney,
      );
      final journeyP95Us = _p95(journeyRun.samples);
      final projectedThreeNodes = journeyRun.last.nodes.length == 3;

      final renderSamples = <int>[];
      AdventureJourneySnapshot? renderedSnapshot;
      for (var index = 0; index < _warmupCount + _sampleCount; index++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final stopwatch = Stopwatch()..start();
        final localCatalog = PackagedAdventureWorldCatalog.forLocale('th');
        validator.requireValid(
          localCatalog,
          packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
        );
        final snapshot = await journeyReader.compose(
          AdventureJourneyRequest(
            ownerId: _ownerId,
            evaluatedAtUtc: _now,
            catalog: localCatalog,
            today: today,
          ),
        );
        await tester.pumpWidget(_adventureApp(snapshot));
        await tester.pump();
        final meaningfulRender =
            find.byKey(const ValueKey('adventure-hub')).evaluate().isNotEmpty &&
            find
                .byKey(const ValueKey('adventure-map-list-switch'))
                .evaluate()
                .isNotEmpty &&
            find
                .byKey(const ValueKey('adventure-map-node:today-mission'))
                .evaluate()
                .isNotEmpty;
        stopwatch.stop();
        if (!meaningfulRender) {
          fail('Adventure did not reach its meaningful local render marker.');
        }
        renderedSnapshot = snapshot;
        if (index >= _warmupCount) {
          renderSamples.add(stopwatch.elapsedMicroseconds);
        }
      }
      final renderP95Us = _p95(renderSamples);

      final mission = journeyRun.last.primaryMission;
      if (mission == null) {
        fail('The canonical Today snapshot did not produce a mission.');
      }
      const composer = CanonicalAdventureSessionComposer();
      const bridge = AdventureLearningBridge();
      final sessionPreparationRun = await _measureSessionPreparationPairs(
        warmups: _warmupCount,
        samples: _sampleCount,
        composer: composer,
        bridge: bridge,
        mission: mission,
        today: today,
        configuration: configuration,
        entry: entryRun.last,
      );
      final standardSessionStartP95Us = _p95(
        sessionPreparationRun.standardSamples,
      );
      final adventureSessionStartP95Us = _p95(
        sessionPreparationRun.adventureSamples,
      );
      final sessionOverheadP95Us = _p95(sessionPreparationRun.overheadSamples);
      final commandAuthorityPreserved =
          sessionPreparationRun.allCommandsEquivalent;
      final pairedSessionStartInputsEquivalent =
          sessionPreparationRun.allInputsEquivalent;
      final snapshotAuthorityPreserved =
          sessionPreparationRun.lastAdventure.plan.sourceEvaluatedAtUtc ==
              today.evaluatedAtUtc &&
          _sameContent(
            sessionPreparationRun.lastAdventure.plan.content,
            mission.content,
          ) &&
          identical(
            sessionPreparationRun.lastAdventure.plan.configuration,
            configuration,
          );
      final evidenceAuthorityPreserved = !sessionPreparationRun
          .lastAdventure
          .plan
          .origin
          .toJson()
          .containsKey('evidence');

      final actualSessionConfiguration =
          sessionPreparationRun.lastAdventure.plan.configuration;
      final timeoutPolicy = _performanceTimeoutPolicy.toString();
      if (timeoutPolicy != 'none') {
        fail('The performance test no longer has an unbounded timeout policy.');
      }
      final pauseRun = await _verifyUntimedSessionAfterInjectedClock(
        launch: sessionPreparationRun.lastAdventure,
        bridge: bridge,
      );
      var missionStarts = 0;
      await tester.pumpWidget(
        _adventureApp(
          renderedSnapshot!,
          onStartMission: (_) async {
            missionStarts += 1;
          },
        ),
      );
      await tester.pump();
      final missionButton = find.byKey(
        const ValueKey('adventure-start-mission'),
      );
      final missionAvailableAfterPause =
          missionButton.evaluate().length == 1 &&
          tester.widget<ButtonStyleButton>(missionButton).onPressed != null &&
          missionStarts == 0 &&
          pauseRun.sessionAvailableAfterClockAdvance;

      await tester.ensureVisible(
        find.byKey(const ValueKey('adventure-map-list-switch')),
      );
      await tester.pumpAndSettle();
      await _selectJourneyPresentation(tester, showList: true);
      await _selectJourneyPresentation(tester, showList: false);
      final transitionFrames = await _measureSettledTransitionFrames(
        binding: binding,
        tester: tester,
        transitions: _sampleCount,
      );
      final frameTimes = transitionFrames.frameTimesUs;
      final frameP95Us = _p95(frameTimes);
      final frameMaxUs = frameTimes.reduce(
        (left, right) => left >= right ? left : right,
      );
      final frameCoveragePassed =
          transitionFrames.transitionsWithFrames == _sampleCount &&
          transitionFrames.minimumFramesPerTransition >= 1 &&
          frameTimes.length >= _sampleCount;

      final timeline = await binding.traceTimeline(() async {
        for (var index = 0; index < _sampleCount; index++) {
          final task = developer.TimelineTask(
            filterKey: _timelineTaskFilterKey,
          );
          task.start(
            _timelineTaskName,
            arguments: <String, Object?>{'transitionIndex': index},
          );
          try {
            await _selectJourneyPresentation(tester, showList: index.isEven);
          } finally {
            task.finish();
          }
        }
      }, streams: const <String>['Dart']);
      final timelineEvents = timeline.traceEvents ?? const [];
      final timelineTaskSummary = _summarizeTransitionTimeline(timelineEvents);
      if (timelineTaskSummary.transitionMarkerCount != _sampleCount) {
        fail(
          'Expected $_sampleCount bounded transition timeline markers, found '
          '${timelineTaskSummary.transitionMarkerCount}.',
        );
      }
      final timelineSynchronousTaskSamples =
          timelineTaskSummary.synchronousTaskDurationsUs;
      if (timelineSynchronousTaskSamples.isEmpty) {
        fail('The bounded transition timeline contained no synchronous work.');
      }
      final timelineTaskP95Us = _p95(timelineSynchronousTaskSamples);
      final timelineTaskMaxUs = timelineSynchronousTaskSamples.reduce(
        (left, right) => left >= right ? left : right,
      );
      final longFrameCount = frameTimes
          .where((value) => value > _longFrameOrTaskBudgetUs)
          .length;
      final timelineLongTaskCount = timelineSynchronousTaskSamples
          .where((value) => value > _longFrameOrTaskBudgetUs)
          .length;

      final entryPassed = entryP95Us <= _entryBudgetUs;
      final journeyPassed =
          journeyP95Us <= _journeyBudgetUs && projectedThreeNodes;
      final renderPassed = renderP95Us <= _renderBudgetUs;
      final sessionPassed =
          sessionOverheadP95Us <= _sessionOverheadBudgetUs &&
          commandAuthorityPreserved &&
          pairedSessionStartInputsEquivalent &&
          snapshotAuthorityPreserved &&
          evidenceAuthorityPreserved;
      final transitionsPassed =
          frameCoveragePassed &&
          frameP95Us <= _frameBudgetUs &&
          frameMaxUs <= _longFrameOrTaskBudgetUs &&
          longFrameCount == 0;
      final timelineTasksPassed =
          timelineTaskSummary.transitionMarkerCount == _sampleCount &&
          timelineSynchronousTaskSamples.isNotEmpty &&
          timelineTaskMaxUs <= _longFrameOrTaskBudgetUs &&
          timelineLongTaskCount == 0;
      final pausePassed = missionAvailableAfterPause;
      final allBudgetsPassed =
          kProfileMode &&
          catalogValidation.isValid &&
          entryPassed &&
          journeyPassed &&
          renderPassed &&
          sessionPassed &&
          transitionsPassed &&
          timelineTasksPassed &&
          pausePassed &&
          deviceViewportCaptured;

      final profile = <String, Object?>{
        'schemaVersion': 1,
        'profileId': _profileId,
        'buildMode': kProfileMode ? 'profile' : 'not-profile',
        'benchmarkSink': _benchmarkSink,
        'percentileMethod': 'nearest-rank',
        'deviceViewport': <String, double>{
          'physicalWidthPx': physicalSize.width,
          'physicalHeightPx': physicalSize.height,
          'logicalWidth': logicalSize.width,
          'logicalHeight': logicalSize.height,
          'devicePixelRatio': devicePixelRatio,
        },
        'sampleCounts': <String, int>{
          'localEntryResolution': entryRun.samples.length,
          'journeyProjection': journeyRun.samples.length,
          'firstMeaningfulRender': renderSamples.length,
          'standardSessionStart': sessionPreparationRun.standardSamples.length,
          'adventureSessionStart':
              sessionPreparationRun.adventureSamples.length,
          'pairedSessionStartOverhead':
              sessionPreparationRun.overheadSamples.length,
          'mapListTransitions': _sampleCount,
          'mapListTransitionsWithFrames':
              transitionFrames.transitionsWithFrames,
          'mapListMinimumFramesPerTransition':
              transitionFrames.minimumFramesPerTransition,
          'mapListFrames': frameTimes.length,
          'timelineTransitionMarkers':
              timelineTaskSummary.transitionMarkerCount,
        },
        'budgets': <String, Object?>{
          'localEntryResolutionP95Ms': _milliseconds(_entryBudgetUs),
          'journeyProjectionP95Ms': _milliseconds(_journeyBudgetUs),
          'firstMeaningfulRenderP95Ms': _milliseconds(_renderBudgetUs),
          'adventureSessionStartOverheadP95Ms': _milliseconds(
            _sessionOverheadBudgetUs,
          ),
          'mapListFrameP95Ms': _milliseconds(_frameBudgetUs),
          'longFrameOrTaskMs': _milliseconds(_longFrameOrTaskBudgetUs),
        },
        'metrics': <String, Object?>{
          'localEntryResolutionP95Ms': _milliseconds(entryP95Us),
          'journeyProjectionP95Ms': _milliseconds(journeyP95Us),
          'firstMeaningfulRenderP95Ms': _milliseconds(renderP95Us),
          'standardSessionStartP95Ms': _milliseconds(standardSessionStartP95Us),
          'adventureSessionStartP95Ms': _milliseconds(
            adventureSessionStartP95Us,
          ),
          'adventureSessionStartOverheadP95Ms': _milliseconds(
            sessionOverheadP95Us,
          ),
          'mapListFrameP95Ms': _milliseconds(frameP95Us),
          'mapListFrameMaxMs': _milliseconds(frameMaxUs),
          'timelineSynchronousTaskP95Ms': _milliseconds(timelineTaskP95Us),
          'timelineSynchronousTaskMaxMs': _milliseconds(timelineTaskMaxUs),
          'mapListLongFrameCount': longFrameCount,
          'timelineLongTaskCount': timelineLongTaskCount,
          'timelineSynchronousTaskCount': timelineSynchronousTaskSamples.length,
          'timelineSourceEventCount': timelineTaskSummary.sourceEventCount,
        },
        'passes': <String, bool>{
          'profileMode': kProfileMode,
          'localAssetsValid': catalogValidation.isValid,
          'localEntryResolution': entryPassed,
          'threeNodeJourneyProjection': journeyPassed,
          'firstMeaningfulRender': renderPassed,
          'adventureSessionStartOverhead': sessionPassed,
          'mapListFrameCoverage': frameCoveragePassed,
          'mapListTransitions': transitionsPassed,
          'timelineLongTasks': timelineTasksPassed,
          'learnerPause': pausePassed,
          'deviceViewportCaptured': deviceViewportCaptured,
        },
        'authorityInvariants': <String, bool>{
          'threeNodeProjection': projectedThreeNodes,
          'standardAdventureCommandsEquivalent': commandAuthorityPreserved,
          'canonicalSnapshotPinned': snapshotAuthorityPreserved,
          'evidenceAuthorityUnchanged': evidenceAuthorityPreserved,
          'pairedSessionStartInputsEquivalent':
              pairedSessionStartInputsEquivalent,
        },
        'measurementScope': <String, String>{
          'firstMeaningfulRender':
              'packaged catalog and asset validation, production journey '
              'projection, and AdventureHubScreen first meaningful frame',
          'sessionStartOverhead':
              'Per-sample Adventure canonical compose+bridge preparation '
              'minus the equivalent production Standard LessonStartCommand '
              'preparation using the same mission, configuration, owner, '
              'session ID, and start instant; alternating pair order limits '
              'ordering bias, p95 is calculated from paired differences, and '
              'the unchanged shared controller start is excluded',
          'mapListFrame':
              'maximum of Flutter build and raster duration for every frame '
              'captured in 20 isolated fully settled map/list transition '
              'groups, each required to contain a real transition frame',
          'mapListTask':
              '20 Dart TimelineTask markers bound the tap-through-settle '
              'trace; long tasks are complete or paired synchronous Dart '
              'events within that trace, and only aggregate '
              'p95/max/count values are retained, never the raw timeline',
          'learnerPause':
              'the canonical Adventure launch is started through the '
              'production UnifiedLessonController with its injected '
              'configuration monotonic clock advanced beyond maximum active '
              'effort; the controller must observe the jump, exclude idle '
              'time, and remain active and operation-available',
        },
        'learnerPause': <String, Object?>{
          'timeoutPolicy': timeoutPolicy,
          'sessionTiming': actualSessionConfiguration.timing.kind.name,
          'maximumActiveEffortMs': pauseRun.maximumActiveEffort.inMilliseconds,
          'fakeClockAdvanceMs': pauseRun.injectedClockAdvance.inMilliseconds,
          'clockSource': pauseRun.clockSource,
          'appObservedMonotonicMs':
              pauseRun.appObservedMonotonic.inMilliseconds,
          'configurationActiveEffortMs':
              pauseRun.configurationActiveEffort.inMilliseconds,
          'excludedIdleMs': pauseRun.excludedIdle.inMilliseconds,
          'idleTimeExcluded': pauseRun.idleTimeExcluded,
          'configurationIdle': pauseRun.configurationIdle,
          'sessionStatus': pauseRun.sessionStatus,
          'configurationAcceptsOperations':
              pauseRun.configurationAcceptsOperations,
          'boundaryExceeded': pauseRun.boundaryExceeded,
          'missionAvailableAfterPause': missionAvailableAfterPause,
        },
        'allBudgetsPassed': allBudgetsPassed,
      };
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['adventurePerformance'] = profile;
      debugPrintSynchronously(
        'LEXIQUEST_ADVENTURE_PERFORMANCE ${jsonEncode(profile)}',
      );

      expect(kProfileMode, isTrue, reason: 'Run this target in profile mode.');
      expect(
        catalogValidation.isValid,
        isTrue,
        reason: catalogValidation.violations.toString(),
      );
      expect(
        entryP95Us,
        lessThanOrEqualTo(_entryBudgetUs),
        reason: 'Local entry resolution p95 exceeded 50 ms.',
      );
      expect(projectedThreeNodes, isTrue);
      expect(
        journeyP95Us,
        lessThanOrEqualTo(_journeyBudgetUs),
        reason: 'Three-node journey projection p95 exceeded 100 ms.',
      );
      expect(
        renderP95Us,
        lessThanOrEqualTo(_renderBudgetUs),
        reason: 'First meaningful Adventure render p95 exceeded 1.5 s.',
      );
      expect(commandAuthorityPreserved, isTrue);
      expect(pairedSessionStartInputsEquivalent, isTrue);
      expect(snapshotAuthorityPreserved, isTrue);
      expect(evidenceAuthorityPreserved, isTrue);
      expect(
        sessionOverheadP95Us,
        lessThanOrEqualTo(_sessionOverheadBudgetUs),
        reason: 'Adventure-added session-start overhead p95 exceeded 150 ms.',
      );
      expect(
        frameP95Us,
        lessThanOrEqualTo(_frameBudgetUs),
        reason: 'Map/list frame p95 exceeded 16.7 ms.',
      );
      expect(
        frameCoveragePassed,
        isTrue,
        reason: 'Fewer than 20 frames covered the 20 map/list transitions.',
      );
      expect(longFrameCount, 0, reason: 'A map/list frame exceeded 100 ms.');
      expect(
        timelineLongTaskCount,
        0,
        reason: 'A timeline-derived map/list task exceeded 100 ms.',
      );
      expect(
        missionAvailableAfterPause,
        isTrue,
        reason: 'Learner pause disabled or started the mission.',
      );
    },
    timeout: _performanceTimeoutPolicy,
  );
}

AdventureEntryUseCases _entryUseCases({
  required AdventureWorldCatalog catalog,
  required Object todayIdentity,
  required Object learningIdentity,
}) => AdventureEntryUseCases(
  rollout: AdventureRolloutGate(
    features: const BuildFeatureRegistry(<Feature, FeatureState>{
      Feature.adventureMotivation: FeatureState.enabled,
    }),
    requiredDependenciesReady: () => true,
    catalogReadiness: () => AdventureCatalogReadiness.ready,
  ),
  catalog: catalog,
  todayHubIdentity: todayIdentity,
  learningIdentity: learningIdentity,
);

Widget _adventureApp(
  AdventureJourneySnapshot snapshot, {
  Future<void> Function(AdventureMissionRef)? onStartMission,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: M3Theme.lightTheme,
  home: AdventureHubScreen(
    snapshot: snapshot,
    reaction: const AdventureReactionSelector().select(
      catalogVersion: AdventureReactionCatalog.v1Version,
      trigger: AdventureReactionTrigger.missionReady,
      variantSeed: 0,
    ),
    rewardOwnership: const RewardAccount(
      coinBalance: 0,
      catalogVersion: RewardCatalog.version,
      ownedItemIds: <String>{},
      equippedBySlot: <String, String>{},
      transactionCount: 0,
    ),
    onStartMission: onStartMission ?? (_) async {},
    onPresentationChanged: (_) {},
    onRefresh: () {},
    reactionLanguage: AdventureReactionLanguage.th,
  ),
);

Future<void> _selectJourneyPresentation(
  WidgetTester tester, {
  required bool showList,
}) async {
  await tester.tap(find.text(showList ? 'รายการ' : 'แผนที่'));
  await tester.pumpAndSettle();
  final target = find.byKey(
    ValueKey(showList ? 'adventure-map-list' : 'adventure-map'),
  );
  if (target.evaluate().length != 1) {
    fail('Adventure map/list transition did not settle.');
  }
}

Future<
  ({
    List<int> frameTimesUs,
    int transitionsWithFrames,
    int minimumFramesPerTransition,
  })
>
_measureSettledTransitionFrames({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required int transitions,
}) async {
  final frameTimesUs = <int>[];
  var transitionsWithFrames = 0;
  int? minimumFramesPerTransition;

  for (var transition = 0; transition < transitions; transition++) {
    final reportKey = '$_frameReportKey:$transition';
    await binding.watchPerformance(
      () => _selectJourneyPresentation(tester, showList: transition.isEven),
      reportKey: reportKey,
    );
    final rawSummary = binding.reportData?.remove(reportKey);
    if (rawSummary is! Map) {
      fail('Flutter did not return frame timing for transition $transition.');
    }
    final frameSummary = Map<String, dynamic>.from(rawSummary);
    final buildTimes = _integerList(frameSummary['frame_build_times']);
    final rasterTimes = _integerList(frameSummary['frame_rasterizer_times']);
    if (buildTimes.isEmpty || buildTimes.length != rasterTimes.length) {
      fail(
        'Flutter returned inconsistent frame timing for transition '
        '$transition.',
      );
    }
    final transitionFrameTimes = <int>[
      for (var frame = 0; frame < buildTimes.length; frame++)
        buildTimes[frame] >= rasterTimes[frame]
            ? buildTimes[frame]
            : rasterTimes[frame],
    ];
    transitionsWithFrames += 1;
    minimumFramesPerTransition = switch (minimumFramesPerTransition) {
      null => transitionFrameTimes.length,
      final current when transitionFrameTimes.length < current =>
        transitionFrameTimes.length,
      final current => current,
    };
    frameTimesUs.addAll(transitionFrameTimes);
  }

  return (
    frameTimesUs: List<int>.unmodifiable(frameTimesUs),
    transitionsWithFrames: transitionsWithFrames,
    minimumFramesPerTransition: minimumFramesPerTransition ?? 0,
  );
}

Future<
  ({
    Duration maximumActiveEffort,
    Duration injectedClockAdvance,
    String clockSource,
    Duration appObservedMonotonic,
    Duration configurationActiveEffort,
    Duration excludedIdle,
    bool idleTimeExcluded,
    bool configurationIdle,
    String sessionStatus,
    bool configurationAcceptsOperations,
    bool boundaryExceeded,
    bool sessionAvailableAfterClockAdvance,
  })
>
_verifyUntimedSessionAfterInjectedClock({
  required AdventureLearningLaunch launch,
  required AdventureLearningBridge bridge,
}) async {
  final configuration = launch.plan.configuration;
  if (!configuration.timing.isUntimedAlternative) {
    fail(
      'The canonical Adventure launch did not retain 10-minute untimed timing.',
    );
  }
  final maximumActiveEffort =
      configuration.timing.maximumActiveEffort ??
      fail('The canonical Adventure launch lost its active-effort boundary.');
  if (maximumActiveEffort != const Duration(minutes: 10)) {
    fail(
      'The canonical Adventure launch did not retain 10-minute untimed timing.',
    );
  }

  final repository = _PerformanceSessionRepository(launch);
  var nextId = 0;
  final learning = LearningUseCases(
    owners: const _PerformanceOwnerRepository(),
    repository: repository,
    generateId: () => 'performance-controller-${++nextId}',
    nowUtc: () => _now,
    buildInfo: const AppBuildInfo(
      version: 'adventure-performance',
      buildId: 'adventure-performance',
    ),
  );
  final clock = _InjectedConfigurationClock();
  final controller = UnifiedLessonController(
    learning: learning,
    adapter: const TypedRecallModeAdapter(),
    configurationMonotonicMicros: clock.read,
  );
  try {
    await bridge.start(
      launch: launch,
      controller: controller,
      revalidateConfiguration: (candidate) async {
        if (!identical(candidate, configuration)) {
          throw StateError(
            'Adventure session configuration authority drifted.',
          );
        }
        return candidate;
      },
    );
    final injectedClockAdvance =
        maximumActiveEffort + _learnerPauseBoundaryMargin;
    clock.advance(injectedClockAdvance);
    await controller.recordActiveLearningInteraction(
      launch.command.startedAtUtc.add(injectedClockAdvance),
    );

    final appObservedMonotonic = clock.lastObserved;
    final configurationActiveEffort = controller.configurationActiveEffort;
    final excludedIdle = appObservedMonotonic - configurationActiveEffort;
    final boundaryExceeded = appObservedMonotonic > maximumActiveEffort;
    final idleTimeExcluded =
        configurationActiveEffort == _untimedIdleCutoff &&
        excludedIdle == injectedClockAdvance - _untimedIdleCutoff;
    final sessionStatus = controller.state.status.name;
    final configurationAcceptsOperations =
        controller.configurationAcceptsOperations;
    final sessionAvailableAfterClockAdvance =
        boundaryExceeded &&
        idleTimeExcluded &&
        !controller.configurationLimitReached &&
        configurationAcceptsOperations &&
        sessionStatus == LessonSessionStatus.active.name &&
        repository.configurationActiveEffort == configurationActiveEffort;

    return (
      maximumActiveEffort: maximumActiveEffort,
      injectedClockAdvance: injectedClockAdvance,
      clockSource: 'configurationMonotonicMicros',
      appObservedMonotonic: appObservedMonotonic,
      configurationActiveEffort: configurationActiveEffort,
      excludedIdle: excludedIdle,
      idleTimeExcluded: idleTimeExcluded,
      configurationIdle: controller.configurationIsIdle,
      sessionStatus: sessionStatus,
      configurationAcceptsOperations: configurationAcceptsOperations,
      boundaryExceeded: boundaryExceeded,
      sessionAvailableAfterClockAdvance: sessionAvailableAfterClockAdvance,
    );
  } finally {
    controller.dispose();
  }
}

final class _InjectedConfigurationClock {
  Duration _elapsed = Duration.zero;
  Duration _lastObserved = Duration.zero;

  Duration get lastObserved => _lastObserved;

  int read() {
    _lastObserved = _elapsed;
    return _elapsed.inMicroseconds;
  }

  void advance(Duration delta) {
    if (delta <= Duration.zero) {
      throw ArgumentError.value(delta, 'delta', 'must be positive');
    }
    _elapsed += delta;
  }
}

final class _PerformanceOwnerRepository implements LocalOwnerRepository {
  const _PerformanceOwnerRepository();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: _ownerId, createdAtUtc: _now);

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      Future<LocalOwner>.error(
        UnsupportedError('Performance profile never binds Firebase identity.'),
      );
}

final class _PerformanceSessionRepository
    implements LearningRepository, SessionConfiguredLearningRepository {
  _PerformanceSessionRepository(this._launch);

  final AdventureLearningLaunch _launch;
  Duration _configurationActiveEffort = Duration.zero;

  Duration get configurationActiveEffort => _configurationActiveEffort;

  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) async {
    if (ownerId != _launch.command.ownerId ||
        sessionId != _launch.command.sessionId) {
      return null;
    }
    return LearningSessionSummary(
      id: sessionId,
      ownerId: ownerId,
      activityType: _launch.command.mode.name,
      state: 'active',
      startedAtUtc: _launch.command.startedAtUtc,
      correctCount: 0,
      wrongCount: 0,
      score: 0,
      appVersion: 'adventure-performance',
      buildId: 'adventure-performance',
      sessionConfiguration: _launch.plan.configuration,
      configurationActiveEffort: _configurationActiveEffort,
    );
  }

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) async {
    if (ownerId != _launch.command.ownerId ||
        sessionId != _launch.command.sessionId ||
        configurationIdentity != _launch.plan.configuration.contentIdentity ||
        delta <= Duration.zero) {
      throw StateError('Performance session effort authority drifted.');
    }
    _configurationActiveEffort += delta;
    return _configurationActiveEffort;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({List<int> samples, T last})> _measureAsync<T>({
  required int warmups,
  required int samples,
  required Future<T> Function(int index) action,
  required void Function(T value) consume,
}) async {
  for (var index = 0; index < warmups; index++) {
    consume(await action(index));
  }
  final durations = <int>[];
  late T last;
  for (var index = 0; index < samples; index++) {
    final stopwatch = Stopwatch()..start();
    last = await action(index + warmups);
    consume(last);
    stopwatch.stop();
    durations.add(stopwatch.elapsedMicroseconds);
  }
  return (samples: List<int>.unmodifiable(durations), last: last);
}

Future<
  ({
    List<int> standardSamples,
    List<int> adventureSamples,
    List<int> overheadSamples,
    LessonStartCommand lastStandard,
    AdventureLearningLaunch lastAdventure,
    bool allCommandsEquivalent,
    bool allInputsEquivalent,
  })
>
_measureSessionPreparationPairs({
  required int warmups,
  required int samples,
  required CanonicalAdventureSessionComposer composer,
  required AdventureLearningBridge bridge,
  required AdventureMissionRef mission,
  required TodayHubSnapshot today,
  required SessionConfiguration configuration,
  required AdventureProductEntryDecision entry,
}) async {
  final standardSamples = <int>[];
  final adventureSamples = <int>[];
  final overheadSamples = <int>[];
  late LessonStartCommand lastStandard;
  late AdventureLearningLaunch lastAdventure;
  var allCommandsEquivalent = true;
  var allInputsEquivalent = true;

  for (var index = 0; index < warmups + samples; index++) {
    final sessionId = 'session:performance:$index';
    late ({LessonStartCommand value, int elapsedUs}) standard;
    late ({AdventureLearningLaunch value, int elapsedUs}) adventure;

    ({LessonStartCommand value, int elapsedUs}) prepareStandard() {
      final stopwatch = Stopwatch()..start();
      final value = LessonStartCommand(
        mode: configuration.mode,
        sessionId: sessionId,
        startedAtUtc: _now,
        itemCount: mission.content.length,
        ownerId: _ownerId,
        configuration: configuration,
      );
      stopwatch.stop();
      _consumeCommand(value);
      return (value: value, elapsedUs: stopwatch.elapsedMicroseconds);
    }

    Future<({AdventureLearningLaunch value, int elapsedUs})>
    prepareAdventure() async {
      final stopwatch = Stopwatch()..start();
      final plan = await composer.compose(
        mission: mission,
        today: today,
        requestedConfiguration: configuration,
        entry: entry,
      );
      final value = bridge.prepare(
        plan: plan,
        activeOwnerId: _ownerId,
        sessionId: sessionId,
        startedAtUtc: _now,
      );
      stopwatch.stop();
      _consumeLaunch(value);
      return (value: value, elapsedUs: stopwatch.elapsedMicroseconds);
    }

    if (index.isEven) {
      standard = prepareStandard();
      adventure = await prepareAdventure();
    } else {
      adventure = await prepareAdventure();
      standard = prepareStandard();
    }
    lastStandard = standard.value;
    lastAdventure = adventure.value;

    final commandsEquivalent =
        jsonEncode(_commandPayload(adventure.value.command)) ==
        jsonEncode(_commandPayload(standard.value));
    allCommandsEquivalent &= commandsEquivalent;
    allInputsEquivalent &=
        commandsEquivalent &&
        identical(standard.value.configuration, configuration) &&
        identical(adventure.value.plan.configuration, configuration) &&
        adventure.value.plan.sourceEvaluatedAtUtc == today.evaluatedAtUtc &&
        _sameContent(adventure.value.plan.content, mission.content);

    if (index >= warmups) {
      standardSamples.add(standard.elapsedUs);
      adventureSamples.add(adventure.elapsedUs);
      overheadSamples.add(adventure.elapsedUs - standard.elapsedUs);
    }
  }

  return (
    standardSamples: List<int>.unmodifiable(standardSamples),
    adventureSamples: List<int>.unmodifiable(adventureSamples),
    overheadSamples: List<int>.unmodifiable(overheadSamples),
    lastStandard: lastStandard,
    lastAdventure: lastAdventure,
    allCommandsEquivalent: allCommandsEquivalent,
    allInputsEquivalent: allInputsEquivalent,
  );
}

({
  List<int> synchronousTaskDurationsUs,
  int transitionMarkerCount,
  int sourceEventCount,
})
_summarizeTransitionTimeline(Iterable<Object?> events) {
  final markerStartsById = <String, int>{};
  final synchronousStacks = <String, List<({String name, int startedAtUs})>>{};
  final synchronousTaskDurationsUs = <int>[];
  var transitionMarkerCount = 0;
  var sourceEventCount = 0;

  for (final rawEvent in events) {
    sourceEventCount += 1;
    if (sourceEventCount > _maximumTimelineSourceEvents) {
      throw StateError(
        'Bounded transition trace exceeded $_maximumTimelineSourceEvents '
        'source events.',
      );
    }
    final dynamic event = rawEvent;
    final Object? rawJson = event.json;
    if (rawJson is! Map) continue;
    final json = Map<String, Object?>.from(rawJson);
    final timestamp = json['ts'];
    if (timestamp is! num) continue;
    final phase = json['ph'];
    final name = json['name']?.toString() ?? '<unnamed>';

    if (name == _timelineTaskName) {
      final arguments = json['args'];
      if (arguments is! Map ||
          arguments['filterKey'] != _timelineTaskFilterKey) {
        continue;
      }
      final id = _timelineEventId(json['id'] ?? json['id2']);
      if (id == null) continue;
      if (phase == 'b' || phase == 'S') {
        markerStartsById[id] = timestamp.round();
      } else if (phase == 'e' || phase == 'F') {
        final startedAt = markerStartsById.remove(id);
        if (startedAt != null && timestamp >= startedAt) {
          transitionMarkerCount += 1;
        }
      }
      continue;
    }

    if (phase == 'X') {
      final duration = json['dur'];
      if (duration is num && duration >= 0) {
        synchronousTaskDurationsUs.add(duration.round());
      }
      continue;
    }
    final threadKey = '${json['pid'] ?? ''}:${json['tid'] ?? ''}';
    if (phase == 'B') {
      synchronousStacks
          .putIfAbsent(threadKey, () => <({String name, int startedAtUs})>[])
          .add((name: name, startedAtUs: timestamp.round()));
      continue;
    }
    if (phase == 'E') {
      final stack = synchronousStacks[threadKey];
      if (stack != null && stack.isNotEmpty) {
        final started = stack.removeLast();
        if (timestamp >= started.startedAtUs) {
          synchronousTaskDurationsUs.add(
            timestamp.round() - started.startedAtUs,
          );
        }
      }
    }
  }

  return (
    synchronousTaskDurationsUs: List<int>.unmodifiable(
      synchronousTaskDurationsUs,
    ),
    transitionMarkerCount: transitionMarkerCount,
    sourceEventCount: sourceEventCount,
  );
}

String? _timelineEventId(Object? value) {
  if (value == null) return null;
  if (value is Map) {
    final nested = value['local'] ?? value['global'];
    return nested?.toString();
  }
  return value.toString();
}

int _p95(List<int> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  final sorted = values.toList()..sort();
  final index = (sorted.length * 0.95).ceil() - 1;
  return sorted[index];
}

double _milliseconds(int microseconds) =>
    double.parse((microseconds / 1000).toStringAsFixed(3));

List<int> _integerList(Object? value) {
  if (value is! List || value.any((item) => item is! num)) {
    throw StateError('Expected a numeric Flutter frame timing list.');
  }
  return value.map((item) => (item as num).toInt()).toList(growable: false);
}

void _consumeEntry(AdventureProductEntryDecision value) {
  _benchmarkSink ^= Object.hash(
    value.entryAttemptId,
    value.destination,
    value.catalogVersion,
  );
}

void _consumeJourney(AdventureJourneySnapshot value) {
  _benchmarkSink ^= Object.hash(
    value.inputFingerprintSha256,
    value.nodes.length,
    value.primaryMission?.missionId,
  );
}

void _consumeCommand(LessonStartCommand value) {
  _benchmarkSink ^= Object.hash(
    value.sessionId,
    value.itemCount,
    value.configuration?.contentIdentity,
  );
}

void _consumeLaunch(AdventureLearningLaunch value) {
  _benchmarkSink ^= Object.hash(
    value.plan.planId,
    value.command.sessionId,
    value.content.length,
  );
}

Map<String, Object?> _commandPayload(LessonStartCommand command) =>
    <String, Object?>{
      'mode': command.mode.name,
      'sessionId': command.sessionId,
      'startedAtUtc': command.startedAtUtc.toIso8601String(),
      'itemCount': command.itemCount,
      'ownerId': command.ownerId,
      'configuration': command.configuration?.stableSerialization,
    };

bool _sameContent(List<ContentIdentity> left, List<ContentIdentity> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _uuidFor(int index) =>
    '018f1f90-7b2d-4d58-8d7d-${index.toRadixString(16).padLeft(12, '0')}';

SessionConfiguration _configuration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: _ownerId,
  mode: LessonMode.typedRecall,
  itemCount: 2,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 1,
  timing: const SessionTiming.untimedAlternative(
    maximumActiveEffort: Duration(minutes: 10),
  ),
  packIdentity: null,
  protocolId: 'protocol-local',
  protocolVersion: '1.0.0',
  protocolLimitsIdentity: 'limits-performance-v1',
);

TodayHubSnapshot _today() => TodayHubSnapshot(
  ownerId: _ownerId,
  evaluatedAtUtc: _now,
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: null,
  assignedAssessment: null,
  reviewWork: <TodayHubReviewWorkItem>[_review('word-b'), _review('word-a')],
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
    source: 'packaged-performance-fixture',
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
        source: 'packaged-performance-fixture',
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
