import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_entry_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_rollout_gate.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_pair_experience.dart';
import 'package:vocab_learning_app/features/adventure/presentation/today_experience_host.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/application/experiment_assignment_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_document.dart';
import 'package:vocab_learning_app/features/research/presentation/motivation_measurement_form.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';

import '../../../support/pair_measurement_fixture.dart';
import '../../../support/test_quest_use_cases.dart';

const _attempt = '11111111-1111-4111-8111-111111111111';

void main() {
  test(
    'PM7 synthetic permit rejects payload tampering and wrong issuer key',
    () async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      await f.initialize();
      final validator = f.research.participation.validator;
      expect(validator.signatures, isA<ResearchP256SignatureVerifier>());
      Future<ResearchPermitValidationResult> validate(
        ResearchParticipationPermit permit,
        ResearchParticipationPermitValidator authority,
      ) => authority.validate(
        permit,
        expectedOwnerId: PairMeasurementFixture.owner,
        expectedAssignmentId: f.permit.assignmentId,
        evaluatedAtUtc: f.now,
      );
      expect((await validate(f.permit, validator)).isActive, true);

      final payload =
          jsonDecode(f.permit.canonicalPayload()) as Map<String, dynamic>;
      payload['expiresAtUtc'] = f.permit.expiresAtUtc
          .add(const Duration(days: 1))
          .toIso8601String();
      final tampered = decodeResearchPermitDocument(
        jsonEncode({
          ...payload,
          // Recompute the digest so rejection specifically proves signature binding.
          'payloadSha256': sha256
              .convert(utf8.encode(jsonEncode(payload)))
              .toString(),
          'signature': f.permit.signature,
        }),
      );
      expect(
        (await validate(tampered, validator)).denialReason,
        ResearchPermitDenialReason.invalidSignature,
      );

      // A second explicitly synthetic P-256 key under the same issuer identifier.
      final wrongPublicKey = (ECCurve_secp256r1().G * BigInt.two)!
          .getEncoded(false)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final wrongIssuer = ResearchParticipationPermitValidator(
        protocolId: validator.protocolId,
        protocolVersion: validator.protocolVersion,
        signatures: ResearchP256SignatureVerifier(
          publicKeysSec1Hex: {f.permit.issuerKeyId: wrongPublicKey},
        ),
        receipts: validator.receipts,
      );
      expect(
        (await validate(f.permit, wrongIssuer)).denialReason,
        ResearchPermitDenialReason.invalidSignature,
      );
    },
  );

  for (final presentation in TodayExperiencePresentation.values) {
    for (final direction in PairDirection.values) {
      testWidgets(
        'real Today measurement Pair ${presentation.name} ${direction.name} '
        'keeps one denominator through restart repair rebuild and replay',
        (tester) async {
          final f = PairMeasurementFixture();
          final loseCloseAck =
              presentation == TodayExperiencePresentation.standard &&
              direction == PairDirection.enToTh;
          await _io(
            tester,
            () => f.initialize(
              presentation: presentation,
              loseCloseAckOnce: loseCloseAck,
            ),
          );
          addTearDown(f.database.close);
          final priorRecall = await _io(tester, f.recordPriorRecall);
          expect(
            priorRecall!.evidenceContext!.evidenceClass,
            EvidenceClass.independentRecall,
          );
          expect(
            priorRecall.evidenceContext!.rolloutMode,
            EvidencePolicyRolloutMode.enforced,
          );
          expect(priorRecall.evidenceContext!.engagementAllowed, true);
          expect(
            priorRecall.occurredAtUtc.isBefore(f.today.evaluatedAtUtc),
            true,
            reason:
                'historical recall cannot consume the later Today opportunity',
          );
          final priorLearning =
              jsonDecode((await _io(tester, () => _primaryEffects(f)))!)
                  as Map<String, dynamic>;
          for (final table in ['srs_states', 'points_ledger_entries']) {
            expect(
              priorLearning[table],
              isNotEmpty,
              reason:
                  'canonical prior recall must populate $table before Today',
            );
          }
          final key = GlobalKey<_MeasurementUiState>();
          await tester.pumpWidget(
            _app(
              f,
              _MeasurementUi(
                key: key,
                fixture: f,
                presentation: presentation,
                direction: direction,
              ),
            ),
          );
          await _settle(tester);
          expect(
            await _io(
              tester,
              () => f.research.currentPermit(PairMeasurementFixture.owner),
            ),
            isNotNull,
            reason: 'real P-256 signed synthetic permit must validate',
          );
          await _submitForm(tester, f, MotivationTimepoint.baseline);
          final ui = key.currentState!;
          expect(ui.loader.calls, 1);
          expect(ui.ids, 1);
          ui.rebuild();
          await _settle(tester);
          expect(ui.loader.calls, 1);
          expect(ui.ids, 1);
          await _launch(tester, presentation);
          if (presentation == TodayExperiencePresentation.standard) {
            expect(ui.standardToday, same(f.today));
            expect(ui.rewards.calls, 0);
          } else {
            expect(ui.launch!.today, same(f.today));
            expect(ui.launch!.mission.kind, AdventureMissionKind.review);
            expect(
              ui.launch!.mission.content,
              f.today.reviewWork.map((w) => w.identity).toList(),
            );
            expect(ui.launch!.entryDecision.entryAttemptId, _attempt);
          }
          await _tap(tester, 'pair-timer-seconds60');
          await _tap(tester, 'pair-start');
          await _readyBoard(tester);
          final first = _board(tester).state;
          final sessionId = first.plan.learningSessionId;
          expect(first.plan.sessionPurpose, PairSessionPurpose.learning);
          expect(first.plan.direction, direction);
          expect(first.plan.entryKind, PairSourceSurface.today);
          expect(
            first.plan.sourceSnapshotId,
            'today:${f.today.evaluatedAtUtc.millisecondsSinceEpoch}',
          );
          final accepted = await _io(
            tester,
            () =>
                f.real.getActiveSession(ownerId: PairMeasurementFixture.owner),
          );
          final configuration = accepted!.sessionConfiguration!;
          expect(configuration.protocolId, 'motivation');
          expect(configuration.mode, LessonMode.matching);
          expect(
            configuration.direction,
            direction == PairDirection.enToTh
                ? SessionDirection.forward
                : SessionDirection.reverse,
          );

          // Real in-session timeout restart retains the accepted session and
          // entry denominator; it does not create a second learning operation.
          f.now = f.now.add(const Duration(seconds: 61));
          f.monotonicMicros = 61000000;
          await tester.pump(const Duration(seconds: 1));
          await _settle(tester);
          await _tap(tester, 'pair-timer-action-restart');
          expect(_board(tester).state.plan.learningSessionId, sessionId);
          expect(_board(tester).state.roundOrdinal, 1);
          ui.rebuild();
          await _settle(tester);
          expect(f.controllers, 1);
          expect(ui.ids, 1);
          expect(ui.loader.calls, 1);
          await _wrongThenFinish(tester, allowCloseRetry: loseCloseAck);
          if (loseCloseAck) {
            expect(find.byKey(const ValueKey('pair-retry')), findsOneWidget);
            expect(find.byKey(const ValueKey('pair-result')), findsNothing);
            final committed = await _io(
              tester,
              () => (f.database.select(
                f.database.learningSessions,
              )..where((r) => r.id.equals(sessionId))).getSingle(),
            );
            expect(
              committed!.state,
              'completed',
              reason: 'close committed before its ACK was lost',
            );
            final pending = await _io(
              tester,
              () => f.real.read(
                ownerId: PairMeasurementFixture.owner,
                sessionId: sessionId,
              ),
            );
            expect(pending!.snapshot!.terminal!.presented, false);
            expect(f.closeFaults!.closeCalls, hasLength(1));
            expect(
              f.closeFaults!.closeCalls.single.ownerId,
              PairMeasurementFixture.owner,
            );
            expect(f.closeFaults!.closeCalls.single.sessionId, sessionId);
            final attemptsBeforeRetry = await _io(
              tester,
              () => f.database.select(f.database.answerAttempts).get(),
            );
            f.now = f.now.add(const Duration(minutes: 2));
            await _tap(tester, 'pair-retry');
            expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
            expect(f.closeFaults!.closeCalls, hasLength(2));
            expect(
              f.closeFaults!.closeCalls.toSet(),
              hasLength(1),
              reason: 'retry preserves exact owner/session/close timestamp',
            );
            expect(
              await _io(
                tester,
                () => f.database.select(f.database.answerAttempts).get(),
              ),
              attemptsBeforeRetry,
              reason: 'close retry must not duplicate answers',
            );
            expect(f.controllers, 1);
          }
          await _io(
            tester,
            () => f.research.useCases.reconcile(PairMeasurementFixture.owner),
          );
          await _settle(tester);
          final purpose = await _io(
            tester,
            () => f.real.read(
              ownerId: PairMeasurementFixture.owner,
              sessionId: sessionId,
            ),
          );
          expect(purpose!.snapshot!.terminal!.presented, true);
          expect(
            purpose.snapshot!.engine.attempts.any((a) => !a.isCorrect),
            true,
          );
          expect(
            purpose.snapshot!.engine.attempts.any(
              (a) => a.role != PairAttemptRole.firstOpportunity,
            ),
            true,
          );
          final beforeReplay = await _io(tester, () => _primaryEffects(f));
          final primaryBaseline =
              jsonDecode(beforeReplay!) as Map<String, dynamic>;
          expect(primaryBaseline['srs_states'], isNotEmpty);
          expect(
            primaryBaseline['srs_states'],
            priorLearning['srs_states'],
            reason:
                'Pair recognition must preserve the prior recall SRS baseline',
          );
          await _io(
            tester,
            () => _expectProtocolPoints(
              f,
              sessionId,
              priorLearning['points_ledger_entries'] as List,
              primaryBaseline['points_ledger_entries'] as List,
            ),
          );
          final opportunitiesBefore = await _io(
            tester,
            () => f.database.select(f.database.measurementOpportunities).get(),
          );
          expect(opportunitiesBefore, hasLength(1));
          expect(opportunitiesBefore!.single.entryAttemptId, _attempt);
          expect(opportunitiesBefore.single.learningSessionId, sessionId);

          // Actual result Replay action retains the same presentation adapter.
          // The baseline already contains real normal learning and research.
          await tester.ensureVisible(find.text('Practice Replay'));
          await tester.tap(find.text('Practice Replay'));
          await _settle(tester);
          final replayId = _board(tester).state.plan.learningSessionId;
          expect(replayId, isNot(sessionId));
          expect(
            _board(tester).state.plan.sessionPurpose,
            PairSessionPurpose.practiceReplay,
          );
          expect(_board(tester).state.plan.sourceSessionId, sessionId);
          await _finish(tester);
          await _io(
            tester,
            () => f.research.useCases.reconcile(PairMeasurementFixture.owner),
          );
          expect(await _io(tester, () => _primaryEffects(f)), beforeReplay);
          await _tap(tester, 'pair-result-return');
          await _submitForm(tester, f, MotivationTimepoint.post);

          final completed = await _io(
            tester,
            () => f.research.measurements.load(
              PairMeasurementFixture.owner,
              f.research.measurements.runIdFor(
                PairMeasurementFixture.owner,
                f.permit.id,
              ),
            ),
          );
          expect(completed!.state, MotivationMeasurementRunState.completed);
          expect(completed.responses.map((r) => r.itemId).toSet(), {
            'baseline',
            'post',
          });
          expect(completed.primaryAnalysisEligible, true);
          final stable = await _io(tester, () => _researchEffects(f));
          for (var i = 0; i < 3; i++) {
            await _io(
              tester,
              () => f.research.useCases.reconcile(PairMeasurementFixture.owner),
            );
          }
          ui.rebuild();
          await _settle(tester);
          expect(await _io(tester, () => _researchEffects(f)), stable);
          final events = await _io(
            tester,
            () => f.database.select(f.database.eventsV2).get(),
          );
          for (final type in [
            'TodayExperiencePresented',
            'TodayExperienceMissionStarted',
            'TodayExperienceMissionCompleted',
          ]) {
            expect(
              events!.where((e) => e.eventType == type),
              hasLength(1),
              reason: type,
            );
          }
          final row = await _io(
            tester,
            () => (f.database.select(
              f.database.learningSessions,
            )..where((r) => r.id.equals(sessionId))).getSingle(),
          );
          expect(
            row!.sessionConfigurationIdentity,
            configuration.contentIdentity,
          );
          expect(
            row.sessionConfigurationJson,
            configuration.stableSerialization,
          );
          expect(ui.ids, 1);
          expect(ui.loader.calls, 1);
          await _dispose(tester);
        },
      );
    }

    for (final authority in PairMeasurementAuthority.values.where(
      (value) => value != PairMeasurementAuthority.active,
    )) {
      testWidgets('fresh ${authority.name} ${presentation.name} completes '
          'real baseline Pair with zero research collection', (tester) async {
        final f = PairMeasurementFixture();
        await _io(
          tester,
          () => f.initialize(
            presentation: presentation,
            authority: authority,
            evidenceProtocolEnabled: false,
          ),
        );
        addTearDown(f.database.close);
        final withdrawalBaseline =
            authority == PairMeasurementAuthority.withdrawn
            ? await _withdrawalBaseline(tester, f)
            : null;
        expect(
          await _io(
            tester,
            () => f.rollout.resolve(
              ownerId: PairMeasurementFixture.owner,
              evidenceContext: null,
            ),
          ),
          EvidencePolicyRolloutMode.legacy,
        );
        await tester.pumpWidget(
          _app(
            f,
            _MeasurementUi(
              fixture: f,
              presentation: presentation,
              direction: PairDirection.enToTh,
              withoutResearch: authority == PairMeasurementAuthority.absent,
            ),
          ),
        );
        await _settle(tester);
        expect(find.byType(MotivationMeasurementForm), findsNothing);
        await _launch(tester, presentation);
        await _tap(tester, 'pair-start');
        final sessionId = _board(tester).state.plan.learningSessionId;
        await _finish(tester);
        final row = await _io(
          tester,
          () => (f.database.select(
            f.database.learningSessions,
          )..where((r) => r.id.equals(sessionId))).getSingle(),
        );
        expect(row!.state, 'completed');
        expect(
          SessionConfiguration.fromStableSerialization(
            row.sessionConfigurationJson!,
          ).protocolId,
          'protocol:local-standard',
        );
        expect(
          await _io(
            tester,
            () => f.database.select(f.database.answerAttempts).get(),
          ),
          hasLength(4),
        );
        await _tap(tester, 'pair-result-return');
        await _expectNoResearch(
          tester,
          f,
          enabledSync: authority != PairMeasurementAuthority.withdrawn,
          withdrawalBaseline: withdrawalBaseline,
        );
        await _dispose(tester);
      });
    }

    for (final authority in [
      PairMeasurementAuthority.expired,
      PairMeasurementAuthority.denied,
    ]) {
      testWidgets(
        '${authority.name} permit ${presentation.name} preserves active evidence '
        'configuration while research collection stays denied',
        (tester) async {
          final f = PairMeasurementFixture();
          await _io(
            tester,
            () =>
                f.initialize(presentation: presentation, authority: authority),
          );
          addTearDown(f.database.close);
          expect(
            await _io(
              tester,
              () => f.research.currentPermit(PairMeasurementFixture.owner),
            ),
            isNull,
          );
          // Evidence assignment/consent and presentation participation are distinct
          // authorities: unavailable Motivation authority must not rewrite pins.
          expect(
            (await _io(
              tester,
              () => f.protocols.resolveForOwner(PairMeasurementFixture.owner),
            ))!.protocolId,
            'motivation',
          );
          await tester.pumpWidget(
            _app(
              f,
              _MeasurementUi(
                fixture: f,
                presentation: presentation,
                direction: PairDirection.thToEn,
              ),
            ),
          );
          await _settle(tester);
          await _launch(tester, presentation);
          await _tap(tester, 'pair-start');
          final accepted = await _io(
            tester,
            () => f.database.select(f.database.learningSessions).getSingle(),
          );
          expect(
            SessionConfiguration.fromStableSerialization(
              accepted!.sessionConfigurationJson!,
            ).protocolId,
            'motivation',
          );
          await _finish(tester);
          final completed = await _io(
            tester,
            () => f.database.select(f.database.learningSessions).getSingle(),
          );
          expect(completed!.state, 'completed');
          expect(
            completed.sessionConfigurationJson,
            accepted.sessionConfigurationJson,
          );
          final attempts = await _io(
            tester,
            () => f.database.select(f.database.answerAttempts).get(),
          );
          expect(attempts, hasLength(4));
          for (final attempt in attempts!) {
            final evidence = EvidenceContext.fromJson(
              (jsonDecode(attempt.evidenceContextJson) as Map)
                  .cast<String, Object?>(),
            );
            _expectProtocolEvidence(f, evidence);
            expect(evidence.evidenceClass, EvidenceClass.recognition);
          }
          await _tap(tester, 'pair-result-return');
          await _expectNoResearch(tester, f, enabledSync: true);
          await _dispose(tester);
        },
      );
    }
  }
}

