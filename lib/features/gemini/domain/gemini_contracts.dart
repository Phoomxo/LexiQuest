import 'dart:async';

enum GeminiFailureCode {
  missingKey,
  consentRequired,
  invalidKey,
  quota,
  rateLimited,
  offline,
  timeout,
  providerUnavailable,
  malformedResponse,
  blocked,
  cancelled,
  validation,
  secureStorage,
}

final class GeminiException implements Exception {
  const GeminiException(this.code);

  final GeminiFailureCode code;

  @override
  String toString() => 'GeminiException(${code.name})';
}

final class GeminiCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}

final class GeminiSettingsStatus {
  const GeminiSettingsStatus({
    required this.hasKey,
    required this.providerConsent,
    required this.shareLearningSummary,
  });

  final bool hasKey;
  final bool providerConsent;
  final bool shareLearningSummary;
}

final class GeminiTutorReply {
  const GeminiTutorReply({
    required this.text,
    required this.model,
    required this.generatedAtUtc,
  });

  final String text;
  final String model;
  final DateTime generatedAtUtc;
}

abstract interface class GeminiSettingsStore {
  Future<String?> readKey();
  Future<void> writeKey(String key);
  Future<void> deleteKey();
  Future<bool> readProviderConsent();
  Future<void> writeProviderConsent(bool value);
  Future<bool> readLearningSummaryConsent();
  Future<void> writeLearningSummaryConsent(bool value);
}

abstract interface class GeminiGateway {
  String get model;

  Future<void> validateKey(String key, {GeminiCancellation? cancellation});

  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  });

  Future<List<String>> listModels(String key, {GeminiCancellation? cancellation});
}

abstract interface class GeminiTutorController {
  Future<GeminiSettingsStatus> loadSettings();

  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  });

  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  });

  Future<void> removeKey();

  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiCancellation? cancellation,
  });

  Future<void> dispose();
}
