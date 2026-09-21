import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
// Explicitly synthetic local widget journeys. The native document picker is
// injected; real export generation, consent reads and temporary file bytes run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
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

void main() {
  for (final format in ExportFormat.values) {
    testWidgets('real export button saves readable ${format.name} bytes', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(_ExportFixture.create))!;
      try {
        if (format == ExportFormat.researchJson) {
          await tester.runAsync(fixture.consent.accept);
        }
        final registry = MenuActionRegistry(currentOwner: () => 'test');
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

  testWidgets('write failure has no success state and real retry saves once', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_ExportFixture.create))!;
    fixture.saver = (_) async => throw PlatformException(
      code: 'PERMISSION_DENIED',
      message: 'synthetic-private-detail-do-not-display',
    );
    try {
      await _open(tester, fixture);
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).contains('ไม่มีสิทธิ์'));
      expect(_status(tester), isNot(contains('บันทึกแล้ว')));
      expect(_status(tester), isNot(contains('synthetic-private-detail')));
      expect(await tester.runAsync(() => fixture.directory.list().length), 0);
      fixture.saver = null;
      await _tap(tester, find.text('สร้างและบันทึกไฟล์'));
      await _until(tester, () => _status(tester).startsWith('บันทึกแล้ว'));
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
    try {
      await _open(tester, fixture);
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
      expect(find.text('สร้างและบันทึกไฟล์'), findsNothing);
      expect(find.byType(RadioListTile<ExportFormat>), findsNWidgets(5));
      for (final radio in tester.widgetList<RadioListTile<ExportFormat>>(
        find.byType(RadioListTile<ExportFormat>),
      )) {
        expect(radio.enabled, isFalse);
      }
      await _tap(tester, find.text('ยกเลิก'));
      await _until(tester, () => _status(tester).contains('กำลังยกเลิก'));
      picker.complete(null);
      await _until(tester, () => _status(tester).contains('ยกเลิกการส่งออก'));
      expect(fixture.artifacts, hasLength(1));
      expect(await tester.runAsync(() => fixture.directory.list().length), 0);
    } finally {
      if (!picker.isCompleted) picker.complete(null);
      await _close(tester, fixture);
    }
  });
}

Future<void> _open(
  WidgetTester tester,
  _ExportFixture fixture, {
  MenuActionRegistry? registry,
}) async {
  await tester.pumpWidget(
    MenuActionScope(
      registry: registry ?? MenuActionRegistry(currentOwner: () => 'test'),
      child: MaterialApp(home: ExportCenterScreen(exports: fixture.exports)),
    ),
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
