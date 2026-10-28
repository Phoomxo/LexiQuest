import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';

void main() {
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
      await tester.tap(find.widgetWithText(FilledButton, 'Clear usage'));
      await tester.pumpAndSettle();

      expect(tutor.clearCalls, 1);
      expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
      expect(
        find.text('Local AI accounting is temporarily unavailable.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

final class _FailingClearTutor implements AiTutorController {
  int clearCalls = 0;

  @override
  Future<AiTutorSettingsStatus> loadSettings() async =>
      const AiTutorSettingsStatus(
        hasKey: false,
        providerConsent: false,
        shareLearningSummary: false,
        providerId: AiProviderId.gemini,
        model: null,
      );

  @override
  Future<List<AiUsageSummary>> loadUsage() async => const <AiUsageSummary>[];

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
  }) => throw UnimplementedError();

  @override
  Future<void> removeKey() => throw UnimplementedError();

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
  }) => throw UnimplementedError();
}
