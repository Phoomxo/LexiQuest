import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';

void main() {
  final noopClient = MockClient((_) async => http.Response('{}', 200));

  test('gemini resolves a gateway with the Gemini provider id', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProvider.gemini,
      model: 'gemini-2.5-flash-lite',
    );
    expect(gateway.providerId, AiProvider.gemini);
    expect(gateway.model, 'gemini-2.5-flash-lite');
  });

  test('openai resolves the native Responses API gateway', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProvider.openai,
      model: 'gpt-4o-mini',
    );
    expect(gateway.providerId, AiProvider.openai);
    expect(gateway.model, 'gpt-4o-mini');
  });

  test('maxPlus resolves an OpenAI-compatible preset', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProviderId.maxPlus,
      model: 'maxplus-model',
    );
    expect(gateway.providerId, AiProviderId.maxPlus);
    expect(gateway.model, 'maxplus-model');
  });

  test('openrouter resolves a gateway with the OpenRouter base URL', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProvider.openrouter,
      model: 'openai/gpt-4o-mini',
    );
    expect(gateway.providerId, AiProvider.openrouter);
  });

  test('claude resolves the Anthropic gateway', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProvider.claude,
      model: 'claude-3-5-haiku-latest',
    );
    expect(gateway.providerId, AiProvider.claude);
    expect(gateway.model, 'claude-3-5-haiku-latest');
  });

  test('customOpenAi uses the supplied custom base URL', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    final gateway = factory.create(
      providerId: AiProvider.customOpenAi,
      model: 'cointh-chat-v1',
      customBaseUrl: Uri.https('api.cointh.example', '/v1/'),
    );
    expect(gateway.providerId, AiProvider.customOpenAi);
    expect(gateway.model, 'cointh-chat-v1');
  });

  test('customOpenAi rejects an unsafe base URL at the factory boundary', () {
    final factory = AiTutorGatewayFactory(client: noopClient);

    expect(
      () => factory.create(
        providerId: AiProvider.customOpenAi,
        model: 'local-model',
        customBaseUrl: Uri.parse('http://192.168.1.20/v1/'),
      ),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.unsafeEndpoint,
        ),
      ),
    );
  });

  test('requires an explicit model instead of using a stale default', () {
    final factory = AiTutorGatewayFactory(client: noopClient);
    expect(
      () => factory.create(providerId: AiProvider.openai),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.missingModel,
        ),
      ),
    );
  });

  test('createForStore reads provider and model from the store', () async {
    final backing = _MemoryValueStore()
      ..write('ai_provider_id', 'openai')
      ..write('ai_model', 'gpt-4o');
    final store = SecureAiTutorSettingsStore(backing);
    final factory = AiTutorGatewayFactory(client: noopClient);

    final gateway = await factory.createForStore(store);

    expect(gateway.providerId, AiProvider.openai);
    expect(gateway.model, 'gpt-4o');
  });
}

final class _MemoryValueStore implements SecureValueStore {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}