PairBoardModel _board(WidgetTester tester) =>
    tester.widget<PairBoardView>(find.byType(PairBoardView)).model;

Future<void> _readyBoard(WidgetTester tester) async {
  for (
    var i = 0;
    i < 200 && find.byType(PairBoardView).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(PairBoardView), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  // Drift work started by a widget belongs to the fake-async zone. Give real
  // IO a turn and then pump that zone before asking whether frames settled.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Do not await a real-zone transaction behind unfinished fake-zone UI work.
/// Start the canonical query in the widget zone, and drive both schedulers
/// until it completes. Errors remain test failures; no persistence is mocked.
Future<T?> _io<T>(WidgetTester tester, Future<T> Function() action) async {
  var done = false;
  T? value;
  Object? failure;
  StackTrace? failureStack;
  action().then<void>(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      done = true;
    },
  );
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done) {
    fail('PM7 canonical IO did not complete within bounded scheduler pumps');
  }
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value;
}

Future<void> _launch(
  WidgetTester tester,
  TodayExperiencePresentation presentation,
) async {
  if (presentation == TodayExperiencePresentation.standard) {
    expect(find.byType(TodayHubView), findsOneWidget);
    // The real review action follows four review cards in a lazy ListView.
    // Build it by scrolling that actual view before ensureVisible/tap.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('today-hub-open-review')),
      250,
      scrollable: find.descendant(
        of: find.byType(TodayHubView),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 12,
    );
    await _settle(tester);
  } else {
    final hub = find.byKey(const ValueKey('adventure-hub'));
    expect(hub, findsOneWidget);
    // The real mission sheet follows the full map in a lazy vertical list.
    // Select that list explicitly because the hub also has horizontal scrollers.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adventure-start-mission')),
      250,
      scrollable: find.descendant(
        of: hub,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
      maxScrolls: 24,
    );
    await _settle(tester);
  }
  await _tap(
    tester,
    presentation == TodayExperiencePresentation.standard
        ? 'today-hub-open-review'
        : 'adventure-start-mission',
  );
}

