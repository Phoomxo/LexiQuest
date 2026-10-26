import 'dart:convert';

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

  final SecureValueStore _storage;

  String _path(GeminiScope scope) =>
      'lq_gemini_scoped_v1_${base64Url.encode(utf8.encode(jsonEncode([scope.ownerId, scope.firebaseUid, scope.isAnonymous])))}';

  @override
  Future<GeminiConfiguration> read(GeminiScope scope) async {
    try {
      final raw = await _storage.read(_path(scope));
      if (raw == null) return const GeminiConfiguration();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['v'] != 1 ||
          !(data['key'] == null || data['key'] is String) ||
          !data.containsKey('key') ||
          data['providerConsent'] is! bool ||
          data['shareLearningSummary'] is! bool) {
        throw const GeminiException(GeminiFailureCode.secureStorage);
      }
      // A stored credential never restores session consent, including old records.
      return GeminiConfiguration(key: data['key'] as String?);
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }

  @override
  Future<void> write(
    GeminiScope scope,
    GeminiConfiguration configuration,
  ) async {
    try {
      // One secure item prevents mixed key/consent revisions; no legacy lookup.
      await _storage.write(
        _path(scope),
        jsonEncode({
          'v': 1,
          'key': configuration.key,
          'providerConsent': false,
          'shareLearningSummary': false,
        }),
      );
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }

  Future<void> delete(GeminiScope scope) async {
    try {
      await _storage.delete(_path(scope));
    } on Object {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }
}
