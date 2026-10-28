import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/gemini_contracts.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The field-study build performs unattended reads while AI Tutor opens, so it
/// uses the package's standard RSA-wrapped AES configuration rather than its
/// biometric key cipher. The v2 namespace intentionally leaves the broken
/// pre-study AES-key namespace behind; no participant key was stored there.
///
/// Automatic migration/reset are disabled because flutter_secure_storage
/// 10.3.1 can recursively re-enter recovery on some Android Keystore failures.
/// A failure is returned to Dart and shown as a typed storage error instead of
/// terminating the process.
const lexiQuestGeminiAndroidOptions = AndroidOptions(
  storageNamespace: 'lexiquest_gemini_byok_v2',
  resetOnError: false,
  migrateOnAlgorithmChange: false,
  keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
  storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
);

final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: lexiQuestGeminiAndroidOptions,
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