Future<void> _submitForm(
  WidgetTester tester,
  PairMeasurementFixture f,
  MotivationTimepoint timepoint,
) async {
  for (
    var i = 0;
    i < 200 && find.byType(MotivationMeasurementForm).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    tester
        .widget<MotivationMeasurementForm>(
          find.byType(MotivationMeasurementForm),
        )
        .timepoint,
    timepoint,
  );
  f.now = f.now.add(const Duration(milliseconds: 1));
  await _tap(tester, '${timepoint.name}-high');
  await _tap(tester, 'research-measurement-complete');
  expect(find.byType(MotivationMeasurementForm), findsNothing);
}

Future<void> _wrongThenFinish(
  WidgetTester tester, {
  bool allowCloseRetry = false,
}) async {
  final ids = _board(
    tester,
  ).state.plan.orderedLexicalItems.map((i) => i.wordId).toList();
  await _tap(tester, 'pair-tile:prompt:${ids[0]}');
  await _tap(tester, 'pair-tile:target:${ids[1]}');
  expect(find.byKey(const ValueKey('pair-feedback:wrong')), findsOneWidget);
  await _finish(tester, allowCloseRetry: allowCloseRetry);
}

Future<void> _finish(
  WidgetTester tester, {
  bool allowCloseRetry = false,
}) async {
  for (var step = 0; step < 12; step++) {
    if (find.byKey(const ValueKey('pair-result')).evaluate().isNotEmpty) return;
    if (allowCloseRetry &&
        find.byKey(const ValueKey('pair-retry')).evaluate().isNotEmpty) {
      return;
    }
    final state = _board(tester).state;
    final playable = state.plan.orderedLexicalItems
        .map((i) => i.wordId)
        .where(
          (id) =>
              !state.matchedWordIds.contains(id) &&
              state.repairFor(id)?.status != PairRepairStatus.waiting &&
              state.repairFor(id)?.status != PairRepairStatus.guidedRequired,
        )
        .toList();
    if (playable.isNotEmpty) {
      await _tap(tester, 'pair-tile:prompt:${playable.first}');
      await _tap(tester, 'pair-tile:target:${playable.first}');
    } else {
      final ticket = state.repairTickets.firstWhere(
        (r) => r.status == PairRepairStatus.guidedRequired,
      );
      await _tap(tester, 'pair-confirm-guided:${ticket.wordId}');
    }
  }
  fail('Bounded real Pair UI did not reach canonical result');
}

