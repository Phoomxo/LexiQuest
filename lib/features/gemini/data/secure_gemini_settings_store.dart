import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/gemini_contracts.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'lexiquest_gemini_byok',
              keyCipherAlgorithm: KeyCipherAlgorithm.AES_GCM_NoPadding,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class SecureGeminiSettingsStore implements GeminiSettingsStore {
  SecureGeminiSettingsStore(this._storage);

  factory SecureGeminiSettingsStore.production() =>
      SecureGeminiSettingsStore(FlutterSecureValueStore());

  static const _apiKey = 'gemini_api_key';
  static const _providerConsent = 'gemini_provider_consent';
  static const _summaryConsent = 'gemini_learning_summary_consent';

  final SecureValueStore _storage;

  @override
  Future<String?> readKey() => _read(_apiKey);

  @override
  Future<void> writeKey(String key) => _write(_apiKey, key);

  @override
  Future<void> deleteKey() => _delete(_apiKey);

  @override
  Future<bool> readProviderConsent() async =>
      await _read(_providerConsent) == 'true';

  @override
  Future<void> writeProviderConsent(bool value) =>
      _write(_providerConsent, value.toString());

  @override
  Future<bool> readLearningSummaryConsent() async =>
      await _read(_summaryConsent) == 'true';

  @override
  Future<void> writeLearningSummaryConsent(bool value) =>
      _write(_summaryConsent, value.toString());

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key);
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key, value);
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key);
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }
}
