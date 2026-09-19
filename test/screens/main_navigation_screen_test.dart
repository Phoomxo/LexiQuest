import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_motivation_projection_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_presentation_preferences.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_result_next_action_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_session_composer.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_mixed_review_screen.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_lifecycle_screen.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_today_entry_card.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/screens/study_planning_hub_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';
import '../features/learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness;

Future<Uint8List?> _navigationStarterAsset(ContentIdentity identity) async {
  final data = await rootBundle.load(
    'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<void> _showLearnSecondary(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find
        .descendant(
          of: find.byType(ChooseModeScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(timezone_data.initializeTimeZones);
  for (final boundary in ['normal', 'stale-owner', 'disabled-quiz']) {
    testWidgets(
      'Today History packaged Pair replay owns route and practice boundary $boundary',
      (tester) async {
        final staleOwner = boundary == 'stale-owner';
        final disabledQuiz = boundary == 'disabled-quiz';
        final registry = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(registry.dispose);
        const ownerId = 'synthetic-navigation-pair';
        const launchId = 'synthetic-navigation-source';
        final words = PackagedStarterCatalog.words.take(4).toList();
        final h = PairHarness(
          launchId: launchId,
          pinnedPlan: PairMatchingPlanV1(
            ownerId: ownerId,
            orderedLexicalItems: [
              for (final word in words)
                PairLexicalItem(
                  wordId: word.id,
                  contentRevision: 1,
                  checksum: word.coreHash,
                  spelling: word.key,
                  meaning: word.meaning,
                  sourceLocale: 'en',
                  targetLocale: 'th',
                  sourceReasons: const {PairSourceReason.newContent},
                ),
            ],
            direction: PairDirection.enToTh,
            density: PairDensity.compact4,
            shuffleSeed: 42,
            timerPreset: PairTimerPreset.seconds120,
            allowlistVersion: 'packaged-starter-r1',
            learningSessionId: pairSessionId(ownerId, launchId),
            entryKind: PairSourceSurface.learn,
            sourceSnapshotId: 'packaged-starter-r1',
            createdAtUtc: DateTime.utc(2026, 9, 5),
          ),
          provisionVocabulary: (database) => PackagedStarterCatalog.provision(
            database,
            DriftContentManifestRepository(
              database,
              loadArtifactBytes: _navigationStarterAsset,
            ),
            _navigationStarterAsset,
          ),
        );
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final source = await h.restore();
        addTearDown(source.dispose);
        for (final word in words) {
          await h.tap(source, word.id, PairTileSide.prompt);
          await h.tap(source, word.id, PairTileSide.target);
        }
        await source.finish();
        await source.markSummaryPresented();
        final learning = LearningUseCases(
          owners: h.learning.owners,
          repository: h.real,
          generateId: h.learning.generateId,
          nowUtc: h.learning.nowUtc,
          buildInfo: h.learning.buildInfo,
        );
        final ownerReader = _MutableNavigationReviewOwnerIdentities(ownerId);
        final history = LearningHistoryUseCases(
          owners: learning.owners,
          reader: DriftLearningHistoryReader(
            h.db,
            learningTime: DriftLearningTimeRepository(
              h.db,
              owners: learning.owners,
            ),
            nowUtc: learning.nowUtc,
          ),
          pairReader: DriftPairMatchingSessionPurposeReader(h.db),
          sessionLauncher: _NavigationHistorySessionLauncher(learning),
        );
        final rewardsBefore = await h.db
            .customSelect('SELECT * FROM reward_transactions ORDER BY id')
            .get();
        final pointsBefore = await h.db
            .customSelect('SELECT * FROM points_ledger_entries ORDER BY id')
            .get();
        await tester.binding.setSurfaceSize(const Size(1000, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _mainNavigationApp(
            registry,
            databaseOverride: h.db,
            exposeDatabase: true,
            internalPairMatching: true,
            localOwners: learning.owners,
            learningOverride: learning,
            historyOverride: history,
            activeOwnerIdentities: ownerReader,
            todayHub: _NavigationTodayHubLoader(
              _emptyTodayHubSnapshot(ownerId: ownerId),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
        await tester.pumpAndSettle();
        await _showLearnSecondary(tester, 'home/today');
        await tester.tap(find.byKey(const ValueKey<String>('home/today')));
        await tester.pumpAndSettle();
        final historyButton = find.byKey(
          const ValueKey('today-hub-open-history'),
        );
        await tester.ensureVisible(historyButton);
        await tester.tap(historyButton);
        await tester.pumpAndSettle();
        final historyScreen = tester.widget<LearningHistoryScreen>(
          find.byType(LearningHistoryScreen),
        );
        expect(historyScreen.onPairReplay, isNotNull);
        final replayButton = find.byKey(
          ValueKey('pair-replay-history-${h.operation.plan.learningSessionId}'),
        );
        await tester.ensureVisible(replayButton);
        if (staleOwner) ownerReader.ownerId = 'synthetic-other-owner';
        if (disabledQuiz) {
          registry.emergencyOff(Feature.quiz);
          await tester.pumpAndSettle();
        }
        await tester.tap(replayButton);
        await tester.pumpAndSettle();
        if (staleOwner || disabledQuiz) {
          expect(find.byType(PairMatchingExperienceHost), findsNothing);
          expect(await h.db.select(h.db.learningSessions).get(), hasLength(1));
        } else {
          expect(find.byType(PairMatchingExperienceHost), findsOneWidget);
          expect(
            ModalRoute.of(
              tester.element(find.byType(PairMatchingExperienceHost)),
            )?.settings.name,
            'home/today/history/pair-replay',
          );
          final controller = tester
              .widget<UnifiedLessonShell>(find.byType(UnifiedLessonShell))
              .controller!;
          final replayId = controller.state.sessionId!;
          expect(replayId, isNot(h.operation.plan.learningSessionId));
          final replay = await h.real.read(
            ownerId: ownerId,
            sessionId: replayId,
          );
          expect(
            replay.snapshot!.engine.plan.sessionPurpose,
            PairSessionPurpose.practiceReplay,
          );
          expect(
            replay.snapshot!.engine.plan.sourceSessionId,
            h.operation.plan.learningSessionId,
          );
          for (final side in ['prompt', 'target']) {
            final tile = find.byKey(
              ValueKey('pair-tile:$side:${words.first.id}'),
            );
            await tester.ensureVisible(tile);
            await tester.tap(tile);
            await tester.pumpAndSettle();
          }
          final attempts = await h.db
              .customSelect(
                'SELECT * FROM answer_attempts WHERE session_id = ?',
                variables: [Variable<String>(replayId)],
              )
              .get();
          expect(attempts, hasLength(1));
        }
        expect(
          (await h.db
                  .customSelect('SELECT * FROM reward_transactions ORDER BY id')
                  .get())
              .map((row) => row.data)
              .toList(),
          rewardsBefore.map((row) => row.data).toList(),
        );
        expect(
          (await h.db
                  .customSelect(
                    'SELECT * FROM points_ledger_entries ORDER BY id',
                  )
                  .get())
              .map((row) => row.data)
              .toList(),
          pointsBefore.map((row) => row.data).toList(),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Today review answers and completes its attached durable session once',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var now = DateTime.utc(2026, 9, 5, 9);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'review-route-owner',
        nowUtc: () => now,
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabulary = DriftVocabularyRepository(database);
      var generatedId = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabulary,
        ),
        generateId: () => 'review-route-${++generatedId}',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'review-route'),
      );
      final today = _navigationMixedReviewToday(
        ownerId: ownerId,
        identity: seeded.identity,
        checksumSha256: seeded.checksumSha256,
      );
      final work = today.reviewWork.single;

      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.allEnabled(),
          databaseOverride: database,
          localOwners: owners,
          learningOverride: learning,
          vocabularyOverride: VocabularyUseCases(
            owners: owners,
            vocabulary: vocabulary,
            generateId: () => 'unused-review-route-vocabulary',
            nowUtc: () => now,
          ),
          activeOwnerIdentities: _NavigationReviewOwnerIdentities(ownerId),
          todayHub: _NavigationTodayHubLoader(today),
          reviewReaderOverride: _ProbeDueReader(
            ReviewQueueItem(
              snapshot: work.snapshot,
              provenance: work.provenance,
            ),
          ),
          reviewLauncherOverride: LearningUseCasesReviewSessionLauncher(
            learning,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/today');
      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();
      final review = find.byKey(
        const ValueKey<String>('today-hub-open-review'),
      );
      await tester.scrollUntilVisible(
        review,
        160,
        scrollable: find
            .descendant(
              of: find.byType(TodayHubScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(find.text('ตัวเลือกสำหรับทบทวนยังไม่เพียงพอ'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('meaning-quiz-next')),
        findsNothing,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReviewCenterScreen), findsOneWidget);
      var sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.state, 'abandoned');

      await _seedNavigationReviewDistractor(database, ownerId);
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(find.byType(UnifiedLessonShell), findsOneWidget);
      sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(2));
      final firstSessionId = sessions
          .singleWhere((session) => session.state == 'active')
          .id;
      expect(await database.select(database.answerAttempts).get(), isEmpty);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:navigation-station-สถานี',
          ),
        ),
      );
      await tester.pumpAndSettle();
      var attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(1));
      expect(attempts.single.sessionId, firstSessionId);
      expect(attempts.single.isCorrect, isTrue);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('meaning-quiz-next')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('meaning-quiz-next')));
      await tester.pumpAndSettle();

      sessions = await database.select(database.learningSessions).get();
      attempts = await database.select(database.answerAttempts).get();
      expect(sessions, hasLength(2));
      expect(
        sessions.singleWhere((session) => session.id == firstSessionId).state,
        'completed',
      );
      expect(attempts, hasLength(1));
      expect(attempts.single.sessionId, firstSessionId);
      expect(find.byType(ScoreScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReviewCenterScreen), findsOneWidget);
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();
      sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(3));
      final secondSession = sessions.singleWhere(
        (session) => session.id != firstSessionId && session.state == 'active',
      );
      expect(secondSession.state, 'active');

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'meaning-quiz-option-word:navigation-station-สนามบิน',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('meaning-quiz-next')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('meaning-quiz-next')));
      await tester.pumpAndSettle();

      sessions = await database.select(database.learningSessions).get();
      attempts = await database.select(database.answerAttempts).get();
      expect(sessions, hasLength(3));
      expect(sessions.map((session) => session.id).toSet(), hasLength(3));
      expect(
        sessions.where((session) => session.state == 'completed'),
        hasLength(2),
      );
      expect(
        sessions.where((session) => session.state == 'abandoned'),
        hasLength(1),
      );
      expect(attempts, hasLength(2));
      expect(attempts.first.isCorrect, isTrue);
      expect(attempts.last.isCorrect, isFalse);
      expect(
        attempts.map((attempt) => attempt.sessionId).toSet(),
        hasLength(2),
      );
      for (final session in sessions.where(
        (session) => session.state == 'completed',
      )) {
        expect(
          attempts.where((attempt) => attempt.sessionId == session.id),
          hasLength(1),
        );
      }
      final learningEvents = (await database.select(database.eventsV2).get())
          .where((event) => event.eventId.startsWith('learning-event:'))
          .toList(growable: false);
      expect(learningEvents, hasLength(2));
      expect(
        learningEvents.map((event) => event.aggregateId).toSet(),
        hasLength(2),
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(find.byType(ScoreScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Today planning opens the existing hub and rejects stale owner and live gate',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      final identity = _MutableNavigationReviewOwnerIdentities(
        'owner:main-navigation',
      );
      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(_emptyTodayHubSnapshot()),
          activeOwnerIdentities: identity,
        ),
      );
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/today');
      await tester.tap(find.byKey(const ValueKey('home/today')));
      await tester.pumpAndSettle();
      final screen = tester.widget<TodayHubScreen>(find.byType(TodayHubScreen));
      final planning = find.byKey(const ValueKey('today-hub-open-planning'));
      await tester.scrollUntilVisible(
        planning,
        160,
        scrollable: find
            .descendant(
              of: find.byType(TodayHubScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(planning);
      await tester.pumpAndSettle();
      expect(find.byType(StudyPlanningHubScreen), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byType(StudyPlanningHubScreen)),
        )?.settings.name,
        'home/study-planning',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      identity.ownerId = 'synthetic-owner-b';
      await screen.actions.openPlanning(ownerId: 'owner:main-navigation');
      await tester.pumpAndSettle();
      expect(find.byType(StudyPlanningHubScreen), findsNothing);
      identity.ownerId = 'owner:main-navigation';
      registry.emergencyOff(Feature.studyPlanning);
      await tester.pumpAndSettle();
      await screen.actions.openPlanning(ownerId: identity.ownerId);
      await tester.pumpAndSettle();
      expect(find.byType(StudyPlanningHubScreen), findsNothing);
      expect(find.byType(TodayHubScreen), findsOneWidget);
    },
  );
  testWidgets(
    'available quickstart precedes secondary Today entry without loading it',
    (tester) async {
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());
      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.allEnabled(),
          todayHub: loader,
        ),
      );
      await tester.pumpAndSettle();
      final starter = find.byKey(const ValueKey('learn-starter'));
      final today = find.byKey(const ValueKey('home/today'));
      expect(starter, findsOneWidget);
      expect(today, findsOneWidget);
      expect(
        tester.getTopLeft(starter).dy,
        lessThan(tester.getTopLeft(today).dy),
      );
      expect(
        loader.calls,
        0,
        reason: 'Learning must not wait for the Today snapshot.',
      );
    },
  );
  testWidgets(
    'Task5 mastery review uses the live daily parent gate and canonical weakness route',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(_emptyTodayHubSnapshot()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีข้อมูลการเรียน'), findsNothing);
      expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsNothing);
      final review = find.byKey(const ValueKey('mastery-open-review'));
      expect(review, findsOneWidget);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewCenterScreen), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byType(ReviewCenterScreen)),
        )?.settings.name,
        'home/today/review',
      );
      registry.emergencyOff(Feature.researchAssessment);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewCenterScreen), findsOneWidget);
      registry.emergencyOff(Feature.dailyContinuity);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewCenterScreen), findsNothing);
      expect(
        tester
            .widget<ProductionFeatureUnavailable>(
              find.byType(ProductionFeatureUnavailable),
            )
            .feature,
        Feature.dailyContinuity,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MasteryDashboardScreen>(find.byType(MasteryDashboardScreen))
            .onOpenReview,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('home/weakness')));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(WeaknessClinicScreen)),
        )?.settings.name,
        'home/weakness',
      );
    },
  );

  testWidgets(
    'Task5 profile selects retained visible mastery and hides the callback on live removal',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      final masteryState = tester.state(find.byType(MasteryDashboardScreen));
      await tester.tap(find.byKey(const ValueKey('home/profile')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('profile-open-mastery'));
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find
            .descendant(
              of: find.byType(ProfileSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(MasteryDashboardScreen)),
        same(masteryState),
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(
        Navigator.of(
          tester.element(find.byType(MasteryDashboardScreen)),
        ).canPop(),
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('home/profile')));
      await tester.pumpAndSettle();
      registry.emergencyOff(Feature.mastery);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProfileSettingsScreen>(find.byType(ProfileSettingsScreen))
            .onOpenMastery,
        isNull,
      );
      expect(find.byKey(const ValueKey('profile-open-mastery')), findsNothing);
    },
  );

  testWidgets(
    'Task5 rewards callbacks open canonical gated routes and disappear live',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/achievements')));
      await tester.pumpAndSettle();
      for (final entry in <(String, String, Feature)>[
        ('rewards-open-quests', 'rewards/quests', Feature.questV2),
        ('rewards-open-shop', 'rewards/shop', Feature.shop),
      ]) {
        final action = find.byKey(ValueKey(entry.$1));
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        final gate = find.byWidgetPredicate(
          (widget) =>
              widget is ProductionFeatureGate && widget.feature == entry.$3,
        );
        expect(ModalRoute.of(tester.element(gate))?.settings.name, entry.$2);
        registry.emergencyOff(entry.$3);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ProductionFeatureUnavailable>(
                find.byType(ProductionFeatureUnavailable),
              )
              .feature,
          entry.$3,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(action, findsNothing);
      }
      final rewards = tester.widget<AchievementsScreen>(
        find.byType(AchievementsScreen),
      );
      expect(rewards.onOpenQuests, isNull);
      expect(rewards.onOpenShop, isNull);
    },
  );

  testWidgets(
    'registry replacement reconciles selection and ignores old registry changes',
    (tester) async {
      final oldRegistry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      final replacement = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      )..emergencyOff(Feature.mastery);
      addTearDown(oldRegistry.dispose);
      addTearDown(replacement.dispose);
      await tester.pumpWidget(_mainNavigationApp(oldRegistry));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_mainNavigationApp(replacement));
      await tester.pumpAndSettle();
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home/mastery')), findsNothing);
      oldRegistry.emergencyOff(Feature.vocabulary);
      await tester.pump();
      expect(find.byKey(const ValueKey('home/vocabulary')), findsOneWidget);
      replacement.clearOverride(Feature.mastery);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home/mastery')), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'local failure is visible in the header and never claims learning is ready',
    (tester) async {
      for (final availability in [
        RuntimeAvailability.degraded,
        RuntimeAvailability.unavailable,
      ]) {
        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            runtimeStatusOverride: AppRuntimeStatus(
              localData: availability,
              firebase: RuntimeAvailability.ready,
              supabase: RuntimeAvailability.ready,
              backends: RuntimeAvailability.ready,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final banner = tester.widget<Text>(
          find.byKey(const ValueKey('runtime-status-banner')),
        );
        expect(
          banner.data,
          contains(
            availability == RuntimeAvailability.degraded
                ? 'บางส่วน'
                : 'ไม่พร้อม',
          ),
        );
        await tester.tap(find.byKey(const ValueKey('runtime-status-details')));
        await tester.pumpAndSettle();
        final details = tester.widget<Text>(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Text),
              )
              .at(1),
        );
        expect(details.data, isNot(contains('การเรียนในเครื่องยังใช้ได้')));
        expect(details.data, contains('ตรวจสถานะ'));
        await tester.tap(find.widgetWithText(TextButton, 'ปิด'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'secondary routes remain reachable when learning and mastery are hidden',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      for (final feature in [
        Feature.quiz,
        Feature.srs,
        Feature.reading,
        Feature.mastery,
      ]) {
        registry.emergencyOff(feature);
      }
      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(_emptyTodayHubSnapshot()),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in <(String, Type)>[
        ('home/today', TodayHubScreen),
        ('home/study-planning', StudyPlanningHubScreen),
        ('home/weakness', WeaknessClinicScreen),
      ]) {
        await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
        await tester.pumpAndSettle();
        final target = find.byKey(ValueKey(entry.$1));
        await tester.scrollUntilVisible(
          target,
          150,
          scrollable: find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byType(entry.$2), findsOneWidget);
        expect(
          ModalRoute.of(tester.element(find.byType(entry.$2)))?.settings.name,
          entry.$1,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets('initialIndex explicitly indexes visible primary destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(
        const BuildFeatureRegistry.allEnabled(),
        initialIndex: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('production-feature-view-vocabulary')),
      findsOneWidget,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
  testWidgets(
    'five primary destinations retain tap semantics at 360px and 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        final profile = NavigationGlossary.require('home/profile');
        tester.semantics.performAction(
          _bottomDestinationFinder(profile),
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProfileSettingsScreen), findsOneWidget);
        expect(
          _bottomDestinationSemantics(profile).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'primary navigation starts learning and uses five semantic destinations',
    (tester) async {
      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((entry) => entry.key),
        [
          const ValueKey('home/learn'),
          const ValueKey('home/vocabulary'),
          const ValueKey('home/mastery'),
          const ValueKey('home/achievements'),
          const ValueKey('home/profile'),
        ],
      );
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets(
    'selected primary removal falls back and reenable keeps semantic selection',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      registry.emergencyOff(Feature.mastery);
      await tester.pumpAndSettle();
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      registry.clearOverride(Feature.mastery);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home/mastery')), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets(
    'Today is a named secondary route and resume closes only that route',
    (tester) async {
      final loader = _NavigationTodayHubLoader(
        _emptyTodayHubSnapshot(
          resumableSession: LearningSessionSummary(
            id: 'synthetic-resume',
            ownerId: 'owner:main-navigation',
            activityType: 'meaningQuiz',
            state: 'active',
            startedAtUtc: DateTime.utc(2026, 9, 8),
            correctCount: 0,
            wrongCount: 0,
            score: 0,
          ),
        ),
      );
      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.allEnabled(),
          todayHub: loader,
        ),
      );
      await tester.pumpAndSettle();
      final today = find.byKey(const ValueKey('home/today'));
      await tester.ensureVisible(today);
      await tester.pumpAndSettle();
      await tester.tap(today);
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(TodayHubScreen)),
        )?.settings.name,
        'home/today',
      );
      await tester.tap(find.byKey(const ValueKey('today-hub-resume-action')));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubScreen), findsNothing);
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        Navigator.of(
          tester.element(find.byType(MainNavigationScreen)),
        ).canPop(),
        isFalse,
      );
    },
  );
  testWidgets('system banner and menu respect the phone status inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      _mainNavigationApp(
        const BuildFeatureRegistry.allEnabled(),
        runtimeStatusOverride: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final banner = tester.getRect(
      find.byKey(const ValueKey<String>('runtime-status-banner')),
    );
    final menu = tester.getRect(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    expect(banner.top, greaterThanOrEqualTo(32));
    expect(menu.overlaps(banner), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Adventure adds one Learn card, stable child route, and no bottom destination',
    (tester) async {
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());
      final diagnostics = AdventureDiagnostics();
      AppDependencies? composed;
      final enabled = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(enabled.dispose);
      await tester.pumpWidget(
        _mainNavigationApp(
          enabled,
          todayHub: loader,
          includeAdventure: true,
          adventureDiagnosticsOverride: diagnostics,
          onDependencies: (value) => composed = value,
        ),
      );
      await tester.pumpAndSettle();
      final bottomCount = find.byType(NavigationDestination).evaluate().length;
      expect(loader.calls, 0);

      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/learn/today-experience');
      expect(find.byType(AdventureTodayEntryCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home/learn/today-experience')),
        findsOneWidget,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(bottomCount));
      final callsBeforeAdventureEntry = loader.calls;

      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/today-experience')),
      );
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 10 && loader.calls == callsBeforeAdventureEntry;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(TodayExperienceHost), findsOneWidget);
      expect(loader.calls, callsBeforeAdventureEntry + 1);
      final host = tester.widget<TodayExperienceHost>(
        find.byType(TodayExperienceHost),
      );
      expect(composed!.adventureDiagnostics, same(diagnostics));
      expect(host.entry.diagnostics, same(diagnostics));
      expect(
        diagnostics.snapshot().counters,
        containsPair(AdventureDiagnosticReasonCode.entryStandard, 1),
      );

      enabled.emergencyOff(Feature.adventureMotivation);
      await tester.pumpAndSettle();
      expect(find.byType(TodayExperienceHost), findsNothing);
      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      expect(loader.calls, callsBeforeAdventureEntry + 1);
    },
  );

  testWidgets(
    'Adventure launches canonical mixed review and emergency-off finishes as Standard',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'navigation-mixed-review',
        nowUtc: () => DateTime.utc(2026, 9, 5, 8),
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabularyRepository = DriftVocabularyRepository(database);
      var now = DateTime.utc(2026, 9, 5, 9);
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabularyRepository,
        ),
        generateId: () => 'navigation-mixed-review-session',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'navigation-mixed-review',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: vocabularyRepository,
        generateId: () => 'unused',
        nowUtc: () => now,
      );
      final today = _navigationMixedReviewToday(
        ownerId: ownerId,
        identity: seeded.identity,
        checksumSha256: seeded.checksumSha256,
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      final dependencyRegistry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      )..emergencyOff(Feature.quiz);
      addTearDown(dependencyRegistry.dispose);

      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          dependencyFeatureRegistry: dependencyRegistry,
          todayHub: _NavigationTodayHubLoader(today),
          localOwners: owners,
          databaseOverride: database,
          learningOverride: learning,
          vocabularyOverride: vocabulary,
          activeOwnerIdentities: _NavigationReviewOwnerIdentities(ownerId),
          includeAdventure: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/learn/today-experience');
      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/today-experience')),
      );
      await tester.pumpAndSettle();
      final host = tester.widget<TodayExperienceHost>(
        find.byType(TodayExperienceHost),
      );
      final mission = AdventureMissionRef(
        missionId: 'review:${seeded.identity.id}',
        ownerId: ownerId,
        nodeId: 'resume-review',
        kind: AdventureMissionKind.review,
        sourceId: seeded.identity.id,
        content: <ContentIdentity>[seeded.identity],
        reasonCode: 'due_review',
        sourceEvaluatedAtUtc: today.evaluatedAtUtc,
        suggestedMode: null,
      );
      final launch = host.onStartMission(
        AdventureMissionLaunchContext(
          mission: mission,
          today: today,
          entryDecision: AdventureProductEntryDecision(
            entryAttemptId: 'entry-navigation-mixed-review',
            availability: AdventureAvailability.available,
            destination: AdventureEntryDestination.adventure,
            fallbackReason: AdventureFallbackReason.none,
            catalogId: host.catalog.catalogId,
            catalogVersion: host.catalog.catalogVersion,
            catalogSchemaVersion: host.catalog.schemaVersion,
            treatment: 'adventure',
          ),
          rewardOwnership: const RewardAccount(
            coinBalance: 0,
            catalogVersion: RewardCatalog.version,
            ownedItemIds: <String>{},
            equippedBySlot: <String, String>{},
            transactionCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('session-configuration-sheet')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.pumpAndSettle();
      await launch;
      await tester.pumpAndSettle();

      expect(find.byType(AdventureMixedReviewScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('mixed-review-typed-input')),
        findsOneWidget,
      );
      final active = await database.select(database.learningSessions).get();
      expect(active, hasLength(1));
      expect(active.single.activityType, mixedReviewActivityType);
      expect(active.single.state, 'active');

      registry.emergencyOff(Feature.adventureMotivation);
      await tester.pump();
      expect(find.byType(AdventureMixedReviewScreen), findsOneWidget);
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey<String>('mixed-review-typed-input')),
        seeded.spelling,
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('mixed-review-submit')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('mixed-review-submit')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('mixed-review-next')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('mixed-review-next')));
      await tester.pumpAndSettle();

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(find.byType(AdventureResultLifecycleScreen), findsNothing);
      final completed = await database.select(database.learningSessions).get();
      expect(completed.single.state, 'completed');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Today resumes snapshotted mixed review without Adventure or vocabulary dependencies',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'navigation-mixed-review-resume',
        nowUtc: () => DateTime.utc(2026, 9, 5, 10),
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabularyRepository = DriftVocabularyRepository(database);
      var now = DateTime.utc(2026, 9, 5, 11);
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabularyRepository,
        ),
        generateId: () => 'navigation-mixed-review-resume-session',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'navigation-mixed-review-resume',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: vocabularyRepository,
        generateId: () => 'unused',
        nowUtc: () => now,
      );
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (_, _, _) => false,
      );
      await recovery.startOrResume(
        plan: _navigationMixedReviewPlan(
          ownerId: ownerId,
          identity: seeded.identity,
          checksumSha256: seeded.checksumSha256,
        ),
        activeOwnerId: ownerId,
        buildPromptCatalogSnapshot: (session) async {
          final lexicalWords = await vocabulary.readPinnedByIds(
            session.questions.map((question) => question.word.id),
          );
          return AdventureMixedReviewPromptCatalog(
            session: session,
            lexicalWords: lexicalWords,
            registry: buildLessonModeRegistry(),
            direction: SessionDirection.forward,
          ).snapshot;
        },
      );
      final activeSession = await learning.getActiveSession();
      expect(activeSession, isNotNull);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      )..emergencyOff(Feature.adventureMotivation);
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(
            _navigationResumeToday(ownerId, activeSession!),
          ),
          localOwners: owners,
          databaseOverride: database,
          learningOverride: learning,
          includeVocabulary: false,
          activeOwnerIdentities: _NavigationReviewOwnerIdentities(ownerId),
          includeAdventure: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('today-hub-resume-action')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdventureMixedReviewScreen), findsOneWidget);
      expect(find.text('ทบทวนคำศัพท์'), findsOneWidget);
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey<String>('mixed-review-typed-input')),
        seeded.spelling,
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('mixed-review-submit')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('mixed-review-submit')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('mixed-review-next')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('mixed-review-next')));
      await tester.pumpAndSettle();

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(find.byType(AdventureResultLifecycleScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'catalog preflight failure leaves no accepted mixed review behind',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'navigation-mixed-review-catalog-failure',
        nowUtc: () => DateTime.utc(2026, 9, 5, 12),
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabularyRepository = _FailingSecondPinnedReadVocabularyRepository(
        DriftVocabularyRepository(database),
      );
      var now = DateTime.utc(2026, 9, 5, 13);
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabularyRepository,
        ),
        generateId: () => 'navigation-mixed-review-catalog-failure-session',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'navigation-mixed-review-catalog-failure',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: vocabularyRepository,
        generateId: () => 'unused',
        nowUtc: () => now,
      );
      final today = _navigationMixedReviewToday(
        ownerId: ownerId,
        identity: seeded.identity,
        checksumSha256: seeded.checksumSha256,
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(today),
          localOwners: owners,
          databaseOverride: database,
          learningOverride: learning,
          vocabularyOverride: vocabulary,
          activeOwnerIdentities: _NavigationReviewOwnerIdentities(ownerId),
          includeAdventure: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/learn/today-experience');
      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/today-experience')),
      );
      await tester.pumpAndSettle();
      final host = tester.widget<TodayExperienceHost>(
        find.byType(TodayExperienceHost),
      );
      final launch = host.onStartMission(
        AdventureMissionLaunchContext(
          mission: AdventureMissionRef(
            missionId: 'review:${seeded.identity.id}',
            ownerId: ownerId,
            nodeId: 'resume-review',
            kind: AdventureMissionKind.review,
            sourceId: seeded.identity.id,
            content: <ContentIdentity>[seeded.identity],
            reasonCode: 'due_review',
            sourceEvaluatedAtUtc: today.evaluatedAtUtc,
            suggestedMode: LessonMode.typedRecall,
          ),
          today: today,
          entryDecision: AdventureProductEntryDecision(
            entryAttemptId: 'entry-navigation-catalog-failure',
            availability: AdventureAvailability.available,
            destination: AdventureEntryDestination.adventure,
            fallbackReason: AdventureFallbackReason.none,
            catalogId: host.catalog.catalogId,
            catalogVersion: host.catalog.catalogVersion,
            catalogSchemaVersion: host.catalog.schemaVersion,
            treatment: 'adventure',
          ),
          rewardOwnership: const RewardAccount(
            coinBalance: 0,
            catalogVersion: RewardCatalog.version,
            ownedItemIds: <String>{},
            equippedBySlot: <String, String>{},
            transactionCount: 0,
          ),
        ),
      );
      final launchFailure = expectLater(launch, throwsA(isA<StateError>()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.pumpAndSettle();

      await launchFailure;
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, isEmpty);
      expect(vocabularyRepository.pinnedReadCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'owner drift during atomic persistence performs zero stale writes and zero launch',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'navigation-mixed-review-owner-drift',
        nowUtc: () => DateTime.utc(2026, 9, 5, 13, 30),
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabularyRepository = DriftVocabularyRepository(database);
      var now = DateTime.utc(2026, 9, 5, 13, 31);
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabularyRepository,
        ),
        generateId: () => 'navigation-mixed-review-owner-drift-session',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'navigation-mixed-review-owner-drift',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: vocabularyRepository,
        generateId: () => 'unused',
        nowUtc: () => now,
      );
      final today = _navigationMixedReviewToday(
        ownerId: ownerId,
        identity: seeded.identity,
        checksumSha256: seeded.checksumSha256,
      );
      final ownerIdentities = _MutableNavigationReviewOwnerIdentities(ownerId);
      final configurations = _GatedActiveOwnerSessionConfigurationStore(
        ownerId,
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(today),
          localOwners: owners,
          databaseOverride: database,
          learningOverride: learning,
          vocabularyOverride: vocabulary,
          activeOwnerIdentities: ownerIdentities,
          sessionConfigurationsOverride: configurations,
          includeAdventure: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();
      await _showLearnSecondary(tester, 'home/learn/today-experience');
      await tester.tap(
        find.byKey(const ValueKey<String>('home/learn/today-experience')),
      );
      await tester.pumpAndSettle();
      final host = tester.widget<TodayExperienceHost>(
        find.byType(TodayExperienceHost),
      );
      final launch = host.onStartMission(
        AdventureMissionLaunchContext(
          mission: AdventureMissionRef(
            missionId: 'review:${seeded.identity.id}',
            ownerId: ownerId,
            nodeId: 'resume-review',
            kind: AdventureMissionKind.review,
            sourceId: seeded.identity.id,
            content: <ContentIdentity>[seeded.identity],
            reasonCode: 'due_review',
            sourceEvaluatedAtUtc: today.evaluatedAtUtc,
            suggestedMode: LessonMode.typedRecall,
          ),
          today: today,
          entryDecision: AdventureProductEntryDecision(
            entryAttemptId: 'entry-navigation-owner-drift',
            availability: AdventureAvailability.available,
            destination: AdventureEntryDestination.adventure,
            fallbackReason: AdventureFallbackReason.none,
            catalogId: host.catalog.catalogId,
            catalogVersion: host.catalog.catalogVersion,
            catalogSchemaVersion: host.catalog.schemaVersion,
            treatment: 'adventure',
          ),
          rewardOwnership: const RewardAccount(
            coinBalance: 0,
            catalogVersion: RewardCatalog.version,
            ownedItemIds: <String>{},
            equippedBySlot: <String, String>{},
            transactionCount: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('session-configuration-sheet')),
        findsOneWidget,
      );

      final launchFailure = expectLater(
        launch,
        throwsA(
          isA<SessionConfigurationResetRequired>().having(
            (error) => error.reason,
            'reason',
            SessionConfigurationResetReason.ownerDrift,
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-config-start')),
      );
      await tester.pump();
      await configurations.persistenceStarted.future;
      ownerIdentities.ownerId = 'owner:changed-during-persistence';
      configurations.activeOwnerId = ownerIdentities.ownerId;
      configurations.releasePersistence.complete();
      await tester.pumpAndSettle();

      await launchFailure;
      expect(configurations.atomicSaveCalls, 1);
      expect(configurations.saveCalls, 0);
      expect(configurations.writeCalls, 0);
      expect(find.byType(AdventureMixedReviewScreen), findsNothing);
      expect(await database.select(database.learningSessions).get(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'emergency-off exposes completed unpresented mixed review on Learn',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'navigation-terminal-recovery',
        nowUtc: () => DateTime.utc(2026, 9, 5, 14),
      );
      final ownerId = (await owners.getOrCreateActiveOwner()).id;
      final seeded = await _seedNavigationMixedReviewWord(database, ownerId);
      final vocabularyRepository = DriftVocabularyRepository(database);
      var now = DateTime.utc(2026, 9, 5, 15);
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(
          database,
          lexicalVocabulary: vocabularyRepository,
        ),
        generateId: () => 'navigation-terminal-recovery-session',
        nowUtc: () {
          final value = now;
          now = now.add(const Duration(seconds: 1));
          return value;
        },
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'navigation-terminal-recovery',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: vocabularyRepository,
        generateId: () => 'unused',
        nowUtc: () => now,
      );
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      final recovery = AdventureRecoveryUseCases(
        learning: learning,
        evidence: evidence,
        canStartNewMission: () => true,
        isRepairModeEligible: (_, _, _) => false,
      );
      final plan = _navigationMixedReviewPlan(
        ownerId: ownerId,
        identity: seeded.identity,
        checksumSha256: seeded.checksumSha256,
      );
      final run = await recovery.startOrResume(
        plan: plan,
        activeOwnerId: ownerId,
        buildPromptCatalogSnapshot: (session) async {
          final lexicalWords = await vocabulary.readPinnedByIds(
            session.questions.map((question) => question.word.id),
          );
          return AdventureMixedReviewPromptCatalog(
            session: session,
            lexicalWords: lexicalWords,
            registry: buildLessonModeRegistry(),
            direction: SessionDirection.forward,
          ).snapshot;
        },
      );
      final pending = evidence.capture(
        ownerId: ownerId,
        input: CurrentActivityInput.typedRecall,
        sessionId: run.session.id,
        wordId: seeded.identity.id,
        isCorrect: true,
        responseTimeMs: 500,
        attemptNumber: 1,
      );
      await recovery.checkpointPendingEvidence(
        pending: pending,
        originalIndex: 0,
        role: AdventureLearningItemRole.original,
        mode: LessonMode.typedRecall,
      );
      await pending.record();
      recovery.acceptPendingOccurrence(
        AdventureRepairAttempt(
          identity: seeded.identity,
          mode: LessonMode.typedRecall,
          promptVariant: 'typedRecall',
          outcome: AdventureAttemptOutcome.correct,
          evidenceClass: EvidenceClass.independentRecall,
          canonicalEvidenceCommitted: true,
          sourceEvidenceId: pending.sourceEvidenceId,
        ),
        nextOriginalIndex: 1,
        remainingOriginalItems: 0,
      );
      await recovery.completeSession(
        learning.captureSessionClose(
          sessionId: run.session.id,
          ownerId: ownerId,
        ),
      );
      expect(await learning.getActiveSession(), isNull);

      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      )..emergencyOff(Feature.adventureMotivation);
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        _mainNavigationApp(
          registry,
          todayHub: _NavigationTodayHubLoader(
            _emptyTodayHubSnapshot(ownerId: ownerId),
          ),
          localOwners: owners,
          databaseOverride: database,
          learningOverride: learning,
          includeVocabulary: false,
          activeOwnerIdentities: _NavigationReviewOwnerIdentities(ownerId),
          includeAdventure: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
      await tester.pumpAndSettle();

      expect(find.text('ทำบทเรียนที่บันทึกไว้ให้เสร็จ'), findsOneWidget);
      await tester.tap(find.text('ทำบทเรียนที่บันทึกไว้ให้เสร็จ'));
      await tester.pumpAndSettle();

      expect(find.byType(ScoreScreen), findsOneWidget);
      expect(find.byType(AdventureResultLifecycleScreen), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ScoreScreen), findsNothing);
      expect(find.text('ทำบทเรียนที่บันทึกไว้ให้เสร็จ'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('hidden Adventure leaves the Learn surface unchanged', (
    tester,
  ) async {
    final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());
    await tester.pumpWidget(
      _mainNavigationApp(
        const BuildFeatureRegistry.fieldDefaults(),
        todayHub: loader,
        includeAdventure: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
    await tester.pumpAndSettle();

    expect(find.byType(AdventureTodayEntryCard), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('home/learn/today-experience')),
      findsNothing,
    );
    expect(loader.calls, 0);
  });

  testWidgets(
    'Adventure entry fails closed when a launch authority is absent',
    (tester) async {
      for (final missing in <String>[
        'vocabulary',
        'lessonModes',
        'controller',
        'configurationStore',
        'atomicConfigurationStore',
        'evidence',
        'rewardReader',
        'sessionComposer',
        'motivationReader',
        'resultNextActionReader',
        'reviewCenter',
        'activeOwnerIdentities',
        'receiptRefresher',
      ]) {
        AppDependencies? composed;
        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: _NavigationTodayHubLoader(_emptyTodayHubSnapshot()),
            includeAdventure: true,
            includeVocabulary: missing != 'vocabulary',
            includeLessonModes: missing != 'lessonModes',
            includeCreateLessonController: missing != 'controller',
            includeSessionConfigurations: missing != 'configurationStore',
            sessionConfigurationsOverride: missing == 'atomicConfigurationStore'
                ? _CountingSessionConfigurationStore()
                : null,
            includeCurrentActivityEvidence: missing != 'evidence',
            includeRewardAccounts: missing != 'rewardReader',
            includeAdventureSessionComposer: missing != 'sessionComposer',
            includeAdventureMotivation: missing != 'motivationReader',
            includeAdventureResultNextAction:
                missing != 'resultNextActionReader',
            includeReviewCenter: missing != 'reviewCenter',
            includeActiveOwnerIdentities: missing != 'activeOwnerIdentities',
            includeAdventureReceiptRefresher: missing != 'receiptRefresher',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          composed!.hasComposedDependencyFor(Feature.adventureMotivation),
          isFalse,
          reason: missing,
        );
        await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AdventureTodayEntryCard),
          findsNothing,
          reason: missing,
        );
      }
    },
  );

  testWidgets(
    'Adventure entry fails closed when result next-action authority identities drift',
    (tester) async {
      for (final mismatch in <String>[
        'implementation',
        'reviewReader',
        'ownerIdentities',
        'reviewCenterOwnerIdentities',
        'reviewSessionAuthority',
      ]) {
        AppDependencies? composed;
        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: _NavigationTodayHubLoader(_emptyTodayHubSnapshot()),
            includeAdventure: true,
            useNonCanonicalAdventureResultNextAction:
                mismatch == 'implementation',
            mismatchAdventureResultReviewIdentity: mismatch == 'reviewReader',
            mismatchAdventureResultOwnerIdentity: mismatch == 'ownerIdentities',
            mismatchReviewCenterOwnerIdentity:
                mismatch == 'reviewCenterOwnerIdentities',
            mismatchReviewSessionAuthority:
                mismatch == 'reviewSessionAuthority',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          composed!.hasComposedDependencyFor(Feature.adventureMotivation),
          isFalse,
          reason: mismatch,
        );
        await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AdventureTodayEntryCard),
          findsNothing,
          reason: mismatch,
        );
      }
    },
  );

  testWidgets(
    'f42 Today delivery fails closed for default-off or missing dependency',
    (tester) async {
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.fieldDefaults(),
          todayHub: loader,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
      expect(loader.calls, 0);

      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
    },
  );

  testWidgets(
    'f42 live Today delivery opens the real Hub and emergency-off removes it',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());
      await tester.pumpWidget(_mainNavigationApp(features, todayHub: loader));
      await tester.pumpAndSettle();

      final entry = find.byKey(const ValueKey<String>('home/today'));
      expect(entry, findsOneWidget);
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((destination) => destination.label),
        isNot(contains('วันนี้')),
      );

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(loader.calls, 1);

      features.emergencyOff(Feature.dailyContinuity);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
      expect(find.byType(TodayHubScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(loader.calls, 1);
    },
  );

  testWidgets(
    'f42 signoff Today delivery requires its Hub review and history authorities',
    (tester) async {
      for (final missing in <String>['review', 'history']) {
        AppDependencies? composed;
        final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: loader,
            includeReviewCenter: missing != 'review',
            includeLearningHistory: missing != 'history',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          composed!.hasComposedDependencyFor(Feature.dailyContinuity),
          isFalse,
          reason: 'missing $missing authority must fail closed',
        );
        expect(
          find.byKey(const ValueKey<String>('home/today')),
          findsNothing,
          reason: 'missing $missing authority must hide Today delivery',
        );
        expect(loader.calls, 0);
      }
    },
  );

  testWidgets(
    'f42 signoff Today owner validation never invokes the creating owner API',
    (tester) async {
      final owner = _NavigationOwner(ownerId: 'owner:different');
      final loader = _NavigationTodayHubLoader(
        _emptyTodayHubSnapshot(
          resumableSession: LearningSessionSummary(
            id: 'session:today-owner-check',
            ownerId: 'owner:main-navigation',
            activityType: 'meaningQuiz',
            state: 'active',
            startedAtUtc: DateTime.utc(2026, 8, 31, 7, 55),
            correctCount: 0,
            wrongCount: 0,
            score: 0,
          ),
        ),
      );

      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.allEnabled(),
          todayHub: loader,
          localOwners: owner,
          activeOwnerIdentities: const _UnavailableNavigationOwnerIdentities(),
        ),
      );
      await tester.pumpAndSettle();
      final callsBeforeTodayAction = owner.getOrCreateCalls;

      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-hub-resume-action')));
      await tester.pumpAndSettle();

      expect(
        owner.getOrCreateCalls,
        callsBeforeTodayAction,
        reason: 'a read-only owner check must not create an owner',
      );
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
    },
  );

  testWidgets(
    'f42 final signoff Today delivery requires every learning launch authority and identity',
    (tester) async {
      for (final missing in <String>[
        'learning',
        'lessonModes',
        'createLessonController',
        'reviewSessionAuthority',
        'historySessionAuthority',
      ]) {
        AppDependencies? composed;
        final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: loader,
            includeLearning: missing != 'learning',
            includeLessonModes: missing != 'lessonModes',
            includeCreateLessonController: missing != 'createLessonController',
            mismatchReviewSessionAuthority: missing == 'reviewSessionAuthority',
            mismatchHistorySessionAuthority:
                missing == 'historySessionAuthority',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          composed!.hasComposedDependencyFor(Feature.dailyContinuity),
          isFalse,
          reason: '$missing must fail closed',
        );
        expect(
          find.byKey(const ValueKey<String>('home/today')),
          findsNothing,
          reason: '$missing must hide Today delivery',
        );
        expect(loader.calls, 0);
      }
    },
  );

  testWidgets(
    'all-enabled composition renders five destinations and opens secondary weakness',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((destination) => destination.label),
        <String>['เรียน', 'คำศัพท์', 'ความก้าวหน้า', 'รางวัล', 'โปรไฟล์'],
      );

      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      expect(find.text('ภาพรวมการเรียน'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home/weakness')));
      await tester.pumpAndSettle();
      expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home/achievements')));
      await tester.pumpAndSettle();
      expect(find.text('ความสำเร็จ'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home/profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Thai glossary bottom destinations preserve tab semantics and callbacks',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
        );
        await tester.pumpAndSettle();

        const entryIds = <String>[
          'home/learn',
          'home/vocabulary',
          'home/mastery',
          'home/achievements',
          'home/profile',
        ];
        final destinations = tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .toList(growable: false);
        expect(destinations, hasLength(entryIds.length));
        expect(
          destinations.map((destination) => destination.label),
          entryIds.map(
            (entryId) => NavigationGlossary.require(entryId).shortThaiLabel,
          ),
        );
        final localizations = MaterialLocalizations.of(
          tester.element(find.byType(NavigationBar)),
        );

        final learning = tester.widget<NavigationDestination>(
          find.byKey(const ValueKey<String>('home/learn')),
        );
        expect(learning.label, 'เรียน');
        expect((learning.icon as Icon).icon, Icons.school_outlined);
        expect((learning.selectedIcon! as Icon).icon, Icons.school);

        for (var index = 0; index < entryIds.length; index++) {
          final entry = NavigationGlossary.require(entryIds[index]);
          final data = _bottomDestinationSemantics(entry);
          expect(data.hasAction(SemanticsAction.tap), isTrue, reason: entry.id);
          expect(data.role, SemanticsRole.tab, reason: entry.id);
          expect(
            data.flagsCollection.isSelected == Tristate.isTrue,
            index == 0,
            reason: entry.id,
          );
          expect(data.label, contains(entry.semanticsLabel), reason: entry.id);
          expect(
            data.label,
            contains(
              localizations.tabLabel(
                tabIndex: index + 1,
                tabCount: entryIds.length,
              ),
            ),
            reason: entry.id,
          );
        }

        for (var index = 1; index < entryIds.length; index++) {
          final entry = NavigationGlossary.require(entryIds[index]);
          tester.semantics.performAction(
            _bottomDestinationFinder(entry),
            SemanticsAction.tap,
          );
          await tester.pump();

          final navigationBar = tester.widget<NavigationBar>(
            find.byType(NavigationBar),
          );
          expect(navigationBar.selectedIndex, index);
          for (
            var candidateIndex = 0;
            candidateIndex < entryIds.length;
            candidateIndex++
          ) {
            final candidate = NavigationGlossary.require(
              entryIds[candidateIndex],
            );
            expect(
              _bottomDestinationSemantics(
                    candidate,
                  ).flagsCollection.isSelected ==
                  Tristate.isTrue,
              candidateIndex == index,
              reason: candidate.id,
            );
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('Thai glossary renders exact drawer destination semantics', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('legacy-drawer-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ร้านค้า'), findsOneWidget);
      expect(find.text('สแกนวัตถุ'), findsOneWidget);
      expect(find.text('ฝึกพูดตาม'), findsOneWidget);
      expect(find.text('ผู้ช่วยสอน AI'), findsOneWidget);
      expect(find.text('ตั้งค่าการเชื่อมต่อ AI'), findsOneWidget);

      final quests = find.byKey(
        const ValueKey<String>('drawer/rewards/quests'),
      );
      await tester.scrollUntilVisible(
        quests,
        200,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ),
      );
      expect(quests, findsOneWidget);
      expect(
        find.descendant(of: quests, matching: find.text('ภารกิจการเรียน')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quests, matching: find.byIcon(Icons.flag_outlined)),
        findsOneWidget,
      );
      _expectSingleThaiDrawerAction(
        tester,
        action: quests,
        entryId: 'drawer/rewards/quests',
        visibleLabel: NavigationGlossary.require(
          'drawer/rewards/quests',
        ).fullThaiLabel,
      );
      expect(find.text('AI Tutor'), findsNothing);
      expect(find.text('AI Provider BYOK'), findsNothing);
      expect(find.text('Quests'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'study-planning has one canonical entry and fails closed when unavailable',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('home/study-planning')),
        findsNothing,
      );

      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: registry,
            builder: (_) {
              builds += 1;
              return const Text('study-planning must not build');
            },
          ),
        ),
      );
      expect(builds, 0);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);

      registry.emergencyOff(Feature.studyPlanning);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('home/study-planning')),
        findsNothing,
      );
    },
  );

  testWidgets('only the selected indexed destination keeps tickers active', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('home/mastery')));
    await tester.pump();

    final masteryContext = tester.element(find.byType(MasteryDashboardScreen));
    expect(TickerMode.valuesOf(masteryContext).enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('home/vocabulary')));
    await tester.pump();
    expect(TickerMode.valuesOf(masteryContext).enabled, isFalse);
  });

  testWidgets('live emergency-off rebuilds mounted navigation', (
    WidgetTester tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(_mainNavigationApp(registry));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));

    registry.emergencyOff(Feature.mastery);
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets(
    'removing an earlier entry preserves the selected feature and State',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      final selectedState = tester.state(find.byType(MasteryDashboardScreen));

      registry.emergencyOff(Feature.vocabulary);
      await tester.pump();

      expect(find.byType(MasteryDashboardScreen), findsOneWidget);
      expect(
        tester.state(find.byType(MasteryDashboardScreen)),
        same(selectedState),
      );
    },
  );

  testWidgets(
    'disabling the selected entry removes its destination but gates its view',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home/mastery')));
      await tester.pumpAndSettle();
      expect(find.byType(MasteryDashboardScreen), findsOneWidget);

      registry.emergencyOff(Feature.mastery);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byType(MasteryDashboardScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
    },
  );

  testWidgets(
    'disabling every selected Learning capability selects the first visible primary',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home/learn')));
      await tester.pumpAndSettle();
      expect(find.byType(ChooseModeScreen), findsOneWidget);

      registry.emergencyOff(Feature.quiz);
      registry.emergencyOff(Feature.srs);
      registry.emergencyOff(Feature.reading);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      expect(find.byType(ChooseModeScreen), findsNothing);
      expect(find.text('อ่านเชื่อมโยงความจำ'), findsNothing);
      expect(find.text('Word Scramble'), findsNothing);
    },
  );

  testWidgets(
    'missing or all-hidden registries keep a one-entry Profile shell',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationScreen(
            featureRegistry: BuildFeatureRegistry(<Feature, FeatureState>{}),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
    },
  );

  testWidgets('one-entry fallback automatically selects Profile', (
    tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(_mainNavigationApp(registry));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home/mastery')));
    await tester.pumpAndSettle();
    for (final feature in <Feature>[
      Feature.vocabulary,
      Feature.quiz,
      Feature.srs,
      Feature.reading,
      Feature.mastery,
      Feature.weakness,
      Feature.achievements,
      Feature.studyPlanning,
    ]) {
      registry.emergencyOff(feature);
    }
    await tester.pump();

    expect(find.byType(ProductionFeatureUnavailable), findsNothing);
    final profileFallback = find.byKey(
      const ValueKey<String>('profile-fallback-destination'),
    );
    expect(profileFallback, findsOneWidget);

    await tester.tap(profileFallback);
    await tester.pump();
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.byType(ProductionFeatureUnavailable), findsNothing);
  });

  testWidgets('AI settings drawer route uses provider-neutral screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.key_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AiTutorSettingsScreen), findsOneWidget);
  });
}

