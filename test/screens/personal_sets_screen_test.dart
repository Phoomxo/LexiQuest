import 'dart:async';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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

  Future<void> Function()? beforeOwnerRead;
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
    beforeOwnerRead = null;
    Future<String> owner() async {
      await beforeOwnerRead?.call();
      return 'a';
    }

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

  screenTest('optional context separates drafts previews and confirmed sets', (
    tester,
  ) async {
    String? aiOwner;
    final registry = MenuActionRegistry(currentOwner: () => aiOwner);
    Map<String, dynamic> summary() =>
        jsonDecode(
              (registry.snapshot()['context'] as List).singleWhere(
                    (e) => e['id'] == 'study-planning/personal-sets/context',
                  )['value']
                  as String,
            )
            as Map<String, dynamic>;
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(home: PersonalSetsScreen(useCases: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(registry.snapshot()['context'], isEmpty);
    aiOwner = 'a';
    expect(summary()['state'], 'list');
    expect(summary()['savedSetCount'], 0);
    await tester.tap(find.text('สร้างชุดคำ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('set-title')),
      'Private set',
    );
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(summary()['state'], 'draft');
    expect(summary()['draft']['title'], 'Private set');
    expect(summary()['draft']['memberCount'], 1);
    expect(summary()['lastConfirmed'], isNull);
    expect(await app.list(await app.begin()), isEmpty);
    await tester.tap(find.text('ดูตัวอย่าง'));
    await tester.pumpAndSettle();
    expect(summary()['state'], 'preview');
    expect(summary()['manualSaveRequired'], true);
    expect(summary()['draft']['revision'], 1);
    aiOwner = null;
    expect(registry.snapshot()['context'], isEmpty);
    await tester.tap(find.text('บันทึกชุดคำ'));
    await tester.pumpAndSettle();
    expect((await app.list(await app.begin())).single.title, 'Private set');
    aiOwner = 'a';
    expect(summary()['state'], 'list');
    expect(summary()['savedSetCount'], 1);
    await tester.tap(find.text('Private set'));
    await tester.pumpAndSettle();
    expect(summary()['state'], 'detail');
    expect(summary()['lastConfirmed']['title'], 'Private set');
    await tester.tap(find.text('แก้ไข'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('set-title')),
      'Changed draft',
    );
    await tester.pump();
    expect(summary()['draft']['title'], 'Changed draft');
    expect(summary()['lastConfirmed']['title'], 'Private set');
    aiOwner = 'foreign';
    expect(registry.snapshot()['context'], isEmpty);
    aiOwner = 'a';
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(summary()['draft'], isNull);
    expect(summary()['state'], 'list');
    await tester.tap(find.text('สำรองและกู้คืนชุดคำ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('set-import-json')),
      'PRIVATE_RAW_IMPORT',
    );
    await tester.pump();
    expect(summary()['state'], 'backup');
    expect(
      jsonEncode(registry.snapshot()),
      isNot(contains('PRIVATE_RAW_IMPORT')),
    );
    expect(registry.snapshot()['actions'], isEmpty);
  });

  screenTest(
    'invalid personal-set draft does not expose confirmed data and owner change retires context',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(home: PersonalSetsScreen(useCases: app)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Unsaved private title',
      );
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      final snapshot = registry.snapshot();
      final summary = jsonDecode(
        (snapshot['context'] as List).singleWhere(
              (e) => e['id'] == 'study-planning/personal-sets/context',
            )['value']
            as String,
      );
      expect(summary['state'], 'unconfirmed');
      expect(summary.containsKey('lastConfirmed'), false);
      expect(jsonEncode(snapshot), isNot(contains('Unsaved private title')));
      expect(await app.list(await app.begin()), isEmpty);
      await app.ownerGeneration.duringTransition(() async {});
      // Native operation revalidates the generation and clears the private view.
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
    },
  );

  screenTest(
    'pending save disconnect failure and retry preserve one revision',
    (tester) async {
      String? aiOwner = 'a';
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      Map<String, dynamic> summary() =>
          jsonDecode(
                (registry.snapshot()['context'] as List).singleWhere(
                      (e) => e['id'] == 'study-planning/personal-sets/context',
                    )['value']
                    as String,
              )
              as Map<String, dynamic>;
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(home: PersonalSetsScreen(useCases: app)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Retry private set',
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      final release = Completer<void>();
      final entered = Completer<void>();
      beforeOwnerRead = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        throw StateError('PRIVATE_STORAGE_FAILURE');
      };
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pump();
      await tester.runAsync(() => entered.future);
      expect(summary()['state'], 'processing');
      expect(summary().containsKey('draft'), false);
      aiOwner = null;
      expect(registry.snapshot()['context'], isEmpty);
      release.complete();
      await tester.pumpAndSettle();
      aiOwner = 'a';
      expect(summary()['state'], 'unconfirmed');
      expect(summary().containsKey('lastConfirmed'), false);
      expect(
        jsonEncode(registry.snapshot()),
        isNot(contains('PRIVATE_STORAGE_FAILURE')),
      );
      beforeOwnerRead = null;
      expect(await app.list(await app.begin()), isEmpty);
      aiOwner = null;
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      aiOwner = 'a';
      expect(summary()['state'], 'list');
      final revisions = await db.select(db.personalSetRevisions).get();
      expect(revisions, hasLength(1));
      expect(
        (await app.list(await app.begin())).single.title,
        'Retry private set',
      );
      expect(registry.snapshot()['actions'], isEmpty);
    },
  );

  screenTest(
    'committed save confirmation failure retries without duplicate revision',
    (tester) async {
      String? aiOwner = 'a';
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      Map<String, dynamic> summary() =>
          jsonDecode(
                (registry.snapshot()['context'] as List).singleWhere(
                      (e) => e['id'] == 'study-planning/personal-sets/context',
                    )['value']
                    as String,
              )
              as Map<String, dynamic>;
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(home: PersonalSetsScreen(useCases: app)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างชุดคำ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('set-title')),
        'Retry private set',
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('ดูตัวอย่าง'));
      await tester.pumpAndSettle();
      var injected = false;
      beforeOwnerRead = () async {
        final rows = await db.select(db.personalSetRevisions).get();
        if (rows.isNotEmpty && !injected) {
          // Active-owner lookup runs when the list operation acquires its
          // lease, after the save operation has committed and returned.
          injected = true;
          throw StateError('PRIVATE_CONFIRMATION_FAILURE');
        }
      };
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      expect(injected, true);
      aiOwner = 'a';
      expect(summary()['state'], 'unconfirmed');
      expect(summary().containsKey('lastConfirmed'), false);
      expect(
        jsonEncode(registry.snapshot()),
        isNot(contains('PRIVATE_CONFIRMATION_FAILURE')),
      );
      beforeOwnerRead = null;
      final committed = await db.select(db.personalSetRevisions).get();
      expect(committed, hasLength(1));
      final committedPayload = committed.single.payloadHash;
      aiOwner = null;
      await tester.tap(find.text('บันทึกชุดคำ'));
      await tester.pumpAndSettle();
      aiOwner = 'a';
      expect(summary()['state'], 'list');
      final revisions = await db.select(db.personalSetRevisions).get();
      expect(revisions, hasLength(1));
      expect(revisions.single.payloadHash, committedPayload);
      expect(
        (await app.list(await app.begin())).single.title,
        'Retry private set',
      );
      expect(registry.snapshot()['actions'], isEmpty);
    },
  );

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
