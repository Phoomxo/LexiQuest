import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test(
    'every production screen stays behind composed AI and voice facades',
    () {
      final screens = Directory('lib/screens')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList(growable: false);
      final forbidden = <RegExp>[
        RegExp(r"package:http/http\.dart"),
        RegExp(r"import\s+'dart:io'"),
        RegExp(r'\bVoiceProvider\b'),
        RegExp(r'VoiceUseCases\.createDefault'),
        RegExp(r'VoiceServiceFactory'),
        RegExp(r'\.provider\b'),
        RegExp(r'\bdisposeIfOwned\b'),
        RegExp(r'String\.fromEnvironment'),
        RegExp(r'\bAiTutorUseCases\s*\('),
        RegExp(r'\bGeminiTutorUseCases\s*\('),
        RegExp(r'\bAiTutorGatewayFactory\s*\('),
        RegExp(r'\bGeminiRestGateway\s*\('),
        RegExp(r'\bOpenAiResponsesGateway\s*\('),
        RegExp(r'\bOpenAiCompatibleGateway\s*\('),
        RegExp(r'\bAnthropicGateway\s*\('),
      ];

      expect(screens, isNotEmpty);
      for (final file in screens) {
        final source = file.readAsStringSync();
        for (final pattern in forbidden) {
          expect(
            pattern.hasMatch(source),
            isFalse,
            reason: '${file.path} crosses ${pattern.pattern}',
          );
        }
        if (source.contains('VoiceUseCases?')) {
          expect(
            source,
            contains('RouteVoiceSessionMixin'),
            reason: '${file.path} must acquire an opaque route voice session',
          );
          expect(
            source,
            contains('AppDependenciesScope.maybeOf(context)'),
            reason: '${file.path} must resolve the bootstrap-owned facade',
          );
        }
      }
    },
  );

  test('use-case boundaries do not own hidden clients or raw providers', () {
    final aiUseCases = _read(
      'lib/features/ai_tutor/application/ai_tutor_use_cases.dart',
    );
    final voiceUseCases = _read(
      'lib/features/voice/application/voice_use_cases.dart',
    );
    final voiceFactory = _read('lib/voice/voice_service_factory.dart');
    final backgroundAudio = _read(
      'lib/services/background_audio_player_service.dart',
    );

    expect(aiUseCases, isNot(contains('package:http/http.dart')));
    expect(aiUseCases, isNot(contains('http.Client')));
    expect(aiUseCases, isNot(contains('AiTutorGatewayFactory(')));
    expect(voiceUseCases, isNot(contains('VoiceUseCases.createDefault')));
    expect(voiceUseCases, isNot(contains('disposeIfOwned')));
    expect(voiceUseCases, isNot(contains(' get provider')));
    expect(voiceFactory, isNot(contains('AppConfig.fromEnvironment')));
    expect(voiceFactory, isNot(contains('http.Client()')));
    expect(backgroundAudio, contains('VoiceSession'));
    expect(backgroundAudio, isNot(contains('VoiceProvider')));
    expect(
      File('lib/runtime/scoped_voice_provider.dart').existsSync(),
      isFalse,
    );
  });

  test('AppDependencies exposes one provider-neutral production boundary', () {
    final dependencies = _read('lib/runtime/app_dependencies.dart');
    final bootstrap = _read('lib/runtime/app_bootstrap.dart');

    expect(dependencies, contains('final AiTutorController? aiTutor;'));
    expect(dependencies, contains('final VoiceUseCases? voice;'));
    expect(dependencies, isNot(contains('AiUsageRepository')));
    expect(dependencies, isNot(contains('GeminiTutorController')));
    expect(dependencies, isNot(contains('geminiTutor')));
    expect(bootstrap, contains('ManagedAiTutorBuilder'));
    expect(bootstrap, contains('ManagedVoiceBuilder'));
  });

  test('Task 6 feature invocation authority remains unchanged', () {
    final gate = _read('lib/runtime/production_feature_gate.dart');
    final dependencies = _read('lib/runtime/app_dependencies.dart');

    expect(gate, contains('final Feature feature;'));
    expect(gate, contains('final WidgetBuilder builder;'));
    expect(gate, contains('AppDependenciesScope.maybeOf(context)?.features'));
    expect(dependencies, contains('required this.quest'));
    expect(dependencies, contains('final QuestUseCases quest;'));
  });
}