Future<String> _researchEffects(PairMeasurementFixture f) async => jsonEncode({
  for (final table in [
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
  ])
    table:
        (await f.database.customSelect('SELECT * FROM $table ORDER BY 1').get())
            .map((r) => r.data)
            .toList(),
  'events': (await f.database.select(f.database.eventsV2).get())
      .where((e) => ResearchSyncContract.eventTypes.contains(e.eventType))
      .map((e) => [e.eventId, e.payloadJson])
      .toList(),
});

void _expectProtocolEvidence(
  PairMeasurementFixture f,
  EvidenceContext evidence,
) {
  expect(evidence.rolloutMode, EvidencePolicyRolloutMode.enforced);
  expect(evidence.classificationSource, EvidenceClassificationSource.declared);
  expect(evidence.protocolId, 'motivation');
  expect(evidence.protocolVersion, '1');
  expect(evidence.experimentId, 'motivation');
  expect(evidence.experimentVersion, 1);
  expect(evidence.assignmentId, f.permit.assignmentId);
  expect(evidence.cohort, f.permit.assignedTreatment.name);
  expect(evidence.researchConsentVersion, 1);
  expect(evidence.engagementAllowed, true);
  // Pair answers are learning evidence, not responses to a Motivation form.
  expect(evidence.instrumentId, isNull);
  expect(evidence.instrumentVersion, isNull);
  expect(evidence.formId, isNull);
  expect(evidence.formVersion, isNull);
}