SemanticsNode _bottomDestinationNode(NavigationGlossaryEntry entry) {
  final matchingNodes = _bottomDestinationFinder(
    entry,
  ).evaluate().toList(growable: false);
  expect(matchingNodes, hasLength(1), reason: entry.id);
  return matchingNodes.single;
}

SemanticsFinder _bottomDestinationFinder(NavigationGlossaryEntry entry) =>
    find.semantics.byLabel(RegExp(RegExp.escape(entry.semanticsLabel)));

SemanticsData _bottomDestinationSemantics(NavigationGlossaryEntry entry) =>
    _bottomDestinationNode(entry).getSemanticsData();

void _expectSingleThaiDrawerAction(
  WidgetTester tester, {
  required Finder action,
  required String entryId,
  required String visibleLabel,
}) {
  final entry = NavigationGlossary.require(entryId);
  expect(
    find.descendant(of: action, matching: find.text(visibleLabel)),
    findsOneWidget,
  );
  expect(find.byTooltip(entry.tooltip), findsOneWidget);
  final semanticActions = find
      .bySemanticsLabel(RegExp('^${RegExp.escape(entry.semanticsLabel)}\$'))
      .evaluate()
      .toList(growable: false);
  expect(semanticActions, hasLength(1));
  final semanticAction = find.byElementPredicate(
    (element) => identical(element, semanticActions.single),
  );
  expect(
    tester
        .getSemantics(semanticAction)
        .getSemanticsData()
        .hasAction(SemanticsAction.tap),
    isTrue,
  );
}

