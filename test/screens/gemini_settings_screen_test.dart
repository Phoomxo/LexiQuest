import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/screens/gemini_settings_screen.dart';

void main() {
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
    await tester.tap(find.byKey(const ValueKey('gemini-save-key')));
    await tester.pumpAndSettle();
    expect(find.text('ต้องยืนยันการยินยอมก่อนบันทึก key'), findsOneWidget);
    expect(tutor.configuredKeys, isEmpty);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byKey(const ValueKey('gemini-save-key')));
    await tester.pumpAndSettle();

    expect(tutor.configuredKeys, ['private-key-sentinel-that-is-long']);
    expect(find.textContaining('เก็บ key ในที่จัดเก็บปลอดภัย'), findsOneWidget);
    expect(find.text('private-key-sentinel-that-is-long'), findsNothing);
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
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ key'));
    await tester.pumpAndSettle();

    expect(tutor.removeCalls, 1);
    expect(find.text('สถานะ: ยังไม่มี key'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('gemini-save-key')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Key ไม่ถูกต้อง'), findsOneWidget);

    tutor.configureFailure = const GeminiException(GeminiFailureCode.quota);
    await tester.tap(find.byKey(const ValueKey('gemini-save-key')));
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
      await tester.tap(find.byKey(const ValueKey('gemini-save-key')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}

final class _FakeSettingsTutor implements GeminiTutorController {
  bool hasKey = false;
  bool providerConsent = false;
  bool summaryConsent = false;
  int removeCalls = 0;
  final List<String> configuredKeys = [];
  GeminiException? configureFailure;
  Completer<void>? configureGate;

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
  Future<GeminiSettingsStatus> loadSettings() async => GeminiSettingsStatus(
    hasKey: hasKey,
    providerConsent: providerConsent,
    shareLearningSummary: summaryConsent,
  );

  @override
  Future<void> removeKey() async {
    removeCalls += 1;
    hasKey = false;
    providerConsent = false;
    summaryConsent = false;
  }

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    this.providerConsent = providerConsent;
    summaryConsent = providerConsent && shareLearningSummary;
  }
}
