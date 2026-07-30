import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

void main() {
  test('stores key and consent without exposing key through status', () async {
    final values = <String, String>{};
    final store = SecureGeminiSettingsStore(_MemorySecureStore(values));

    await store.writeKey('private-key');
    await store.writeProviderConsent(true);
    await store.writeLearningSummaryConsent(true);

    expect(await store.readKey(), 'private-key');
    expect(await store.readProviderConsent(), isTrue);
    expect(await store.readLearningSummaryConsent(), isTrue);
    await store.deleteKey();
    expect(await store.readKey(), isNull);
  });

  test('maps platform storage errors without including secret', () async {
    final store = SecureGeminiSettingsStore(_FailingSecureStore());

    await expectLater(
      store.writeKey('secret-sentinel'),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.secureStorage,
        ),
      ),
    );
  });
}

final class _MemorySecureStore implements SecureValueStore {
  _MemorySecureStore(this.values);
  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
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