Future<void> _expectProtocolPoints(
  PairMeasurementFixture f,
  String sessionId,
  List prior,
  List actual,
) async {
  final attempts = await (f.database.select(
    f.database.answerAttempts,
  )..where((row) => row.sessionId.equals(sessionId))).get();
  final expected = <Object?>[...prior];
  final receipts = DriftLearningEventStore(f.database);
  var eligibleCorrect = 0;
  for (final attempt in attempts) {
    final evidence = EvidenceContext.fromJson(
      (jsonDecode(attempt.evidenceContextJson) as Map).cast<String, Object?>(),
    );
    _expectProtocolEvidence(f, evidence);
    expect(
      evidence.evidenceClass,
      isIn([EvidenceClass.recognition, EvidenceClass.guidedPractice]),
    );
    final isRecognition = evidence.evidenceClass == EvidenceClass.recognition;
    final source = await receipts.readValidatedSourceForAttempt(
      attempt: attempt,
    );
    expect(source, isNotNull);
    // Require the already committed canonical decision receipt. This read
    // cannot create a missing receipt to make the assertion pass.
    final decision = await receipts.requireExistingDecisionSetForAttempt(
      attempt: attempt,
      sourceEvent: source!,
    );
    expect(decision.sourceEvidenceId, attempt.id);
    expect(
      decision.decisionFor(LearningProjection.xp).effectiveDecision,
      isRecognition
          ? ProjectionDisposition.protocolControlled
          : ProjectionDisposition.deny,
    );
    expect(decision.allows(LearningProjection.xp), isRecognition);
    expect(decision.allows(LearningProjection.masterySrs), false);
    if (!attempt.isCorrect || !isRecognition) continue;
    eligibleCorrect++;
    expected.add(<String, Object?>{
      'id': 'points:${attempt.id}',
      'owner_id': attempt.ownerId,
      'idempotency_key': 'correct-answer:${attempt.id}',
      'entry_type': 'quizCorrect',
      'amount': 1,
      'source_event_id': attempt.id,
      'occurred_at_utc_ms': attempt.occurredAtUtcMs,
    });
  }
  expect(eligibleCorrect, greaterThan(0));
  expect(
    actual,
    unorderedEquals(expected),
    reason:
        'Preserve every prior row and grant exactly one canonical point '
        'per protocol-eligible correct recognition; wrong/guided answers grant none',
  );
}

