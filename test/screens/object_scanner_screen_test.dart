import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/services/object_vocabulary_database.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  Future<void> openSelectedSetScanner(
    WidgetTester tester,
    _FakeScanner scanner, {
    AppDependencies? dependencies,
    String categoryId = 'category:travel',
    String categoryName = 'ชุดทดสอบ',
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final word = await Navigator.of(context).push<VocabularyWord>(
                MaterialPageRoute<VocabularyWord>(
                  builder: (_) => ObjectScannerScreen(
                    scanner: scanner,
                    voice: VoiceUseCases(_FakeVoice()),
                    targetCategoryId: categoryId,
                    targetCategoryName: categoryName,
                  ),
                ),
              );
              if (context.mounted && word != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('กลับชุด ${word.categoryId}')),
                );
              }
            },
            child: const Text('ถ่ายภาพเพิ่มคำในชุด'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      dependencies == null
          ? app
          : AppDependenciesScope(dependencies: dependencies, child: app),
    );
    await tester.tap(find.text('ถ่ายภาพเพิ่มคำในชุด'));
    await _pumpUntilManual(
      tester,
      find.byKey(const ValueKey('camera-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
  }

  Future<
    ({
      AppDatabase database,
      AppDependencies dependencies,
      _FakeScanner scanner,
      String categoryA,
      String categoryB,
      String ownerId,
      _ControlledVocabularyRepository repository,
    })
  >
  manualFixture() async {
    final database = AppDatabase(NativeDatabase.memory());
    var sequence = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'manual-owner-${++sequence}',
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    final owner = await owners.getOrCreateActiveOwner();
    final delegate = DriftVocabularyRepository(database);
    final seed = VocabularyUseCases(
      owners: owners,
      vocabulary: delegate,
      generateId: () => 'manual-${++sequence}',
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    final categoryA = await seed.createCategory('ชุด A');
    final categoryB = await seed.createCategory('ชุด B');
    final repository = _ControlledVocabularyRepository(delegate);
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: repository,
      generateId: () => 'manual-${++sequence}',
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    final scanner = _FakeScanner()
      ..captureResult = ObjectScanResult(
        classifications: const [
          ModelClassification(index: 1, label: 'wombat', confidence: 0.152),
        ],
        vocabulary: null,
        matchedClassification: null,
        modelId: 'model',
        modelVersion: 'model-v1',
        capturedAtUtc: DateTime.utc(2026, 11, 14),
      );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _UnusedGuestSession(),
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      objectScanner: scanner,
    );
    return (
      database: database,
      dependencies: dependencies,
      scanner: scanner,
      categoryA: categoryA.id,
      categoryB: categoryB.id,
      ownerId: owner.id,
      repository: repository,
    );
  }

  Future<void> enterManualWord(WidgetTester tester) async {
    await _pumpUntilManual(tester, find.byKey(const ValueKey('word-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('word-field')), 'mug');
    await tester.enterText(find.byKey(const ValueKey('meaning-field')), 'แก้ว');
    await tester.enterText(
      find.byKey(const ValueKey('part-of-speech-field')),
      'noun',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-word')));
  }

  Future<void> disposeManualFixture(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'unmapped scan opens an editable draft and saves only the selected set',
    (tester) async {
      final fixture = (await tester.runAsync(manualFixture))!;
      try {
        await openSelectedSetScanner(
          tester,
          fixture.scanner,
          dependencies: fixture.dependencies,
          categoryId: fixture.categoryA,
          categoryName: 'ชุด A',
        );
        expect(find.text('เพิ่มเข้าคลัง'), findsNothing);
        await tester.tap(find.text('กรอกคำเอง'));
        await _pumpUntilManual(tester, find.byType(AddWordScreen));
        await tester.pumpAndSettle();
        expect(find.text('เก็บในชุด ชุด A'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('word-field')))
              .controller!
              .text,
          'wombat',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('part-of-speech-field')),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          isEmpty,
        );
        await enterManualWord(tester);
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilManual(
          tester,
          find.text('กลับชุด ${fixture.categoryA}'),
        );
        final words = await tester.runAsync(
          () => fixture.database.select(fixture.database.vocabularyWords).get(),
        );
        expect(words, hasLength(1));
        expect(words!.single.categoryId, fixture.categoryA);
        expect(words.single.ownerId, fixture.ownerId);
        expect(words.single.spelling, 'mug');
        expect(words.single.meaning, 'แก้ว');
        expect(words.single.source, 'object-scanner:manualCorrection');
        expect(fixture.scanner.acceptCalls, 0);
        expect(fixture.scanner.captureResult!.vocabulary, isNull);
      } finally {
        await disposeManualFixture(tester, fixture.database);
      }
    },
  );

  testWidgets(
    'cancelling manual correction resumes the unchanged scan without writes',
    (tester) async {
      final fixture = (await tester.runAsync(manualFixture))!;
      try {
        await openSelectedSetScanner(
          tester,
          fixture.scanner,
          dependencies: fixture.dependencies,
          categoryId: fixture.categoryA,
        );
        await tester.tap(find.text('กรอกคำเอง'));
        await _pumpUntilManual(tester, find.byType(AddWordScreen));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await _pumpUntilManual(tester, find.text('กรอกคำเอง'));
        await tester.pumpAndSettle();
        expect(find.text('wombat'), findsOneWidget);
        expect(fixture.scanner.resumeCalls, 1);
        expect(fixture.scanner.acceptCalls, 0);
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          isEmpty,
        );
      } finally {
        await disposeManualFixture(tester, fixture.database);
      }
    },
  );

  testWidgets(
    'mapped wrong guess can be corrected without accepting the model word',
    (tester) async {
      final fixture = (await tester.runAsync(manualFixture))!;
      fixture.scanner.captureResult = null;
      try {
        await openSelectedSetScanner(
          tester,
          fixture.scanner,
          dependencies: fixture.dependencies,
          categoryId: fixture.categoryA,
        );
        expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
        await tester.tap(find.text('กรอกคำเอง'));
        await _pumpUntilManual(tester, find.byType(AddWordScreen));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('word-field')))
              .controller!
              .text,
          'apple',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
              .controller!
              .text,
          isEmpty,
        );
        await enterManualWord(tester);
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilManual(
          tester,
          find.text('กลับชุด ${fixture.categoryA}'),
        );
        final words = await tester.runAsync(
          () => fixture.database.select(fixture.database.vocabularyWords).get(),
        );
        expect(words, hasLength(1));
        expect(words!.single.spelling, 'mug');
        expect(words.single.categoryId, fixture.categoryA);
        expect(words.single.source, 'object-scanner:manualCorrection');
        expect(fixture.scanner.acceptCalls, 0);
      } finally {
        await disposeManualFixture(tester, fixture.database);
      }
    },
  );

  testWidgets('no confident scan still opens a blank manual draft', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(manualFixture))!;
    fixture.scanner.captureFailure = const CameraPracticeException(
      CameraFailureCode.noConfidentMatch,
    );
    try {
      await openSelectedSetScanner(
        tester,
        fixture.scanner,
        dependencies: fixture.dependencies,
        categoryId: fixture.categoryA,
      );
      expect(find.text('wombat'), findsNothing);
      await tester.tap(find.text('กรอกคำเอง'));
      await _pumpUntilManual(tester, find.byType(AddWordScreen));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('word-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => fixture.database.select(fixture.database.vocabularyWords).get(),
        ),
        isEmpty,
      );
      expect(fixture.scanner.acceptCalls, 0);
    } finally {
      await disposeManualFixture(tester, fixture.database);
    }
  });

  testWidgets('manual correction rejects an owner change before Save', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(manualFixture))!;
    try {
      await openSelectedSetScanner(
        tester,
        fixture.scanner,
        dependencies: fixture.dependencies,
        categoryId: fixture.categoryA,
      );
      await tester.tap(find.text('กรอกคำเอง'));
      await enterManualWord(tester);
      await tester.runAsync(() async {
        await fixture.database.customStatement(
          'UPDATE local_owners SET is_active = 0',
        );
        await fixture.database
            .into(fixture.database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'manual-switched-owner',
                createdAtUtcMs: DateTime.utc(
                  2026,
                  11,
                  14,
                ).millisecondsSinceEpoch,
              ),
            );
      });
      await tester.tap(find.byKey(const ValueKey('save-word')));
      await _pumpUntilManual(
        tester,
        find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
      );
      expect(
        await tester.runAsync(
          () => fixture.database.select(fixture.database.vocabularyWords).get(),
        ),
        isEmpty,
      );
      expect(fixture.scanner.acceptCalls, 0);
    } finally {
      await disposeManualFixture(tester, fixture.database);
    }
  });

  testWidgets(
    'manual draft rejects a replacement scope with unavailable owners before writing',
    (tester) async {
      final fixture = (await tester.runAsync(manualFixture))!;
      try {
        await openSelectedSetScanner(
          tester,
          fixture.scanner,
          dependencies: fixture.dependencies,
          categoryId: fixture.categoryA,
        );
        await tester.tap(find.text('กรอกคำเอง'));
        await _pumpUntilManual(tester, find.byType(AddWordScreen));
        await tester.pumpAndSettle();
        final editor = tester.state(find.byType(AddWordScreen));
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        final before = await tester.runAsync(
          () =>
              fixture.database.select(fixture.database.outboxOperations).get(),
        );
        final replacement = AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.unavailable,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _UnusedGuestSession(),
        );
        await tester.pumpWidget(
          AppDependenciesScope(dependencies: replacement, child: app),
        );
        expect(tester.state(find.byType(AddWordScreen)), same(editor));
        await enterManualWord(tester);
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilManual(
          tester,
          find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
        );
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          isEmpty,
        );
        final after = await tester.runAsync(
          () =>
              fixture.database.select(fixture.database.outboxOperations).get(),
        );
        expect(
          after!.map((row) => row.toJson()).toList(),
          before!.map((row) => row.toJson()).toList(),
        );
        expect(tester.state(find.byType(AddWordScreen)), same(editor));
        expect(find.text('กลับชุด ${fixture.categoryA}'), findsNothing);
      } finally {
        await disposeManualFixture(tester, fixture.database);
      }
    },
  );

  testWidgets('manual correction opens once and guards pending Save and Back', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(manualFixture))!;
    try {
      fixture.repository.pendingSave = Completer<void>();
      await openSelectedSetScanner(
        tester,
        fixture.scanner,
        dependencies: fixture.dependencies,
        categoryId: fixture.categoryA,
      );
      final launch = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'กรอกคำเอง'),
      );
      launch.onPressed!();
      launch.onPressed!();
      await enterManualWord(tester);
      expect(find.byType(AddWordScreen), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('save-word')),
      );
      save.onPressed!();
      save.onPressed!();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(fixture.repository.createCalls, 1);
      await tester.pageBack();
      await tester.pump();
      expect(find.byType(AddWordScreen), findsOneWidget);
      fixture.repository.pendingSave!.complete();
      await _pumpUntilManual(tester, find.text('กลับชุด ${fixture.categoryA}'));
      expect(
        await tester.runAsync(
          () => fixture.database.select(fixture.database.vocabularyWords).get(),
        ),
        hasLength(1),
      );
      expect(fixture.scanner.acceptCalls, 0);
    } finally {
      final pending = fixture.repository.pendingSave;
      if (pending != null && !pending.isCompleted) pending.complete();
      await disposeManualFixture(tester, fixture.database);
    }
  });

  testWidgets(
    'manual correction retains edited fields after a failed write for retry',
    (tester) async {
      final fixture = (await tester.runAsync(manualFixture))!;
      try {
        fixture.repository.failNextSave = true;
        await openSelectedSetScanner(
          tester,
          fixture.scanner,
          dependencies: fixture.dependencies,
          categoryId: fixture.categoryA,
        );
        await tester.tap(find.text('กรอกคำเอง'));
        await enterManualWord(tester);
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilManual(tester, find.text('บันทึกคำศัพท์ไม่สำเร็จ'));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('word-field')))
              .controller!
              .text,
          'mug',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('meaning-field')))
              .controller!
              .text,
          'แก้ว',
        );
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          isEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilManual(
          tester,
          find.text('กลับชุด ${fixture.categoryA}'),
        );
        expect(fixture.repository.createCalls, 2);
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          hasLength(1),
        );
      } finally {
        await disposeManualFixture(tester, fixture.database);
      }
    },
  );

  testWidgets('selected-set confirmation returns the saved word to its set', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await openSelectedSetScanner(tester, scanner);

    expect(find.text('เก็บในชุด ชุดทดสอบ'), findsOneWidget);
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(scanner.acceptedCategoryId, 'category:travel');
    expect(scanner.acceptCalls, 1);
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
    expect(find.byType(ObjectScannerScreen), findsNothing);
  });

  testWidgets('pending confirmation blocks repeated taps capture and Back', (
    tester,
  ) async {
    final scanner = _FakeScanner()..pendingAccept = Completer<void>();
    await openSelectedSetScanner(tester, scanner);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'เพิ่มเข้าคลัง'),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pump();

    expect(scanner.acceptCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('object-scanner-capture-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(ObjectScannerScreen), findsOneWidget);

    scanner.pendingAccept!.complete();
    await tester.pumpAndSettle();
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
  });

  testWidgets('failed confirmation keeps the proposal for a safe retry', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..acceptFailure = StateError('synthetic save failure');
    await openSelectedSetScanner(tester, scanner);
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(
      find.text('บันทึกคำศัพท์ไม่สำเร็จ กรุณาลองอีกครั้ง'),
      findsOneWidget,
    );
    expect(find.text('บันทึกแล้ว'), findsNothing);
    scanner.acceptFailure = null;
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();
    expect(scanner.acceptCalls, 2);
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
  });

  for (final selectedSet in [false, true]) {
    testWidgets(
      'owner switch stops confirmation before the scanner writes $selectedSet',
      (tester) async {
        final scanner = _FakeScanner();
        final owners = _MutableOwners();
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
              guestSessionService: _UnusedGuestSession(),
              localOwners: owners,
            ),
            child: MaterialApp(
              home: ObjectScannerScreen(
                scanner: scanner,
                voice: VoiceUseCases(_FakeVoice()),
                targetCategoryId: selectedSet ? 'category:travel' : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await tester.pumpAndSettle();
        owners.ownerId = 'owner:other';

        await tester.tap(find.text('เพิ่มเข้าคลัง'));
        await tester.pumpAndSettle();

        expect(scanner.acceptCalls, 0);
        expect(
          find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
          findsOneWidget,
        );
        expect(find.text('บันทึกแล้ว'), findsNothing);
      },
    );
  }

  testWidgets('captures real adapter result and persists accepted vocabulary', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('object-scanner-simulate-button')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(find.textContaining('91.0%'), findsOneWidget);
    expect(find.text('ผลจากโมเดลสแกนวัตถุในอุปกรณ์'), findsOneWidget);
    expect(find.textContaining('model-v1'), findsNothing);

    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(scanner.acceptCalls, 1);
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
  });

  testWidgets('shows honest permanent camera permission failure', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.permissionPermanentlyDenied,
      );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('สิทธิ์กล้องถูกปิดถาวร'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('object-scanner-error')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ถ่ายภาพและวิเคราะห์'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('เปิดศูนย์สิทธิ์อุปกรณ์'), findsOneWidget);
  });

  testWidgets('retries one transient camera initialization failure', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.initializationFailed,
      );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('object-scanner-retry-camera')),
      200,
    );
    expect(find.text('ลองเปิดกล้องอีกครั้ง'), findsOneWidget);

    scanner.initializeFailure = null;
    await tester.tap(find.text('ลองเปิดกล้องอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(scanner.initializeCalls, 2);
    expect(scanner.isReady, isTrue);
  });

  testWidgets('clears stale results and retries an uncertain scan', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);

    scanner.captureFailure = const CameraPracticeException(
      CameraFailureCode.captureFailed,
    );
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsNothing);
    expect(find.text('เพิ่มเข้าคลัง'), findsNothing);
    expect(find.text('ถ่ายภาพหรือวิเคราะห์ไม่สำเร็จ'), findsOneWidget);

    scanner.captureFailure = const CameraPracticeException(
      CameraFailureCode.noConfidentMatch,
    );
    final capture = find.byKey(const ValueKey('object-scanner-capture-button'));
    await tester.tap(capture);
    await tester.pumpAndSettle();

    final guidance = find.text(
      'ยังระบุวัตถุไม่ได้ ลองเพิ่มแสงและถ่ายวัตถุทีละชิ้น',
    );
    expect(guidance, findsOneWidget);
    expect(find.text('รูปภาพนี้ไม่สามารถนำมาวิเคราะห์ได้'), findsNothing);
    expect(find.text('เพิ่มเข้าคลัง'), findsNothing);

    scanner.captureFailure = null;
    await tester.tap(capture);
    await tester.pumpAndSettle();
    expect(guidance, findsNothing);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
  });

  testWidgets('releases and restores camera across app lifecycle', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scanner.pauseCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scanner.resumeCalls, 1);
    expect(scanner.isReady, isTrue);
  });

  testWidgets('offers verified model download when no active model exists', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.modelUnavailable,
      );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('object-scanner-download-model')),
      findsOneWidget,
    );
    expect(find.textContaining('ยังไม่มีโมเดลที่ตรวจสอบแล้ว'), findsOneWidget);
  });
  testWidgets('runs bounded CPU and XNNPACK benchmarks on demand', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('object-scanner-benchmark-model')),
    );
    await tester.pumpAndSettle();

    expect(scanner.benchmarkCalls, 1);
    expect(find.textContaining('โหมดมาตรฐาน · ทดสอบ 10 ครั้ง'), findsOneWidget);
    expect(
      find.textContaining('โหมดเร่งความเร็ว · ทดสอบ 10 ครั้ง'),
      findsOneWidget,
    );
    expect(find.textContaining('XNNPACK'), findsNothing);
    expect(find.textContaining('90% ไม่เกิน'), findsNWidgets(2));
  });

  for (final size in const [Size(360, 800), Size(412, 915), Size(800, 360)]) {
    testWidgets('scanner result actions remain reachable at 2x on $size', (
      tester,
    ) async {
      final scanner = _FakeScanner();
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ObjectScannerScreen(
              scanner: scanner,
              voice: VoiceUseCases(_FakeVoice()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final capture = find.byKey(
        const ValueKey('object-scanner-capture-button'),
      );
      await tester.scrollUntilVisible(capture, 200);
      await tester.tap(capture);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('เพิ่มเข้าคลัง'), 200);

      expect(find.text('ฟังเสียง'), findsOneWidget);
      expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
      final title = find.text('สแกนวัตถุ');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scanner route title stays readable with Back at 2x', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scanner = _FakeScanner();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ObjectScannerScreen(
                    scanner: scanner,
                    voice: VoiceUseCases(_FakeVoice()),
                  ),
                ),
              ),
              child: const Text('เปิดเครื่องสแกน'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดเครื่องสแกน'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    final title = find.text('สแกนวัตถุ');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
    expect(tester.takeException(), isNull);
  });
}

