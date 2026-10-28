import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
// Explicitly synthetic local widget journeys. The native document picker is
// injected; real export generation, consent reads and temporary file bytes run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'AD inherited dependency removal cancels preparation and retry uses restored service',
    (tester) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      final font = Completer<ByteData>();
      var preparing = false;
      final exports = _copyExports(
        fixture.exports,
        font: () {
          preparing = true;
          return font.future;
        },
      );
      final owners = DriftReviewOwnerIdentityReader(fixture.database);
      final registry = MenuActionRegistry(
        currentOwner: () => 'local:synthetic-ui-export-owner',
      );
      Future<void> mount(ExportUseCases? value) async {
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: AppDependenciesScope(
              dependencies: _dependencies(fixture, value, owners),
              child: const MaterialApp(home: ExportCenterScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      try {
        await mount(exports);
        await _choose(tester, ExportFormat.pdf);
        await _tap(tester, find.text('ประวัติการอ่าน'));
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => preparing);
        await mount(null);
        await _reveal(tester, find.text('สร้างและบันทึกไฟล์'));
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        font.complete(await fixture.exports.loadThaiFont());
        await tester.pumpAndSettle();
        expect(fixture.artifacts, isEmpty);
        await mount(fixture.exports);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
        expect(fixture.artifacts.single.format, ExportFormat.pdf);
        expect(_guidance(registry)['selection']['reading'], isFalse);
      } finally {
        if (!font.isCompleted) font.completeError(StateError('test cleanup'));
        await _close(tester, fixture);
      }
    },
  );

  testWidgets(
    'AD owner reader replacement cancels pending preparation without saving stale data',
    (tester) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      final font = Completer<ByteData>();
      var preparing = false;
      final exports = _copyExports(
        fixture.exports,
        font: () {
          preparing = true;
          return font.future;
        },
      );
      final owners = DriftReviewOwnerIdentityReader(fixture.database);
      final registry = MenuActionRegistry(
        currentOwner: () => 'local:synthetic-ui-export-owner',
      );
      try {
        await _mount(tester, exports, owners, registry);
        await _choose(tester, ExportFormat.pdf);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => preparing);
        await _mount(tester, exports, _UnavailableOwner(), registry);
        expect(registry.snapshot()['context'], isEmpty);
        font.complete(await fixture.exports.loadThaiFont());
        await tester.pumpAndSettle();
        expect(fixture.artifacts, isEmpty);
        expect(_status(tester), isEmpty);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
        expect(fixture.artifacts, hasLength(1));
        expect(registry.snapshot()['context'], isEmpty);
      } finally {
        if (!font.isCompleted) font.completeError(StateError('test cleanup'));
        await _close(tester, fixture);
      }
    },
  );

  for (final boundary in ['font', 'desktop-picker']) {
    testWidgets(
      'AD $boundary failure is private and explicitly retryable at 360px 200%',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(_ExportFixture.create))!;
        var fail = true;
        var calls = 0;
        final exports = _copyExports(
          fixture.exports,
          font: boundary == 'font'
              ? () async {
                  calls++;
                  if (fail) throw StateError('private-font-path');
                  return fixture.exports.loadThaiFont();
                }
              : null,
          store: boundary == 'desktop-picker'
              ? FileSelectorExportStore(
                  isAndroid: false,
                  desktopLocation: (artifact) async {
                    calls++;
                    if (fail) throw StateError('private-picker-path');
                    return File.fromUri(
                      fixture.directory.uri.resolve(artifact.suggestedFileName),
                    ).path;
                  },
                  temporaryDirectory: () async => fixture.directory,
                )
              : null,
        );
        final owners = DriftReviewOwnerIdentityReader(fixture.database);
        final registry = MenuActionRegistry(
          currentOwner: () => 'local:synthetic-ui-export-owner',
        );
        try {
          await _mount(tester, exports, owners, registry, large: true);
          await _choose(tester, ExportFormat.pdf);
          await _tap(tester, find.text('ประวัติคำตอบ'));
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _guidance(registry)['status'] == 'failed');
          await _reveal(
            tester,
            find.byKey(const ValueKey<String>('export-status')),
          );
          expect(_status(tester), contains('ลองอีกครั้ง'));
          expect(_status(tester), isNot(contains('private-')));
          expect(_guidance(registry).toString(), isNot(contains('private-')));
          expect(_guidance(registry)['selection']['attempts'], isFalse);
          expect(registry.snapshot()['actions'], isEmpty);
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            0,
          );
          await tester.pump(const Duration(seconds: 1));
          expect(calls, 1);
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _guidance(registry)['status'] == 'failed');
          expect(calls, 2);
          fail = false;
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
          expect(calls, 3);
          expect(_guidance(registry)['format'], 'pdf');
          expect(_guidance(registry)['selection']['attempts'], isFalse);
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            1,
          );
        } finally {
          await _close(tester, fixture);
        }
      },
    );
  }

  for (final late in ['success', 'failure']) {
    testWidgets(
      'AD replacement cancels old picker and fences late $late and callbacks',
      (tester) async {
        final fixture = (await tester.runAsync(_ExportFixture.create))!;
        final pending = Completer<String?>();
        final newPicker = Completer<String?>();
        var oldPickerCalls = 0;
        var oldWrites = 0;
        final oldExports = _copyExports(
          fixture.exports,
          store: FileSelectorExportStore(
            isAndroid: false,
            desktopLocation: (_) {
              oldPickerCalls++;
              return pending.future;
            },
            desktopSaver: (_, _) async {
              oldWrites++;
            },
            temporaryDirectory: () async => fixture.directory,
          ),
        );
        final owners = DriftReviewOwnerIdentityReader(fixture.database);
        final registry = MenuActionRegistry(
          currentOwner: () => 'local:synthetic-ui-export-owner',
        );
        try {
          await _mount(tester, oldExports, owners, registry);
          await _choose(tester, ExportFormat.anki);
          await _reveal(tester, find.text('สร้างและบันทึกไฟล์'));
          final oldStart = tester
              .widget<FilledButton>(find.byType(FilledButton))
              .onPressed!;
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => oldPickerCalls == 1);
          final oldCancel = tester
              .widget<OutlinedButton>(find.byType(OutlinedButton))
              .onPressed!;
          await _mount(tester, fixture.exports, owners, registry);
          expect(_guidance(registry)['status'], 'idle');
          expect(_guidance(registry)['format'], 'anki');
          oldStart();
          oldCancel();
          await tester.pump();
          expect(_guidance(registry)['status'], 'idle');
          expect(fixture.artifacts, isEmpty);
          fixture.saver = (_) => newPicker.future;
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => fixture.artifacts.isNotEmpty);
          if (late == 'success') {
            pending.complete(
              File.fromUri(fixture.directory.uri.resolve('stale.csv')).path,
            );
          } else {
            pending.completeError(StateError('private-stale-picker'));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(oldWrites, 0);
          expect(oldPickerCalls, 1);
          expect(_guidance(registry)['status'], 'running');
          oldCancel();
          await tester.pump();
          expect(_guidance(registry)['status'], 'running');
          newPicker.complete(null);
          await _until(
            tester,
            () => _guidance(registry)['failureCode'] == 'cancelled',
          );
          fixture.saver = null;
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
          expect(_guidance(registry)['status'], 'saved');
          expect(fixture.artifacts, hasLength(2));
        } finally {
          if (!pending.isCompleted) pending.complete(null);
          if (!newPicker.isCompleted) newPicker.complete(null);
          await _close(tester, fixture);
        }
      },
    );
  }

  testWidgets(
    'AD optional owner reader replacement rejects late identity and old status',
    (tester) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      final pending = Completer<String>();
      final oldOwners = _DeferredOwner(pending.future);
      final newOwners = _DeferredOwner(Future.value('new-guidance-owner'));
      var currentOwner = 'new-guidance-owner';
      final registry = MenuActionRegistry(currentOwner: () => currentOwner);
      try {
        await _mount(tester, fixture.exports, oldOwners, registry);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
        await _mount(tester, fixture.exports, newOwners, registry);
        expect(
          tester
              .widget<MenuActionBinding>(find.byType(MenuActionBinding))
              .ownerId,
          'new-guidance-owner',
        );
        expect(_guidance(registry)['status'], 'idle');
        expect(_status(tester), isEmpty);
        pending.complete('local:synthetic-ui-export-owner');
        await tester.pumpAndSettle();
        expect(_guidance(registry)['status'], 'idle');
        currentOwner = 'local:synthetic-ui-export-owner';
        registry.invalidateSession(preserveContext: true);
        expect(registry.snapshot()['context'], isEmpty);
        expect(fixture.artifacts, hasLength(1));
      } finally {
        if (!pending.isCompleted)
          pending.complete('local:synthetic-ui-export-owner');
        await _close(tester, fixture);
      }
    },
  );

  for (final late in ['success', 'failure']) {
    testWidgets(
      'AD route pop cancels pending preparation before transition ends ($late)',
      (tester) async {
        final fixture = (await tester.runAsync(_ExportFixture.create))!;
        final font = Completer<ByteData>();
        var fontCalls = 0;
        final exports = _copyExports(
          fixture.exports,
          font: () {
            fontCalls++;
            return font.future;
          },
        );
        final navigator = GlobalKey<NavigatorState>();
        final owners = DriftReviewOwnerIdentityReader(fixture.database);
        final registry = MenuActionRegistry(
          currentOwner: () => 'local:synthetic-ui-export-owner',
        );
        try {
          await tester.pumpWidget(
            MenuActionScope(
              registry: registry,
              child: MaterialApp(
                navigatorKey: navigator,
                home: const Scaffold(body: Text('home')),
              ),
            ),
          );
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ExportCenterScreen(exports: exports, ownerIdentities: owners),
            ),
          );
          await tester.pumpAndSettle();
          await _choose(tester, ExportFormat.pdf);
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => fontCalls == 1);
          final staleCancel = tester
              .widget<OutlinedButton>(find.byType(OutlinedButton))
              .onPressed!;
          navigator.currentState!.pop();
          // The outgoing state is still mounted during the reverse transition.
          expect(find.byType(ExportCenterScreen), findsOneWidget);
          if (late == 'success') {
            font.complete(await fixture.exports.loadThaiFont());
          } else {
            font.completeError(StateError('private-late-font'));
          }
          await tester.pump();
          await tester.pumpAndSettle();
          staleCancel();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(fixture.artifacts, isEmpty);
          expect(registry.snapshot()['context'], isEmpty);
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            0,
          );
        } finally {
          if (!font.isCompleted) font.completeError(StateError('test cleanup'));
          await _close(tester, fixture);
        }
      },
    );
  }

  for (final format in ExportFormat.values) {
    testWidgets('real export button saves readable ${format.name} bytes', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      try {
        if (format == ExportFormat.researchJson) {
          await tester.runAsync(fixture.consent.accept);
        }
        final registry = MenuActionRegistry(
          currentOwner: () => 'local:synthetic-ui-export-owner',
        );
        await _open(tester, fixture, registry: registry);
        await _choose(tester, format);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
        expect(fixture.artifacts, hasLength(1));
        final artifact = fixture.artifacts.single;
        expect(artifact.format, format);
        expect(artifact.bytes, isNotEmpty);
        final saved = File.fromUri(
          fixture.directory.uri.resolve(artifact.suggestedFileName),
        );
        final bytes = (await tester.runAsync(saved.readAsBytes))!;
        expect(bytes, orderedEquals(artifact.bytes));
        expect(_status(tester), contains(saved.path));
        final data = jsonDecode(
          (registry.snapshot()['context'] as List).single['value'] as String,
        );
        expect(data['status'], 'saved');
        expect(data.containsKey('path'), false);
        expect(data.toString(), isNot(contains(saved.path)));
        if (format == ExportFormat.anki) {
          expect(data['columns'], ['word', 'meaning', 'category', 'recordId']);
          final rows = const LineSplitter()
              .convert(utf8.decode(bytes))
              .where((line) => !line.startsWith('#'))
              .toList();
          expect(rows, hasLength(1));
          expect(
            rows.single.split('\t'),
            hasLength((data['columns'] as List).length),
          );
          expect(data['purpose'], contains('หมวดหมู่'));
          expect(data['purpose'], contains('รหัสรายการ'));
        }
        if (format == ExportFormat.csv) {
          await _tap(tester, find.text('คลังคำศัพท์'));
          final changed = jsonDecode(
            (registry.snapshot()['context'] as List).single['value'] as String,
          );
          expect(changed['status'], 'idle');
          expect(changed['selection']['vocabulary'], false);
          expect(fixture.artifacts, hasLength(1));
        }
        if (format == ExportFormat.pdf) {
          expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        } else {
          final content = utf8.decode(bytes).replaceFirst('\uFEFF', '');
          expect(content, contains('apple'));
          if (format == ExportFormat.researchJson ||
              format == ExportFormat.ownerArchiveJson) {
            expect(jsonDecode(content), isA<Map<String, dynamic>>());
          }
        }
      } finally {
        await _close(tester, fixture);
      }
    });
  }

  testWidgets('research consent blocks saving while personal archive works', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ExportFixture.create))!;
    try {
      await _open(tester, fixture);
      await _choose(tester, ExportFormat.researchJson);
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).contains('ยินยอม'));
      expect(fixture.artifacts, isEmpty);
      expect(await tester.runAsync(() => fixture.directory.list().length), 0);
      await _choose(tester, ExportFormat.ownerArchiveJson);
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
      expect(fixture.artifacts.single.format, ExportFormat.ownerArchiveJson);
      expect((await tester.runAsync(fixture.consent.load))!.accepted, isFalse);
    } finally {
      await _close(tester, fixture);
    }
  });

  testWidgets('picker cancel leaves no saved file and permits another export', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ExportFixture.create))!;
    fixture.saver = (_) async => null;
    try {
      await _open(tester, fixture);
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).contains('ยกเลิกการส่งออก'));
      expect(await tester.runAsync(() => fixture.directory.list().length), 0);
      fixture.saver = null;
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
      expect(fixture.artifacts, hasLength(2));
      expect(await tester.runAsync(() => fixture.directory.list().length), 1);
    } finally {
      await _close(tester, fixture);
    }
  });

  for (final failure in const [
    ('PERMISSION_DENIED', 'permissionDenied', 'ไม่มีสิทธิ์'),
    ('INSUFFICIENT_SPACE', 'insufficientSpace', 'พื้นที่จัดเก็บ'),
    ('UNAVAILABLE', 'unavailable', 'ไม่พร้อมใช้งาน'),
    ('CLEANUP_FAILED', 'cleanupFailed', 'อาจมีไฟล์ค้าง'),
    ('WRITE_FAILED', 'writeFailed', 'ยังยืนยัน'),
  ]) {
    testWidgets(
      'export ${failure.$1} context and disconnected retry save once',
      (tester) async {
        final fixture = (await tester.runAsync(_ExportFixture.create))!;
        fixture.saver = (_) async => throw PlatformException(
          code: failure.$1,
          message: 'synthetic-private-detail-do-not-display',
        );
        String? aiOwner = 'local:synthetic-ui-export-owner';
        final registry = MenuActionRegistry(currentOwner: () => aiOwner);
        try {
          await _open(tester, fixture, registry: registry);
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _status(tester).contains(failure.$3));
          expect(_status(tester), isNot(contains('บันทึกแล้ว')));
          expect(_status(tester), isNot(contains('synthetic-private-detail')));
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            0,
          );
          final failed = _guidance(registry);
          expect(failed['status'], 'failed');
          expect(failed['failureCode'], failure.$2);
          expect(
            failed.toString(),
            isNot(contains('synthetic-private-detail')),
          );
          expect(registry.snapshot()['actions'], isEmpty);
          aiOwner = null;
          registry.invalidateSession(preserveContext: true);
          await tester.pump();
          expect(registry.snapshot()['context'], isEmpty);
          fixture.saver = null;
          await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
          await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            1,
          );
          expect(registry.snapshot()['context'], isEmpty);
          aiOwner = 'local:synthetic-ui-export-owner';
          registry.invalidateSession(preserveContext: true);
          await tester.pump();
          final saved = _guidance(registry);
          expect(saved['status'], 'saved');
          expect(saved.containsKey('failureCode'), isFalse);
          expect(saved.toString(), isNot(contains(fixture.directory.path)));
          aiOwner = 'another-owner';
          registry.invalidateSession(preserveContext: true);
          await tester.pump();
          expect(registry.snapshot()['context'], isEmpty);
          expect(_status(tester), startsWith('บันทึกแล้ว'));
          expect(
            await tester.runAsync(() => fixture.directory.list().length),
            1,
          );
        } finally {
          await _close(tester, fixture);
        }
      },
    );
  }

  testWidgets(
    'export saved before first AI login attaches without rebuilding',
    (tester) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      String? aiOwner;
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      try {
        await _open(tester, fixture, registry: registry);
        expect(registry.snapshot()['context'], isEmpty);
        await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
        await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
        expect(registry.snapshot()['context'], isEmpty);
        aiOwner = 'local:synthetic-ui-export-owner';
        registry.invalidateSession(preserveContext: true);
        await tester.pump();
        expect(_guidance(registry)['status'], 'saved');
        expect(registry.snapshot()['actions'], isEmpty);
        expect(await tester.runAsync(() => fixture.directory.list().length), 1);
      } finally {
        await _close(tester, fixture);
      }
    },
  );

  testWidgets('optional owner lookup failure leaves native saving available', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ExportFixture.create))!;
    final registry = MenuActionRegistry(
      currentOwner: () => 'local:synthetic-ui-export-owner',
    );
    try {
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: ExportCenterScreen(
              exports: fixture.exports,
              ownerIdentities: _UnavailableOwner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
      expect(registry.snapshot()['context'], isEmpty);
      expect(registry.snapshot()['actions'], isEmpty);
      expect(await tester.runAsync(() => fixture.directory.list().length), 1);
    } finally {
      await _close(tester, fixture);
    }
  });

  testWidgets('pending export locks format and duplicate start then cancels', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ExportFixture.create))!;
    final picker = Completer<String?>();
    fixture.saver = (_) => picker.future;
    final registry = MenuActionRegistry(
      currentOwner: () => 'local:synthetic-ui-export-owner',
    );
    try {
      await _open(tester, fixture, registry: registry);
      final start = find.text('สร้างและบันทึกไฟล์');
      await _reveal(tester, start);
      await tester.pump();
      expect(start.hitTestable(), findsOneWidget);
      await tester.tap(start);
      // Before rebuilding, a second physical tap must not start another write.
      await tester.tap(start);
      await _until(tester, () => fixture.artifacts.isNotEmpty);
      await _reveal(tester, find.byKey(const ValueKey(ExportFormat.csv)), -200);
      expect(fixture.artifacts, hasLength(1));
      expect(_guidance(registry)['status'], 'running');
      expect(find.text('สร้างและบันทึกไฟล์'), findsNothing);
      expect(find.byType(RadioListTile<ExportFormat>), findsNWidgets(5));
      for (final radio in tester.widgetList<RadioListTile<ExportFormat>>(
        find.byType(RadioListTile<ExportFormat>),
      )) {
        expect(radio.enabled, isFalse);
      }
      await _tap(tester, find.text('ยกเลิก'));
      await _until(tester, () => _status(tester).contains('กำลังยกเลิก'));
      expect(_guidance(registry)['status'], 'cancelling');
      picker.complete(null);
      await _until(tester, () => _status(tester).contains('ยกเลิกการส่งออก'));
      expect(_guidance(registry)['status'], 'failed');
      expect(_guidance(registry)['failureCode'], 'cancelled');
      expect(fixture.artifacts, hasLength(1));
      expect(await tester.runAsync(() => fixture.directory.list().length), 0);
    } finally {
      if (!picker.isCompleted) picker.complete(null);
      await _close(tester, fixture);
    }
  });
}