Future<String> _primaryEffects(PairMeasurementFixture f) async => jsonEncode({
  for (final table in [
    'srs_states',
    'points_ledger_entries',
    'achievement_unlocks',
    'reward_transactions',
    'owned_reward_items',
    'equipped_reward_items',
    'quest_instances',
    'quest_objective_progress',
    'streak_states',
    'learning_day_log',
    'learning_time_segments',
    'session_configurations',
    'assessment_runs',
  ])
    table:
        (await f.database.customSelect('SELECT * FROM $table ORDER BY 1').get())
            .map((r) => r.data)
            .toList(),
  'research': await _researchEffects(f),
});

Future<void> _expectNoResearch(
  WidgetTester tester,
  PairMeasurementFixture f, {
  bool enabledSync = false,
  String? withdrawalBaseline,
}) async {
  await _io(
    tester,
    () => f.research.useCases.reconcile(PairMeasurementFixture.owner),
  );
  for (final table in [
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
  ]) {
    expect(
      await _io(
        tester,
        () => f.database.customSelect('SELECT * FROM $table').get(),
      ),
      isEmpty,
      reason: table,
    );
  }
  final events = await _io(
    tester,
    () => f.database.select(f.database.eventsV2).get(),
  );
  expect(
    events!.where((e) => ResearchSyncContract.eventTypes.contains(e.eventType)),
    isEmpty,
  );
  // Default-off real Sync store is the product control; no network transport
  // is mounted in this synthetic local UI fixture.
  expect(
    await _io(
      tester,
      () => DriftSyncStore(f.database).enqueueResearchForOwner(
        ownerId: PairMeasurementFixture.owner,
        nowUtc: f.now,
      ),
    ),
    0,
  );
  if (enabledSync) {
    // Exercise the actual local enqueue/claim boundary with synthetic identity
    // and real authorization; zero claimed research mutations means no upload
    // request is available. No network service or production account is used.
    await _io(tester, () async {
      const uid = 'pm7-synthetic-sync-uid';
      await (f.database.update(f.database.localOwners)
            ..where((r) => r.id.equals(PairMeasurementFixture.owner)))
          .write(const LocalOwnersCompanion(firebaseUid: Value(uid)));
      final authorizer = DriftResearchSyncAuthorizer(
        database: f.database,
        study: f.base.study,
        validator: f.research.participation.validator,
        nowUtc: () => f.now,
      );
      final store = DriftSyncStore(
        f.database,
        payloadRollout: const SyncPayloadRollout.answerAttemptV2(),
        researchMeasurementRollout:
            const ResearchMeasurementSyncRollout.localEmulatorV1(
              deployedRulesRevision: researchMeasurementV1RulesRevision,
            ),
        researchAuthorizer: authorizer.authorize,
      );
      expect(
        await store.enqueueResearchForOwner(
          ownerId: PairMeasurementFixture.owner,
          nowUtc: f.now,
        ),
        0,
      );
      final gate = DriftOwnerOperationGate(f.database);
      const token = 'pm7-synthetic-claim-gate';
      expect(
        await gate.tryAcquire(
          token: token,
          nowUtc: f.now,
          leaseDuration: const Duration(minutes: 2),
        ),
        true,
      );
      try {
        final claims = await store.claimPending(
          ownerId: PairMeasurementFixture.owner,
          firebaseUid: uid,
          limit: 50,
          leaseToken: 'pm7-synthetic-claim',
          ownerGateToken: token,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: f.now,
        );
        expect(
          claims.where(
            (c) => ResearchSyncContract.collections.contains(
              c.mutation.collection,
            ),
          ),
          isEmpty,
        );
      } finally {
        await gate.release(token: token);
      }
    });
  }
  final outbox = await _io(
    tester,
    () => f.database.select(f.database.outboxOperations).get(),
  );
  final researchOutbox = outbox!
      .where(
        (o) =>
            ResearchSyncContract.collectionForEntityType(o.entityType) != null,
      )
      .toList();
  if (withdrawalBaseline == null) {
    expect(researchOutbox, isEmpty);
  } else {
    // A pre-existing owner denial is legitimate sync work. Pair must neither
    // duplicate it nor attach learning/measurement content to that operation.
    expect(
      await _io(
        tester,
        () => _enabledStore(f).enqueueResearchForOwner(
          ownerId: PairMeasurementFixture.owner,
          nowUtc: f.now,
        ),
      ),
      0,
    );
    expect(
      jsonEncode(researchOutbox.map((r) => r.toJson()).toList()),
      withdrawalBaseline,
    );
  }
  expect(find.byType(MotivationMeasurementForm), findsNothing);
}