Widget _mainNavigationApp(
  FeatureRegistry registry, {
  int initialIndex = 0,
  double textScale = 1,
  AppRuntimeStatus? runtimeStatusOverride,
  FeatureRegistry? dependencyFeatureRegistry,
  TodayHubSnapshotLoader? todayHub,
  LocalOwnerRepository? localOwners,
  AppDatabase? databaseOverride,
  bool exposeDatabase = false,
  bool internalPairMatching = false,
  LearningHistoryUseCases? historyOverride,
  LearningUseCases? learningOverride,
  VocabularyUseCases? vocabularyOverride,
  ReviewOwnerIdentityReader? activeOwnerIdentities,
  ReviewCenterReader? reviewReaderOverride,
  ReviewSessionLauncher? reviewLauncherOverride,
  bool includeReviewCenter = true,
  bool includeLearningHistory = true,
  bool includeLearning = true,
  bool includeVocabulary = true,
  bool includeLessonModes = true,
  bool includeCreateLessonController = true,
  bool includeSessionConfigurations = true,
  SessionConfigurationStore? sessionConfigurationsOverride,
  bool includeCurrentActivityEvidence = true,
  bool includeRewardAccounts = true,
  bool includeAdventureMotivation = true,
  bool includeAdventureResultNextAction = true,
  bool includeAdventureReceiptRefresher = true,
  bool includeAdventureSessionComposer = true,
  bool includeActiveOwnerIdentities = true,
  bool useNonCanonicalAdventureResultNextAction = false,
  bool mismatchReviewSessionAuthority = false,
  bool mismatchHistorySessionAuthority = false,
  bool mismatchAdventureResultReviewIdentity = false,
  bool mismatchAdventureResultOwnerIdentity = false,
  bool mismatchReviewCenterOwnerIdentity = false,
  bool includeAdventure = false,
  AdventureDiagnostics? adventureDiagnosticsOverride,
  ValueSetter<AppDependencies>? onDependencies,
}) {
  final database = databaseOverride ?? AppDatabase(NativeDatabase.memory());
  if (databaseOverride == null) addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owner = localOwners ?? _NavigationOwner();
  final ownerIdentities =
      activeOwnerIdentities ?? const _NavigationReviewOwnerIdentities();
  final reviewReader = reviewReaderOverride ?? const _NavigationReviewReader();
  final progress = ProgressUseCases(
    owners: owner,
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
  );
  final learning =
      learningOverride ??
      LearningUseCases(
        owners: owner,
        repository: _NavigationLearningRepository(),
        generateId: () => 'navigation-learning',
        nowUtc: () => DateTime.utc(2026, 8, 24),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
  final learnerPreferences = LearnerPreferencesUseCases(
    repository: _NavigationPreferences(),
    owners: owner,
    nowUtc: () => DateTime.utc(2026, 8, 30),
  );
  final otherLearning = LearningUseCases(
    owners: owner,
    repository: _NavigationLearningRepository(),
    generateId: () => 'navigation-other-learning',
    nowUtc: () => DateTime.utc(2026, 8, 24),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  final adventureCatalog = PackagedAdventureWorldCatalog.forLocale('th');
  final adventureDiagnostics =
      adventureDiagnosticsOverride ?? AdventureDiagnostics();
  final adventureCatalogRecovery = AdventureCatalogRecoveryOperations(
    manager: const _NavigationOfflineContentManager(),
    diagnostics: adventureDiagnostics,
  );
  final adventureEntry = AdventureEntryUseCases(
    rollout: AdventureRolloutGate(
      features: registry,
      requiredDependenciesReady: () => true,
      catalogReadiness: () => AdventureCatalogReadiness.ready,
    ),
    catalog: adventureCatalog,
    todayHubIdentity: todayHub ?? Object(),
    learningIdentity: learning,
    preferences: LearnerAdventurePresentationPreferences(learnerPreferences),
    diagnostics: adventureDiagnostics,
  );
  final dependencies = AppDependencies(
    database: exposeDatabase ? database : null,
    initialRoute: AppRoute.home,
    runtimeStatus:
        runtimeStatusOverride ??
        const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.ready,
          supabase: RuntimeAvailability.ready,
          backends: RuntimeAvailability.ready,
        ),
    config: null,
    guestSessionService: _NavigationGuestSession(),
    quest: testQuestUseCases(),
    features: dependencyFeatureRegistry ?? registry,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    vocabulary: includeVocabulary
        ? vocabularyOverride ??
              VocabularyUseCases(
                owners: owner,
                vocabulary: _NavigationVocabularyRepository(),
                generateId: () => 'navigation-vocabulary',
                nowUtc: () => DateTime.utc(2026, 8, 24),
              )
        : null,
    localOwners: owner,
    learning: includeLearning ? learning : null,
    lessonModes: includeLessonModes
        ? buildLessonModeRegistry(
            internalPairMatching: internalPairMatching,
            matchingDeliveryState: internalPairMatching
                ? LessonModeDeliveryState.enabled
                : LessonModeDeliveryState.implementedOff,
          )
        : null,
    createLessonController: includeCreateLessonController
        ? (adapter) =>
              UnifiedLessonController(learning: learning, adapter: adapter)
        : null,
    currentActivityEvidence: includeLearning && includeCurrentActivityEvidence
        ? CurrentActivityEvidenceAdapter(learning: learning)
        : null,
    sessionConfigurations: includeSessionConfigurations
        ? sessionConfigurationsOverride ??
              DriftSessionConfigurationStore(database)
        : null,
    progress: progress,
    learnerPreferences: learnerPreferences,
    rewardAccounts: includeAdventure && includeRewardAccounts
        ? const _NavigationRewardAccounts()
        : null,
    todayHub: todayHub,
    activeOwnerIdentities: includeActiveOwnerIdentities
        ? ownerIdentities
        : null,
    reviewCenter: includeReviewCenter
        ? ReviewCenterUseCases(
            reader: reviewReader,
            ownerIdentities: mismatchReviewCenterOwnerIdentity
                ? _NavigationReviewOwnerIdentities()
                : ownerIdentities,
            sessionLauncher:
                reviewLauncherOverride ??
                _NavigationReviewSessionLauncher(
                  mismatchReviewSessionAuthority ? otherLearning : learning,
                ),
            nowUtc: () => DateTime.utc(2026, 8, 24),
            timezoneId: 'Asia/Bangkok',
          )
        : null,
    learningHistory: includeLearningHistory
        ? historyOverride ??
              LearningHistoryUseCases(
                owners: owner,
                reader: const _NavigationHistoryReader(),
                sessionLauncher: _NavigationHistorySessionLauncher(
                  mismatchHistorySessionAuthority ? otherLearning : learning,
                ),
              )
        : null,
    studyPlanning: StudyPlanningUseCases(
      packs: _NavigationLearningPacks(),
      progress: progress,
    ),
    aiTutor: _NavigationAiTutor(),
    adventureEntry: includeAdventure ? adventureEntry : null,
    adventureCatalog: includeAdventure ? adventureCatalog : null,
    adventurePresentationPermits: includeAdventure
        ? const NoActivePresentationPermitReader()
        : null,
    adventureJourney: includeAdventure ? AdventureJourneyUseCases() : null,
    adventureSessionComposer:
        includeAdventure && includeAdventureSessionComposer
        ? CanonicalAdventureSessionComposer(diagnostics: adventureDiagnostics)
        : null,
    adventureMotivation: includeAdventure && includeAdventureMotivation
        ? const _NavigationAdventureMotivation()
        : null,
    adventureResultNextAction:
        includeAdventure && includeAdventureResultNextAction
        ? useNonCanonicalAdventureResultNextAction
              ? const _NavigationAdventureResultNextActionReader()
              : ReviewCenterAdventureResultNextActionReader(
                  reader: mismatchAdventureResultReviewIdentity
                      ? _NavigationReviewReader()
                      : reviewReader,
                  ownerIdentities: mismatchAdventureResultOwnerIdentity
                      ? _NavigationReviewOwnerIdentities()
                      : ownerIdentities,
                  nowUtc: () => DateTime.utc(2026, 8, 24),
                  timezoneId: 'Asia/Bangkok',
                )
        : null,
    adventureReceiptBarrier:
        includeAdventure && includeAdventureReceiptRefresher
        ? const _NavigationAdventureReceiptRefresher()
        : null,
    adventureDiagnostics: includeAdventure ? adventureDiagnostics : null,
    adventureCatalogRecovery: includeAdventure
        ? adventureCatalogRecovery
        : null,
  );
  onDependencies?.call(dependencies);
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: MainNavigationScreen(
        featureRegistry: registry,
        initialIndex: initialIndex,
      ),
    ),
  );
}

