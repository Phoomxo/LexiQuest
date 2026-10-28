import 'dart:async';

/// Providers supported by the private BYOK field release.
enum AiProviderId { gemini, openai, openrouter, claude, maxPlus, customOpenAi }

/// Temporary source-compatibility alias while older P8-H tests migrate.
typedef AiProvider = AiProviderId;

enum AiFailureCode {
  missingKey,
  missingModel,
  consentRequired,
  invalidKey,
  requestRejected,
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
  unsafeEndpoint,
  providerDisabled,
  circuitOpen,
  localPersistence,
}

final class AiTutorException implements Exception {
  const AiTutorException(this.code);

  final AiFailureCode code;

  @override
  String toString() => 'AiTutorException(${code.name})';
}

final class AiCancellation {
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

final class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUri,
    required this.defaultModel,
    required this.supportsCustomModel,
    required this.supportsCustomBaseUrl,
  });

  final AiProviderId id;
  final String displayName;
  final Uri baseUri;

  /// Null by design: users select a model returned by the provider rather
  /// than silently inheriting an aging hard-coded model id.
  final String? defaultModel;
  final bool supportsCustomModel;
  final bool supportsCustomBaseUrl;

  /// Direct-client BYOK is limited to the controlled field rollout.
  bool get isExperimental => true;

  static final Map<AiProviderId, AiProviderConfig> _configs = {
    AiProviderId.gemini: AiProviderConfig(
      id: AiProviderId.gemini,
      displayName: 'Google Gemini',
      baseUri: Uri.https('generativelanguage.googleapis.com', '/'),
      defaultModel: null,
      supportsCustomModel: false,
      supportsCustomBaseUrl: false,
    ),
    AiProviderId.openai: AiProviderConfig(
      id: AiProviderId.openai,
      displayName: 'OpenAI',
      baseUri: Uri.https('api.openai.com', '/v1/'),
      defaultModel: null,
      supportsCustomModel: false,
      supportsCustomBaseUrl: false,
    ),
    AiProviderId.openrouter: AiProviderConfig(
      id: AiProviderId.openrouter,
      displayName: 'OpenRouter',
      baseUri: Uri.https('openrouter.ai', '/api/v1/'),
      defaultModel: null,
      supportsCustomModel: false,
      supportsCustomBaseUrl: false,
    ),
    AiProviderId.claude: AiProviderConfig(
      id: AiProviderId.claude,
      displayName: 'Anthropic Claude',
      baseUri: Uri.https('api.anthropic.com', '/'),
      defaultModel: null,
      supportsCustomModel: false,
      supportsCustomBaseUrl: false,
    ),
    AiProviderId.maxPlus: AiProviderConfig(
      id: AiProviderId.maxPlus,
      displayName: 'MaxPlus',
      baseUri: Uri.https('api.maxplus-ai.cc', '/v1/'),
      defaultModel: null,
      supportsCustomModel: false,
      supportsCustomBaseUrl: false,
    ),
    AiProviderId.customOpenAi: AiProviderConfig(
      id: AiProviderId.customOpenAi,
      displayName: 'Custom OpenAI-compatible',
      baseUri: Uri.https('api.example.com', '/v1/'),
      defaultModel: null,
      supportsCustomModel: true,
      supportsCustomBaseUrl: true,
    ),
  };

  static AiProviderConfig forId(AiProviderId id) => _configs[id]!;

  static List<AiProviderConfig> get all =>
      AiProviderId.values.map(forId).toList(growable: false);
}

final class AiModel {
  const AiModel({required this.id, this.displayName});

  final String id;
  final String? displayName;
}

final class AiTokenUsage {
  const AiTokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cachedTokens,
    this.providerReportedCostMicrosUsd,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? cachedTokens;
  final int? providerReportedCostMicrosUsd;
}

final class AiUsageEvent {
  AiUsageEvent({
    required this.eventId,
    required this.occurredAtUtc,
    required this.providerId,
    required this.model,
    required this.requestType,
    required this.outcome,
    required this.latencyMs,
    this.errorCategory,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cachedTokens,
    this.providerReportedCostMicrosUsd,
    this.schemaVersion = 1,
  }) {
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    if (eventId.trim().isEmpty ||
        model.trim().isEmpty ||
        requestType.trim().isEmpty ||
        outcome.trim().isEmpty ||
        latencyMs < 0 ||
        schemaVersion != 1) {
      throw ArgumentError('Invalid AI usage metadata');
    }
  }

  final String eventId;
  final DateTime occurredAtUtc;
  final AiProviderId providerId;
  final String model;
  final String requestType;
  final String outcome;
  final String? errorCategory;
  final int latencyMs;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? cachedTokens;
  final int? providerReportedCostMicrosUsd;
  final int schemaVersion;
}

