import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/screens/personal_sets_screen.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import '../support/r15_visual_capture.dart';

void main() {
  setUpAll(loadR15Fonts);
  void screenTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        // Drift defers watch-query disposal by one event-loop turn.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      }
    });
  }

  late AppDatabase db;
  late PersonalSetsUseCases app;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    final bytes = await File(PackagedSenseCrosswalk.assetPath).readAsBytes();
    final manifests = DriftContentManifestRepository(
      db,
      loadArtifactBytes: (_) async => bytes,
    );
    await manifests.provisionPackagedArtifact(
      PackagedSenseCrosswalk.verify(bytes),
    );
    Future<String> owner() async => 'a';
    app = PersonalSetsUseCases(
      repository: DriftPersonalSetRepository(
        db,
        SenseCrosswalkRepository(manifests),
        nowUtc: () => DateTime.now().toUtc(),
      ),
      ownerGeneration: OwnerGeneration(
        activeOwnerId: owner,
        readDurableStamp: DriftOwnerGeneration(db).read,
      ),
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: owner,
      ),
    );
  });
  tearDown(() => db.close());

  screenTest(
    'create preview save reopen edit and archive retain immutable history',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PersonalSetsScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีชุดคำส่วนตัว'), findsOneWidget);
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'My objects',
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ความหมายที่เลือก: 1'), findsOneWidget);
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      final token = await app.begin();
      final saved = (await app.list(token)).single;
      expect(saved.title, 'My objects');
      await tester.tap(find.text('My objects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('แก้ไข'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Edited objects',
      );
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      expect((await app.list(token)).single.revision, 2);
      expect(
        (await app.read(token, setId: saved.setId, revision: 1))!.title,
        'My objects',
      );
      await tester.tap(find.text('Edited objects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เก็บเข้าคลัง'));
      await tester.pumpAndSettle();
      expect(await app.list(token), isEmpty);
      expect((await app.list(token, includeArchived: true)).single.revision, 3);
      expect(tester.takeException(), isNull);
    },
  );

  screenTest('missing composition has explicit unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PersonalSetsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ชุดคำส่วนตัวยังไม่พร้อมใช้งาน'), findsOneWidget);
    expect(find.text('สร้างชุดคำ'), findsNothing);
  });

  screenTest(
    'stale owner preview is discarded and cannot save into new generation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PersonalSetsScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Private draft',
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      await app.ownerGeneration.duringTransition(() async {});
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      expect(find.text('Private draft'), findsNothing);
      expect(find.text('เปิดชุดคำใหม่'), findsOneWidget);
      expect(await app.list(await app.begin()), isEmpty);
    },
  );

  screenTest(
    'invalid draft explains missing input and large text stays operable',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: PersonalSetsScreen(useCases: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ดูตัวอย่าง'));
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      expect(
        find.text('ใส่ชื่อชุดคำและเลือกอย่างน้อยหนึ่งความหมาย'),
        findsOneWidget,
      );
      expect(await app.list(await app.begin()), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  screenTest(
    'durable owner epoch change clears a visible draft without another click',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PersonalSetsScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Private visible draft',
      );
      await DriftOwnerGeneration(db).advance();
      await tester.pumpAndSettle();
      expect(find.text('Private visible draft'), findsNothing);
      expect(find.text('เปิดชุดคำใหม่'), findsOneWidget);
    },
  );

  screenTest(
    'backup exposes owner bound scope and rejects newer import without writes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PersonalSetsScreen(useCases: app)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สำรองและกู้คืนชุดคำ'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('เฉพาะชุดคำส่วนตัวของบัญชีนี้'),
        findsOneWidget,
      );
      await tester.tap(find.text('แสดงข้อมูลสำรอง'));
      await tester.pumpAndSettle();
      final exported = tester
          .widget<SelectableText>(find.byKey(const ValueKey('set-backup-json')))
          .data!;
      final content = (jsonDecode(exported) as Map)['content'] as Map;
      expect(content['ownerId'], 'a');
      content['schemaVersion'] = 999;
      await tester.enterText(
        find.byKey(const ValueKey('set-import-json')),
        jsonEncode({
          'content': content,
          'contentSha256': sha256
              .convert(utf8.encode(jsonEncode(content)))
              .toString(),
        }),
      );
      await tester.tap(find.text('กู้คืนชุดคำ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('นำเข้าไม่ได้'), findsOneWidget);
      expect(await app.list(await app.begin()), isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('set-import-json')),
        exported,
      );
      await tester.tap(find.text('กู้คืนชุดคำ'));
      await tester.pumpAndSettle();
      expect(find.text('กู้คืนชุดคำแล้ว'), findsOneWidget);
    },
  );
  screenTest('sense search filters choices without dropping selected members', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PersonalSetsScreen(useCases: app)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('สร้างชุดคำ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('set-title')),
      'Filtered objects',
    );
    await tester.enterText(find.byKey(const ValueKey('set-search')), 'book');
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.enterText(find.byKey(const ValueKey('set-search')), 'pencil');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('ดูตัวอย่าง'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ความหมายที่เลือก: 2'), findsOneWidget);
    await tester.tap(find.text('บันทึกชุดคำ'));
    await tester.pumpAndSettle();
    final saved = (await app.list(await app.begin())).single;
    expect(saved.members.map((r) => r.wordId), [
      'word:starter-book',
      'word:starter-pencil',
    ]);
    expect(saved.filterSnapshot['query'], 'pencil');
  });
  screenTest('mobile editor and preview expose labeled accessible controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('synthetic-r15-surface'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: M3Theme.lightTheme,
            home: PersonalSetsScreen(useCases: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'ของรอบตัว',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await captureR15Surface(tester, 'E21-personal-set-editor-mobile');
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await captureR15Surface(tester, 'E21-personal-set-preview-mobile');
    } finally {
      semantics.dispose();
    }
  });
}
