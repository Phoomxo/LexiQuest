import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

void main() {
  test('uses non-biometric Android Keystore wrapping for unattended reads', () {
    final options = lexiQuestGeminiAndroidOptions.toMap();

    expect(options['storageNamespace'], 'lexiquest_gemini_byok_v2');
    expect(
      options['keyCipherAlgorithm'],
      'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
    );
    expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
    expect(options['enforceBiometrics'], 'false');
    expect(options['migrateOnAlgorithmChange'], 'false');
    expect(options['resetOnError'], 'false');
  });

  test('stores key and consent without exposing key through status', () async {
    final values = <String, String>{};
    final store = SecureGeminiSettingsStore(_MemorySecureStore(values));

    await store.write(
      _scopeA,
      const GeminiConfiguration(
        key: 'synthetic-private-key',
        providerConsent: true,
        shareLearningSummary: true,
      ),
    );
    final configuration = await store.read(_scopeA);
    expect(configuration.key, 'synthetic-private-key');
    expect(configuration.status.providerConsent, isFalse);
    expect(configuration.status.shareLearningSummary, isFalse);
    expect(
      configuration.status.toString(),
      isNot(contains('synthetic-private-key')),
    );
    expect((await store.read(_scopeB)).key, isNull);
    await store.write(_scopeA, const GeminiConfiguration());
    expect((await store.read(_scopeA)).key, isNull);
  });

  test('maps platform storage errors without including secret', () async {
    final store = SecureGeminiSettingsStore(_FailingSecureStore());

    await expectLater(
      store.write(_scopeA, const GeminiConfiguration(key: 'secret-sentinel')),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.secureStorage,
        ),
      ),
    );
  });

  test('deletes only the exact scoped secret and is idempotent', () async {
    final values = <String, String>{'gemini_api_key': 'synthetic-legacy'};
    final store = SecureGeminiSettingsStore(_MemorySecureStore(values));
    await store.write(_scopeA, const GeminiConfiguration(key: 'synthetic-A'));
    await store.write(_scopeB, const GeminiConfiguration(key: 'synthetic-B'));

    await store.delete(_scopeA);
    await store.delete(_scopeA);

    expect((await store.read(_scopeA)).key, isNull);
    expect((await store.read(_scopeB)).key, 'synthetic-B');
    expect(values['gemini_api_key'], 'synthetic-legacy');
  });

  test('maps delete failures to secure storage failure', () async {
    final store = SecureGeminiSettingsStore(_FailingSecureStore());

    await expectLater(
      store.delete(_scopeA),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.secureStorage,
        ),
      ),
    );
  });

  test(
    'legacy globals are neither read nor changed and scoped record restores coherently',
    () async {
      final values = <String, String>{
        'gemini_api_key': 'synthetic-legacy',
        'gemini_provider_consent': 'true',
        'gemini_learning_summary_consent': 'true',
      };
      final storage = _MemorySecureStore(values);
      final store = SecureGeminiSettingsStore(storage);
      expect((await store.read(_scopeA)).status.hasKey, isFalse);
      await store.write(
        _scopeA,
        const GeminiConfiguration(
          key: 'synthetic-A',
          providerConsent: true,
          shareLearningSummary: true,
        ),
      );
      final restarted = SecureGeminiSettingsStore(storage);
      expect((await restarted.read(_scopeA)).key, 'synthetic-A');
      expect((await restarted.read(_scopeB)).status.hasKey, isFalse);
      expect(
        (await restarted.read(
          const GeminiScope(
            ownerId: 'A',
            firebaseUid: 'uid-A',
            isAnonymous: true,
          ),
        )).status.hasKey,
        isFalse,
      );
      expect(storage.accesses.any((key) => key.startsWith('gemini_')), isFalse);
      expect(values['gemini_api_key'], 'synthetic-legacy');
      expect(values['gemini_provider_consent'], 'true');
      expect(values['gemini_learning_summary_consent'], 'true');
      expect(storage.writes, 1);
    },
  );

  test(
    'malformed or incomplete scoped record fails closed without leaking content',
    () async {
      final values = <String, String>{};
      final storage = _MemorySecureStore(values);
      final store = SecureGeminiSettingsStore(storage);
      await store.write(
        _scopeA,
        const GeminiConfiguration(key: 'synthetic-key', providerConsent: true),
      );
      final path = values.keys.single;
      for (final malformed in [
        'secret-sentinel',
        '{}',
        '{"v":1,"key":"synthetic-key","providerConsent":true}',
      ]) {
        values[path] = malformed;
        await expectLater(
          store.read(_scopeA),
          throwsA(
            isA<GeminiException>().having(
              (e) => e.code,
              'code',
              GeminiFailureCode.secureStorage,
            ),
          ),
        );
      }
    },
  );
}

const _scopeA = GeminiScope(
  ownerId: 'A',
  firebaseUid: 'uid-A',
  isAnonymous: false,
);
const _scopeB = GeminiScope(
  ownerId: 'B',
  firebaseUid: 'uid-B',
  isAnonymous: false,
);

final class _MemorySecureStore implements SecureValueStore {
  _MemorySecureStore(this.values);
  final Map<String, String> values;
  final accesses = <String>[];
  int writes = 0;

  @override
  Future<void> delete(String key) async {
    accesses.add(key);
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    accesses.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    accesses.add(key);
    writes += 1;
    values[key] = value;
  }
}

final class _FailingSecureStore implements SecureValueStore {
  @override
  Future<void> delete(String key) =>
      throw PlatformException(code: 'secure-failure');

  @override
  Future<String?> read(String key) =>
      throw PlatformException(code: 'secure-failure');

  @override
  Future<void> write(String key, String value) =>
      throw PlatformException(code: 'secure-failure');
}
