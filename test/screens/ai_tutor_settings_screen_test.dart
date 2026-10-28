import 'dart:async';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';

void main() {
  testWidgets(
    'F04 inherited replacement retires deferred usage and preserves B data',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final gate = Completer<void>();
      final old = _FailingClearTutor()
        ..consent = true
        ..usageGate = gate
        ..usageSummaries = [_summary('old-usage')];
      final current = _FailingClearTutor()
        ..usageSummaries = [_summary('current-usage')];
      Widget shell(AiTutorController tutor) => AppDependenciesScope(
        dependencies: _dependencies(db, tutor),
        child: const MaterialApp(home: AiTutorSettingsScreen()),
      );
      await tester.pumpWidget(shell(old));
      await tester.pump();
      await tester.pumpWidget(shell(current));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'OpenAI / current-usage');
      await tester.scrollUntilVisible(
        tile,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tile, findsOneWidget);
      expect(find.text('OpenAI / old-usage'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('F04 replacement usage failure displays unknown not old usage', (
    tester,
  ) async {
    final old = _FailingClearTutor()..usageSummaries = [_summary('old-usage')];
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: old)),
    );
    await tester.pumpAndSettle();
    final current = _FailingClearTutor()..failUsageLoad = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: current)),
    );
    await tester.pumpAndSettle();
    final clear = find.byKey(const ValueKey('ai-clear-usage'));
    await tester.scrollUntilVisible(
      clear,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OpenAI / old-usage'), findsNothing);
    expect(find.text('ยังโหลดสถิติการใช้ AI ไม่สำเร็จ'), findsOneWidget);
  });

  testWidgets(
    'F04 old mutation failure cannot reconcile replacement settings',
    (tester) async {
      final gate = Completer<void>();
      final old = _FailingClearTutor()
        ..consent = true
        ..consentGate = gate
        ..failConsent = true;
      final current = _FailingClearTutor();
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: old)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-withdraw-consent')));
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: current)),
      );
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(old.settingsReads, 1);
      expect(
        find.text('ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ai-settings-error')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('F04 null initial tutor is visibly unavailable', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AiTutorSettingsScreen()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
  });

  for (final pendingUsage in [false, true]) {
    testWidgets('F04 replacement retires old load usage=$pendingUsage', (
      tester,
    ) async {
      final gate = Completer<void>();
      final old = _FailingClearTutor()..consent = true;
      if (pendingUsage) {
        old.usageGate = gate;
      } else {
        old.settingsGate = gate;
      }
      final current = _FailingClearTutor();
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: old)),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: current)),
      );
      await tester.pumpAndSettle();
      expect(current.settingsReads, 1);
      expect(
        find.text('ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ'),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('ความยินยอมที่บันทึก: อนุญาตส่งข้อความ'), findsNothing);
      expect(
        find.text('ความยินยอมที่บันทึก: ไม่อนุญาตส่งข้อความ'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('F04 failed replacement clears known saved state', (
    tester,
  ) async {
    final old = _FailingClearTutor()..consent = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: old)),
    );
    await tester.pumpAndSettle();
    final current = _FailingClearTutor()..failSettingsLoad = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: current)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('ยังตรวจสอบการตั้งค่าและความยินยอมไม่ได้'),
      findsOneWidget,
    );
    expect(find.text('ความยินยอมที่บันทึก: อนุญาตส่งข้อความ'), findsNothing);
  });

  for (final remove in [true, false]) {
    testWidgets(
      'F04 old confirmation cannot mutate replacement remove=$remove',
      (tester) async {
        final old = _FailingClearTutor()..consent = true;
        final current = _FailingClearTutor();
        final selected = ValueNotifier<AiTutorController>(old);
        addTearDown(selected.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<AiTutorController>(
              valueListenable: selected,
              builder: (_, tutor, _) => AiTutorSettingsScreen(aiTutor: tutor),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(
          ValueKey(remove ? 'ai-remove-key' : 'ai-clear-usage'),
        );
        await tester.scrollUntilVisible(
          button,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        selected.value = current;
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            remove ? 'ลบรหัสเชื่อมต่อ' : 'ล้างสถิติในเครื่อง',
          ),
        );
        await tester.pumpAndSettle();
        expect(old.removeCalls + old.clearCalls, 0);
        expect(current.removeCalls + current.clearCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
  Completer<void>? settingsGate;
  Completer<void>? usageGate;
  int removeCalls = 0;
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
    await settingsGate?.future;
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
    await usageGate?.future;
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
  Future<void> removeKey() async {
    removeCalls++;
  }

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

AiUsageSummary _summary(String model) => AiUsageSummary(
  providerId: AiProviderId.openai,
  model: model,
  requestCount: 1,
  successCount: 1,
  failureCount: 0,
  indeterminateCount: 0,
  totalTokens: 5,
  knownTokens: 5,
  tokenReportedRequestCount: 1,
  totalLatencyMs: 1,
  providerReportedCostMicrosUsd: null,
);

AppDependencies _dependencies(AppDatabase database, AiTutorController tutor) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
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
    aiTutor: tutor,
  );
}

class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