final class _NavigationOfflineContentManager implements OfflineContentManager {
  const _NavigationOfflineContentManager();

  @override
  Future<List<OfflineContentState>> catalog() async => const [];

  @override
  Future<OfflineContentState> download(ContentIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<bool> canRemove(ContentIdentity identity) async => false;

  @override
  Future<int> removeBytes(ContentIdentity identity) async => 0;

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> dispose() async {}
}

final class _NavigationRewardAccounts implements RewardAccountReader {
  const _NavigationRewardAccounts();

  @override
  Future<RewardAccount> loadForOwner(String ownerId) async =>
      const RewardAccount(
        coinBalance: 0,
        catalogVersion: RewardCatalog.version,
        ownedItemIds: <String>{},
        equippedBySlot: <String, String>{},
        transactionCount: 0,
      );
}

final class _NavigationAdventureReceiptRefresher
    implements AdventureProjectionReceiptBarrier {
  const _NavigationAdventureReceiptRefresher();

  @override
  Future<void> waitForCanonicalProjection(String ownerId) async {}
}

final class _NavigationAdventureMotivation
    implements AdventureMotivationProjectionReader {
  const _NavigationAdventureMotivation();

  static const AdventureProjectionOutcome _notEligible =
      AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.notEligible,
      );

  @override
  Future<AdventureMotivationSnapshot> read(
    AdventureMotivationProjectionRequest request,
  ) async => _snapshot(null);

