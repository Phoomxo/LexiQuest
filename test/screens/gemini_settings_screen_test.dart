import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';

void main() {
  testWidgets('discovers a model and saves only after provider consent', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor();
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Google Gemini (experimental)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ai-key-input')),
      'private-key-sentinel-that-is-long',
    );
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Provider consent is required.'), findsOneWidget);
    expect(tutor.listCalls, 0);
    expect(tutor.configuredKeys, isEmpty);

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await _selectModel(tester, 'model-a');
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();

    expect(tutor.configuredKeys, ['private-key-sentinel-that-is-long']);
    expect(find.text('Key validated and stored securely.'), findsOneWidget);
    expect(find.text('private-key-sentinel-that-is-long'), findsNothing);
  });

  testWidgets('model discovery requires an explicit model choice', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor();
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.enterText(
      find.byKey(const ValueKey('ai-key-input')),
      'private-key-sentinel-that-is-long',
    );
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();

    expect(tutor.configuredKeys, isEmpty);
    expect(find.text('Select or enter a model.'), findsOneWidget);
  });

  testWidgets('removing key disables provider and summary consent', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor()
      ..hasKey = true
      ..providerConsent = true
      ..summaryConsent = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final removeKey = find.byKey(const ValueKey('ai-remove-key'));
    await tester.tap(removeKey);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete key'));
    await tester.pumpAndSettle();

    expect(tutor.removeCalls, 1);
    expect(find.text('Status: no key', skipOffstage: false), findsOneWidget);
  });

  testWidgets('shows distinct invalid key and quota failures', (tester) async {
    final tutor = _FakeSettingsTutor()
      ..configureFailure = const AiTutorException(AiFailureCode.invalidKey);
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.enterText(
      find.byKey(const ValueKey('ai-key-input')),
      'invalid-key-that-is-long-enough',
    );
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await _selectModel(tester, 'model-a');
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid API key.'), findsOneWidget);

    tutor.configureFailure = const AiTutorException(AiFailureCode.quota);
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();
    expect(find.text('Provider quota is exhausted.'), findsOneWidget);

    tutor.configureFailure = const AiTutorException(
      AiFailureCode.requestRejected,
    );
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The provider rejected this model or request. Choose another listed model or check provider restrictions. Your previous configuration is still active.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('leaving during key validation does not update disposed state', (
    tester,
  ) async {
    final gate = Completer<void>();
    final tutor = _FakeSettingsTutor()..configureGate = gate;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.enterText(
      find.byKey(const ValueKey('ai-key-input')),
      'private-key-sentinel-that-is-long',
    );
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await _selectModel(tester, 'model-a');
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('provider and model labels fit a vivo-width layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final tutor = _FakeSettingsTutor()
      ..models = const [
        AiModel(
          id: 'model-with-a-very-long-provider-specific-identifier',
          displayName: 'A very long experimental provider model display name',
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: AiTutorSettingsScreen(aiTutor: tutor),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.enterText(
      find.byKey(const ValueKey('ai-key-input')),
      'private-key-sentinel-that-is-long',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-load-models')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('ai-model-select')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows local usage totals and lets the user clear them', (
    tester,
  ) async {
    final usage = _FakeUsageRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorSettingsScreen(
          aiTutor: _FakeSettingsTutor(),
          aiUsage: usage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 requests'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-clear-usage')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear usage'));
    await tester.pumpAndSettle();

    expect(usage.clearCalls, 1);
    expect(find.text('No local API usage recorded.'), findsOneWidget);
  });

  testWidgets('active key: loads models without re-entering the key', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor()
      ..hasKey = true
      ..providerConsent = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    // Key field is empty — the stored-key path should be taken.
    expect(find.text('Status: active key'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();

    expect(tutor.listActiveCalls, 1);
    expect(tutor.listCalls, 0);
    // Model must not be pre-selected after discovery.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Select a model'), findsOneWidget);
  });

  testWidgets('active key: saves model using stored credential', (
    tester,
  ) async {
    final tutor = _FakeSettingsTutor()
      ..hasKey = true
      ..providerConsent = true;
    await tester.pumpWidget(
      MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
    );
    await tester.pumpAndSettle();

    // Load models using the stored key, then pick one and save.
    await tester.tap(find.byKey(const ValueKey('ai-load-models')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await _selectModel(tester, 'model-a');
    await tester.tap(find.byKey(const ValueKey('ai-save-key')));
    await tester.pumpAndSettle();

    expect(tutor.configureActiveCalls, 1);
    expect(tutor.lastConfiguredActiveModel, 'model-a');
    expect(tutor.configuredKeys, isEmpty);
    expect(find.text('Model updated and stored securely.'), findsOneWidget);
  });

  testWidgets(
    'active key: entering a new key falls through to full configure',
    (tester) async {
      final tutor = _FakeSettingsTutor()
        ..hasKey = true
        ..providerConsent = true;
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: tutor)),
      );
      await tester.pumpAndSettle();

      // Type a new key — should use the regular configure path, not stored-key.
      await tester.enterText(
        find.byKey(const ValueKey('ai-key-input')),
        'new-replacement-key-long',
      );
      await tester.tap(find.byKey(const ValueKey('ai-load-models')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await _selectModel(tester, 'model-a');
      await tester.tap(find.byKey(const ValueKey('ai-save-key')));
      await tester.pumpAndSettle();

      expect(tutor.configuredKeys, ['new-replacement-key-long']);
      expect(tutor.configureActiveCalls, 0);
      expect(tutor.listActiveCalls, 0);
    },
  );
}

Future<void> _selectModel(WidgetTester tester, String model) async {
  await tester.tap(find.byKey(const ValueKey('ai-model-select')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(model).last);
  await tester.pumpAndSettle();
}

final class _FakeUsageRepository implements AiUsageRepository {
  int clearCalls = 0;

  @override
  Future<void> clear() async => clearCalls += 1;

  @override
  Future<String> exportAggregateJson({required bool researchConsent}) =>
      throw UnimplementedError();

  @override
  Future<int> purgeExpired(DateTime nowUtc) async => 0;

  @override
  Future<void> record(AiUsageEvent event) async {}

  @override
  Future<List<AiUsageSummary>> summarize() async => clearCalls == 0
      ? const [
          AiUsageSummary(
            providerId: AiProviderId.openai,
            model: 'model-a',
            requestCount: 2,
            successCount: 2,
            failureCount: 0,
            totalTokens: 30,
            totalLatencyMs: 100,
            providerReportedCostMicrosUsd: null,
          ),
        ]
      : const [];
}

final class _FakeSettingsTutor implements AiTutorController {
  bool hasKey = false;
  bool providerConsent = false;
  bool summaryConsent = false;
  int removeCalls = 0;
  final List<String> configuredKeys = [];
  AiTutorException? configureFailure;
  Completer<void>? configureGate;
  List<AiModel> models = const [AiModel(id: 'model-a')];
  int listCalls = 0;
  int listActiveCalls = 0;
  int configureActiveCalls = 0;
  String? lastConfiguredActiveModel;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {
    if (!providerConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
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
  Future<AiTutorSettingsStatus> loadSettings() async => AiTutorSettingsStatus(
    hasKey: hasKey,
    providerConsent: providerConsent,
    shareLearningSummary: summaryConsent,
    providerId: AiProviderId.gemini,
    model: hasKey ? 'model-a' : null,
  );

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {
    listCalls += 1;
    return models;
  }

  @override
  Future<void> removeKey() async {
    removeCalls += 1;
    hasKey = false;
    providerConsent = false;
    summaryConsent = false;
  }

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    AiCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    this.providerConsent = providerConsent;
    summaryConsent = providerConsent && shareLearningSummary;
  }

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) async {
    listActiveCalls += 1;
    if (!hasKey) throw const AiTutorException(AiFailureCode.missingKey);
    return models;
  }

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) async {
    final failure = configureFailure;
    if (failure != null) throw failure;
    await configureGate?.future;
    configureActiveCalls += 1;
    lastConfiguredActiveModel = model;
    summaryConsent = shareLearningSummary;
  }
}
