import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';

void main() {
  for (final tokenCase in <(String, int?, int, int, int)>[
    ('unknown', null, 0, 0, 2),
    ('partial', null, 10, 3, 4),
    ('measured-zero', 0, 0, 1, 1),
  ]) {
    testWidgets('usage token copy distinguishes ${tokenCase.$1}', (
      tester,
    ) async {
      final tutor = _FailingClearTutor()
        ..usageSummaries = [
          AiUsageSummary(
            providerId: AiProviderId.openai,
            model: 'synthetic-usage',
            requestCount: tokenCase.$5,
            successCount: tokenCase.$5,
            failureCount: 0,
            indeterminateCount: 0,
            totalTokens: tokenCase.$2,
            knownTokens: tokenCase.$3,
            tokenReportedRequestCount: tokenCase.$4,
            totalLatencyMs: 10,
            providerReportedCostMicrosUsd: 0,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'OpenAI / synthetic-usage');
      await tester.scrollUntilVisible(
        tile,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final subtitle = (tester.widget<ListTile>(tile).subtitle! as Text).data!;
      expect(subtitle, isNot(contains('null')));
      expect(subtitle, contains('หน่วยข้อความ'));
      expect(
        subtitle,
        contains('0.000000 USD'),
        reason: 'Token completeness must not change reported cost.',
      );
      if (tokenCase.$1 == 'unknown') {
        expect(subtitle, contains('ไม่ทราบ'));
        expect(subtitle, isNot(contains('0 หน่วยข้อความ')));
        expect(subtitle, isNot(contains('บางส่วน')));
      } else if (tokenCase.$1 == 'partial') {
        expect(subtitle, contains('บางส่วน'));
        expect(subtitle, contains('10 หน่วยข้อความ'));
        expect(subtitle, contains('3 จาก 4 คำขอ'));
      } else {
        expect(subtitle, contains('0 หน่วยข้อความ'));
        expect(subtitle, isNot(contains('ไม่ทราบ')));
        expect(subtitle, isNot(contains('บางส่วน')));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final readbackFails in [false, true]) {
    testWidgets(
      'consent commit acknowledgment failure reconciles readback=$readbackFails',
      (tester) async {
        final tutor = _FailingClearTutor()
          ..consent = true
          ..commitThenFail = true
          ..failReadback = readbackFails;
        await tester.pumpWidget(
          MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-withdraw-consent')));
        await tester.pumpAndSettle();
        expect(tutor.consentCalls, 1);
        expect(tutor.consent, isFalse);
        expect(tutor.settingsReads, 2);
        expect(
          find.text('บันทึกไม่สำเร็จ ความยินยอมเดิมยังมีผล'),
          findsNothing,
        );
        expect(
          find.text('ความยินยอมที่บันทึก: อนุญาตส่งข้อความ'),
          findsNothing,
        );
        expect(
          find.text(
            readbackFails
                ? 'ยังยืนยันผลการบันทึกและความยินยอมปัจจุบันไม่ได้'
                : 'ตรวจสอบแล้ว: ไม่อนุญาตส่งข้อความและสรุปการเรียน',
          ),
          findsOneWidget,
        );
        expect(
          find.text('ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ'),
          readbackFails ? findsNothing : findsOneWidget,
        );
      },
    );
  }
  testWidgets('settings read failure does not claim consent is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorSettingsScreen(
          aiTutor: _FailingClearTutor()..failSettingsLoad = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('ยังตรวจสอบการตั้งค่าและความยินยอมไม่ได้'),
      findsOneWidget,
    );
    expect(find.text('ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ'), findsNothing);
  });
  testWidgets('usage load failure preserves loaded persisted consent', (
    tester,
  ) async {
    final tutor = _FailingClearTutor()
      ..consent = true
      ..failUsageLoad = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-withdraw-consent')), findsOneWidget);
    expect(find.text('ความยินยอมที่บันทึก: อนุญาตส่งข้อความ'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
    final usage = find.byKey(const ValueKey('ai-clear-usage'));
    await tester.scrollUntilVisible(
      usage,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีสถิติการใช้ AI ในเครื่อง'), findsNothing);
    expect(find.text('ยังโหลดสถิติการใช้ AI ไม่สำเร็จ'), findsOneWidget);
  });
  testWidgets(
    'changing provider never silently calls stored credential destination',
    (tester) async {
      final tutor = _FailingClearTutor()..consent = true;
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final provider = find.byKey(const ValueKey('ai-provider-select'));
      await tester.ensureVisible(provider);
      await tester.pumpAndSettle();
      await tester.tap(provider);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI (ทดลอง)').last);
      await tester.pumpAndSettle();
      final load = find.byKey(const ValueKey('ai-load-models'));
      await tester.scrollUntilVisible(
        load,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(load);
      await tester.pumpAndSettle();
      expect(tutor.activeModelCalls, 0);
      expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
    },
  );
  testWidgets(
    'edited consent remains unsaved and leaving asks before discard',
    (tester) async {
      final tutor = _FailingClearTutor()..consent = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AiTutorSettingsScreen(aiTutor: tutor),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final consent = find.byKey(const ValueKey('ai-provider-consent'));
      expect(consent, findsOneWidget);
      await tester.ensureVisible(consent);
      await tester.pumpAndSettle();
      await tester.tap(consent);
      await tester.pumpAndSettle();
      expect(tutor.consent, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ออกโดยไม่บันทึก?'), findsOneWidget);
      await tester.tap(find.text('กลับไปแก้ไข'));
      await tester.pumpAndSettle();
      expect(find.byType(AiTutorSettingsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ออกโดยไม่บันทึก'));
      await tester.pumpAndSettle();
      expect(find.byType(AiTutorSettingsScreen), findsNothing);
      expect(tutor.consent, isTrue);
    },
  );

  for (final fails in [false, true]) {
    testWidgets('withdraw consent reports persisted outcome failure=$fails', (
      tester,
    ) async {
      final tutor = _FailingClearTutor()
        ..consent = true
        ..consentGate = Completer<void>()
        ..failConsent = fails;
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
      );
      await tester.pumpAndSettle();
      final withdraw = find.byKey(const ValueKey('ai-withdraw-consent'));
      expect(withdraw, findsOneWidget);
      await tester.scrollUntilVisible(
        withdraw,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(withdraw);
      await tester.pump();
      expect(tutor.consentCalls, 1);
      expect(tutor.consent, isTrue);
      expect(find.text('กำลังบันทึกความยินยอม…'), findsOneWidget);
      tutor.consentGate!.complete();
      await tester.pumpAndSettle();
      expect(tutor.consent, fails);
      expect(
        find.text(
          fails
              ? 'ตรวจสอบแล้ว: อนุญาตส่งข้อความตามสถานะที่บันทึก'
              : 'หยุดอนุญาตการส่งข้อความและสรุปการเรียนแล้ว',
        ),
        findsOneWidget,
      );
      expect((await tutor.loadSettings()).providerConsent, fails);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings and error fit narrow viewport with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
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
        home: AiTutorSettingsScreen(aiTutor: _FailingClearTutor()),
      ),
    );
    await tester.pumpAndSettle();
    final load = find.byKey(const ValueKey('ai-load-models'));
    await tester.scrollUntilVisible(
      load,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(load);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clear usage failure renders a typed error without an uncaught async error',
    (tester) async {
      final tutor = _FailingClearTutor();
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
      );
      await tester.pumpAndSettle();

      final clearButton = find.byKey(const ValueKey('ai-clear-usage'));
      await tester.scrollUntilVisible(
        clearButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'ล้างสถิติในเครื่อง'));
      await tester.pumpAndSettle();

      expect(tutor.clearCalls, 1);
      expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
      expect(
        find.text('บันทึกสถิติ AI ในเครื่องไม่ได้ชั่วคราว กรุณาลองภายหลัง'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

final class _FailingClearTutor implements AiTutorController {
  int clearCalls = 0;
  int activeModelCalls = 0;
  bool consent = false;
  bool failConsent = false;
  bool failUsageLoad = false;
  List<AiUsageSummary> usageSummaries = const [];
  bool failSettingsLoad = false;
  bool commitThenFail = false;
  bool failReadback = false;
  int settingsReads = 0;
  int consentCalls = 0;
  Completer<void>? consentGate;

  @override
  Future<AiTutorSettingsStatus> loadSettings() async {
    settingsReads++;
    if (failSettingsLoad || (settingsReads > 1 && failReadback)) {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
    return AiTutorSettingsStatus(
      hasKey: consent,
      providerConsent: consent,
      shareLearningSummary: false,
      providerId: AiProviderId.gemini,
      model: null,
    );
  }

  @override
  Future<List<AiUsageSummary>> loadUsage() async {
    if (failUsageLoad) {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    return usageSummaries;
  }

  @override
  Future<void> clearUsage() async {
    clearCalls += 1;
    throw const AiTutorException(AiFailureCode.localPersistence);
  }

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> dispose() async {}

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) async {
    activeModelCalls++;
    return const [AiModel(id: 'synthetic-model')];
  }

  @override
  Future<void> removeKey() => throw UnimplementedError();

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    TutorRequestContext? context,
    AiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    consentCalls++;
    await consentGate?.future;
    if (commitThenFail) {
      consent = providerConsent;
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    if (failConsent) throw const AiTutorException(AiFailureCode.secureStorage);
    consent = providerConsent;
  }
}
