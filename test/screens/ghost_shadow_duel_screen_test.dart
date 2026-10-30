import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/ghost_shadow_duel_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('fresh account shows zero evidence and no sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GhostShadowDuelScreen(
          progressLoader: () async => _empty,
          learning: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.text('perseverance'), findsNothing);
  });

  group('Ghost durable intent', () {
    late _Fixture fixture;
    setUp(() async {
      fixture = _Fixture();
      await fixture.seed();
    });
    tearDown(() async {
      for (final gate in [
        fixture.repository.answerGate,
        fixture.repository.finishGate,
        fixture.repository.sessionGate,
      ]) {
        if (gate != null && !gate.isCompleted) gate.complete();
      }
      await fixture.db.close();
    });

    for (final afterCommit in [false, true]) {
      testWidgets(
        'answer retry preserves full evidence afterCommit=$afterCommit',
        (tester) async {
          fixture.repository.failAnswer = true;
          fixture.repository.afterCommit = afterCommit;
          await _open(tester, fixture);
          expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
          final ghostHealth = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
          expect(ghostHealth.semanticsLabel, 'พลังของสถิติเดิม 100 จาก 100');
          await tester.enterText(find.byType(TextField), 'apple');
          await tester.tap(find.text('ตอบ'));
          await _until(tester, find.text('ลองบันทึกคำตอบอีกครั้ง'));
          final first = fixture.repository.commands.single;
          expect(first.evidenceContext.evidenceClass.name, 'recreational');
          expect(
            first.evidenceContext.contentRevision,
            'local-vocabulary-v1:1',
          );
          expect(
            find.textContaining('พลังผู้เรียน 100 · พลังสถิติเดิม 100'),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).enabled,
            isFalse,
          );
          tester.widget<TextField>(find.byType(TextField)).controller!.text =
              'contradictory';
          await tester.pump(const Duration(seconds: 20));
          await tester.tap(find.text('ลองบันทึกคำตอบอีกครั้ง'));
          await _until(tester, find.text('จบรอบและบันทึกผล'));
          expect(_evidence(fixture.repository.commands.last), _evidence(first));
          expect(
            find.textContaining('พลังผู้เรียน 100 · พลังสถิติเดิม 75'),
            findsOneWidget,
          );
          expect(
            await fixture.db.select(fixture.db.answerAttempts).get(),
            hasLength(1),
          );
          expect(
            await fixture.db.select(fixture.db.pointsLedgerEntries).get(),
            hasLength(1),
          );
          final coins = await fixture.db
              .select(fixture.db.rewardTransactions)
              .get();
          expect(coins, hasLength(1));
          expect(coins.single.amount, 1);
          expect(
            await fixture.db.select(fixture.db.outboxOperations).get(),
            hasLength(2),
          );
          expect(fixture.repository.finishCalls, 0);
          expect(
            (await fixture.db.select(fixture.db.learningSessions).getSingle())
                .state,
            'active',
          );
        },
      );

      testWidgets('Finish retries only Finish afterCommit=$afterCommit', (
        tester,
      ) async {
        fixture.repository.failFinish = true;
        fixture.repository.afterCommit = afterCommit;
        await _open(tester, fixture);
        await tester.enterText(find.byType(TextField), 'wrong');
        await tester.tap(find.text('ตอบ'));
        await _until(tester, find.text('จบรอบและบันทึกผล'));
        await tester.tap(find.text('จบรอบและบันทึกผล'));
        await _until(tester, find.text('ลองบันทึกผลรอบอีกครั้ง'));
        expect(find.text('บันทึกผลรอบนี้แล้ว'), findsNothing);
        await tester.tap(find.text('ลองบันทึกผลรอบอีกครั้ง'));
        await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
        expect(fixture.repository.commands, hasLength(1));
        expect(fixture.repository.finishCalls, 2);
        expect(find.text('ตอบถูก 0 · ตอบผิด 1 · รวม 1 คำตอบ'), findsOneWidget);
        expect(
          (await fixture.db.select(fixture.db.learningSessions).getSingle())
              .state,
          'completed',
        );
        expect(
          await fixture.db.select(fixture.db.rewardTransactions).get(),
          isEmpty,
        );
      });
    }

    testWidgets('dispose does not manufacture completion or achievements', (
      tester,
    ) async {
      await _open(tester, fixture);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(fixture.repository.finishCalls, 0);
      expect(
        (await fixture.db.select(fixture.db.learningSessions).getSingle())
            .state,
        'active',
      );
      expect(
        await fixture.db.select(fixture.db.achievementUnlocks).get(),
        isEmpty,
      );
    });

    testWidgets('double submit and Finish wait for acknowledgements', (
      tester,
    ) async {
      final answerGate = fixture.repository.answerGate = Completer<void>();
      await _open(tester, fixture);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.tap(find.text('ตอบ'));
      await tester.tap(find.text('ตอบ'));
      await _waitFor(tester, () => fixture.repository.commands.length == 1);
      expect(find.text('บันทึกคำตอบแล้ว'), findsNothing);
      expect(
        find.textContaining('พลังผู้เรียน 100 · พลังสถิติเดิม 100'),
        findsOneWidget,
      );
      answerGate.complete();
      await _until(tester, find.text('จบรอบและบันทึกผล'));
      final outbox =
          (await fixture.db.select(fixture.db.outboxOperations).get())
              .map((r) => r.toJson())
              .toList();
      final srs = (await fixture.db.select(fixture.db.srsStates).getSingle())
          .toJson();
      final finishGate = fixture.repository.finishGate = Completer<void>();
      await tester.tap(find.text('จบรอบและบันทึกผล'));
      await tester.tap(find.text('จบรอบและบันทึกผล'));
      await _waitFor(tester, () => fixture.repository.finishCalls == 1);
      expect(find.text('บันทึกผลรอบนี้แล้ว'), findsNothing);
      finishGate.complete();
      await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
      expect(fixture.repository.commands, hasLength(1));
      expect(fixture.repository.finishCalls, 1);
      expect(find.text('ตอบถูก 1 · ตอบผิด 0 · รวม 1 คำตอบ'), findsOneWidget);
      final afterFinish = await fixture.db
          .select(fixture.db.outboxOperations)
          .get();
      expect(
        afterFinish
            .where((r) => r.entityType != 'achievementUnlock')
            .map((r) => r.toJson()),
        outbox,
      );
      expect(
        afterFinish.where((r) => r.entityType == 'achievementUnlock'),
        hasLength(2),
      );
      expect(
        (await fixture.db.select(fixture.db.srsStates).getSingle()).toJson(),
        srs,
      );
    });

    testWidgets('dispose while loading creates no session', (tester) async {
      final loading = Completer<ProgressSnapshot>();
      await tester.pumpWidget(
        MaterialApp(
          home: GhostShadowDuelScreen(
            learning: fixture.learning,
            progressLoader: () => loading.future,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'กำลังเตรียมสถิติเดิม',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      loading.complete(_history);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(fixture.repository.finishCalls, 0);
      expect(
        await fixture.db.select(fixture.db.learningSessions).get(),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'leaving a pending dispatched answer does not undo it or finish',
      (tester) async {
        final gate = fixture.repository.answerGate = Completer<void>();
        fixture.repository.holdBeforeAnswer = true;
        await _open(tester, fixture);
        await tester.enterText(find.byType(TextField), 'apple');
        await tester.tap(find.text('ตอบ'));
        await _waitFor(tester, () => fixture.repository.commands.isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await _waitFor(tester, () => fixture.repository.answerCompleted);
        expect(fixture.repository.finishCalls, 0);
        expect(
          await fixture.db.select(fixture.db.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          (await fixture.db.select(fixture.db.learningSessions).getSingle())
              .state,
          'active',
        );
        final achievements = await fixture.db
            .select(fixture.db.achievementUnlocks)
            .get();
        expect(achievements.map((r) => r.achievementId).toSet(), {
          'first_answer',
          'first_correct',
        });
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'owner change during progress load cannot start a new owner session',
      (tester) async {
        final loading = Completer<ProgressSnapshot>();
        await tester.pumpWidget(
          MaterialApp(
            home: GhostShadowDuelScreen(
              learning: fixture.learning,
              progressLoader: () => loading.future,
            ),
          ),
        );
        await tester.pump();
        fixture.owners.id = 'b';
        loading.complete(_history);
        await _until(tester, find.textContaining('บริบทการเรียนเปลี่ยน'));
        expect(
          await fixture.db.select(fixture.db.learningSessions).get(),
          isEmpty,
        );
      },
    );

    for (final duringFinish in [false, true]) {
      testWidgets(
        'owner change while ${duringFinish ? 'Finish' : 'answer'} is pending hides stale success',
        (tester) async {
          final gate = Completer<void>();
          await _open(tester, fixture);
          if (!duringFinish) fixture.repository.answerGate = gate;
          await tester.enterText(find.byType(TextField), 'apple');
          await tester.tap(find.text('ตอบ'));
          if (duringFinish) {
            await _until(tester, find.text('จบรอบและบันทึกผล'));
            fixture.repository.finishGate = gate;
            await tester.tap(find.text('จบรอบและบันทึกผล'));
            await _waitFor(tester, () => fixture.repository.finishCalls == 1);
          } else {
            await _waitFor(tester, () => fixture.repository.answerCompleted);
          }
          fixture.owners.id = 'b';
          gate.complete();
          await _until(tester, find.textContaining('บริบทการเรียนเปลี่ยน'));
          expect(find.text('บันทึกผลรอบนี้แล้ว'), findsNothing);
          final attempts = await fixture.db
              .select(fixture.db.answerAttempts)
              .get();
          expect(attempts.single.ownerId, 'a');
          expect(
            (await fixture.db.select(fixture.db.learningSessions).getSingle())
                .ownerId,
            'a',
          );
        },
      );
    }

    testWidgets('owner change before submit fails closed without a dispatch', (
      tester,
    ) async {
      await _open(tester, fixture);
      fixture.owners.id = 'b';
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.tap(find.text('ตอบ'));
      await _until(tester, find.textContaining('บริบทการเรียนเปลี่ยน'));
      expect(fixture.repository.commands, isEmpty);
      expect(await fixture.db.select(fixture.db.answerAttempts).get(), isEmpty);
    });

    testWidgets('owner read failure cannot admit an answer', (tester) async {
      await _open(tester, fixture);
      fixture.owners.failRead = true;
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.tap(find.text('ตอบ'));
      await _until(tester, find.textContaining('บริบทการเรียนเปลี่ยน'));
      expect(fixture.repository.commands, isEmpty);
    });

    testWidgets('changed learning dependency invalidates admitted duel', (
      tester,
    ) async {
      Future<ProgressSnapshot> loader() async => _history;
      await _open(tester, fixture, loader: loader);
      final replacement = LearningUseCases(
        owners: fixture.owners,
        repository: fixture.repository,
        generateId: () => 'replacement',
        nowUtc: fixture.learning.nowUtc,
        buildInfo: fixture.learning.buildInfo,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GhostShadowDuelScreen(
            learning: replacement,
            progressLoader: loader,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('บริบทการเรียนเปลี่ยน'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(fixture.repository.commands, isEmpty);
    });

    testWidgets(
      'owner switch during session start leaves only unfinished original session',
      (tester) async {
        final gate = fixture.repository.sessionGate = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: GhostShadowDuelScreen(
              learning: fixture.learning,
              progressLoader: () async => _history,
            ),
          ),
        );
        await _waitFor(tester, () => fixture.repository.sessionStarted);
        fixture.owners.id = 'b';
        gate.complete();
        await _until(tester, find.textContaining('บริบทการเรียนเปลี่ยน'));
        final sessions = await fixture.db
            .select(fixture.db.learningSessions)
            .get();
        expect(sessions, hasLength(1));
        expect(sessions.single.ownerId, 'a');
        expect(sessions.single.state, 'active');
        expect(fixture.repository.commands, isEmpty);
        expect(fixture.repository.finishCalls, 0);
      },
    );

    for (final completed in [false, true]) {
      testWidgets(
        'unconfirmed summary cannot display success completed=$completed',
        (tester) async {
          await _open(tester, fixture);
          await tester.enterText(find.byType(TextField), 'wrong');
          await tester.tap(find.text('ตอบ'));
          await _until(tester, find.text('จบรอบและบันทึกผล'));
          fixture.repository.summaryOverride = LearningSessionSummary(
            id: completed
                ? 'wrong-session'
                : fixture.repository.commands.single.sessionId,
            state: completed ? 'completed' : 'active',
            correctCount: 99,
            wrongCount: 99,
            score: 99,
          );
          await tester.tap(find.text('จบรอบและบันทึกผล'));
          await _until(tester, find.text('ลองบันทึกผลรอบอีกครั้ง'));
          expect(find.text('บันทึกผลรอบนี้แล้ว'), findsNothing);
          fixture.repository.summaryOverride = null;
          await tester.tap(find.text('ลองบันทึกผลรอบอีกครั้ง'));
          await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
          expect(
            find.text('ตอบถูก 0 · ตอบผิด 1 · รวม 1 คำตอบ'),
            findsOneWidget,
          );
          expect(fixture.repository.commands, hasLength(1));
        },
      );
    }

    testWidgets('Back leaves an unfinished duel without closing its session', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GhostShadowDuelScreen(
                    learning: fixture.learning,
                    progressLoader: () async => _history,
                  ),
                ),
              ),
              child: const Text('เปิดเกม'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('เปิดเกม'));
      await _until(tester, find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(GhostShadowDuelScreen), findsNothing);
      expect(fixture.repository.finishCalls, 0);
      expect(
        (await fixture.db.select(fixture.db.learningSessions).getSingle())
            .state,
        'active',
      );
    });

    testWidgets('empty answer never dispatches evidence', (tester) async {
      await _open(tester, fixture);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('ตอบ'));
      await tester.pump();
      expect(fixture.repository.commands, isEmpty);
      expect(fixture.repository.finishCalls, 0);
    });

    for (final visible in [false, true]) {
      testWidgets('historical Weakness CTA respects feature gate=$visible', (
        tester,
      ) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(
          () => fixture.db.customStatement(
            'UPDATE local_owners SET is_active = (id = ?)',
            ['a'],
          ),
        );
        final features = BuildFieldFeatureRegistry({
          FieldFeature.weakness: visible
              ? FieldFeatureState.enabled
              : FieldFeatureState.hidden,
        });
        final dependencies = AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _UnusedGuest(),
          fieldFeatures: features,
          database: fixture.db,
          localOwners: fixture.owners,
          learning: fixture.learning,
          progress: ProgressUseCases(
            owners: fixture.owners,
            queries: DriftProgressQueries(fixture.db),
            nowUtc: fixture.learning.nowUtc,
          ),
        );
        try {
          await _open(
            tester,
            fixture,
            features: features,
            dependencies: dependencies,
          );
          await tester.enterText(find.byType(TextField), 'wrong');
          await tester.tap(find.text('ตอบ'));
          await _until(tester, find.text('จบรอบและบันทึกผล'));
          expect(find.text('ฝึกคำที่ผิดจากประวัติ'), findsNothing);
          await tester.tap(find.text('จบรอบและบันทึกผล'));
          await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
          expect(
            find.text('ฝึกคำที่ผิดจากประวัติ'),
            visible ? findsOneWidget : findsNothing,
          );
          if (visible) {
            await tester.tap(find.text('ฝึกคำที่ผิดจากประวัติ'));
            await _until(tester, find.byType(WeaknessClinicScreen));
            await _until(tester, find.text('apple'));
            await tester.pumpAndSettle();
            expect(find.text('apple'), findsOneWidget);
            expect(
              await fixture.db.select(fixture.db.answerAttempts).get(),
              hasLength(1),
            );
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(fixture.db.close);
        }
      });
    }

    for (final size in [const Size(360, 800), const Size(800, 360)]) {
      testWidgets('2x with IME can reach retry Finish and result $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        fixture.repository.failAnswer = true;
        fixture.repository.failFinish = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: size.width > size.height
                  ? Brightness.dark
                  : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: GhostShadowDuelScreen(
              learning: fixture.learning,
              progressLoader: () async => _history,
            ),
          ),
        );
        await _until(tester, find.textContaining('Shadow Self'));
        await tester.scrollUntilVisible(find.byType(TextField), 150);
        await tester.enterText(find.byType(TextField), 'apple');
        await _tap(tester, 'ตอบ');
        await _until(tester, find.text('ลองบันทึกคำตอบอีกครั้ง'));
        await _tap(tester, 'ลองบันทึกคำตอบอีกครั้ง');
        await _waitFor(tester, () => fixture.repository.answerCompleted);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 1000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('จบรอบและบันทึกผล'), 100);
        await _tap(tester, 'จบรอบและบันทึกผล');
        await _until(tester, find.text('ลองบันทึกผลรอบอีกครั้ง'));
        await _tap(tester, 'ลองบันทึกผลรอบอีกครั้ง');
        await _until(tester, find.text('บันทึกผลรอบนี้แล้ว'));
        await tester.ensureVisible(find.text('บันทึกผลรอบนี้แล้ว'));
        expect(find.text('บันทึกผลรอบนี้แล้ว').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<void> _open(
  WidgetTester tester,
  _Fixture fixture, {
  GhostProgressLoader? loader,
  FieldFeatureRegistry? features,
  AppDependencies? dependencies,
}) async {
  final app = MaterialApp(
    home: GhostShadowDuelScreen(
      learning: fixture.learning,
      progressLoader: loader ?? () async => _history,
      featureRegistry: features,
    ),
  );
  await tester.pumpWidget(
    dependencies == null
        ? app
        : AppDependenciesScope(dependencies: dependencies, child: app),
  );
  await _until(tester, find.byType(TextField));
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Timed out waiting for fixture operation');
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  expect(find.text(text).hitTestable(), findsOneWidget);
  await tester.tap(find.text(text));
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Object _evidence(RecordAnswerCommand c) => (
  c.id,
  c.ownerId,
  c.sessionId,
  c.wordId,
  c.promptMode,
  c.isCorrect,
  c.responseTimeMs,
  c.attemptNumber,
  c.occurredAtUtc,
  c.providerProvenance,
  jsonEncode(c.evidenceContext.toJson()),
);

final class _UnusedGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      throw StateError('Synthetic guest entry must not run in this fixture');
}

final class _Owners implements LocalOwnerRepository {
  String id = 'a';
  bool failRead = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (failRead) throw StateError('synthetic owner unavailable');
    return LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 10, 23));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final owners = _Owners();
  late final repository = _Repository(DriftLearningRepository(db));
  int sequence = 0;
  late final learning = LearningUseCases(
    owners: owners,
    repository: repository,
    generateId: () => '${++sequence}',
    nowUtc: () => DateTime.utc(2026, 10, 23),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  Future<void> seed() async {
    for (final id in ['a', 'b']) {
      await db
          .into(db.localOwners)
          .insert(LocalOwnersCompanion.insert(id: id, createdAtUtcMs: 1));
    }
    await db
        .into(db.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category',
            ownerId: 'a',
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'apple',
            ownerId: 'a',
            categoryId: 'category',
            spelling: 'apple',
            normalizedSpelling: 'apple',
            meaning: 'ผลไม้สังเคราะห์',
            normalizedMeaning: 'ผลไม้สังเคราะห์',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
}

final class _Repository implements LearningRepository {
  _Repository(this.delegate);
  final LearningRepository delegate;
  final commands = <RecordAnswerCommand>[];
  int finishCalls = 0;
  bool failAnswer = false, failFinish = false, afterCommit = false;
  Completer<void>? answerGate, finishGate;
  bool holdBeforeAnswer = false;
  bool answerCompleted = false;
  Completer<void>? sessionGate;
  bool sessionStarted = false;
  LearningSessionSummary? summaryOverride;
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (holdBeforeAnswer) await answerGate?.future;
    if (failAnswer && commands.length == 1 && !afterCommit) {
      throw StateError('synthetic storage failure');
    }
    final result = await delegate.recordAnswer(command);
    answerCompleted = true;
    if (!holdBeforeAnswer) await answerGate?.future;
    if (failAnswer && commands.length == 1 && afterCommit) {
      throw StateError('synthetic lost answer ack');
    }
    return result;
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls++;
    if (failFinish && finishCalls == 1 && !afterCommit) {
      throw StateError('synthetic finish failure');
    }
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    await finishGate?.future;
    if (failFinish && finishCalls == 1 && afterCommit) {
      throw StateError('synthetic lost finish ack');
    }
    return summaryOverride ?? result;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
  @override
  Future<void> startSession(LearningSessionDraft session) async {
    await delegate.startSession(session);
    sessionStarted = true;
    await sessionGate?.future;
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );
  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}

const _history = ProgressSnapshot(
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'apple',
      spelling: 'apple',
      meaning: 'ผลไม้สังเคราะห์',
      sampleSize: 1,
      incorrectCount: 1,
      errorRate: 1,
      dueAtUtc: null,
    ),
  ],
  recommendations: [],
  averageResponseTimeMs: 90000,
);

const _empty = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