/// Durable request intent written before any provider work begins.
final class AiUsageAttempt {
  AiUsageAttempt({
    required this.eventId,
    required this.occurredAtUtc,
    required this.providerId,
    required this.model,
    required this.requestType,
    this.schemaVersion = 1,
  }) {
    if (!occurredAtUtc.isUtc ||
        eventId.trim().isEmpty ||
        model.trim().isEmpty ||
        requestType.trim().isEmpty ||
        schemaVersion != 1) {
      throw ArgumentError('Invalid AI usage attempt metadata');
    }
  }

  final String eventId;
  final DateTime occurredAtUtc;
  final AiProviderId providerId;
  final String model;
  final String requestType;
  final int schemaVersion;
}

/// Terminal accounting fields applied to one previously-pending attempt.
final class AiUsageCompletion {
  AiUsageCompletion({
    required this.eventId,
    required this.outcome,
    required this.latencyMs,
    this.errorCategory,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cachedTokens,
    this.providerReportedCostMicrosUsd,
  }) {
    if (eventId.trim().isEmpty ||
        latencyMs < 0 ||
        (outcome != 'success' &&
            outcome != 'failure' &&
            outcome != 'indeterminate') ||
        ((outcome == 'failure' || outcome == 'indeterminate') &&
            (errorCategory == null || errorCategory!.trim().isEmpty)) ||
        (outcome == 'success' && errorCategory != null) ||
        <int?>[
          inputTokens,
          outputTokens,
          totalTokens,
          cachedTokens,
          providerReportedCostMicrosUsd,
        ].any((value) => value != null && value < 0) ||
        (cachedTokens != null &&
            totalTokens != null &&
            cachedTokens! > totalTokens!) ||
        (inputTokens != null &&
            outputTokens != null &&
            totalTokens != null &&
            totalTokens! < inputTokens! + outputTokens!)) {
      throw ArgumentError('Invalid AI usage completion metadata');
    }
  }

  final String eventId;
  final String outcome;
  final String? errorCategory;
  final int latencyMs;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? cachedTokens;
  final int? providerReportedCostMicrosUsd;
}

enum AiUsageFinalizeResult { finalized, alreadyFinalized }

final class AiUsageSummary {
  const AiUsageSummary({
    required this.providerId,
    required this.model,
    required this.requestCount,
    required this.successCount,
    required this.failureCount,
    required this.indeterminateCount,
    required this.totalTokens,
    required this.totalLatencyMs,
    required this.providerReportedCostMicrosUsd,
  });

  final AiProviderId providerId;
  final String model;
  final int requestCount;
  final int successCount;
  final int failureCount;
  final int indeterminateCount;
  final int totalTokens;
  final int totalLatencyMs;

  /// Null means the provider did not report a cost. Zero is a reported zero.
  final int? providerReportedCostMicrosUsd;
}

abstract interface class AiUsageRepository {
  Future<void> beginForOwner(String ownerId, AiUsageAttempt attempt);
  Future<AiUsageFinalizeResult> finalizeForOwner(
    String ownerId,
    AiUsageCompletion completion,
  );
  Future<int> recoverPendingStartedBefore(
    DateTime cutoffUtc, {
    required DateTime recoveredAtUtc,
  });
  Future<int> purgeExpired(DateTime nowUtc);
  Future<int> purgeExpiredForOwner(String ownerId, DateTime nowUtc);
  Future<List<AiUsageSummary>> summarize();
  Future<List<AiUsageSummary>> summarizeForOwner(String ownerId);
  Future<void> clear();
  Future<void> clearForOwner(String ownerId);
  Future<String> exportAggregateJson({required bool researchConsent});
}

final class AiGatewayReply {
  const AiGatewayReply({required this.text, this.usage});

  final String text;
  final AiTokenUsage? usage;
}

final class AiTutorReply {
  const AiTutorReply({
    required this.text,
    required this.providerId,
    required this.model,
    required this.generatedAtUtc,
    this.usage,
  });

  final String text;
  final AiProviderId providerId;
  final String model;
  final DateTime generatedAtUtc;
  final AiTokenUsage? usage;
}

final class AiTutorSettingsStatus {
  const AiTutorSettingsStatus({
    required this.hasKey,
    required this.providerConsent,
    required this.shareLearningSummary,
    required this.providerId,
    required this.model,
    this.customBaseUrl,
  });

  final bool hasKey;
  final bool providerConsent;
  final bool shareLearningSummary;
  final AiProviderId providerId;
  final String? model;
  final String? customBaseUrl;
}

final class AiTutorCredential {
  const AiTutorCredential({
    required this.key,
    required this.providerId,
    required this.model,
    required this.providerConsent,
    required this.shareLearningSummary,
    this.customBaseUrl,
  });

