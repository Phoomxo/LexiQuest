import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';

/// In-memory SecureValueStore for tests.
final class _MemoryValueStore implements SecureValueStore {
  final Map<String, String> _data = {};
  bool failNextProfileWrite = false;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == 'ai_active_profile_v1' && failNextProfileWrite) {
      failNextProfileWrite = false;
      throw StateError('injected write failure');
    }
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

void main() {
  late _MemoryValueStore backing;
  late SecureAiTutorSettingsStore store;

  setUp(() {
    backing = _MemoryValueStore();
    store = SecureAiTutorSettingsStore(backing);
  });

  test('reads and writes provider id', () async {
    expect(await store.readProviderId(), AiProvider.gemini);
    await store.writeProviderId(AiProvider.openai);
    expect(await store.readProviderId(), AiProvider.openai);
  });

  test('reads and writes model', () async {
    expect(await store.readModel(), isNull);
    await store.writeModel('gpt-4o');
    expect(await store.readModel(), 'gpt-4o');
  });

  test('reads and writes the API key', () async {
    expect(await store.readKey(), isNull);
    await store.writeKey('sk-test-123');
    expect(await store.readKey(), 'sk-test-123');
  });

  test(
    'migrates a legacy gemini_api_key to the new key on first read',
    () async {
      await backing.write('gemini_api_key', 'legacy-gemini-key');
      final store = SecureAiTutorSettingsStore(backing);

      final key = await store.readKey();

      expect(key, 'legacy-gemini-key');
      final credential = await store.readCredential();
      expect(credential?.key, 'legacy-gemini-key');
      expect(credential?.providerId, AiProviderId.gemini);
    },
  );

  test('deleteKey removes the api key', () async {
    await store.writeKey('sk-test-456');
    await store.deleteKey();
    expect(await store.readKey(), isNull);
  });

  test('writes and reads consent flags', () async {
    await store.writeProviderConsent(true);
    await store.writeLearningSummaryConsent(true);
    expect(await store.readProviderConsent(), isTrue);
    expect(await store.readLearningSummaryConsent(), isTrue);
  });

  test('a corrupted provider id falls back to gemini', () async {
    await backing.write('ai_provider_id', 'not-a-real-provider');
    expect(await store.readProviderId(), AiProvider.gemini);
  });

  test('writes the active credential as one secure profile', () async {
    await store.writeCredential(
      const AiTutorCredential(
        key: 'sk-secret-value',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );

    final restored = await store.readCredential();
    expect(restored?.key, 'sk-secret-value');
    expect(restored?.providerId, AiProviderId.openrouter);
    expect(restored?.model, 'provider/model');
    expect(backing._data.keys, contains('ai_active_profile_v1'));
  });

  test('failed profile replacement leaves the old profile active', () async {
    await store.writeCredential(
      const AiTutorCredential(
        key: 'old-key',
        providerId: AiProviderId.gemini,
        model: 'old-model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    backing.failNextProfileWrite = true;

    await expectLater(
      store.writeCredential(
        const AiTutorCredential(
          key: 'new-key',
          providerId: AiProviderId.openai,
          model: 'new-model',
          providerConsent: true,
          shareLearningSummary: false,
        ),
      ),
      throwsA(isA<AiTutorException>()),
    );

    final restored = await store.readCredential();
    expect(restored?.key, 'old-key');
    expect(restored?.providerId, AiProviderId.gemini);
  });
}
