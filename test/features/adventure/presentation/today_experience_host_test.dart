import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_presentation_preferences.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_hub_screen.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_document.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/research/application/adventure_research_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import '../../../support/motivation_research_fixture.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

void main() {
  testWidgets(
    'Standard contextual actions capture exact inputs without Adventure reads',
    (tester) async {
      final today = _today();
      final loader = _Loader(today);
      final journey = _Journey();
      final rewards = _RewardAccounts(_rewardAccount());
      final originalActions = _Actions();
      final replacement = _Actions();
      TodayHubSnapshot? capturedToday;
      AdventureProductEntryDecision? capturedDecision;
      bool Function()? current;
      var ids = 0;
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: journey,
          rewardAccounts: rewards,
          actions: originalActions,
          createId: () {
            ids++;
            return '11111111-1111-4111-8111-111111111111';
          },
          contextualStandardActions:
              ({
                required today,
                required entryDecision,
                required fallback,
                required isCurrent,
              }) {
                capturedToday = today;
                capturedDecision = entryDecision;
                current = isCurrent;
                expect(fallback, same(originalActions));
                return replacement;
              },
        ),
      );
      await tester.pumpAndSettle();
      expect(capturedToday, same(today));
      expect(
        capturedDecision!.entryAttemptId,
        '11111111-1111-4111-8111-111111111111',
      );
      expect(current!(), isTrue);
      expect(
        tester.widget<TodayHubView>(find.byType(TodayHubView)).actions,
        same(replacement),
      );
      expect(loader.calls, 1);
      expect(ids, 1);
      expect(journey.today, isNull);
      expect(rewards.calls, 0);
    },
  );

  testWidgets(
    'Standard default preserves exact original delegate and avoids Adventure reads',
    (tester) async {
      final fallback = _Actions();
      final journey = _Journey();
      final rewards = _RewardAccounts(_rewardAccount());
      await tester.pumpWidget(
        _app(
          loader: _Loader(_today()),
          journey: journey,
          rewardAccounts: rewards,
          actions: fallback,
          createId: () => '11111111-1111-4111-8111-111111111111',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TodayHubView>(find.byType(TodayHubView)).actions,
        same(fallback),
      );
      expect(journey.today, isNull);
      expect(rewards.calls, 0);
    },
  );

  testWidgets('Standard captured action guard rejects refresh and disposal', (
    tester,
  ) async {
    final guards = <bool Function()>[];
    final loader = _Loader(_today());
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        contextualStandardActions:
            ({
              required today,
              required entryDecision,
              required fallback,
              required isCurrent,
            }) {
              guards.add(isCurrent);
              return fallback;
            },
      ),
    );
    await tester.pumpAndSettle();
    final original = guards.last;
    expect(original(), isTrue);
    await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
    await tester.pumpAndSettle();
    expect(original(), isFalse);
    expect(guards.last(), isTrue);
    expect(loader.calls, 2);
    final refreshed = guards.last;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(refreshed(), isFalse);
  });

  testWidgets('signed renewal replaces the open Host permit deadline', (
    tester,
  ) async {
    final f = MotivationResearchFixture();
    await tester.runAsync(f.initialize);
    addTearDown(f.database.close);
    final runtime = AdventureResearchRuntime(
      participation: f.participation,
      measurements: f.measurements,
      opportunities: DriftMeasurementOpportunityRepository(
        f.database,
        measurements: f.measurements,
        nowUtc: () => f.now,
      ),
      consent: DriftResearchConsentRepository(f.database),
    );
    final loader = _Loader(_today(ownerId: 'owner:a'));
    await tester.pumpWidget(
      _app(
        ownerId: 'owner:a',
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        activePermits: f.participation,
        research: runtime,
        nowUtc: () => f.now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MotivationMeasurementForm), findsOneWidget);
    final next = f.permit(expiresAtUtc: f.now.add(const Duration(minutes: 10)));
    final payload = {
      ...jsonDecode(next.canonicalPayload()) as Map<String, dynamic>,
      'localRevision': 2,
      'cloudRevision': 2,
    };
    final renewed = decodeResearchPermitDocument(
      jsonEncode({
        ...payload,
        'payloadSha256': sha256
            .convert(utf8.encode(jsonEncode(payload)))
            .toString(),
        'signature': next.signature,
      }),
    );
    await tester.runAsync(() => f.participation.importPermit(renewed));
    await tester.pumpAndSettle();
    f.now = f.now.add(const Duration(minutes: 11));
    await tester.pump(const Duration(minutes: 11));
    await tester.pumpAndSettle();
    expect(find.byType(MotivationMeasurementForm), findsNothing);
    expect(find.byType(TodayHubView), findsOneWidget);
    expect(loader.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'rendered switches drain in order while an earlier research queue hook is delayed',
    (tester) async {
      final f = MotivationResearchFixture();
      await tester.runAsync(f.initialize);
      addTearDown(f.database.close);
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var held = false;
      final runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
        onLocalMutation: (_) async {
          if (!held &&
              (await f.database.select(f.database.eventsV2).get()).any(
                (e) => e.eventType == 'TodayExperiencePresented',
              )) {
            held = true;
            await release.future;
          }
        },
      );
      final run = (await tester.runAsync(
        () =>
            runtime.useCases.prepare(ownerId: 'owner:a', permitId: 'permit:a'),
      ))!;
      await tester.runAsync(
        () => f.measurements.record(
          MotivationResponse(
            ownerId: 'owner:a',
            runId: run.id,
            itemId: 'baseline',
            responseCode: 'high',
          ),
        ),
      );
      final loader = _Loader(_today(ownerId: 'owner:a'));
      var ids = 0;
      await tester.pumpWidget(
        _app(
          ownerId: 'owner:a',
          loader: loader,
          journey: _Journey(),
          createId: () {
            ids++;
            return '11111111-1111-4111-8111-111111111111';
          },
          activePermits: f.participation,
          research: runtime,
          nowUtc: () => f.now,
        ),
      );
      await tester.pumpAndSettle();
      expect(held, isTrue);
      for (var change = 0; change < 12; change++) {
        await tester.tap(find.text(change.isEven ? 'มาตรฐาน' : 'ผจญภัย'));
        await tester.pumpAndSettle();
        expect(
          find.byType(TodayHubView),
          change.isEven ? findsOneWidget : findsNothing,
        );
      }
      release.complete();
      await tester.pumpAndSettle();
      final events = (await tester.runAsync(
        () => f.database.select(f.database.eventsV2).get(),
      ))!;
      expect(
        events.where((e) => e.eventType == 'TodayExperiencePresented'),
        hasLength(1),
      );
      expect(
        events.where(
          (e) => e.eventType == 'TodayExperiencePresentationChanged',
        ),
        hasLength(10),
      );
      final opportunities = (await tester.runAsync(
        () => f.database.select(f.database.measurementOpportunities).get(),
      ))!;
      expect(opportunities, hasLength(1));
      expect(opportunities.single.lastSwitchOrdinal, 10);
      expect(opportunities.single.suppressedSwitchCount, 2);
      expect(opportunities.single.effectivePresentation, 'adventure');
      expect(loader.calls, 1);
      expect(ids, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'owner change while Today is pending cannot reveal the old owner after load',
    (tester) async {
      final f = MotivationResearchFixture();
      await tester.runAsync(f.initialize);
      addTearDown(f.database.close);
      final runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
      );
      final pending = Completer<TodayHubSnapshot>();
      await tester.pumpWidget(
        _app(
          ownerId: 'owner:a',
          loader: _PendingLoader(pending.future),
          journey: _Journey(),
          createId: () => '11111111-1111-4111-8111-111111111111',
          activePermits: f.participation,
          research: runtime,
          nowUtc: () => f.now,
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => f.database.transaction(() async {
          await (f.database.update(f.database.localOwners)
                ..where((o) => o.id.equals('owner:a')))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await f.database
              .into(f.database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'owner:b',
                  createdAtUtcMs: f.now.millisecondsSinceEpoch,
                  isActive: const Value(true),
                ),
              );
        }),
      );
      pending.complete(_today(ownerId: 'owner:a'));
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      expect(find.byType(TodayHubView), findsNothing);
      expect(find.text('ป่าแห่งคำศัพท์'), findsNothing);
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.motivationMeasurementRuns).get(),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'research post prompt follows canonical completion and owner change hides old snapshot',
    (tester) async {
      final f = MotivationResearchFixture();
      await tester.runAsync(f.initialize);
      addTearDown(f.database.close);
      final runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
      );
      final run = (await tester.runAsync(
        () =>
            runtime.useCases.prepare(ownerId: 'owner:a', permitId: 'permit:a'),
      ))!;
      await tester.runAsync(
        () => f.measurements.record(
          MotivationResponse(
            ownerId: 'owner:a',
            runId: run.id,
            itemId: 'baseline',
            responseCode: 'high',
          ),
        ),
      );
      final loader = _Loader(_today(ownerId: 'owner:a'));
      await tester.pumpWidget(
        _app(
          ownerId: 'owner:a',
          loader: loader,
          journey: _Journey(),
          createId: () => '11111111-1111-4111-8111-111111111111',
          activePermits: f.participation,
          research: runtime,
          nowUtc: () => f.now,
        ),
      );
      await tester.pumpAndSettle();
      final c = SessionConfiguration.validated(
        schemaVersion: 1,
        policyVersion: sessionConfigurationPolicyVersion,
        ownerId: 'owner:a',
        mode: LessonMode.meaningQuiz,
        itemCount: 2,
        direction: SessionDirection.forward,
        difficulty: SessionDifficulty.standard,
        hintBudget: 0,
        timing: const SessionTiming.timed(Duration(minutes: 2)),
        packIdentity: null,
        protocolId: 'standard',
        protocolVersion: '1',
        protocolLimitsIdentity: 'standard',
      );
      await tester.runAsync(
        () => f.database
            .into(f.database.learningSessions)
            .insert(
              LearningSessionsCompanion.insert(
                id: 'session:one',
                ownerId: 'owner:a',
                activityType: 'quiz',
                state: 'active',
                startedAtUtcMs: f.now.millisecondsSinceEpoch,
                appVersion: '1',
                buildId: 'test',
                sessionConfigurationIdentity: Value(c.contentIdentity),
                sessionConfigurationJson: Value(c.stableSerialization),
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      f.now = f.now.add(const Duration(minutes: 2));
      await tester.runAsync(
        () =>
            (f.database.update(
              f.database.learningSessions,
            )..where((s) => s.id.equals('session:one'))).write(
              LearningSessionsCompanion(
                state: const Value('completed'),
                endedAtUtcMs: Value(f.now.millisecondsSinceEpoch),
              ),
            ),
      );
      await tester.pumpAndSettle();
      final post = tester.widget<MotivationMeasurementForm>(
        find.byType(MotivationMeasurementForm),
      );
      expect(post.timepoint, MotivationTimepoint.post);
      expect(loader.calls, 1);
      f.now = f.now.add(const Duration(minutes: 30, milliseconds: 1));
      await tester.pump(const Duration(minutes: 30, milliseconds: 1));
      await tester.pumpAndSettle();
      expect(
        find.byType(MotivationMeasurementForm),
        findsNothing,
        reason:
            'an open post form must retire at its own deadline, before the permit expires',
      );
      expect(loader.calls, 1);
      await tester.runAsync(
        () => f.database.transaction(() async {
          await f.database.customStatement(
            'UPDATE local_owners SET is_active=0',
          );
          await f.database
              .into(f.database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'owner:b',
                  createdAtUtcMs: f.now.millisecondsSinceEpoch,
                  isActive: const Value(true),
                ),
              );
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      expect(find.byType(TodayHubView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'research baseline precedes treatment; Skip retains denominator and learning',
    (tester) async {
      final f = MotivationResearchFixture();
      await tester.runAsync(f.initialize);
      addTearDown(f.database.close);
      final runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
      );
      final loader = _Loader(_today(ownerId: 'owner:a'));
      var ids = 0;
      await tester.pumpWidget(
        _app(
          ownerId: 'owner:a',
          loader: loader,
          journey: _Journey(),
          createId: () {
            ids++;
            return '11111111-1111-4111-8111-111111111111';
          },
          activePermits: f.participation,
          research: runtime,
          nowUtc: () => f.now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsOneWidget);
      final form = tester.widget<MotivationMeasurementForm>(
        find.byType(MotivationMeasurementForm),
      );
      expect(form.timepoint, MotivationTimepoint.baseline);
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.measurementOpportunities).get(),
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.eventsV2).get(),
        ),
        isEmpty,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('research-measurement-skip')),
      );
      await tester.tap(find.byKey(const ValueKey('research-measurement-skip')));
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(loader.calls, 1);
      expect(ids, 1);
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.measurementOpportunities).get(),
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.eventsV2).get(),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'baseline completion and Standard switch keep one Today/opportunity',
    (tester) async {
      final f = MotivationResearchFixture();
      await tester.runAsync(f.initialize);
      addTearDown(f.database.close);
      final runtime = AdventureResearchRuntime(
        participation: f.participation,
        measurements: f.measurements,
        opportunities: DriftMeasurementOpportunityRepository(
          f.database,
          measurements: f.measurements,
          nowUtc: () => f.now,
        ),
        consent: DriftResearchConsentRepository(f.database),
      );
      final loader = _Loader(_today(ownerId: 'owner:a'));
      var ids = 0;
      await tester.pumpWidget(
        _app(
          ownerId: 'owner:a',
          loader: loader,
          journey: _Journey(),
          createId: () {
            ids++;
            return '11111111-1111-4111-8111-111111111111';
          },
          activePermits: f.participation,
          research: runtime,
          nowUtc: () => f.now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('baseline-high')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('research-measurement-complete')),
      );
      await tester.tap(
        find.byKey(const ValueKey('research-measurement-complete')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MotivationMeasurementForm), findsNothing);
      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(loader.calls, 1);
      expect(ids, 1);
      final events = await tester.runAsync(
        () => f.database.select(f.database.eventsV2).get(),
      );
      expect(
        events!.where((e) => e.eventType == 'TodayExperiencePresented'),
        hasLength(1),
      );
      expect(
        events.where(
          (e) => e.eventType == 'TodayExperiencePresentationChanged',
        ),
        hasLength(1),
      );
      await tester.runAsync(() => runtime.withdraw('owner:a'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.eventsV2).get(),
        ),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Standard escape is visible and usable while Today is loading', (
    tester,
  ) async {
    final pending = Completer<TodayHubSnapshot>();
    final loader = _PendingLoader(pending.future);
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pump();

    expect(find.byType(TodayHubLoading), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .onSelectionChanged,
      isNotNull,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .selected,
      <TodayExperiencePresentation>{TodayExperiencePresentation.standard},
    );

    pending.complete(_today());
    await tester.pumpAndSettle();
    expect(find.byType(TodayHubView), findsOneWidget);
    expect(loader.calls, 1);
  });

  testWidgets('Standard escape recovers from Adventure load failure', (
    tester,
  ) async {
    final loader = _Loader(_today());
    final savedChoices = <TodayExperiencePresentation>[];
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _FailingJourney(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        activePermits: _Permits(_permit()),
        presentationPreferences: _CallbackPreferenceWriter(
          (_, choice) async => savedChoices.add(choice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodayHubLoadFailure), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pumpAndSettle();

    expect(find.byType(TodayHubView), findsOneWidget);
    expect(loader.calls, 1);
    expect(savedChoices, isEmpty);
  });

  testWidgets('Standard escape stays usable in the unavailable state', (
    tester,
  ) async {
    final loader = _Loader(_today(ownerId: 'owner:other'));
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'กิจกรรมแบบผจญภัยยังไม่พร้อม รายการเรียนเดิมของคุณไม่เปลี่ยนแปลง',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('adventure-standard-switch')),
      findsOneWidget,
    );

    await tester.tap(find.text('มาตรฐาน'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<TodayExperiencePresentation>>(
            find.byKey(const ValueKey('adventure-standard-switch')),
          )
          .selected,
      <TodayExperiencePresentation>{TodayExperiencePresentation.standard},
    );
    expect(loader.calls, 1);
  });

  testWidgets(
    'active Adventure permit escapes to Standard without reopening or saving',
    (tester) async {
      final today = _today();
      final loader = _Loader(today);
      final journey = _Journey();
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      final app = _app(
        loader: loader,
        journey: journey,
        createId: () {
          const id = '11111111-1111-4111-8111-111111111111';
          ids.add(id);
          return id;
        },
        activePermits: _Permits(_permit()),
        presentationPreferences: _CallbackPreferenceWriter(
          (_, choice) async => savedChoices.add(choice),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(
        tester.widget<TodayHubView>(find.byType(TodayHubView)).snapshot,
        same(today),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(loader.calls, 1);
      expect(ids, hasLength(1));
      expect(journey.today, same(today));
      expect(savedChoices, isEmpty);
    },
  );

  testWidgets(
    'Standard escape during unresolved permit read never saves protocol preference',
    (tester) async {
      final permits = _PendingPermits();
      final loader = _Loader(_today());
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: _Journey(),
          createId: () {
            const id = '11111111-1111-4111-8111-111111111111';
            ids.add(id);
            return id;
          },
          activePermits: permits,
          presentationPreferences: _CallbackPreferenceWriter(
            (_, choice) async => savedChoices.add(choice),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TodayHubLoading), findsOneWidget);
      await tester.tap(find.text('มาตรฐาน'));
      await tester.pump();
      expect(savedChoices, isEmpty);

      permits.complete(_permit());
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, isEmpty);
      expect(permits.calls, 1);
      expect(loader.calls, 1);
      expect(ids, hasLength(1));
    },
  );

  testWidgets(
    'confirmed no-permit opening stays nonparticipant until refresh adopts permit',
    (tester) async {
      final permits = _MutablePermits();
      final loader = _Loader(_today());
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: _Journey(),
          createId: () {
            final id = ids.isEmpty
                ? '11111111-1111-4111-8111-111111111111'
                : '22222222-2222-4222-8222-222222222222';
            ids.add(id);
            return id;
          },
          activePermits: permits,
          presentationPreferences: _CallbackPreferenceWriter(
            (_, choice) async => savedChoices.add(choice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();

      permits.permit = _permit();
      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
        TodayExperiencePresentation.standard,
      ]);
      expect(loader.calls, 1);
      expect(ids, hasLength(1));
      expect(permits.calls, 1);

      await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);
      expect(loader.calls, 2);
      expect(ids, hasLength(2));
      expect(permits.calls, 2);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
        TodayExperiencePresentation.standard,
      ]);
      expect(permits.calls, 2);
    },
  );

  testWidgets(
    'refresh activation fences an in-flight nonparticipant save drain',
    (tester) async {
      final permits = _MutablePermits();
      final loader = _Loader(_today());
      final ids = <String>[];
      final saver = _ControlledPreferenceSaver();
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: _Journey(),
          createId: () {
            final id = ids.isEmpty
                ? '11111111-1111-4111-8111-111111111111'
                : '22222222-2222-4222-8222-222222222222';
            ids.add(id);
            return id;
          },
          activePermits: permits,
          presentationPreferences: saver,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();
      expect(saver.started, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
      ]);

      permits.permit = _permit();
      await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      saver.failNext();
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubView), findsOneWidget);
      expect(saver.started, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
      ]);
      expect(saver.completed, isEmpty);
      expect(
        find.byKey(const ValueKey('today-presentation-save-failure')),
        findsNothing,
      );
      expect(loader.calls, 2);
      expect(ids, hasLength(2));
      expect(permits.calls, 2);
    },
  );

  testWidgets(
    'loads Today once and reuses the exact snapshot and UUID across switches',
    (tester) async {
      final today = _today();
      final loader = _Loader(today);
      final journey = _Journey();
      final ids = <String>[];
      final savedChoices = <TodayExperiencePresentation>[];
      await tester.pumpWidget(
        _app(
          loader: loader,
          journey: journey,
          createId: () {
            const id = '11111111-1111-4111-8111-111111111111';
            ids.add(id);
            return id;
          },
          presentationPreferences: _CallbackPreferenceWriter(
            (_, choice) async => savedChoices.add(choice),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(find.byType(TodayHubView), findsOneWidget);
      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(ids, hasLength(1));
      expect(identical(journey.today, today), isTrue);
      expect(find.byKey(const ValueKey('adventure-hub')), findsOneWidget);

      await tester.tap(find.text('มาตรฐาน'));
      await tester.pumpAndSettle();
      expect(loader.calls, 1);
      expect(find.byType(TodayHubView), findsOneWidget);
      expect(savedChoices, <TodayExperiencePresentation>[
        TodayExperiencePresentation.adventure,
        TodayExperiencePresentation.standard,
      ]);
    },
  );

  testWidgets('explicit refresh creates a new UUID and reloads Today', (
    tester,
  ) async {
    final loader = _Loader(_today());
    var idNumber = 0;
    await tester.pumpWidget(
      _app(
        loader: loader,
        journey: _Journey(),
        createId: () {
          idNumber += 1;
          return idNumber == 1
              ? '11111111-1111-4111-8111-111111111111'
              : '22222222-2222-4222-8222-222222222222';
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
    await tester.pumpAndSettle();
    expect(idNumber, 2);
    expect(loader.calls, 2);
  });

  testWidgets('rapid switches serialize saves and persist the last selection', (
    tester,
  ) async {
    final saver = _ControlledPreferenceSaver();
    await tester.pumpWidget(
      _app(
        loader: _Loader(_today()),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: saver,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('มาตรฐาน'));
    await tester.pump();

    expect(saver.started, <TodayExperiencePresentation>[
      TodayExperiencePresentation.adventure,
    ]);
    saver.completeNext();
    await tester.pump();
    expect(saver.started, <TodayExperiencePresentation>[
      TodayExperiencePresentation.adventure,
      TodayExperiencePresentation.standard,
    ]);
    saver.completeNext();
    await tester.pumpAndSettle();

    expect(saver.completed.last, TodayExperiencePresentation.standard);
    expect(find.byType(TodayHubView), findsOneWidget);
  });

  testWidgets('save failure is visible and retry recovers it', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _app(
        loader: _Loader(_today()),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: _CallbackPreferenceWriter((_, _) async {
          calls += 1;
          if (calls == 1) throw StateError('disk unavailable');
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsOneWidget,
    );

    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsNothing,
    );
  });

  testWidgets('explicit refresh clears a stale presentation-save failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        loader: _Loader(_today()),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: _CallbackPreferenceWriter((_, _) async {
          throw StateError('disk unavailable');
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsNothing,
    );
  });

  testWidgets('owner change fences an old pending presentation save', (
    tester,
  ) async {
    final oldSave = Completer<void>();
    final calls = <String>[];
    final writer = _CallbackPreferenceWriter((ownerId, presentation) {
      calls.add('$ownerId/${presentation.name}');
      return ownerId == 'owner:one' ? oldSave.future : Future<void>.value();
    });
    var owner = 'owner:one';

    await tester.pumpWidget(
      _app(
        ownerId: owner,
        loader: _Loader(_today(ownerId: owner)),
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
        presentationPreferences: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pump();

    owner = 'owner:two';
    await tester.pumpWidget(
      _app(
        ownerId: owner,
        loader: _Loader(_today(ownerId: owner)),
        journey: _Journey(),
        createId: () => '22222222-2222-4222-8222-222222222222',
        presentationPreferences: writer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();

    expect(calls, <String>['owner:one/adventure', 'owner:two/adventure']);
    oldSave.completeError(StateError('stale owner failure'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today-presentation-save-failure')),
      findsNothing,
    );
  });

  testWidgets('stale owner result is discarded without rendering a snapshot', (
    tester,
  ) async {
    final pending = Completer<TodayHubSnapshot>();
    final loader = _PendingLoader(pending.future);
    await tester.pumpWidget(
      _app(
        ownerId: 'owner:one',
        loader: loader,
        journey: _Journey(),
        createId: () => '11111111-1111-4111-8111-111111111111',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      _app(
        ownerId: 'owner:two',
        loader: loader,
        journey: _Journey(),
        createId: () => '22222222-2222-4222-8222-222222222222',
      ),
    );
    pending.complete(_today(ownerId: 'owner:one'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayHubView), findsNothing);
  });

  testWidgets('mission launch keeps the exact Today and entry decision', (
    tester,
  ) async {
    final today = _today();
    final mission = AdventureMissionRef(
      missionId: 'mission:one',
      ownerId: today.ownerId,
      nodeId: 'today-mission',
      kind: AdventureMissionKind.recommendation,
      sourceId: 'word:one',
      content: const [],
      reasonCode: 'due',
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
    );
    AdventureMissionLaunchContext? captured;
    var launches = 0;
    final account = _rewardAccount();
    await tester.pumpWidget(
      _app(
        loader: _Loader(today),
        journey: _Journey(mission: mission),
        createId: () => '11111111-1111-4111-8111-111111111111',
        rewardAccounts: _RewardAccounts(account),
        onStartMission: (launch) async {
          launches++;
          captured = launch;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ผจญภัย'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure-start-mission')));
    await tester.pumpAndSettle();

    expect(captured?.mission, same(mission));
    expect(captured?.today, same(today));
    expect(captured?.rewardOwnership, same(account));
    expect(captured!.isCurrent!(), isTrue);
    expect(
      captured?.entryDecision.destination,
      AdventureEntryDestination.adventure,
    );
    final oldCallback = tester
        .widget<AdventureHubScreen>(find.byType(AdventureHubScreen))
        .onStartMission;
    final oldContext = captured!;
    await tester.tap(find.byKey(const ValueKey('adventure-refresh')));
    await tester.pumpAndSettle();
    expect(oldContext.isCurrent!(), isFalse);
    await oldCallback(mission);
    expect(launches, 1);
  });

  testWidgets(
    'Adventure hub reads ownership and renders mission-ready reaction',
    (tester) async {
      final today = _today();
      final mission = AdventureMissionRef(
        missionId: 'mission:ready',
        ownerId: today.ownerId,
        nodeId: 'today-mission',
        kind: AdventureMissionKind.recommendation,
        sourceId: 'word:one',
        content: const [],
        reasonCode: 'due',
        sourceEvaluatedAtUtc: today.evaluatedAtUtc,
      );
      final rewards = _RewardAccounts(
        _rewardAccount(
          equippedBySlot: const <String, String>{'headgear': 'headgear_ipa'},
        ),
      );
      await tester.pumpWidget(
        _app(
          loader: _Loader(today),
          journey: _Journey(mission: mission),
          createId: () => '11111111-1111-4111-8111-111111111111',
          rewardAccounts: rewards,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ผจญภัย'));
      await tester.pumpAndSettle();

      expect(rewards.calls, 1);
      expect(rewards.ownerIds, <String>[today.ownerId]);
      expect(find.text('ภารกิจพร้อมแล้ว เริ่มเมื่อคุณพร้อมนะ'), findsOneWidget);
      expect(find.text('หมวก IPA'), findsOneWidget);
    },
  );
}

Widget _app({
  String ownerId = 'owner:one',
  required TodayHubSnapshotLoader loader,
  required AdventureJourneyReader journey,
  required String Function() createId,
  Future<void> Function(AdventureMissionLaunchContext)? onStartMission,
  AdventurePresentationPreferenceWriter? presentationPreferences,
  RewardAccountReader? rewardAccounts,
  ActivePresentationPermitReader activePermits =
      const NoActivePresentationPermitReader(),
  AdventureResearchRuntime? research,
  DateTime Function()? nowUtc,
  TodayHubActionDelegate? actions,
  ContextualTodayActionsFactory? contextualStandardActions,
}) {
  final catalog = PackagedAdventureWorldCatalog.forLocale('th');
  final entry = AdventureEntryUseCases(
    rollout: AdventureRolloutGate(
      features: const BuildFeatureRegistry.allEnabled(),
      requiredDependenciesReady: () => true,
      catalogReadiness: () => AdventureCatalogReadiness.ready,
    ),
    catalog: catalog,
    todayHubIdentity: loader,
    learningIdentity: Object(),
  );
  return MaterialApp(
    home: TodayExperienceHost(
      ownerId: ownerId,
      entry: entry,
      activePermits: activePermits,
      todayHub: loader,
      catalog: catalog,
      journey: journey,
      rewardAccounts: rewardAccounts ?? _RewardAccounts(_rewardAccount()),
      createEntryAttemptId: createId,
      nowUtc: nowUtc ?? () => _now,
      actions: actions ?? _Actions(),
      contextualStandardActions: contextualStandardActions,
      features: const BuildFeatureRegistry.allEnabled(),
      assessmentAvailable: false,
      presentationPreferences: presentationPreferences,
      research: research,
      onStartMission: onStartMission ?? (_) async {},
    ),
  );
}

final class _RewardAccounts implements RewardAccountReader {
  _RewardAccounts(this.account);

  final RewardAccount account;
  int calls = 0;
  final List<String> ownerIds = <String>[];

  @override
  Future<RewardAccount> loadForOwner(String ownerId) async {
    calls += 1;
    ownerIds.add(ownerId);
    return account;
  }
}

RewardAccount _rewardAccount({
  Map<String, String> equippedBySlot = const <String, String>{},
}) => RewardAccount(
  coinBalance: 0,
  catalogVersion: RewardCatalog.version,
  ownedItemIds: equippedBySlot.values.toSet(),
  equippedBySlot: equippedBySlot,
  transactionCount: 0,
);

final _now = DateTime.utc(2026, 9, 4, 8);

TodayHubSnapshot _today({String ownerId = 'owner:one'}) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: _now,
  sectionOrder: const <TodayHubSectionKind>[TodayHubSectionKind.recommendation],
  resumableSession: null,
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

final class _Loader implements TodayHubSnapshotLoader {
  _Loader(this.snapshot);
  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _PendingLoader implements TodayHubSnapshotLoader {
  _PendingLoader(this.pending);
  final Future<TodayHubSnapshot> pending;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() {
    calls += 1;
    return pending;
  }
}

final class _Permits implements ActivePresentationPermitReader {
  _Permits(this.permit);

  final ActivePresentationPermit? permit;

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async => permit;
}

final class _PendingPermits implements ActivePresentationPermitReader {
  final Completer<ActivePresentationPermit?> _pending =
      Completer<ActivePresentationPermit?>();
  int calls = 0;

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) {
    calls += 1;
    return _pending.future;
  }

  void complete(ActivePresentationPermit? permit) => _pending.complete(permit);
}

final class _MutablePermits implements ActivePresentationPermitReader {
  ActivePresentationPermit? permit;
  int calls = 0;

  @override
  Future<ActivePresentationPermit?> readActivePermit({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    calls += 1;
    return permit;
  }
}

final class _ControlledPreferenceSaver
    implements AdventurePresentationPreferenceWriter {
  final List<TodayExperiencePresentation> started =
      <TodayExperiencePresentation>[];
  final List<TodayExperiencePresentation> completed =
      <TodayExperiencePresentation>[];
  final List<Completer<void>> _pending = <Completer<void>>[];

  @override
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) async {
    started.add(presentation);
    final gate = Completer<void>();
    _pending.add(gate);
    await gate.future;
    completed.add(presentation);
  }

  void completeNext() => _pending.removeAt(0).complete();

  void failNext() =>
      _pending.removeAt(0).completeError(StateError('save unavailable'));
}

final class _CallbackPreferenceWriter
    implements AdventurePresentationPreferenceWriter {
  const _CallbackPreferenceWriter(this.callback);

  final Future<void> Function(
    String ownerId,
    TodayExperiencePresentation presentation,
  )
  callback;

  @override
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) => callback(ownerId, presentation);
}

final class _Journey implements AdventureJourneyReader {
  _Journey({this.mission});

  final AdventureMissionRef? mission;
  TodayHubSnapshot? today;

  @override
  Future<AdventureJourneySnapshot> compose(
    AdventureJourneyRequest request,
  ) async {
    today = request.today;
    return AdventureJourneySnapshot(
      ownerId: request.ownerId,
      evaluatedAtUtc: request.evaluatedAtUtc,
      sourceEvaluatedAtUtc: request.today.evaluatedAtUtc,
      catalogId: request.catalog.catalogId,
      catalogVersion: request.catalog.catalogVersion,
      catalogSchemaVersion: request.catalog.schemaVersion,
      freshness: AdventureSnapshotFreshness.current,
      dependencyStates:
          <AdventureJourneyAuthority, AdventureJourneyDependencyState>{
            for (final authority in AdventureJourneyAuthority.values)
              authority: AdventureJourneyDependencyState.ready,
          },
      nodes: const [],
      primaryMission: mission,
      inputFingerprintSha256: 'a' * 64,
    );
  }
}

final class _FailingJourney implements AdventureJourneyReader {
  @override
  Future<AdventureJourneySnapshot> compose(
    AdventureJourneyRequest request,
  ) async => throw StateError('Adventure projection unavailable');
}

ActivePresentationPermit _permit() => ActivePresentationPermit(
  permitId: 'permit:one',
  ownerId: 'owner:one',
  assignedPresentation: TodayExperiencePresentation.adventure,
  protocolId: 'protocol:one',
  protocolVersion: '1.0.0',
  assignmentId: 'assignment:one',
  expiresAtUtc: _now.add(const Duration(days: 1)),
);

final class _Actions implements TodayHubActionDelegate {
  @override
  Future<void> openPlanning({required String ownerId}) async {}
  @override
  Future<void> openHistory() async {}
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {}
  @override
  Future<void> resume(LearningSessionSummary session) async {}
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {}
  @override
  Future<void> startRecommendation(
    TodayHubRecommendation recommendation,
  ) async {}
}