  final String key;
  final AiProviderId providerId;
  final String model;
  final bool providerConsent;
  final bool shareLearningSummary;
  final String? customBaseUrl;

  AiTutorCredential copyWith({
    String? key,
    AiProviderId? providerId,
    String? model,
    bool? providerConsent,
    bool? shareLearningSummary,
    String? customBaseUrl,
    bool clearCustomBaseUrl = false,
  }) => AiTutorCredential(
    key: key ?? this.key,
    providerId: providerId ?? this.providerId,
    model: model ?? this.model,
    providerConsent: providerConsent ?? this.providerConsent,
    shareLearningSummary: shareLearningSummary ?? this.shareLearningSummary,
    customBaseUrl: clearCustomBaseUrl
        ? null
        : customBaseUrl ?? this.customBaseUrl,
  );
}

abstract interface class AiTutorSettingsStore {
  Future<String> resolveActiveOwnerId();
  Future<AiTutorCredential?> readCredential();
  Future<AiTutorCredential?> readCredentialForOwner(String ownerId);
  Future<void> writeCredential(AiTutorCredential credential);
  Future<void> writeCredentialForOwner(
    String ownerId,
    AiTutorCredential credential,
  );
  Future<void> deleteCredential();
  Future<void> deleteCredentialForOwner(String ownerId);
  Future<void> replaceCredentialForOwnerFenced(
    String ownerId,
    AiTutorCredential? credential, {
    required String operationVersion,
    required Future<bool> Function() leaseIsOwned,
    required DateTime Function() nowUtc,
  });
  Future<int> recoverCredentialMutations({
    required String leaseToken,
    required DateTime Function() nowUtc,
  });
  Future<void> eraseOwnerCredentialsFenced(
    String ownerId, {
    required String leaseToken,
    required Future<bool> Function() leaseIsOwned,
    required DateTime Function() nowUtc,
  });
  Future<String?> readKey();
  Future<void> writeKey(String key);
  Future<void> deleteKey();
  Future<bool> readProviderConsent();
  Future<void> writeProviderConsent(bool value);
  Future<bool> readLearningSummaryConsent();
  Future<void> writeLearningSummaryConsent(bool value);
  Future<AiProviderId> readProviderId();
  Future<void> writeProviderId(AiProviderId provider);
  Future<String?> readModel();
  Future<void> writeModel(String model);
  Future<String?> readCustomBaseUrl();
  Future<void> writeCustomBaseUrl(String url);
}

abstract interface class AiTutorGateway {
  AiProviderId get providerId;
  String get model;

  Future<void> validateKey(String key, {AiCancellation? cancellation});

  Future<List<AiModel>> listModels(String key, {AiCancellation? cancellation});

  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  });
}

abstract interface class AiTutorController {
  Future<AiTutorSettingsStatus> loadSettings();

  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  });

  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  });

  /// Lists models using the credential already held in secure storage.
  /// The stored key is never returned to the caller.
  /// Throws [AiFailureCode.missingKey] when no credential is stored.
  /// Throws [AiFailureCode.consentRequired] when provider consent is revoked.
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  });

  /// Replaces only the model and [shareLearningSummary] flag using the
  /// credential already held in secure storage. Runs one configuration probe
  /// before the atomic write; failure leaves the previous credential unchanged.
  /// The stored key is never returned to the caller.
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  });

  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  });

  Future<void> removeKey();

  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    AiCancellation? cancellation,
  });

  Future<List<AiUsageSummary>> loadUsage();

  Future<void> clearUsage();

  Future<void> dispose();
}

Uri validateCustomAiBaseUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final ipv4 = host.split('.').map(int.tryParse).toList(growable: false);
  final isIpv4 = ipv4.length == 4 && ipv4.every((part) => part != null);
  final isPrivateIpv4 =
      isIpv4 &&
      (ipv4[0] == 10 ||
          ipv4[0] == 127 ||
          (ipv4[0] == 192 && ipv4[1] == 168) ||
          (ipv4[0] == 172 && ipv4[1]! >= 16 && ipv4[1]! <= 31));
  final unsafe =
      uri.scheme.toLowerCase() != 'https' ||
      host.isEmpty ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host == '::1' ||
      isPrivateIpv4;
  if (unsafe || uri.hasFragment || uri.userInfo.isNotEmpty) {
    throw const AiTutorException(AiFailureCode.unsafeEndpoint);
  }
  return uri;
}

Uri parseAndValidateCustomAiBaseUri(String value) {
  final canonical = value.trim();
  if (canonical.isEmpty || RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(canonical)) {
    throw const AiTutorException(AiFailureCode.unsafeEndpoint);
  }
  try {
    return validateCustomAiBaseUri(Uri.parse(canonical));
  } on AiTutorException {
    rethrow;
  } on Object {
    throw const AiTutorException(AiFailureCode.unsafeEndpoint);
  }
}