DriftSyncStore _enabledStore(PairMeasurementFixture f) => DriftSyncStore(
  f.database,
  researchNowUtc: () => f.now,
  researchMeasurementRollout:
      const ResearchMeasurementSyncRollout.localEmulatorV1(
        deployedRulesRevision: researchMeasurementV1RulesRevision,
      ),
  researchAuthorizer: DriftResearchSyncAuthorizer(
    database: f.database,
    study: f.base.study,
    validator: f.research.participation.validator,
    nowUtc: () => f.now,
  ).authorize,
);

Future<String?> _withdrawalBaseline(
  WidgetTester tester,
  PairMeasurementFixture f,
) => _io(tester, () async {
  const uid = 'pm7-synthetic-sync-uid';
  await (f.database.update(f.database.localOwners)
        ..where((r) => r.id.equals(PairMeasurementFixture.owner)))
      .write(const LocalOwnersCompanion(firebaseUid: Value(uid)));
  final store = _enabledStore(f);
  final beforeEnqueue =
      await (f.database.select(f.database.outboxOperations)..where(
            (row) =>
                row.ownerId.equals(PairMeasurementFixture.owner) &
                row.entityType.equals('researchWithdrawal'),
          ))
          .get();
  expect(beforeEnqueue, hasLength(1));
  expect(beforeEnqueue.single.state, 'pending');
  expect(
    beforeEnqueue.single.operationId,
    ResearchSyncContract.operationIdFor(
      collection: SyncCollection.researchWithdrawals,
      entityId: f.permit.id,
      payload: {
        'permitId': f.permit.id,
        'ownerId': PairMeasurementFixture.owner,
      },
      revision: 1,
    ),
  );
  expect(
    await store.enqueueResearchForOwner(
      ownerId: PairMeasurementFixture.owner,
      nowUtc: f.now,
    ),
    0,
  );
  expect(
    await (f.database.select(f.database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(PairMeasurementFixture.owner) &
              row.entityType.equals('researchWithdrawal'),
        ))
        .get(),
    beforeEnqueue,
    reason:
        'Enqueue must preserve the exact denial already committed at withdrawal',
  );
  const token = 'pm7-withdrawal-baseline-gate';
  final gate = DriftOwnerOperationGate(f.database);
  expect(
    await gate.tryAcquire(
      token: token,
      nowUtc: f.now,
      leaseDuration: const Duration(minutes: 2),
    ),
    true,
  );
  try {
    final claims = await store.claimPending(
      ownerId: PairMeasurementFixture.owner,
      firebaseUid: uid,
      limit: 50,
      leaseToken: 'pm7-withdrawal-baseline-claim',
      ownerGateToken: token,
      leaseDuration: const Duration(minutes: 1),
      nowUtc: f.now,
    );
    final denial = claims
        .where(
          (c) => c.mutation.collection == SyncCollection.researchWithdrawals,
        )
        .single;
    expect(denial.mutation.payload, {
      'ownerId': PairMeasurementFixture.owner,
      'permitId': f.permit.id,
    });
    expect(
      claims.where(
        (c) => ResearchSyncContract.collections.contains(c.mutation.collection),
      ),
      isEmpty,
    );
  } finally {
    await gate.release(token: token);
  }
  return jsonEncode(
    (await f.database.select(f.database.outboxOperations).get())
        .where(
          (o) =>
              ResearchSyncContract.collectionForEntityType(o.entityType) !=
              null,
        )
        .map((r) => r.toJson())
        .toList(),
  );
});

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