  @override
  Future<AdventureMotivationSnapshot> readForEvidence(
    String evidenceId,
  ) async => _snapshot(evidenceId);

  @override
  Future<List<AdventureMotivationSnapshot>> readForSession({
    required String ownerId,
    required String sessionId,
  }) async => const <AdventureMotivationSnapshot>[];

  AdventureMotivationSnapshot _snapshot(String? evidenceId) =>
      AdventureMotivationSnapshot(
        sourceEvidenceId: evidenceId,
        questOutcome: _notEligible,
        streakOutcome: _notEligible,
        rewardOutcome: _notEligible,
        pendingProjection: false,
      );
}

final class _NavigationPreferences implements LearnerPreferencesRepository {
  LearnerPreferences current = LearnerPreferences.defaults(
    ownerId: 'owner:main-navigation',
    updatedAtUtc: DateTime.utc(2026, 8, 30),
  );

  @override
  Future<LearnerPreferences> read(String ownerId) async => current;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = LearnerPreferences(
      ownerId: current.ownerId,
      preferenceVersion: current.preferenceVersion,
      goal: current.goal,
      availableMinutesPerDay: current.availableMinutesPerDay,
      activityPreference: current.activityPreference,
      homeExperience: current.homeExperience,
      updatedAtUtc: current.updatedAtUtc,
      display: display,
    );
  }
}

