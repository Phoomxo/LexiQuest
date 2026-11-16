import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/application/gemini_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/screens/gemini_settings_screen.dart';

Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pump();
}

void main() {
  testWidgets('loading state is announced', (tester) async {
    final gate = Completer<void>();
    final tutor = _FakeSettingsTutor()..loadGate = gate;
    await tester.pumpWidget(
      MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
    );
    await tester.pump();

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.semanticsLabel, 'กำลังโหลดการตั้งค่า Gemini');
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'real controller removal reloads credential status after its own invalidation',
    (tester) async {
      final store = _WidgetStore();
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: _WidgetGateway(),
        nowUtc: () => DateTime.utc(2026),
        readScope: () => const GeminiScope(
          ownerId: 'synthetic-owner',
          firebaseUid: null,
          isAnonymous: true,
        ),
      );
      addTearDown(tutor.dispose);
      await tutor.configure(
        key: 'synthetic-widget-key',
        providerConsent: true,
        shareLearningSummary: true,
      );
      await tester.pumpWidget(
        MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('gemini-remove-key'));
      await tester.scrollUntilVisible(
        remove,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ลบรหัส'));
      await tester.pumpAndSettle();
      final emptyStatus = find.text('สถานะ: ยังไม่มีรหัสเชื่อมต่อ');
      await _scrollTo(tester, emptyStatus, delta: -300);
      expect(emptyStatus, findsOneWidget);
      expect((await tutor.loadSettings()).hasKey, isFalse);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    },
  );
  testWidgets(
    'failed removal remains explicit after its own consent invalidation',
    (tester) async {
      final tutor = _FakeSettingsTutor()
        ..hasKey = true
        ..providerConsent = true
        ..invalidateOnRemove = true
        ..removeFailure = const GeminiException(
          GeminiFailureCode.secureStorage,
        );
      await tester.pumpWidget(
        MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('gemini-remove-key'));
      await tester.scrollUntilVisible(
        remove,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ลบรหัส'));
      await tester.pumpAndSettle();
      expect(
        find.text('ที่จัดเก็บปลอดภัยของอุปกรณ์ไม่พร้อมใช้งาน'),
        findsOneWidget,
      );
      expect(
        find.text('ลบรหัสเชื่อมต่อและปิดการส่งข้อมูลไป Gemini แล้ว'),
        findsNothing,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('สถานะ: มีรหัสเชื่อมต่อที่ตรวจสอบแล้ว'), findsOneWidget);
    },
  );
  testWidgets('validates and saves a key only after provider consent', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor();
    await tester.pumpWidget(
      MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('gemini-key-input')),
      'private-key-sentinel-that-is-long',
    );
    final saveKey = find.byKey(const ValueKey('gemini-save-key'));
    await _scrollTo(tester, saveKey);
    await tester.tap(saveKey);
    await tester.pumpAndSettle();
    final error = find.text('ต้องยืนยันการยินยอมก่อนบันทึกรหัส');
    expect(error, findsOneWidget);
    expect(
      find.ancestor(
        of: error,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(tutor.configuredKeys, isEmpty);

    final providerConsent = find.widgetWithText(
      CheckboxListTile,
      'ยินยอมส่งข้อความที่พิมพ์หรือพูดให้ Google Gemini',
    );
    await _scrollTo(tester, providerConsent, delta: -300);
    await tester.tap(providerConsent);
    await _scrollTo(tester, saveKey);
    await tester.tap(saveKey);
    await tester.pumpAndSettle();

    expect(tutor.configuredKeys, ['private-key-sentinel-that-is-long']);
    final notice = find.textContaining('เก็บรหัสในที่จัดเก็บปลอดภัย');
    expect(notice, findsOneWidget);
    expect(
      find.ancestor(
        of: notice,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('private-key-sentinel-that-is-long'), findsNothing);
  });

  testWidgets('route title stays readable with Back at 2x', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tutor = _FakeSettingsTutor();
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
                  builder: (_) => GeminiSettingsScreen(geminiTutor: tutor),
                ),
              ),
              child: const Text('เปิดการตั้งค่า Gemini'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดการตั้งค่า Gemini'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    final title = find.text('เชื่อมต่อ Gemini');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing key disables provider and summary consent', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor()
      ..hasKey = true
      ..providerConsent = true
      ..summaryConsent = true;
    await tester.pumpWidget(
      MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    final removeKey = find.byKey(const ValueKey('gemini-remove-key'));
    await tester.scrollUntilVisible(
      removeKey,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(removeKey);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ลบรหัส'));
    await tester.pumpAndSettle();

    expect(tutor.removeCalls, 1);
    final emptyStatus = find.text('สถานะ: ยังไม่มีรหัสเชื่อมต่อ');
    await _scrollTo(tester, emptyStatus, delta: -300);
    expect(emptyStatus, findsOneWidget);
  });

  testWidgets('shows distinct invalid key and quota failures', (tester) async {
    final tutor = _FakeSettingsTutor()
      ..configureFailure = const GeminiException(GeminiFailureCode.invalidKey);
    await tester.pumpWidget(
      MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.enterText(
      find.byKey(const ValueKey('gemini-key-input')),
      'invalid-key-that-is-long-enough',
    );
    final saveKey = find.byKey(const ValueKey('gemini-save-key'));
    await _scrollTo(tester, saveKey);
    await tester.tap(saveKey);
    await tester.pumpAndSettle();
    expect(find.textContaining('รหัสเชื่อมต่อไม่ถูกต้อง'), findsOneWidget);

    tutor.configureFailure = const GeminiException(GeminiFailureCode.quota);
    await _scrollTo(tester, saveKey);
    await tester.tap(saveKey);
    await tester.pumpAndSettle();
    expect(find.textContaining('โควตา'), findsOneWidget);
  });

  testWidgets(
    'leaving during key validation never reuses disposed controller',
    (tester) async {
      final gate = Completer<void>();
      final tutor = _FakeSettingsTutor()..configureGate = gate;
      await tester.pumpWidget(
        MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.enterText(
        find.byKey(const ValueKey('gemini-key-input')),
        'private-key-sentinel-that-is-long',
      );
      final saveKey = find.byKey(const ValueKey('gemini-save-key'));
      await _scrollTo(tester, saveKey);
      await tester.tap(saveKey);
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scope change clears key draft and ignores late configuration success',
    (tester) async {
      final gate = Completer<void>();
      final tutor = _FakeSettingsTutor()..configureGate = gate;
      await tester.pumpWidget(
        MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.enterText(
        find.byKey(const ValueKey('gemini-key-input')),
        'synthetic-A-key',
      );
      final saveKey = find.byKey(const ValueKey('gemini-save-key'));
      await _scrollTo(tester, saveKey);
      await tester.tap(saveKey);
      await tester.pump();
      tutor.changeScope();
      await tester.pumpAndSettle();
      final keyInput = find.byKey(const ValueKey('gemini-key-input'));
      await _scrollTo(tester, keyInput, delta: -300);
      expect(tester.widget<TextField>(keyInput).controller!.text, isEmpty);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('เก็บรหัสในที่จัดเก็บปลอดภัย'), findsNothing);
      final emptyStatus = find.text('สถานะ: ยังไม่มีรหัสเชื่อมต่อ');
      await _scrollTo(tester, emptyStatus, delta: -300);
      expect(emptyStatus, findsOneWidget);
    },
  );

  testWidgets(
    'delete confirmation from old scope cannot remove the new scope key',
    (tester) async {
      final tutor = _FakeSettingsTutor()
        ..hasKey = true
        ..providerConsent = true;
      await tester.pumpWidget(
        MaterialApp(home: GeminiSettingsScreen(geminiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final remove = find.byKey(const ValueKey('gemini-remove-key'));
      await tester.scrollUntilVisible(
        remove,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      tutor.changeScope();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ลบรหัส'));
      await tester.pumpAndSettle();
      expect(tutor.removeCalls, 0);
    },
  );
}

final class _WidgetStore implements GeminiSettingsStore {
  GeminiConfiguration value = const GeminiConfiguration();
  @override
  Future<GeminiConfiguration> read(GeminiScope scope) async => value;
  @override
  Future<void> write(
    GeminiScope scope,
    GeminiConfiguration configuration,
  ) async {
    value = configuration;
  }
}

final class _WidgetGateway implements GeminiGateway {
  @override
  String get model => 'synthetic';
  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}
  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async => 'Synthetic';
}

final class _FakeSettingsTutor implements GeminiTutorController {
  @override
  GeminiScope? scope = const GeminiScope(
    ownerId: 'synthetic-A',
    firebaseUid: null,
    isAnonymous: true,
  );
  @override
  int epoch = 0;
  final changes = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> get invalidations => changes.stream;
  void changeScope() {
    scope = const GeminiScope(
      ownerId: 'synthetic-B',
      firebaseUid: null,
      isAnonymous: true,
    );
    hasKey = false;
    providerConsent = false;
    summaryConsent = false;
    changes.add(++epoch);
  }

  bool hasKey = false;
  bool providerConsent = false;
  bool summaryConsent = false;
  int removeCalls = 0;
  bool invalidateOnRemove = false;
  GeminiException? removeFailure;
  final List<String> configuredKeys = [];
  GeminiException? configureFailure;
  Completer<void>? configureGate;
  Completer<void>? loadGate;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) async {
    if (!providerConsent) {
      throw const GeminiException(GeminiFailureCode.consentRequired);
    }
    final failure = configureFailure;
    if (failure != null) throw failure;
    await configureGate?.future;
    configuredKeys.add(key);
    hasKey = true;
    this.providerConsent = providerConsent;
    summaryConsent = shareLearningSummary;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<GeminiSettingsStatus> loadSettings() async {
    await loadGate?.future;
    return GeminiSettingsStatus(
      hasKey: hasKey,
      providerConsent: providerConsent,
      shareLearningSummary: summaryConsent,
    );
  }

  @override
  Future<void> removeKey() async {
    removeCalls += 1;
    providerConsent = false;
    changes.add(++epoch);
    if (removeFailure != null) throw removeFailure!;
    hasKey = false;
    providerConsent = false;
    summaryConsent = false;
  }

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    if (!providerConsent) changes.add(++epoch);
    this.providerConsent = providerConsent;
    summaryConsent = providerConsent && shareLearningSummary;
  }
}
