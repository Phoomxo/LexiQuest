import 'dart:async';

enum GeminiTutorMode { guided, direct }

enum GeminiFailureCode {
  missingKey,
  consentRequired,
  invalidKey,
  quota,
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

final class GeminiScope {
  const GeminiScope({
    required this.ownerId,
    required this.firebaseUid,
    required this.isAnonymous,
  });
  final String ownerId;
  final String? firebaseUid;
  final bool isAnonymous;

  @override
  bool operator ==(Object other) =>
      other is GeminiScope &&
      ownerId == other.ownerId &&
      firebaseUid == other.firebaseUid &&
      isAnonymous == other.isAnonymous;
  @override
  int get hashCode => Object.hash(ownerId, firebaseUid, isAnonymous);
}

final class GeminiConfiguration {
  const GeminiConfiguration({
    this.key,
    this.providerConsent = false,
    this.shareLearningSummary = false,
  });
  final String? key;
  final bool providerConsent;
  final bool shareLearningSummary;
  GeminiSettingsStatus get status => GeminiSettingsStatus(
    hasKey: key?.trim().isNotEmpty == true,
    providerConsent: providerConsent,
    shareLearningSummary: providerConsent && shareLearningSummary,
  );
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
  Future<GeminiConfiguration> read(GeminiScope scope);
  Future<void> write(GeminiScope scope, GeminiConfiguration configuration);
}

abstract interface class GeminiGateway {
  String get model;

  Future<void> validateKey(String key, {GeminiCancellation? cancellation});

  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  });
}

abstract interface class GeminiTutorController {
  GeminiScope? get scope;
  int get epoch;
  Stream<int> get invalidations;
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
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  });

  Future<void> dispose();
}