TodayHubSnapshot _emptyTodayHubSnapshot({
  LearningSessionSummary? resumableSession,
  String ownerId = 'owner:main-navigation',
}) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: DateTime.utc(2026, 8, 31, 8),
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: resumableSession,
  assignedAssessment: null,
  reviewWork: const <TodayHubReviewWorkItem>[],
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.unavailable(
      ownerId: ownerId,
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

Future<({ContentIdentity identity, String checksumSha256, String spelling})>
_seedNavigationMixedReviewWord(AppDatabase database, String ownerId) async {
  const categoryId = 'category:navigation-mixed-review';
  const wordId = 'word:navigation-station';
  const spelling = 'station';
  const meaning = 'สถานี';
  const partOfSpeech = 'noun';
  const source = 'pack';
  const isGlobal = true;
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: categoryId,
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: partOfSpeech,
    cefrLevel: 'A1',
    source: source,
    isGlobal: isGlobal,
  );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Navigation mixed review',
          normalizedName: 'navigation mixed review',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: partOfSpeech,
          cefrLevel: const Value('A1'),
          source: const Value(source),
          isGlobal: const Value(isGlobal),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: Value(ContentProvenance.packaged.name),
          contentReviewState: Value(ContentReviewState.approved.name),
          contentPublicationState: Value(
            ContentPublicationState.published.name,
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  return (
    identity: const ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: wordId,
      revision: 1,
    ),
    checksumSha256: checksum,
    spelling: spelling,
  );
}

