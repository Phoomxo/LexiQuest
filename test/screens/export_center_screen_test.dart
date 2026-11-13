import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';

const _rewardKey = ValueKey<String>('export-rewards');
const _createKey = ValueKey<String>('export-create');
const _statusKey = ValueKey<String>('export-status');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ResearchConsentUseCases consent;
  late _MemoryStore store;
  late ExportUseCases exports;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    await owners.getOrCreateActiveOwner();
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    await consent.accept();
    store = _MemoryStore();
    exports = ExportUseCases(
      owners: owners,
      reader: DriftExportReader(database),
      store: store,
      nowUtc: () => DateTime.utc(2026, 10, 21, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: consent,
    );
    await database.customInsert(
      "INSERT INTO points_ledger_entries VALUES "
      "('legacy-export', 'local:owner', 'legacy-export', 'learning', 5, NULL, 1)",
    );
  });

  tearDown(() => database.close());

  testWidgets('reward export is default-off and limited to CSV and PDF', (
    tester,
  ) async {
    await _pumpExport(tester, exports);

    expect(_rewardTile(tester).value, isFalse);
    await tester.tap(find.byKey(_rewardKey));
    await tester.pump();
    expect(_rewardTile(tester).value, isTrue);

    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(find.byKey(_rewardKey), findsOneWidget);

    await tester.tap(find.text('Anki'));
    await tester.pump();
    expect(find.byKey(_rewardKey), findsNothing);
    await tester.tap(find.text('CSV'));
    await tester.pump();
    expect(_rewardTile(tester).value, isFalse);

    await tester.tap(find.byKey(_rewardKey));
    await tester.pump();
    await tester.tap(find.text('งานวิจัย'));
    await tester.pump();
    expect(find.byKey(_rewardKey), findsNothing);
    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(_rewardTile(tester).value, isFalse);
  });

  testWidgets('reward-only personal CSV works after research withdrawal', (
    tester,
  ) async {
    await tester.runAsync(consent.withdraw);
    final rowsBefore = (await tester.runAsync(
      () => database.select(database.researchConsents).get(),
    ))!;
    await _pumpExport(tester, exports);

    for (final label in ['คลังคำศัพท์', 'ประวัติคำตอบ', 'ประวัติการอ่าน']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    await tester.tap(find.byKey(_rewardKey));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(_createKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(_createKey));
    await _waitFor(tester, () => store.saved != null);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(_statusKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final artifact = store.saved;
    expect(artifact, isNotNull);
    expect(artifact!.format, ExportFormat.csv);
    expect(artifact.schemaVersion, 2);
    expect(artifact.recordCount, 1);
    expect(utf8.decode(artifact.bytes), contains('coin_balance='));
    expect((await tester.runAsync(consent.load))!.accepted, isFalse);
    expect(
      await tester.runAsync(
        () => database.select(database.researchConsents).get(),
      ),
      hasLength(rowsBefore.length),
    );
    expect(_liveRegion(tester, _statusKey), isTrue);
  });

  testWidgets('research format clears reward selection before consent check', (
    tester,
  ) async {
    await tester.runAsync(consent.withdraw);
    await _pumpExport(tester, exports);

    await tester.tap(find.byKey(_rewardKey));
    await tester.pump();
    await tester.tap(find.text('งานวิจัย'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(_createKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(_createKey));
    await _waitFor(
      tester,
      () => find.textContaining('รูปแบบงานวิจัย').evaluate().isNotEmpty,
    );

    expect(find.textContaining('ความยินยอมงานวิจัย'), findsOneWidget);
    expect(find.textContaining('ระบบบันทึกไฟล์ไม่พร้อมใช้งาน'), findsNothing);
    expect(store.saved, isNull);
  });

  testWidgets('empty export explains the next step without statistics jargon', (
    tester,
  ) async {
    await _pumpExport(tester, exports);
    await tester.scrollUntilVisible(
      find.byKey(_createKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(_createKey));
    await _waitFor(tester, () => find.byKey(_createKey).evaluate().isNotEmpty);
    await tester.scrollUntilVisible(
      find.byKey(_statusKey),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('ยังไม่มีข้อมูลสำหรับรูปแบบที่เลือก'), findsOneWidget);
    expect(find.textContaining('N=0'), findsNothing);
    expect(store.saved, isNull);
  });

  testWidgets('export supports 360x800 at 200 percent text', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpExport(tester, exports, textScale: 2);
    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(_rewardKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getSize(find.byKey(_rewardKey)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.scrollUntilVisible(
      find.byKey(_createKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getSize(find.byKey(_createKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpExport(
  WidgetTester tester,
  ExportUseCases exports, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ExportCenterScreen(key: UniqueKey(), exports: exports),
    ),
  );
  await tester.pumpAndSettle();
}

CheckboxListTile _rewardTile(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(find.byKey(_rewardKey));

bool _liveRegion(WidgetTester tester, Key statusKey) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(of: find.byKey(statusKey), matching: find.byType(Semantics))
        .first,
  );
  return semantics.properties.liveRegion == true;
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (condition()) return;
  }
  fail('Timed out waiting for export result: ${tester.takeException()}');
}

final class _MemoryStore implements ExportArtifactStore {
  ExportArtifact? saved;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    saved = artifact;
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
}