ExportUseCases _copyExports(
  ExportUseCases source, {
  ExportFontLoader? font,
  ExportArtifactStore? store,
}) => ExportUseCases(
  reader: source.reader,
  store: store ?? source.store,
  nowUtc: source.nowUtc,
  loadThaiFont: font ?? source.loadThaiFont,
  lifecycleArchive: source.lifecycleArchive,
);

AppDependencies _dependencies(
  _ExportFixture fixture,
  ExportUseCases? exports,
  ReviewOwnerIdentityReader owners,
) {
  final research = InertResearchDependencies(fixture.database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    database: fixture.database,
    exports: exports,
    activeOwnerIdentities: owners,
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-export');
}

Future<void> _mount(
  WidgetTester tester,
  ExportUseCases exports,
  ReviewOwnerIdentityReader owners,
  MenuActionRegistry registry, {
  bool large = false,
}) async {
  await tester.pumpWidget(
    MenuActionScope(
      registry: registry,
      child: MaterialApp(
        builder: large
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: ExportCenterScreen(exports: exports, ownerIdentities: owners),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _until(tester, () => true);
}

final class _DeferredOwner implements ReviewOwnerIdentityReader {
  _DeferredOwner(this.result);
  final Future<String> result;
  @override
  Future<String> requireSingleActiveOwnerId() => result;
}

Future<void> _open(
  WidgetTester tester,
  _ExportFixture fixture, {
  MenuActionRegistry? registry,
}) async {
  await tester.pumpWidget(
    MenuActionScope(
      registry:
          registry ??
          MenuActionRegistry(
            currentOwner: () => 'local:synthetic-ui-export-owner',
          ),
      child: MaterialApp(
        home: ExportCenterScreen(
          exports: fixture.exports,
          ownerIdentities: DriftReviewOwnerIdentityReader(fixture.database),
        ),
      ),
    ),
  );
  await _until(
    tester,
    () =>
        tester
            .widget<MenuActionBinding>(find.byType(MenuActionBinding))
            .ownerId !=
        null,
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, ExportFormat format) async {
  final choice = find.byKey(ValueKey(format));
  await _reveal(tester, choice, -200);
  await _tap(tester, choice);
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, [
  double delta = 200,
]) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pump();
}

String _status(WidgetTester tester) {
  final status = find.byKey(const ValueKey<String>('export-status'));
  return status.evaluate().isEmpty ? '' : tester.widget<Text>(status).data!;
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var step = 0; step < 300; step++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    expect(tester.takeException(), isNull);
    if (done()) return;
    if (find.byType(ExportCenterScreen).evaluate().isNotEmpty &&
        find
            .byKey(const ValueKey<String>('export-status'))
            .evaluate()
            .isEmpty) {
      await tester.drag(find.byType(ListView), const Offset(0, -160));
    }
  }
  fail('Export UI did not reach expected state: ${_status(tester)}');
}

Future<void> _close(WidgetTester tester, _ExportFixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  var closed = false;
  Object? closeError;
  fixture.database.close().then(
    (_) => closed = true,
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  await _until(tester, () => closed);
  expect(closeError, isNull);
  await tester.runAsync(() async {
    final target = Directory(await fixture.directory.resolveSymbolicLinks());
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    expect(target.parent.path, temporaryRoot);
    expect(
      target.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
      startsWith('lexiquest-ui-export-'),
    );
    await target.delete(recursive: true);
  });
}

final class _ExportFixture {
  _ExportFixture(this.database, this.directory, this.consent);

  final AppDatabase database;
  final Directory directory;
  final ResearchConsentUseCases consent;
  final artifacts = <ExportArtifact>[];
  Future<String?> Function(ExportArtifact)? saver;
  late final ExportUseCases exports;

  static Future<_ExportFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-ui-export-',
    );
    final now = DateTime.utc(2026, 9, 8, 8);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-ui-export-owner',
      nowUtc: () => now,
    );
    await owners.getOrCreateActiveOwner();
    var id = 0;
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-ui-export-${id++}',
      nowUtc: () => now,
    );
    final category = await vocabulary.createCategory('ข้อมูลทดสอบสังเคราะห์');
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'apple',
        meaning: 'แอปเปิล',
        partOfSpeech: 'noun',
      ),
    );
    final consent = ResearchConsentUseCases(
      owners: owners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => now,
    );
    final fixture = _ExportFixture(database, directory, consent);
    fixture.exports = ExportUseCases(
      reader: DriftExportReader(database),
      store: FileSelectorExportStore(
        isAndroid: true,
        androidSaver: (artifact) async {
          fixture.artifacts.add(artifact);
          final saver = fixture.saver;
          if (saver != null) return saver(artifact);
          final destination = File.fromUri(
            directory.uri.resolve(artifact.suggestedFileName),
          );
          await destination.writeAsBytes(artifact.bytes, flush: true);
          return destination.path;
        },
      ),
      nowUtc: () => now,
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      lifecycleArchive: OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => now,
      ),
    );
    return fixture;
  }
}

Map<String, dynamic> _guidance(MenuActionRegistry registry) =>
    jsonDecode(
          (registry.snapshot()['context'] as List).single['value'] as String,
        )
        as Map<String, dynamic>;

final class _UnavailableOwner implements ReviewOwnerIdentityReader {
  @override
  Future<String> requireSingleActiveOwnerId() async =>
      throw StateError('synthetic owner lookup failure');
}