Future<void> _seedNavigationReviewDistractor(
  AppDatabase database,
  String ownerId,
) async {
  const categoryId = 'category:navigation-mixed-review';
  const spelling = 'airport';
  const meaning = 'สนามบิน';
  const partOfSpeech = 'noun';
  const source = 'pack';
  const isGlobal = true;
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: categoryId,
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: partOfSpeech,
    cefrLevel: 'A1',
    source: source,
    isGlobal: isGlobal,
  );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:navigation-airport-distractor',
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: partOfSpeech,
          cefrLevel: const Value('A1'),
          source: const Value(source),
          isGlobal: const Value(isGlobal),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: Value(ContentProvenance.packaged.name),
          contentReviewState: Value(ContentReviewState.approved.name),
          contentPublicationState: Value(
            ContentPublicationState.published.name,
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

TodayHubSnapshot _navigationMixedReviewToday({
  required String ownerId,
  required ContentIdentity identity,
  required String checksumSha256,
}) {
  final evaluatedAtUtc = DateTime.utc(2026, 9, 5, 9);
  final item = TodayHubReviewWorkItem(
    item: ReviewQueueItem(
      snapshot: ReviewedLexicalContentSnapshot(
        identity: identity,
        categoryId: 'category:navigation-mixed-review',
        spelling: 'station',
        normalizedSpelling: 'station',
        meaning: 'สถานี',
        normalizedMeaning: 'สถานี',
        partOfSpeech: 'noun',
        cefrLevel: 'A1',
        source: 'pack',
        isGlobal: true,
        coreChecksumSha256: checksumSha256,
        provenance: ContentProvenance.packaged,
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        artifact: null,
      ),
      provenance: <ReviewReasonProvenance>[
        ReviewReasonProvenance.due(
          sourceId: 'srs:${identity.id}',
          dueAtUtc: evaluatedAtUtc,
        ),
      ],
    ),
    recommendation: null,
  );
  return TodayHubSnapshot(
    ownerId: ownerId,
    evaluatedAtUtc: evaluatedAtUtc,
    sectionOrder: TodayHubSectionKind.values,
    resumableSession: null,
    assignedAssessment: null,
    reviewWork: <TodayHubReviewWorkItem>[item],
    recommendation: TodayHubRecommendation(
      result: RecommendationPanelResult.unavailable(
        ownerId: ownerId,
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
}

AdventureSessionPlanV1 _navigationMixedReviewPlan({
  required String ownerId,
  required ContentIdentity identity,
  required String checksumSha256,
}) {
  final createdAtUtc = DateTime.utc(2026, 9, 5, 11);
  final limits = const SessionConfigurationProtocolLimits.standard().copyWith(
    maximumItemCount: 1,
  );
  final registration = buildLessonModeRegistry().resolve(
    LessonMode.typedRecall,
  )!;
  final configuration = const SessionConfigurationPolicy().validate(
    draft: const SessionConfigurationDraft(
      itemCount: 1,
      direction: SessionDirection.mixed,
      difficulty: SessionDifficulty.standard,
      hintBudget: 1,
      timing: SessionTiming.timed(Duration(minutes: 5)),
      packIdentity: null,
    ),
    registration: registration,
    limits: limits,
    ownerId: ownerId,
    availablePackIdentities: const <ContentIdentity>[],
  );
  const planId = 'adventure-plan:navigation-mixed-review';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: ownerId,
    createdAtUtc: createdAtUtc,
    sourceEvaluatedAtUtc: createdAtUtc,
    content: <ContentIdentity>[identity],
    contentChecksumsSha256: <String, String>{identity.id: checksumSha256},
    mode: LessonMode.typedRecall,
    configuration: configuration,
    recommendationPolicyVersion: 'f14-v1',
    sourceReasonCode: 'due_review',
    learnerOverrideApplied: false,
    origin: const AdventureOriginContextV1(
      planId: planId,
      nodeId: 'resume-review',
      catalogId: PackagedAdventureWorldCatalog.catalogId,
      catalogVersion: PackagedAdventureWorldCatalog.catalogVersion,
      catalogSchemaVersion: 1,
      presentation: TodayExperiencePresentation.adventure,
    ),
  );
}

TodayHubSnapshot _navigationResumeToday(
  String ownerId,
  LearningSessionSummary session,
) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: DateTime.utc(2026, 9, 5, 11, 1),
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: session,
  assignedAssessment: null,
  reviewWork: const <TodayHubReviewWorkItem>[],
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.unavailable(
      ownerId: ownerId,
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

final class _NavigationTodayHubLoader implements TodayHubSnapshotLoader {
  _NavigationTodayHubLoader(this.snapshot);

  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _NavigationReviewReader implements ReviewCenterReader {
  const _NavigationReviewReader();

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async =>
      const <ReviewQueueItem>[];
}

final class _ProbeDueReader implements ReviewCenterReader {
  const _ProbeDueReader(this.item);

  final ReviewQueueItem item;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async =>
      <ReviewQueueItem>[item];
}

final class _NavigationAdventureResultNextActionReader
    implements AdventureResultNextActionReader {
  const _NavigationAdventureResultNextActionReader();

  @override
  Future<AdventureNextAction> read({required String ownerId}) async =>
      AdventureNextAction.none;
}

final class _NavigationReviewOwnerIdentities
    implements ReviewOwnerIdentityReader {
  const _NavigationReviewOwnerIdentities([
    this.ownerId = 'owner:main-navigation',
  ]);

  final String ownerId;

  @override
  Future<String> requireSingleActiveOwnerId() async => ownerId;
}

final class _MutableNavigationReviewOwnerIdentities
    implements ReviewOwnerIdentityReader {
  _MutableNavigationReviewOwnerIdentities(this.ownerId);

  String ownerId;

  @override
  Future<String> requireSingleActiveOwnerId() async => ownerId;
}

final class _CountingSessionConfigurationStore
    implements SessionConfigurationStore {
  int saveCalls = 0;

  @override
  Future<void> clear({
    required String ownerId,
    required LessonMode mode,
  }) async {}

  @override
  Future<SessionConfiguration?> read({
    required String ownerId,
    required LessonMode mode,
  }) async => null;

  @override
  Future<void> save(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  }) async {
    saveCalls += 1;
  }
}

final class _GatedActiveOwnerSessionConfigurationStore
    implements ActiveOwnerSessionConfigurationStore {
  _GatedActiveOwnerSessionConfigurationStore(this.activeOwnerId);

  String activeOwnerId;
  final Completer<void> persistenceStarted = Completer<void>();
  final Completer<void> releasePersistence = Completer<void>();
  int saveCalls = 0;
  int atomicSaveCalls = 0;
  int writeCalls = 0;

  @override
  Future<void> clear({
    required String ownerId,
    required LessonMode mode,
  }) async {}

  @override
  Future<SessionConfiguration?> read({
    required String ownerId,
    required LessonMode mode,
  }) async => null;

  @override
  Future<void> save(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  }) {
    saveCalls += 1;
    return _persist(configuration, validateActiveOwner: false);
  }

  @override
  Future<void> saveForActiveOwner(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  }) {
    atomicSaveCalls += 1;
    return _persist(configuration, validateActiveOwner: true);
  }

  Future<void> _persist(
    SessionConfiguration configuration, {
    required bool validateActiveOwner,
  }) async {
    if (!persistenceStarted.isCompleted) persistenceStarted.complete();
    await releasePersistence.future;
    if (validateActiveOwner && configuration.ownerId != activeOwnerId) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.ownerDrift,
      );
    }
    writeCalls += 1;
  }
}

