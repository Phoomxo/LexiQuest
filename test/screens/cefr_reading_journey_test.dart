import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('Home opens the authored reading menu at 200%', (tester) async {
    await _openHome(tester);
    await _openReadingMenu(tester);

    expect(find.text('เลือกคำตามระดับ'), findsOneWidget);
    expect(find.text('ลองตอบก่อนเลือกระดับ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A2 sample search, self-rating and Back keep the same deck', (
    tester,
  ) async {
    await _withLocalGuest(tester, (database) async {
      await _openReadingMenu(tester);
      await _tap(tester, 'เลือกคำตามระดับ');
      await _tap(tester, 'A2 · การเดินทาง');
      expect(find.text('คำศัพท์ระดับ A2'), findsOneWidget);
      expect(find.text('journey'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'meticulous');
      await tester.pumpAndSettle();
      expect(find.text('ไม่พบคำในชุดนี้'), findsOneWidget);
      expect(find.text('journey'), findsNothing);
      await _tap(tester, 'ล้างคำค้น');
      expect(find.text('คำศัพท์ระดับ A2'), findsOneWidget);
      expect(find.text('journey'), findsOneWidget);

      await _tap(tester, 'เริ่มทบทวนคำนี้');
      await _tap(tester, 'พลิกดูความหมาย');
      await _tap(tester, 'ยังนึกไม่ออก · ลองอีกครั้ง');
      expect(find.text('journey'), findsOneWidget);
      await _tap(tester, 'พลิกดูความหมาย');
      await _tap(tester, 'จำได้แล้ว');
      expect(find.text('ทบทวนจบแล้ว'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.textContaining('journey'), findsWidgets);
      await _tap(tester, 'กลับไปดูชุดเดิม');
      expect(find.text('คำศัพท์ระดับ A2'), findsOneWidget);
      expect(find.text('journey'), findsOneWidget);

      await _tap(tester, 'เลือกระดับอื่น');
      expect(find.text('เลือกคำตามระดับ'), findsOneWidget);
      await _tap(tester, 'C2 · ปรัชญา');
      expect(find.text('คำศัพท์ระดับ C2'), findsOneWidget);
      expect(find.text('ephemeral'), findsOneWidget);
      await _back(tester);
      await _tap(tester, 'กลับไปเลือกบทเรียน');
      expect(find.text('คำศัพท์และบทอ่าน'), findsOneWidget);
      await _expectNoLocalEvidence(tester, database);
    });
  });

  testWidgets('two correct answers suggest A2 and retain score across routes', (
    tester,
  ) async {
    await _withLocalGuest(tester, (database) async {
      await _openReadingMenu(tester);
      await _tap(tester, 'ลองตอบก่อนเลือกระดับ');
      await _answer(tester, ['แอปเปิล', 'Trip', 'ล้มเหลว', 'ธรรมดา', 'Rare']);
      expect(find.text('ผลที่ลองตอบ'), findsOneWidget);
      expect(find.text('2 / 5'), findsOneWidget);

      await _tap(tester, 'ระดับคำที่แนะนำ · A2');
      expect(find.text('journey'), findsOneWidget);
      await _tap(tester, 'เริ่มทบทวนคำนี้');
      await _tap(tester, 'พลิกดูความหมาย');
      await _tap(tester, 'จำได้แล้ว');
      expect(find.text('1 / 1'), findsOneWidget);
      await _tap(tester, 'กลับไปดูชุดเดิม');
      await _tap(tester, 'กลับไปดูผลเดิม');
      expect(find.text('2 / 5'), findsOneWidget);

      await _tap(tester, 'ดูบทอ่านที่แนะนำ');
      expect(find.text('บทอ่านที่แนะนำ'), findsOneWidget);
      expect(find.text('บทอ่าน A2'), findsOneWidget);
      expect(find.text('นัดกันที่สถานี'), findsOneWidget);
      await _tap(tester, 'เริ่มอ่านเรื่องนี้');
      expect(find.text('นัดกันที่สถานี'), findsOneWidget);
      final reader = find.byType(CefrArticleReaderScreen);
      final openArticle = tester.state(reader);
      await _tap(tester, 'platform');
      expect(find.text('Her friend is on platform two.'), findsOneWidget);
      expect(find.text('เพื่อนของมินารออยู่ที่ชานชาลาสอง'), findsOneWidget);
      await _tap(tester, 'ดูคำอ่านแทน');
      expect(find.text('แพลตฟอร์ม · เน้นพยางค์แรก'), findsOneWidget);
      await _tap(tester, 'อ่านต่อที่เดิม');
      expect(tester.state(reader), same(openArticle));
      await _tap(tester, 'ดูความหมายของ platform');
      expect(find.text('They meet on the platform.'), findsOneWidget);
      expect(find.textContaining('ชานชาลา'), findsWidgets);
      await _tap(tester, 'อ่านต่อที่เดิม');
      expect(tester.state(reader), same(openArticle));
      expect(find.text('คำที่เลือก platform'), findsOneWidget);
      await _tap(tester, 'ฝึกคำจากเรื่องนี้');
      expect(find.text('นึกคำจากเรื่อง'), findsOneWidget);
      await _tap(tester, 'ticket');
      expect(find.text('ticket หมายถึงตั๋ว'), findsOneWidget);
      await _tap(tester, 'กลับไปตอบ');
      await _tap(tester, 'platform');
      final composition = find.byType(TextField);
      await tester.ensureVisible(composition);
      await tester.enterText(composition, 'I wait here.');
      await _tap(tester, 'ดูสรุปการอ่าน');
      expect(find.text('ใส่คำว่า platform ในประโยคก่อนดูสรุป'), findsOneWidget);
      await tester.enterText(composition, 'I wait on platform two.');
      await _tap(tester, 'ดูสรุปการอ่าน');
      expect(find.text('ผลการฝึกครั้งนี้'), findsOneWidget);
      expect(find.text('I wait on platform two.'), findsOneWidget);
      await _tap(tester, 'กลับไปอ่านต่อ');
      expect(tester.state(reader), same(openArticle));
      expect(find.text('คำที่เลือก platform'), findsOneWidget);
      await _completeStationExercise(tester);
      await _tap(tester, 'กลับไปที่บทอ่านแนะนำ');
      expect(reader, findsNothing);
      expect(find.text('บทอ่านที่แนะนำ'), findsOneWidget);
      await _tap(tester, 'กลับไปดูผลเดิม');
      expect(find.text('ผลที่ลองตอบ'), findsOneWidget);
      expect(find.text('2 / 5'), findsOneWidget);
      await _tap(tester, 'เลือกบทเรียนเอง');
      expect(find.text('คำศัพท์และบทอ่าน'), findsOneWidget);
      await _expectNoLocalEvidence(tester, database);
    });
  });

  testWidgets('station result can return directly to Practice Home', (
    tester,
  ) async {
    await _openHome(tester);
    await _openReadingMenu(tester);
    await _tap(tester, 'ซื้อตั๋วรถไฟ');
    await _tap(tester, 'อ่านเรื่องนัดกันที่สถานี');
    await _completeStationExercise(tester);
    await _tap(tester, 'กลับหน้าฝึกภาษา');
    expect(find.byType(ChooseModeScreen), findsOneWidget);
    expect(find.byType(CefrArticleReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero correct answers suggest the A1 ticket reading', (
    tester,
  ) async {
    await _openHome(tester);
    await _openReadingMenu(tester);
    await _tap(tester, 'ลองตอบก่อนเลือกระดับ');
    await _answer(tester, ['กล้วย', 'Food', 'ล้มเหลว', 'ธรรมดา', 'Rare']);
    expect(find.text('0 / 5'), findsOneWidget);
    await _tap(tester, 'ดูบทอ่านที่แนะนำ');
    expect(find.text('บทอ่าน A1'), findsOneWidget);
    expect(find.text('ซื้อตั๋วรถไฟ'), findsOneWidget);
    await _tap(tester, 'เริ่มอ่านเรื่องนี้');
    expect(find.text('ซื้อตั๋วรถไฟ'), findsOneWidget);
    await _back(tester);
    await _tap(tester, 'กลับไปดูผลเดิม');
    expect(find.text('0 / 5'), findsOneWidget);
  });
}

Future<void> _completeStationExercise(WidgetTester tester) async {
  await _tap(tester, 'ฝึกคำจากเรื่องนี้');
  await _tap(tester, 'platform');
  await tester.enterText(find.byType(TextField), 'I wait on platform two.');
  await _tap(tester, 'ดูสรุปการอ่าน');
}

Future<void> _openHome(
  WidgetTester tester, {
  AppDependencies? dependencies,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final app = MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: ChooseModeScreen(loader: () async => _emptyProgress),
  );
  await tester.pumpWidget(
    dependencies == null
        ? app
        : AppDependenciesScope(dependencies: dependencies, child: app),
  );
  await tester.pumpAndSettle();
}

Future<void> _withLocalGuest(
  WidgetTester tester,
  Future<void> Function(AppDatabase database) journey,
) async {
  final database = AppDatabase(NativeDatabase.memory());
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic-cefr-guest',
    nowUtc: () => DateTime.utc(2026, 11, 15),
  );
  var sequence = 0;
  final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () => 'synthetic-cefr-${++sequence}',
    nowUtc: () => DateTime.utc(2026, 11, 15),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  try {
    await tester.runAsync(owners.getOrCreateActiveOwner);
    await _openHome(
      tester,
      dependencies: AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _GuestSession(),
        localOwners: owners,
        learning: learning,
        database: database,
      ),
    );
    await journey(database);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _withFrames(tester, 'database close', database.close);
  }
}

Future<void> _expectNoLocalEvidence(
  WidgetTester tester,
  AppDatabase database,
) async {
  final written = await _withFrames(
    tester,
    'local evidence readback',
    () async {
      return [
        (await database.select(database.learningSessions).get()).length,
        (await database.select(database.answerAttempts).get()).length,
        (await database.select(database.srsStates).get()).length,
        (await database.select(database.eventsV2).get()).length,
        (await database.select(database.readingEvents).get()).length,
        (await database.select(database.researchConsents).get()).length,
        (await database.select(database.rewardTransactions).get()).length,
        (await database.select(database.outboxOperations).get()).length,
      ];
    },
  );
  expect(written, everyElement(isZero));
}

Future<T> _withFrames<T>(
  WidgetTester tester,
  String description,
  Future<T> Function() operation,
) async {
  var done = false;
  final pending = operation().whenComplete(() => done = true);
  unawaited(pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  for (var i = 0; i < 80 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!done) fail('Timed out waiting for $description in CEFR practice');
  return pending;
}

Future<void> _openReadingMenu(WidgetTester tester) async {
  await _tap(tester, 'ดูแบบฝึกทั้งหมด');
  await _tap(tester, 'อ่านและแต่งประโยค');
  expect(find.text('คำศัพท์และบทอ่าน'), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).hitTestable();
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(target, 180, scrollable: scrollable.last);
    }
  }
  expect(target, findsWidgets, reason: 'Could not find $label');
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, List<String> choices) async {
  for (final (index, answer) in choices.indexed) {
    expect(find.text('ข้อ ${index + 1} จาก 5'), findsOneWidget);
    await _tap(tester, answer);
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

final class _GuestSession extends Fake implements GuestSessionService {}

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
