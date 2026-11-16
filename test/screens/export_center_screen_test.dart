import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

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

  testWidgets('replacement export scope dispatches only to B', (tester) async {
    final a = _ScopedExport('A');
    final b = _ScopedExport('B');
    await _pumpExportScope(tester, _exportDependencies(a.exports));
    final state = tester.state(find.byType(ExportCenterScreen));
    await _pumpExportScope(tester, _exportDependencies(b.exports));
    expect(tester.state(find.byType(ExportCenterScreen)), same(state));
    await _startExport(tester);
    await _waitFor(
      tester,
      () => a.store.saved != null || b.store.saved != null,
    );

    expect(a.reader.calls, 0);
    expect(a.store.calls, 0);
    expect(b.reader.calls, 1);
    expect(utf8.decode(b.store.saved!.bytes), contains('private-B'));
    expect(utf8.decode(b.store.saved!.bytes), isNot(contains('private-A')));
  });

  testWidgets('a missing replacement scope cannot fall back to injected A', (
    tester,
  ) async {
    final a = _ScopedExport('A');
    final app = MaterialApp(home: ExportCenterScreen(exports: a.exports));
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _exportDependencies(a.exports),
        child: app,
      ),
    );
    final state = tester.state(find.byType(ExportCenterScreen));
    await tester.pumpWidget(
      AppDependenciesScope(dependencies: _exportDependencies(null), child: app),
    );
    await tester.pump();
    expect(tester.state(find.byType(ExportCenterScreen)), same(state));
    await tester.scrollUntilVisible(
      find.byKey(_createKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<FilledButton>(find.byKey(_createKey));
    expect(button.onPressed, isNull);
    expect(a.reader.calls, 0);
    expect(a.store.calls, 0);
  });

  testWidgets(
    'missing replacement export drops A status and disables dispatch',
    (tester) async {
      final a = _ScopedExport('A');
      await _pumpExportScope(tester, _exportDependencies(a.exports));
      await _startExport(tester);
      await _waitFor(tester, () => a.store.saved != null);
      await tester.scrollUntilVisible(
        find.byKey(_statusKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(_statusKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_statusKey).hitTestable(), findsOneWidget);
      expect(find.textContaining('บันทึกแล้ว'), findsOneWidget);
      expect(a.store.calls, 1);
      expect(utf8.decode(a.store.saved!.bytes), contains('private-A'));

      await _pumpExportScope(tester, _exportDependencies(null));
      expect(find.byKey(_statusKey), findsNothing);
      expect(find.textContaining('บันทึกแล้ว'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('ระบบบันทึกไฟล์ไม่พร้อมใช้งาน'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('ระบบบันทึกไฟล์ไม่พร้อมใช้งาน'));
      await tester.pumpAndSettle();
      expect(find.text('ระบบบันทึกไฟล์ไม่พร้อมใช้งาน'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(_createKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(_createKey));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byKey(_createKey));
      expect(button.onPressed, isNull);
      expect(a.reader.calls, 1);
      expect(a.store.calls, 1);
    },
  );

  testWidgets(
    'replacement scope cancels A during its read before store dispatch',
    (tester) async {
      final a = _ScopedExport('A');
      final b = _ScopedExport('B');
      final read = Completer<ExportDataSet>();
      a.reader.pending = read;
      try {
        await _pumpExportScope(tester, _exportDependencies(a.exports));
        await _startExport(tester);
        await _waitFor(tester, () => a.reader.calls == 1);
        await _pumpExportScope(tester, _exportDependencies(b.exports));
        read.complete(_privateExportData('A'));
        await _waitFor(
          tester,
          () => find.byKey(_createKey).evaluate().isNotEmpty,
        );

        expect(a.store.calls, 0);
        expect(find.textContaining('บันทึกแล้ว'), findsNothing);
        await _startExport(tester);
        await _waitFor(
          tester,
          () => b.store.saved != null || a.store.calls > 0,
        );
        expect(b.store.saved, isNotNull);
        expect(a.reader.calls, 1);
        expect(a.store.calls, 0);
      } finally {
        if (!read.isCompleted) read.complete(_privateExportData('A'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  for (final reuseExports in [false, true]) {
    testWidgets(
      reuseExports
          ? 'replacement scope cancels a pending destination even with the same export service'
          : 'replacement scope cancels a pending A destination before external bytes',
      (tester) async {
        final a = _ScopedExport('A');
        final b = _ScopedExport('B');
        final destination = Completer<void>();
        a.store.destination = destination;
        try {
          await _pumpExportScope(tester, _exportDependencies(a.exports));
          await _startExport(tester);
          await _waitFor(tester, () => a.store.calls == 1);
          await _pumpExportScope(
            tester,
            _exportDependencies(reuseExports ? a.exports : b.exports),
          );
          destination.complete();
          await _waitFor(
            tester,
            () => find.byKey(_createKey).evaluate().isNotEmpty,
          );

          expect(a.store.saved, isNull);
          expect(a.store.cancellation!.isCancelled, isTrue);
          expect(find.textContaining('บันทึกแล้ว'), findsNothing);
          expect(b.reader.calls, 0);
          expect(b.store.calls, 0);
        } finally {
          if (!destination.isCompleted) destination.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }

  testWidgets(
    'injected export replacement dispatches only to its new service',
    (tester) async {
      final a = _ScopedExport('A');
      final b = _ScopedExport('B');
      await tester.pumpWidget(
        MaterialApp(home: ExportCenterScreen(exports: a.exports)),
      );
      await tester.pumpWidget(
        MaterialApp(home: ExportCenterScreen(exports: b.exports)),
      );
      await _startExport(tester);
      await _waitFor(
        tester,
        () => a.store.saved != null || b.store.saved != null,
      );
      expect(a.reader.calls, 0);
      expect(a.store.calls, 0);
      expect(b.store.saved, isNotNull);
    },
  );

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

Future<void> _pumpExportScope(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: const MaterialApp(home: ExportCenterScreen()),
    ),
  );
  await tester.pump();
}

Future<void> _startExport(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(_createKey),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(_createKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_createKey));
  await tester.pump();
}

AppDependencies _exportDependencies(ExportUseCases? exports) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _UnusedGuest(),
  exports: exports,
);

final class _UnusedGuest extends Fake implements GuestSessionService {}

final class _UnusedConsent extends Fake implements ResearchConsentRepository {}

final class _ScopedExport {
  _ScopedExport(String ownerId) {
    reader = _ScopedReader(ownerId);
    final owners = _ExportOwners(ownerId);
    exports = ExportUseCases(
      owners: owners,
      reader: reader,
      store: store,
      nowUtc: () => DateTime.utc(2026, 11, 14),
      loadThaiFont: () => throw StateError('CSV needs no font'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: _UnusedConsent(),
        nowUtc: () => DateTime.utc(2026, 11, 14),
      ),
    );
  }

  late final _ScopedReader reader;
  final store = _ScopedStore();
  late final ExportUseCases exports;
}

final class _ScopedReader implements ExportReader {
  _ScopedReader(this.ownerId);
  final String ownerId;
  int calls = 0;
  Completer<ExportDataSet>? pending;

  @override
  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    bool rewards = false,
  }) async {
    expect(ownerId, this.ownerId);
    calls++;
    return pending == null
        ? _privateExportData(ownerId)
        : await pending!.future;
  }
}

ExportDataSet _privateExportData(String ownerId) => ExportDataSet(
  vocabulary: [
    ExportVocabularyRow(
      id: 'word-$ownerId',
      category: 'category-$ownerId',
      spelling: 'private-$ownerId',
      meaning: 'synthetic-$ownerId',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'synthetic:export-scope-test',
    ),
  ],
  attempts: const [],
  reading: const [],
);

final class _ScopedStore implements ExportArtifactStore {
  int calls = 0;
  Completer<void>? destination;
  ExportCancellation? cancellation;
  ExportArtifact? saved;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    calls++;
    this.cancellation = cancellation;
    if (destination != null) await destination!.future;
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    cancellation.throwIfCancelled();
    saved = artifact;
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
}

final class _ExportOwners implements LocalOwnerRepository {
  _ExportOwners(this.id);
  final String id;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 11, 14));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}