Widget _app(PairMeasurementFixture f, Widget home) {
  final dependencies = AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    quest: testQuestUseCases(),
    database: f.database,
    features: f.runtime.features!,
    learning: f.learning,
    lessonModes: f.runtime.registry,
    createLessonController: f.runtime.createController,
    sessionConfigurationProtocols: f.protocols,
    // Same canonical Learning authority as the real Pair host. Its default
    // Legacy evidence composition remains independent from measurement pins.
    currentActivityEvidence: CurrentActivityEvidenceAdapter(
      learning: f.learning,
    ),
    experiments: f.rollout.experimentRegistry,
    consents: f.rollout.consentRegistry,
    experimentAssignments: ExperimentAssignmentUseCases(
      repository: DriftExperimentAssignmentRepository(f.database),
      consentRegistry: f.rollout.consentRegistry,
    ),
    assignedLearningEventContext:
        f.rollout.currentActivityResearchStateProvider!,
    evidencePolicyRolloutModeProvider: f.rollout,
  );
  expect(dependencies.hasComposedDependencyFor(Feature.quiz), true);
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(home: home),
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'pm7-synthetic-guest');
}

final class _MeasurementUi extends StatefulWidget {
  const _MeasurementUi({
    super.key,
    required this.fixture,
    required this.presentation,
    required this.direction,
    this.withoutResearch = false,
  });
  final PairMeasurementFixture fixture;
  final TodayExperiencePresentation presentation;
  final PairDirection direction;
  final bool withoutResearch;
  @override
  State<_MeasurementUi> createState() => _MeasurementUiState();
}

final class _MeasurementUiState extends State<_MeasurementUi> {
  late final f = widget.fixture;
  late final loader = _Loader(f.today);
  late final catalog = PackagedAdventureWorldCatalog.forLocale('th');
  final rewards = _Rewards();
  final fallback = _Actions();
  final journey = AdventureJourneyUseCases();
  late final entry = AdventureEntryUseCases(
    rollout: AdventureRolloutGate(
      features: const BuildFeatureRegistry.allEnabled(),
      requiredDependenciesReady: () => true,
      catalogReadiness: () => AdventureCatalogReadiness.ready,
    ),
    catalog: catalog,
    todayHubIdentity: loader,
    learningIdentity: f.learning,
    preferences: _Preference(widget.presentation),
  );
  late final pairActions = AdventurePairTodayActions(
    runtime: f.runtime,
    allowlist: f.allowlist,
    preferences: f.preferences,
    direction: widget.direction,
    openExperience: _open,
    onExit: _exit,
  );
  AdventureMissionLaunchContext? launch;
  TodayHubSnapshot? standardToday;
  int ids = 0;
  void rebuild() => setState(() {});
  void _exit() => Navigator.of(context).pop();
  Future<void> _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) => TodayExperienceHost(
    ownerId: PairMeasurementFixture.owner,
    entry: entry,
    activePermits: widget.withoutResearch
        ? const NoActivePresentationPermitReader()
        : f.research.participation,
    todayHub: loader,
    catalog: catalog,
    journey: journey,
    rewardAccounts: rewards,
    createEntryAttemptId: () {
      ids++;
      return _attempt;
    },
    nowUtc: () => f.now,
    actions: fallback,
    features: const BuildFeatureRegistry.allEnabled(),
    assessmentAvailable: false,
    research: widget.withoutResearch ? null : f.research,
    contextualStandardActions:
        ({
          required today,
          required entryDecision,
          required fallback,
          required isCurrent,
        }) {
          standardToday = today;
          return pairActions.contextualize(
            today: today,
            entryDecision: entryDecision,
            fallback: fallback,
            isCurrent: isCurrent,
          );
        },
    onStartMission: (captured) async {
      launch = captured;
      await _open(
        AdventurePairExperience(
          launchContext: captured,
          runtime: f.runtime,
          allowlist: f.allowlist,
          preferences: f.preferences,
          direction: widget.direction,
          onExit: _exit,
        ),
      );
    },
  );
}

final class _Loader implements TodayHubSnapshotLoader {
  _Loader(this.today);
  final TodayHubSnapshot today;
  int calls = 0;
  @override
  Future<TodayHubSnapshot> load() async {
    calls++;
    return today;
  }
}

final class _Preference implements AdventurePresentationPreferenceReader {
  _Preference(this.presentation);
  final TodayExperiencePresentation presentation;
  @override
  Future<TodayExperiencePresentation?> readForOwner(String ownerId) async =>
      presentation;
}

final class _Rewards implements RewardAccountReader {
  int calls = 0;
  @override
  Future<RewardAccount> loadForOwner(String ownerId) async {
    calls++;
    return RewardAccount(
      coinBalance: 0,
      catalogVersion: RewardCatalog.version,
      ownedItemIds: const {},
      equippedBySlot: const {},
      transactionCount: 0,
    );
  }
}

final class _Actions implements TodayHubActionDelegate {
  @override
  Future<void> openPlanning({required String ownerId}) async {}
  @override
  Future<void> openHistory() async {}
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {
    throw StateError(
      'Eligible captured review must use the internal Pair action',
    );
  }

  @override
  Future<void> resume(LearningSessionSummary session) async {}
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {}
  @override
  Future<void> startRecommendation(
    TodayHubRecommendation recommendation,
  ) async {}
}
