import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/result_screen.dart';
import 'package:vocab_learning_app/screens/word_games_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('Practice opens the spelling boss at 200% text', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 11, 13);
    var sequence = 0;
    String generateId() => 'synthetic-spelling-boss-${++sequence}';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: generateId,
      nowUtc: () => now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      localOwners: owners,
      vocabulary: VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: generateId,
        nowUtc: () => now,
      ),
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: generateId,
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    try {
      await tester.runAsync(owners.getOrCreateActiveOwner);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ChooseModeScreen(loader: () async => _emptyProgress),
          ),
        ),
      );
      await _tap(tester, 'ดูแบบฝึกทั้งหมด');
      await _tap(tester, 'เกมฝึกคำ');
      expect(find.byType(WordGamesScreen), findsOneWidget);
      expect(find.text('ด่านสะกดคำ'), findsOneWidget);
      final games = tester.state(find.byType(WordGamesScreen));
      await _tap(tester, 'ด่านสะกดคำ');
      expect(find.text('ชั่วคราว'), findsOneWidget);
      await _submit(tester, 'ephemral');
      expect(find.text('ลองตรวจตัวสะกด'), findsOneWidget);
      expect(find.text('ephemral'), findsOneWidget);
      expect(find.text('หลังตัว m ยังมีตัว e'), findsOneWidget);
      await _tap(tester, 'แก้คำตอบ');
      expect(_currentAnswer(tester), 'ephemral');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('จะออกจากด่านไหม'), findsOneWidget);
      await _tap(tester, 'เล่นคำเดิมต่อ');
      expect(_currentAnswer(tester), 'ephemral');
      await _submit(tester, 'ephemeral');
      expect(find.text('พิถีพิถัน'), findsOneWidget);
      expect(find.text('ผ่านแล้ว 1 จาก 3 คำ'), findsOneWidget);
      await _tap(tester, 'ออกจากด่าน');
      await _tap(tester, 'ออกไปเลือกเกม');
      expect(tester.state(find.byType(WordGamesScreen)), same(games));

      await _tap(tester, 'ด่านสะกดคำ');
      expect(find.text('ชั่วคราว'), findsOneWidget);
      expect(_currentAnswer(tester), isEmpty);
      await _submit(tester, 'ephemeral');
      await _submit(tester, 'meticulous');
      expect(find.text('ยั่งยืน'), findsOneWidget);
      await _submit(tester, 'sustainable');
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('ผ่านด่านสะกดคำแล้ว'), findsOneWidget);
      final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
      await _tap(tester, 'ทวนคำสุดท้าย');
      expect(find.text('sustainable'), findsOneWidget);
      expect(find.text('We need sustainable energy.'), findsOneWidget);
      await _tap(tester, 'กลับไปดูผล');
      expect(
        tester.widget<ResultScreen>(find.byType(ResultScreen)),
        same(result),
      );
      await _tap(tester, 'เลือกเกมอื่น');
      expect(tester.state(find.byType(WordGamesScreen)), same(games));
      await _tap(tester, 'กลับไปเลือกแบบฝึก');
      expect(find.text('เลือกวิธีฝึก'), findsOneWidget);

      final counts = await tester.runAsync(
        () async => [
          (await database.select(database.learningSessions).get()).length,
          (await database.select(database.answerAttempts).get()).length,
          (await database.select(database.srsStates).get()).length,
          (await database.select(database.pointsLedgerEntries).get()).length,
          (await database.select(database.rewardTransactions).get()).length,
          (await database.select(database.eventsV2).get()).length,
          (await database.select(database.outboxOperations).get()).length,
        ],
      );
      expect(counts, everyElement(isZero));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var finished = false;
      final close = database.close().whenComplete(() => finished = true);
      unawaited(close);
      for (var frame = 0; frame < 80 && !finished; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(finished, isTrue, reason: 'database must close');
      await close;
    }
  });
}

String _currentAnswer(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _submit(WidgetTester tester, String spelling) async {
  final field = find.byType(TextField);
  await tester.ensureVisible(field);
  await tester.enterText(field, spelling);
  FocusManager.instance.primaryFocus?.unfocus();
  await _tap(tester, 'ส่งคำตอบ');
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target.hitTestable(),
      140,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

const _emptyProgress = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final class _GuestSession extends Fake implements GuestSessionService {}
