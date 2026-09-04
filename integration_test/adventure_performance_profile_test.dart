import 'dart:convert';

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
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
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
const _learnerPause = Duration(seconds: 3);
const _frameReportKey = 'adventureMapListFrameTiming';

final _now = DateTime.utc(2026, 9, 4, 10);
const _ownerId = 'owner-001';
var _benchmarkSink = 0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Adventure production profile stays within approved Android budgets',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final standardRun = _measureSync<LessonStartCommand>(
        warmups: _warmupCount,
        samples: _sampleCount,
        action: (_) => LessonStartCommand(
          mode: configuration.mode,
          sessionId: 'session:performance',
          startedAtUtc: _now,
          itemCount: mission.content.length,
          ownerId: _ownerId,
          configuration: configuration,
        ),
        consume: _consumeCommand,
      );
      final adventureRun = await _measureAsync<AdventureLearningLaunch>(
        warmups: _warmupCount,
        samples: _sampleCount,
        action: (_) async {
          final plan = await composer.compose(
            mission: mission,
            today: today,
            requestedConfiguration: configuration,
            entry: entryRun.last,
          );
          return bridge.prepare(
            plan: plan,
            activeOwnerId: _ownerId,
            sessionId: 'session:performance',
            startedAtUtc: _now,
          );
        },
        consume: _consumeLaunch,
      );
      final standardSessionStartP95Us = _p95(standardRun.samples);
      final adventureSessionStartP95Us = _p95(adventureRun.samples);
      final sessionOverheadP95Us =
          adventureSessionStartP95Us > standardSessionStartP95Us
          ? adventureSessionStartP95Us - standardSessionStartP95Us
          : 0;
      final commandAuthorityPreserved =
          jsonEncode(_commandPayload(adventureRun.last.command)) ==
          jsonEncode(_commandPayload(standardRun.last));
      final snapshotAuthorityPreserved =
          adventureRun.last.plan.sourceEvaluatedAtUtc == today.evaluatedAtUtc &&
          _sameContent(adventureRun.last.plan.content, mission.content) &&
          identical(adventureRun.last.plan.configuration, configuration);
      final evidenceAuthorityPreserved = !adventureRun.last.plan.origin
          .toJson()
          .containsKey('evidence');

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
      await tester.runAsync(() => Future<void>.delayed(_learnerPause));
      await tester.pump();
      final missionButton = find.byKey(
        const ValueKey('adventure-start-mission'),
      );
      final missionAvailableAfterPause =
          missionButton.evaluate().length == 1 &&
          tester.widget<ButtonStyleButton>(missionButton).onPressed != null &&
          missionStarts == 0;

      await tester.ensureVisible(
        find.byKey(const ValueKey('adventure-map-list-switch')),
      );
      await tester.pumpAndSettle();
      await _selectJourneyPresentation(tester, showList: true);
      await _selectJourneyPresentation(tester, showList: false);
      final transitionTaskSamples = <int>[];
      await binding.watchPerformance(() async {
        for (var index = 0; index < _sampleCount; index++) {
          final showList = index.isEven;
          final stopwatch = Stopwatch()..start();
          await _selectJourneyPresentation(tester, showList: showList);
          stopwatch.stop();
          transitionTaskSamples.add(stopwatch.elapsedMicroseconds);
        }
      }, reportKey: _frameReportKey);
      final frameSummary = Map<String, dynamic>.from(
        binding.reportData![_frameReportKey]! as Map,
      );
      final buildTimes = _integerList(frameSummary['frame_build_times']);
      final rasterTimes = _integerList(frameSummary['frame_rasterizer_times']);
      if (buildTimes.isEmpty || buildTimes.length != rasterTimes.length) {
        fail('Flutter returned inconsistent map/list frame timing data.');
      }
      final frameTimes = <int>[
        for (var index = 0; index < buildTimes.length; index++)
          buildTimes[index] >= rasterTimes[index]
              ? buildTimes[index]
              : rasterTimes[index],
      ];
      final frameP95Us = _p95(frameTimes);
      final frameMaxUs = frameTimes.reduce(
        (left, right) => left >= right ? left : right,
      );
      final transitionTaskP95Us = _p95(transitionTaskSamples);
      final transitionTaskMaxUs = transitionTaskSamples.reduce(
        (left, right) => left >= right ? left : right,
      );
      final longFrameCount = frameTimes
          .where((value) => value > _longFrameOrTaskBudgetUs)
          .length;
      final longTaskCount = transitionTaskSamples
          .where((value) => value > _longFrameOrTaskBudgetUs)
          .length;

      final entryPassed = entryP95Us <= _entryBudgetUs;
      final journeyPassed =
          journeyP95Us <= _journeyBudgetUs && projectedThreeNodes;
      final renderPassed = renderP95Us <= _renderBudgetUs;
      final sessionPassed =
          sessionOverheadP95Us <= _sessionOverheadBudgetUs &&
          commandAuthorityPreserved &&
          snapshotAuthorityPreserved &&
          evidenceAuthorityPreserved;
      final transitionsPassed =
          frameP95Us <= _frameBudgetUs &&
          longFrameCount == 0 &&
          longTaskCount == 0;
      final pausePassed = missionAvailableAfterPause;
      final allBudgetsPassed =
          kProfileMode &&
          catalogValidation.isValid &&
          entryPassed &&
          journeyPassed &&
          renderPassed &&
          sessionPassed &&
          transitionsPassed &&
          pausePassed;

      final profile = <String, Object?>{
        'schemaVersion': 1,
        'profileId': _profileId,
        'buildMode': kProfileMode ? 'profile' : 'not-profile',
        'benchmarkSink': _benchmarkSink,
        'percentileMethod': 'nearest-rank',
        'sampleCounts': <String, int>{
          'localEntryResolution': entryRun.samples.length,
          'journeyProjection': journeyRun.samples.length,
          'firstMeaningfulRender': renderSamples.length,
          'standardSessionStart': standardRun.samples.length,
          'adventureSessionStart': adventureRun.samples.length,
          'mapListFrames': frameTimes.length,
          'mapListTransitionTasks': transitionTaskSamples.length,
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
          'mapListTransitionTaskP95Ms': _milliseconds(transitionTaskP95Us),
          'mapListTransitionTaskMaxMs': _milliseconds(transitionTaskMaxUs),
          'mapListLongFrameCount': longFrameCount,
          'mapListLongTaskCount': longTaskCount,
        },
        'passes': <String, bool>{
          'profileMode': kProfileMode,
          'localAssetsValid': catalogValidation.isValid,
          'localEntryResolution': entryPassed,
          'threeNodeJourneyProjection': journeyPassed,
          'firstMeaningfulRender': renderPassed,
          'adventureSessionStartOverhead': sessionPassed,
          'mapListTransitions': transitionsPassed,
          'learnerPause': pausePassed,
        },
        'authorityInvariants': <String, bool>{
          'threeNodeProjection': projectedThreeNodes,
          'standardAdventureCommandsEquivalent': commandAuthorityPreserved,
          'canonicalSnapshotPinned': snapshotAuthorityPreserved,
          'evidenceAuthorityUnchanged': evidenceAuthorityPreserved,
        },
        'measurementScope': <String, String>{
          'firstMeaningfulRender':
              'packaged catalog and asset validation, production journey '
              'projection, and AdventureHubScreen first meaningful frame',
          'sessionStartOverhead':
              'Adventure compose and bridge preparation minus canonical '
              'Standard LessonStartCommand construction; shared controller '
              'start is unchanged and excluded',
          'mapListFrame':
              'maximum of Flutter build and raster duration for each frame',
          'mapListTask': 'tap, state transition, and settled widget pump',
        },
        'learnerPause': <String, Object?>{
          'timeoutPolicy': 'none',
          'sessionTiming': configuration.timing.kind.name,
          'observedPauseMs': _learnerPause.inMilliseconds,
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
      expect(longFrameCount, 0, reason: 'A map/list frame exceeded 100 ms.');
      expect(
        longTaskCount,
        0,
        reason: 'A map/list transition task exceeded 100 ms.',
      );
      expect(
        missionAvailableAfterPause,
        isTrue,
        reason: 'Learner pause disabled or started the mission.',
      );
    },
    timeout: Timeout.none,
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
  await tester.pump();
  final target = find.byKey(
    ValueKey(showList ? 'adventure-map-list' : 'adventure-map'),
  );
  if (target.evaluate().length != 1) {
    fail('Adventure map/list transition did not settle.');
  }
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

({List<int> samples, T last}) _measureSync<T>({
  required int warmups,
  required int samples,
  required T Function(int index) action,
  required void Function(T value) consume,
}) {
  for (var index = 0; index < warmups; index++) {
    consume(action(index));
  }
  final durations = <int>[];
  late T last;
  for (var index = 0; index < samples; index++) {
    final stopwatch = Stopwatch()..start();
    last = action(index + warmups);
    consume(last);
    stopwatch.stop();
    durations.add(stopwatch.elapsedMicroseconds);
  }
  return (samples: List<int>.unmodifiable(durations), last: last);
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