final class _UnavailableNavigationOwnerIdentities
    implements ReviewOwnerIdentityReader {
  const _UnavailableNavigationOwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() =>
      Future<String>.error(StateError('no active owner'));
}

final class _NavigationReviewSessionLauncher implements ReviewSessionLauncher {
  const _NavigationReviewSessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) => Future<PinnedReviewSessionLaunch>.error(
    StateError('The navigation fixture has no review work.'),
  );

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}

final class _NavigationHistoryReader implements LearningHistoryReader {
  const _NavigationHistoryReader();

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async =>
      const <LearningHistoryEntry>[];

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) => Future<LessonStartCommand>.error(
    StateError('The navigation fixture has no history work.'),
  );
}

final class _NavigationHistorySessionLauncher
    implements LearningHistorySessionLauncher {
  const _NavigationHistorySessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<void> start(LessonStartCommand command) => Future<void>.error(
    StateError('The navigation fixture cannot start history work.'),
  );
}

final class _NavigationOwner implements LocalOwnerRepository {
  _NavigationOwner({this.ownerId = 'owner:main-navigation'});

  final String ownerId;
  int getOrCreateCalls = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    getOrCreateCalls += 1;
    return identity.LocalOwner(
      id: ownerId,
      createdAtUtc: DateTime.utc(2026, 8, 24),
    );
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _NavigationGuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'main-navigation');
}

final class _NavigationVocabularyRepository implements VocabularyRepository {
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      Stream.value(const []);

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      Stream.value(const []);

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingSecondPinnedReadVocabularyRepository
    implements VocabularyRepository {
  _FailingSecondPinnedReadVocabularyRepository(this.delegate);

  final VocabularyRepository delegate;
  int pinnedReadCalls = 0;

  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds) {
    pinnedReadCalls += 1;
    if (pinnedReadCalls == 2) {
      return Future<List<VocabularyWord>>.error(
        StateError('transient mixed-review catalog read failure'),
      );
    }
    return delegate.readPinnedByIds(wordIds);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationLearningRepository implements LearningRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationLearningPacks implements LearningPackRepository {
  @override
  Future<Never> getVersion(String packId, int revision) => Future<Never>.error(
    StateError('Navigation test repository has no pack-detail content.'),
  );

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      const [];
}

final class _NavigationAiTutor implements AiTutorController {
  @override
  Future<AiTutorSettingsStatus> loadSettings() async {
    return const AiTutorSettingsStatus(
      hasKey: false,
      providerConsent: false,
      shareLearningSummary: false,
      providerId: AiProviderId.gemini,
      model: null,
    );
  }

  @override
  Future<List<AiUsageSummary>> loadUsage() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
