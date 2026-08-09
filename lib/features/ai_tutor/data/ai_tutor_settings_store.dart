import 'dart:convert';

import '../../gemini/data/secure_gemini_settings_store.dart';
import '../domain/ai_tutor_contracts.dart';

typedef ActiveAiTutorOwnerIdProvider = Future<String> Function();

/// Stores the single active BYOK profile as one secure value so provider,
/// model, consent, endpoint and key cannot be partially switched.
final class SecureAiTutorSettingsStore implements AiTutorSettingsStore {
  SecureAiTutorSettingsStore(this._storage, {required this.activeOwnerId});

  factory SecureAiTutorSettingsStore.production({
    required ActiveAiTutorOwnerIdProvider activeOwnerId,
  }) => SecureAiTutorSettingsStore(
    FlutterSecureValueStore(),
    activeOwnerId: activeOwnerId,
  );

  final SecureValueStore _storage;
  final ActiveAiTutorOwnerIdProvider activeOwnerId;

  static const _profile = 'ai_active_profile_v2';
  static const _apiKey = 'ai_api_key_v2';
  static const _providerConsent = 'ai_provider_consent_v2';
  static const _summaryConsent = 'ai_learning_summary_consent_v2';
  static const _providerId = 'ai_provider_id_v2';
  static const _model = 'ai_model_v2';
  static const _customBaseUrl = 'ai_custom_base_url_v2';
  static const _scopedKeys = <String>[
    _profile,
    _apiKey,
    _providerConsent,
    _summaryConsent,
    _providerId,
    _model,
    _customBaseUrl,
  ];
  static const _legacyKeys = <String>[
    'ai_active_profile_v1',
    'ai_api_key',
    'gemini_api_key',
    'ai_provider_consent',
    'ai_learning_summary_consent',
    'ai_provider_id',
    'ai_model',
    'ai_custom_base_url',
  ];

  bool _legacyDiscarded = false;

  @override
  Future<AiTutorCredential?> readCredential() async {
    return readCredentialForOwner(await resolveActiveOwnerId());
  }

  @override
  Future<String> resolveActiveOwnerId() async {
    return _requireOwnerId(await activeOwnerId());
  }

  @override
  Future<AiTutorCredential?> readCredentialForOwner(String ownerId) async {
    await _discardUnscopedLegacyValues();
    final raw = await _readForOwner(_profile, _requireOwnerId(ownerId));
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
    await writeCredentialForOwner(await resolveActiveOwnerId(), credential);
  }

  @override
  Future<void> writeCredentialForOwner(
    String ownerId,
    AiTutorCredential credential,
  ) async {
    await _discardUnscopedLegacyValues();
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
    await _writeForOwner(
      _profile,
      _requireOwnerId(ownerId),
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
    await deleteCredentialForOwner(await resolveActiveOwnerId());
  }

  @override
  Future<void> deleteCredentialForOwner(String ownerId) async {
    await _discardUnscopedLegacyValues();
    final ownerToken = _ownerToken(_requireOwnerId(ownerId));
    for (final baseKey in _scopedKeys) {
      await _delete('$baseKey:$ownerToken');
    }
  }

  @override
  Future<String?> readKey() async => (await readCredential())?.key;

  @override
  Future<void> writeKey(String key) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(ownerId, current.copyWith(key: key));
      return;
    }
    await _writeForOwner(_apiKey, ownerId, key);
  }

  @override
  Future<void> deleteKey() => deleteCredential();

  @override
  Future<bool> readProviderConsent() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.providerConsent ??
        await _readForOwner(_providerConsent, ownerId) == 'true';
  }

  @override
  Future<void> writeProviderConsent(bool value) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(
          providerConsent: value,
          shareLearningSummary: value && current.shareLearningSummary,
        ),
      );
      return;
    }
    await _writeForOwner(_providerConsent, ownerId, value.toString());
  }

  @override
  Future<bool> readLearningSummaryConsent() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.shareLearningSummary ??
        await _readForOwner(_summaryConsent, ownerId) == 'true';
  }

  @override
  Future<void> writeLearningSummaryConsent(bool value) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(shareLearningSummary: value),
      );
      return;
    }
    await _writeForOwner(_summaryConsent, ownerId, value.toString());
  }

  @override
  Future<AiProviderId> readProviderId() async {
    final ownerId = await resolveActiveOwnerId();
    final credential = await readCredentialForOwner(ownerId);
    if (credential != null) return credential.providerId;
    final raw = await _readForOwner(_providerId, ownerId);
    return AiProviderId.values
            .where((provider) => provider.name == raw)
            .firstOrNull ??
        AiProviderId.gemini;
  }

  @override
  Future<void> writeProviderId(AiProviderId provider) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.model.isNotEmpty) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(providerId: provider),
      );
      return;
    }
    await _writeForOwner(_providerId, ownerId, provider.name);
  }

  @override
  Future<String?> readModel() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.model.nullIfEmpty ??
        await _readForOwner(_model, ownerId);
  }

  @override
  Future<void> writeModel(String model) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null) {
      await writeCredentialForOwner(ownerId, current.copyWith(model: model));
      return;
    }
    await _writeForOwner(_model, ownerId, model);
  }

  @override
  Future<String?> readCustomBaseUrl() async {
    final ownerId = await resolveActiveOwnerId();
    return (await readCredentialForOwner(ownerId))?.customBaseUrl ??
        await _readForOwner(_customBaseUrl, ownerId);
  }

  @override
  Future<void> writeCustomBaseUrl(String url) async {
    final ownerId = await resolveActiveOwnerId();
    final current = await readCredentialForOwner(ownerId);
    if (current != null && current.providerId == AiProviderId.customOpenAi) {
      await writeCredentialForOwner(
        ownerId,
        current.copyWith(customBaseUrl: url),
      );
      return;
    }
    await _writeForOwner(_customBaseUrl, ownerId, url);
  }

  Future<void> _discardUnscopedLegacyValues() async {
    if (_legacyDiscarded) return;
    for (final key in _legacyKeys) {
      await _delete(key);
    }
    _legacyDiscarded = true;
  }

  Future<String?> _readForOwner(String baseKey, String ownerId) async {
    return _read(_scopedKey(baseKey, ownerId));
  }

  Future<void> _writeForOwner(
    String baseKey,
    String ownerId,
    String value,
  ) async {
    await _write(_scopedKey(baseKey, ownerId), value);
  }

  String _requireOwnerId(String value) {
    final ownerId = value.trim();
    if (ownerId.isEmpty) {
      throw StateError('Active owner id must not be empty.');
    }
    return ownerId;
  }

  String _scopedKey(String baseKey, String ownerId) {
    return '$baseKey:${_ownerToken(_requireOwnerId(ownerId))}';
  }

  String _ownerToken(String ownerId) =>
      base64Url.encode(utf8.encode(ownerId)).replaceAll('=', '');

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
