import 'dart:io';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/goals/application/study_plan_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_study_plan_repository.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/screens/study_plan_screen.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import '../support/r15_visual_capture.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  setUpAll(loadR15Fonts);
  late AppDatabase db;
  late StudyPlanUseCases app;
  late OwnerGeneration generation;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('a',1,1)",
    );
    Future<String> owner() async => 'a';
    generation = OwnerGeneration(
      activeOwnerId: owner,
      readDurableStamp: DriftOwnerGeneration(db).read,
    );
    app = StudyPlanUseCases(
      repository: DriftStudyPlanRepository(
        db,
        nowUtc: () => DateTime.now().toUtc(),
      ),
      ownerGeneration: generation,
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: owner,
      ),
      nowUtc: () => DateTime.now().toUtc(),
      timezoneId: 'Asia/Bangkok',
      isAvailable: () => true,
    );
  });
  tearDown(() => db.close());
  void screenTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
        }
      });
  screenTest(
    'real screen previews rejects accepts and shows old versus new budget',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StudyPlanScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('plan-minutes')), '0');
      await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
      await tester.pumpAndSettle();
      expect(find.text('เวลา: ยังไม่มีแผน เป็น 0 นาที'), findsOneWidget);
      expect(await app.active(await app.begin()), isNull);
      await tester.tap(find.text('ไม่รับข้อเสนอ'));
      await tester.pumpAndSettle();
      expect(await app.active(await app.begin()), isNull);
      await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยอมรับแผน'));
      await tester.pumpAndSettle();
      expect((await app.active(await app.begin()))!.availableMinutes, 0);
      await tester.enterText(find.byKey(const ValueKey('plan-minutes')), '15');
      await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
      await tester.pumpAndSettle();
      expect(find.text('เวลา: 0 เป็น 15 นาที'), findsOneWidget);
      await tester.tap(find.text('ยอมรับแผน'));
      await tester.pumpAndSettle();
      expect((await app.repository.history('a')).length, 2);
    },
  );
  screenTest('conflict leaves accepted revision and offers explicit reload', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StudyPlanScreen(useCases: app)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    final token = await app.begin();
    await app.accept(
      token,
      await app.propose(token, operationId: 'other', availableMinutes: 2),
    );
    await tester.tap(find.text('ยอมรับแผน'));
    await tester.pumpAndSettle();
    expect(find.text('โหลดข้อมูลล่าสุด'), findsOneWidget);
    expect((await app.active(token))!.availableMinutes, 2);
    await tester.tap(find.text('โหลดข้อมูลล่าสุด'));
    await tester.pumpAndSettle();
    expect(find.text('แผนที่ยอมรับ r1'), findsOneWidget);
  });
  screenTest('preview refreshes its diff base after another accepted plan', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StudyPlanScreen(useCases: app)));
    await tester.pumpAndSettle();
    final owner = await app.begin();
    await app.accept(
      owner,
      await app.propose(owner, operationId: 'new-base', availableMinutes: 2),
    );
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    expect(find.text('เวลา: 2 เป็น 10 นาที'), findsOneWidget);
    expect(find.text('ข้อเสนอ r2'), findsOneWidget);
  });
  screenTest('320px and text200 remain scrollable with zero-time proposal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 740),
            textScaler: TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: StudyPlanScreen(useCases: app),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ยอมรับแผน'));
    expect(tester.takeException(), isNull);
  });
  screenTest('durable owner epoch clears proposal and private editor state', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StudyPlanScreen(useCases: app)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plan-minutes')), '37');
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    await DriftOwnerGeneration(db).advance();
    await tester.pumpAndSettle();
    expect(find.text('ยอมรับแผน'), findsNothing);
    expect(find.byKey(const ValueKey('plan-minutes')), findsNothing);
    expect(await app.repository.history('a'), isEmpty);
  });
  screenTest(
    'backup controls restore accepted history through application authority',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: StudyPlanScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยอมรับแผน'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('สำรองประวัติแผน'));
      await tester.tap(find.text('สำรองประวัติแผน'));
      await tester.pumpAndSettle();
      final backup = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('plan-backup-json')),
          )
          .data!;
      await db.customStatement(
        "DELETE FROM active_plan_pointers WHERE owner_id='a'",
      );
      await db.customStatement(
        "DELETE FROM study_plan_revisions WHERE owner_id='a'",
      );
      await tester.enterText(
        find.byKey(const ValueKey('plan-restore-json')),
        backup,
      );
      await tester.ensureVisible(find.text('คืนค่าประวัติแผน'));
      await tester.tap(find.text('คืนค่าประวัติแผน'));
      await tester.pumpAndSettle();
      expect((await app.active(await app.begin()))!.revision, 1);
    },
  );
  screenTest('destination disposed while waiting for lease cannot persist', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: StudyPlanScreen(useCases: app)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    final gate = DriftOwnerOperationGate(db);
    expect(
      await gate.tryAcquire(
        token: 'other',
        nowUtc: DateTime.now().toUtc(),
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    await tester.tap(find.text('ยอมรับแผน'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await gate.release(token: 'other');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(await app.repository.history('a'), isEmpty);
  });
  screenTest('rendered proposal exposes reviewed plan diff', (tester) async {
    await tester.runAsync(
      () => PackagedStarterCatalog.provision(
        db,
        DriftContentManifestRepository(db),
        (identity) => File(
          'assets/content/lexical_metadata/starter-${PackagedStarterCatalog.words.firstWhere((w) => w.identity == identity).key}/r1.json',
        ).readAsBytes(),
      ),
    );
    await db.customStatement(
      "INSERT INTO srs_states(id,owner_id,word_id,due_at_utc_ms,algorithm_version) SELECT 'srs:'||id,'a',id,1,1 FROM vocabulary_words",
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('synthetic-r15-surface'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: M3Theme.thaiFontFamily,
          ),
          home: StudyPlanScreen(useCases: app),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดูข้อเสนอและเปรียบเทียบ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('เพิ่มในวันนี้:'), findsOneWidget);
    expect(find.textContaining('book'), findsOneWidget);
    expect(find.text('ทบทวน 10 · งานใหม่ 0 · ยกยอด 2'), findsOneWidget);
    await captureR15Surface(tester, 'e22-plan-proposal');
  });
}