final class _FakeScanner implements ObjectScannerController {
  CameraPracticeException? initializeFailure;
  CameraPracticeException? captureFailure;
  int acceptCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int benchmarkCalls = 0;
  int initializeCalls = 0;
  String? acceptedCategoryId;
  Completer<void>? pendingAccept;
  Object? acceptFailure;
  ObjectScanResult? captureResult;
  @override
  bool isReady = false;

  @override
  Future<VocabularyWord> accept(
    ObjectScanResult result, {
    String? categoryId,
    String? expectedOwnerId,
  }) async {
    acceptCalls += 1;
    acceptedCategoryId = categoryId;
    await pendingAccept?.future;
    final failure = acceptFailure;
    if (failure != null) throw failure;
    return VocabularyWord(
      id: 'word:apple',
      ownerId: 'owner:1',
      categoryId: categoryId ?? 'category:food',
      spelling: 'apple',
      normalizedSpelling: 'apple',
      meaning: 'แอปเปิล',
      normalizedMeaning: 'แอปเปิล',
      partOfSpeech: 'noun',
      cefrLevel: 'A1',
      source: 'object-scanner:model@model-v1',
      isGlobal: false,
      localRevision: 1,
      isDeleted: false,
      createdAtUtc: DateTime.utc(2026, 7, 30),
      updatedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('camera-preview'), color: Colors.black);

  @override
  Future<ModelDownloadRecord> downloadModel({
    ModelCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<ModelDownloadRecord?> modelStatus() async => null;

  @override
  Future<List<ModelBenchmarkResult>> benchmarkModel({
    String deviceTier = 'field-device',
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) async {
    benchmarkCalls += 1;
    return const [
      ModelBenchmarkResult(
        delegate: ModelDelegate.cpu,
        modelId: 'model',
        modelVersion: 'model-v1',
        deviceTier: 'field-device',
        sampleSize: 10,
        medianMicros: 1000,
        p90Micros: 1200,
        minimumMicros: 900,
        maximumMicros: 1300,
        peakWorkingSetBytes: 1000000,
      ),
      ModelBenchmarkResult(
        delegate: ModelDelegate.xnnpack,
        modelId: 'model',
        modelVersion: 'model-v1',
        deviceTier: 'field-device',
        sampleSize: 10,
        medianMicros: 500,
        p90Micros: 700,
        minimumMicros: 450,
        maximumMicros: 750,
        peakWorkingSetBytes: 1100000,
      ),
    ];
  }

  @override
  Future<ObjectScanResult> captureAndClassify({
    ModelCancellation? cancellation,
  }) async {
    final failure = captureFailure;
    if (failure != null) throw failure;
    final result = captureResult;
    if (result != null) return result;
    return ObjectScanResult(
      classifications: const [
        ModelClassification(index: 1, label: 'Apple', confidence: 0.91),
      ],
      vocabulary: const ScannedVocabulary(
        mlLabel: 'Apple',
        englishWord: 'apple',
        thaiTranslation: 'แอปเปิล',
        cefrLevel: 'A1',
        phonetic: '/apple/',
        exampleSentence: 'I eat an apple.',
        category: 'Food',
      ),
      matchedClassification: const ModelClassification(
        index: 1,
        label: 'Apple',
        confidence: 0.91,
      ),
      modelId: 'model',
      modelVersion: 'model-v1',
      capturedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    final failure = initializeFailure;
    if (failure != null) throw failure;
    isReady = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    isReady = false;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    isReady = true;
  }
}

final class _MutableOwners extends Fake implements LocalOwnerRepository {
  String ownerId = 'owner:1';

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026, 11, 13));
}

final class _UnusedGuestSession extends Fake implements GuestSessionService {}

final class _ControlledVocabularyRepository extends Fake
    implements VocabularyRepository {
  _ControlledVocabularyRepository(this.delegate);
  final VocabularyRepository delegate;
  Completer<void>? pendingSave;
  bool failNextSave = false;
  int createCalls = 0;

  @override
  Future<VocabularyWord> createWord(VocabularyWord word) async {
    createCalls++;
    await pendingSave?.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('synthetic manual save failure');
    }
    return delegate.createWord(word);
  }
}

Future<void> _pumpUntilManual(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 100; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Manual correction did not reach $finder');
}

final class _FakeVoice implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}
