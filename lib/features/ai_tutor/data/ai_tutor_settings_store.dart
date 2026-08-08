import 'dart:convert';

import '../../gemini/data/secure_gemini_settings_store.dart';
import '../domain/ai_tutor_contracts.dart';

/// Stores the single active BYOK profile as one secure value so provider,
/// model, consent, endpoint and key cannot be partially switched.
final class SecureAiTutorSettingsStore implements AiTutorSettingsStore {
  SecureAiTutorSettingsStore(this._storage);

  factory SecureAiTutorSettingsStore.production() =>
      SecureAiTutorSettingsStore(FlutterSecureValueStore());

  final SecureValueStore _storage;

  static const _profile = 'ai_active_profile_v1';
  static const _apiKey = 'ai_api_key';
  static const _legacyApiKey = 'gemini_api_key';
  static const _providerConsent = 'ai_provider_consent';
  static const _summaryConsent = 'ai_learning_summary_consent';
  static const _providerId = 'ai_provider_id';
  static const _model = 'ai_model';
  static const _customBaseUrl = 'ai_custom_base_url';

  bool _migrated = false;

  @override
  Future<AiTutorCredential?> readCredential() async {
    await _migrateLegacyValues();
    final raw = await _read(_profile);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['version'] != 1) {
        throw const FormatException();
      }
      final key = json['key'];
      final providerRaw = json['providerId'];
      final model = json['model'];
      final provider = AiProviderId.values
          .where((value) => value.name == providerRaw)
          .firstOrNull;
      if (key is! String ||
          key.trim().isEmpty ||
          provider == null ||
          model is! String ||
          json['providerConsent'] is! bool ||
          json['shareLearningSummary'] is! bool) {
        throw const FormatException();
      }
      final customBaseUrl = json['customBaseUrl'];
      return AiTutorCredential(
        key: key,
        providerId: provider,
        model: model,
        providerConsent: json['providerConsent'] as bool,
        shareLearningSummary: json['shareLearningSummary'] as bool,
        customBaseUrl: customBaseUrl is String ? customBaseUrl : null,
      );
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  @override
  Future<void> writeCredential(AiTutorCredential credential) async {
    final key = credential.key.trim();
    final model = credential.model.trim();
    if (key.isEmpty || key.length > 512) {
      throw const AiTutorException(AiFailureCode.invalidKey);
    }
    if (model.isEmpty || model.length > 200) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    String? customBaseUrl;
    if (credential.providerId == AiProviderId.customOpenAi) {
      final raw = credential.customBaseUrl;
      if (raw == null || raw.trim().isEmpty) {
        throw const AiTutorException(AiFailureCode.unsafeEndpoint);
      }
      customBaseUrl = validateCustomAiBaseUri(Uri.parse(raw.trim())).toString();
    }
    await _write(
      _profile,
      jsonEncode({
        'version': 1,
        'key': key,
        'providerId': credential.providerId.name,
        'model': model,
        'providerConsent': credential.providerConsent,
        'shareLearningSummary':
            credential.providerConsent && credential.shareLearningSummary,
        'customBaseUrl': ?customBaseUrl,
      }),
    );
  }

  @override
  Future<void> deleteCredential() async {
    await _delete(_profile);
    await _delete(_apiKey);
    await _delete(_legacyApiKey);
  }

  @override
  Future<String?> readKey() async => (await readCredential())?.key;

  @override
  Future<void> writeKey(String key) async {
    final current = await readCredential();
    if (current != null && current.model.isNotEmpty) {
      await writeCredential(current.copyWith(key: key));
      return;
    }
    await _write(_apiKey, key);
    _migrated = false;
  }

  @override
  Future<void> deleteKey() => deleteCredential();

  @override
  Future<bool> readProviderConsent() async =>
      (await readCredential())?.providerConsent ??
      await _read(_providerConsent) == 'true';

  @override
  Future<void> writeProviderConsent(bool value) async {
    final current = await readCredential();
    if (current != null && current.model.isNotEmpty) {
      await writeCredential(
        current.copyWith(
          providerConsent: value,
          shareLearningSummary: value && current.shareLearningSummary,
        ),
      );
      return;
    }
    await _write(_providerConsent, value.toString());
  }

  @override
  Future<bool> readLearningSummaryConsent() async =>
      (await readCredential())?.shareLearningSummary ??
      await _read(_summaryConsent) == 'true';

  @override
  Future<void> writeLearningSummaryConsent(bool value) async {
    final current = await readCredential();
    if (current != null && current.model.isNotEmpty) {
      await writeCredential(current.copyWith(shareLearningSummary: value));
      return;
    }
    await _write(_summaryConsent, value.toString());
  }

  @override
  Future<AiProviderId> readProviderId() async {
    final credential = await readCredential();
    if (credential != null) return credential.providerId;
    final raw = await _read(_providerId);
    return AiProviderId.values
            .where((provider) => provider.name == raw)
            .firstOrNull ??
        AiProviderId.gemini;
  }

  @override
  Future<void> writeProviderId(AiProviderId provider) async {
    final current = await readCredential();
    if (current != null && current.model.isNotEmpty) {
      await writeCredential(current.copyWith(providerId: provider));
      return;
    }
    await _write(_providerId, provider.name);
  }

  @override
  Future<String?> readModel() async =>
      (await readCredential())?.model.nullIfEmpty ?? await _read(_model);

  @override
  Future<void> writeModel(String model) async {
    final current = await readCredential();
    if (current != null) {
      await writeCredential(current.copyWith(model: model));
      return;
    }
    await _write(_model, model);
  }

  @override
  Future<String?> readCustomBaseUrl() async =>
      (await readCredential())?.customBaseUrl ?? await _read(_customBaseUrl);

  @override
  Future<void> writeCustomBaseUrl(String url) async {
    final current = await readCredential();
    if (current != null && current.providerId == AiProviderId.customOpenAi) {
      await writeCredential(current.copyWith(customBaseUrl: url));
      return;
    }
    await _write(_customBaseUrl, url);
  }

  Future<void> _migrateLegacyValues() async {
    if (_migrated) return;
    _migrated = true;
    if (await _read(_profile) != null) return;
    final key = await _read(_apiKey) ?? await _read(_legacyApiKey);
    if (key == null || key.trim().isEmpty) return;
    final providerRaw = await _read(_providerId);
    final provider =
        AiProviderId.values
            .where((value) => value.name == providerRaw)
            .firstOrNull ??
        AiProviderId.gemini;
    final model = await _read(_model) ?? '';
    await _write(
      _profile,
      jsonEncode({
        'version': 1,
        'key': key.trim(),
        'providerId': provider.name,
        'model': model,
        'providerConsent': await _read(_providerConsent) == 'true',
        'shareLearningSummary': await _read(_summaryConsent) == 'true',
        if (await _read(_customBaseUrl) case final String value)
          'customBaseUrl': value,
      }),
    );
    await _delete(_apiKey);
    await _delete(_legacyApiKey);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key, value);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key);
    } on Object {
      throw const AiTutorException(AiFailureCode.secureStorage);
    }
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
