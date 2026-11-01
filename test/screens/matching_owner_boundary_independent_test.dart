import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/matching_quiz_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/configured_quiz_harness.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'independent wrong expected owner denies an issued board before its real writer',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, () async {
            await owners.close();
            await fixture.harness.close();
          });
      addTearDown(
        () => motivationPresentationDeadline(
          tester,
          'wrong-owner/teardown',
          close,
        ),
      );
      try {
        final before = await motivationPresentationIo(
          tester,
          fixture.harness.snapshot,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MatchingQuizScreen(
              matching: fixture.matching,
              expectedOwnerId: configuredOtherOwnerId,
              ownerChanges: owners.stream,
              preparedPlan: fixture.plan,
            ),
          ),
        );
        owners.add(configuredOtherOwnerId);
        await _settled(tester);
        expect(
          await motivationPresentationIo(
            tester,
            () => fixture.harness.count('learning_sessions'),
          ),
          0,
        );
        expect(
          await motivationPresentationIo(tester, fixture.harness.snapshot),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await motivationPresentationDeadline(
          tester,
          'wrong-owner/finally',
          close,
        );
      }
    },
  );

  testWidgets(
    'independent injected service for another actual database cannot bypass app composition',
    (tester) async {
      final installed = (await tester.runAsync(_Fixture.open))!;
      final injected = (await tester.runAsync(_Fixture.open))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, () async {
            await owners.close();
            await injected.harness.close();
            await installed.harness.close();
          });
      addTearDown(
        () => motivationPresentationDeadline(
          tester,
          'foreign-database/teardown',
          close,
        ),
      );
      try {
        final installedBefore = await motivationPresentationIo(
          tester,
          installed.harness.snapshot,
        );
        final injectedBefore = await motivationPresentationIo(
          tester,
          injected.harness.snapshot,
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: const AppRuntimeStatus(
                localData: RuntimeAvailability.ready,
                firebase: RuntimeAvailability.unavailable,
                supabase: RuntimeAvailability.unavailable,
                backends: RuntimeAvailability.unavailable,
              ),
              config: null,
              guestSessionService: _NoGuest(),
              database: installed.harness.database,
              matching: installed.matching,
            ),
            child: MaterialApp(
              home: MatchingQuizScreen(
                matching: injected.matching,
                expectedOwnerId: configuredOwnerId,
                ownerChanges: owners.stream,
                preparedPlan: injected.plan,
              ),
            ),
          ),
        );
        owners.add(configuredOwnerId);
        await _settled(tester);
        expect(
          await motivationPresentationIo(
            tester,
            () => injected.harness.count('learning_sessions'),
          ),
          0,
        );
        expect(
          await motivationPresentationIo(tester, injected.harness.snapshot),
          injectedBefore,
        );
        expect(
          await motivationPresentationIo(tester, installed.harness.snapshot),
          installedBefore,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await motivationPresentationDeadline(
          tester,
          'foreign-database/finally',
          close,
        );
      }
    },
  );
}

Future<void> _settled(WidgetTester tester) async {
  for (var frame = 0; frame < 120; frame++) {
    await motivationPresentationDeadline(
      tester,
      'matching-boundary/frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Actual matching boundary did not settle within bounded frames');
}

final class _Fixture {
  const _Fixture(this.harness, this.matching, this.plan);
  final ConfiguredQuizHarness harness;
  final MatchingUseCases matching;
  final MatchingPlan plan;
  static Future<_Fixture> open() async {
    final harness = await ConfiguredQuizHarness.open();
    final matching = MatchingUseCases(
      repository: DriftMatchingRepository(
        DriftLearningRepository(
          harness.database,
          ownerWrites: harness.ownerWrites,
        ),
      ),
      generateId: () => 'synthetic-independent-owner-boundary',
      nowUtc: () => harness.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-independent',
        buildId: 'synthetic-independent-owner-boundary',
      ),
    );
    final plan = await matching.prepare(
      expectedOwnerId: configuredOwnerId,
      categoryId: configuredCategoryId,
      stillCurrent: () => true,
    );
    return _Fixture(harness, matching, plan!);
  }
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic boundary must not authenticate');
}
