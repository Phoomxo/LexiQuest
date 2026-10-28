import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  group('AiProviderConfig', () {
    test('provides a config for every provider id', () {
      for (final provider in AiProviderId.values) {
        final config = AiProviderConfig.forId(provider);
        expect(config.id, provider);
        expect(config.displayName, isNotEmpty);
      }
    });

    test('all returns every provider in enum order', () {
      final configs = AiProviderConfig.all;
      expect(configs.length, AiProviderId.values.length);
      expect(configs.map((c) => c.id).toList(), AiProviderId.values.toList());
      expect(
        configs.every((config) => config.isExperimental),
        isTrue,
        reason: 'direct-client BYOK remains a controlled rollout feature',
      );
    });

    test('gemini uses the Google endpoint and flash-lite default', () {
      final config = AiProviderConfig.forId(AiProviderId.gemini);
      expect(
        config.baseUri.toString(),
        'https://generativelanguage.googleapis.com/',
      );
      expect(config.defaultModel, isNull);
      expect(config.supportsCustomBaseUrl, isFalse);
    });

    test('openai uses the OpenAI v1 endpoint', () {
      final config = AiProviderConfig.forId(AiProviderId.openai);
      expect(config.baseUri.toString(), 'https://api.openai.com/v1/');
      expect(config.defaultModel, isNull);
    });

    test('openrouter uses the OpenRouter api v1 endpoint', () {
      final config = AiProviderConfig.forId(AiProviderId.openrouter);
      expect(config.baseUri.toString(), 'https://openrouter.ai/api/v1/');
    });

    test('claude uses the Anthropic endpoint', () {
      final config = AiProviderConfig.forId(AiProviderId.claude);
      expect(config.baseUri.toString(), 'https://api.anthropic.com/');
      expect(config.defaultModel, isNull);
    });

    test('maxPlus is a first-class provider preset', () {
      final config = AiProviderConfig.forId(AiProviderId.maxPlus);
      expect(config.baseUri.toString(), 'https://api.maxplus-ai.cc/v1/');
      expect(config.defaultModel, isNull);
      expect(config.supportsCustomBaseUrl, isFalse);
    });

    test('customOpenAi supports a custom base URL', () {
      final config = AiProviderConfig.forId(AiProviderId.customOpenAi);
      expect(config.supportsCustomBaseUrl, isTrue);
      expect(config.supportsCustomModel, isTrue);
    });
  });

  group('AiTutorSettingsStatus', () {
    test('carries provider and model alongside consent state', () {
      const status = AiTutorSettingsStatus(
        hasKey: true,
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openai,
        model: 'gpt-4o',
      );
      expect(status.hasKey, isTrue);
      expect(status.providerId, AiProviderId.openai);
      expect(status.model, 'gpt-4o');
    });
  });

  group('custom endpoint policy', () {
    test('accepts a public HTTPS endpoint', () {
      expect(
        validateCustomAiBaseUri(Uri.parse('https://api.example.com/v1/')),
        Uri.parse('https://api.example.com/v1/'),
      );
    });

    test('rejects HTTP, localhost, and private network endpoints', () {
      for (final value in <String>[
        'http://api.example.com/v1/',
        'https://localhost/v1/',
        'https://127.0.0.1/v1/',
        'https://10.1.2.3/v1/',
        'https://192.168.1.2/v1/',
        'https://172.16.0.1/v1/',
      ]) {
        expect(
          () => validateCustomAiBaseUri(Uri.parse(value)),
          throwsA(
            isA<AiTutorException>().having(
              (error) => error.code,
              'code',
              AiFailureCode.unsafeEndpoint,
            ),
          ),
        );
      }
    });
  });
}
