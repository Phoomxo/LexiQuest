import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

Map<String, String> _productionDartSources() {
  final entries =
      Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map(
            (file) => MapEntry(
              file.path.replaceAll(Platform.pathSeparator, '/'),
              file.readAsStringSync(),
            ),
          )
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, String>.fromEntries(entries);
}

Map<String, int> _matchCounts(Map<String, String> sources, RegExp pattern) {
  final result = <String, int>{};
  for (final entry in sources.entries) {
    final count = pattern.allMatches(entry.value).length;
    if (count > 0) result[entry.key] = count;
  }
  return result;
}

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

  test(
    'current evidence rollout has one domain authority and one composition root',
    () {
      final production = _productionDartSources();
      const authorityPath =
          'lib/features/learning/domain/evidence_policy_rollout.dart';
      final authority = _read(authorityPath);
      final eventStore = _read(
        'lib/features/learning/data/drift_learning_event_store.dart',
      );
      final activity = _read(
        'lib/features/learning/application/current_activity_evidence.dart',
      );
      final bootstrap = _read('lib/runtime/app_bootstrap.dart');
      final dependencies = _read('lib/runtime/app_dependencies.dart');

      expect(
        authority,
        contains('abstract interface class EvidencePolicyRolloutModeProvider'),
      );
      expect(
        eventStore,
        contains("export '../domain/evidence_policy_rollout.dart';"),
      );
      expect(
        eventStore,
        isNot(
          contains(
            'abstract interface class EvidencePolicyRolloutModeProvider',
          ),
        ),
      );
      expect(activity, isNot(contains('CurrentActivityRolloutProvider')));
      expect(activity, contains('EvidencePolicyRolloutModeProvider'));
      expect(bootstrap, contains('final evidenceRolloutModeProvider ='));
      expect(
        RegExp(
          r'rolloutModeProvider:\s*evidenceRolloutModeProvider',
        ).allMatches(bootstrap).length,
        5,
      );
      expect(
        dependencies,
        contains(
          'final CurrentActivityEvidenceAdapter? currentActivityEvidence;',
        ),
      );

      expect(
        _matchCounts(
          production,
          RegExp(
            r'\babstract\s+interface\s+class\s+'
            r'EvidencePolicyRolloutModeProvider\b',
          ),
        ),
        const <String, int>{authorityPath: 1},
      );
      expect(
        _matchCounts(production, RegExp(r'\bCurrentActivityRolloutProvider\b')),
        isEmpty,
      );
      expect(
        _matchCounts(
          production,
          RegExp(r'\bCurrentActivityEvidenceAdapter\s*\('),
        ),
        const <String, int>{
          'lib/features/learning/application/current_activity_evidence.dart': 1,
          'lib/runtime/app_bootstrap.dart': 1,
        },
      );
      expect(
        _matchCounts(
          production,
          RegExp(r'\bBaselineCurrentActivityResearchStateProvider\s*\('),
        ),
        const <String, int>{
          'lib/features/learning/application/current_activity_evidence.dart': 2,
          'lib/runtime/app_bootstrap.dart': 1,
        },
      );
      expect(
        _matchCounts(
          production,
          RegExp(r'\bFixedEvidencePolicyRolloutModeProvider(?!\.legacy)\s*\('),
        ),
        const <String, int>{
          'lib/features/learning/domain/evidence_policy_rollout.dart': 1,
          'lib/runtime/app_bootstrap.dart': 1,
        },
      );
      expect(
        _matchCounts(
          production,
          RegExp(r'\bFixedEvidencePolicyRolloutModeProvider\.legacy\s*\('),
        ),
        const <String, int>{
          'lib/features/identity/data/drift_owner_upgrade_repository.dart': 1,
          'lib/features/learning/application/current_activity_evidence.dart': 1,
          'lib/features/learning/application/learning_side_effect_reconciler.dart':
              1,
          'lib/features/learning/data/drift_learning_event_store.dart': 1,
          'lib/features/learning/data/drift_learning_projection_rebuilder.dart':
              1,
          'lib/features/learning/data/drift_learning_repository.dart': 1,
          'lib/features/learning/domain/evidence_policy_rollout.dart': 1,
          'lib/features/sync/data/drift_sync_store.dart': 1,
        },
      );
      expect(
        _matchCounts(
          production,
          RegExp(r'\bContextEvidencePolicyRolloutModeProvider\s*\('),
        ),
        const <String, int>{
          'lib/features/learning/domain/evidence_policy_rollout.dart': 1,
        },
      );

      const productionConsumers = <String>[
        'lib/features/learning/data/drift_learning_event_store.dart',
        'lib/features/learning/data/drift_learning_repository.dart',
        'lib/features/learning/data/drift_learning_projection_rebuilder.dart',
        'lib/features/learning/application/learning_side_effect_reconciler.dart',
        'lib/features/identity/data/drift_owner_upgrade_repository.dart',
        'lib/features/sync/data/drift_sync_store.dart',
        'lib/features/learning/application/current_activity_evidence.dart',
        'lib/runtime/app_bootstrap.dart',
      ];
      for (final path in productionConsumers) {
        expect(
          _read(path),
          contains('evidence_policy_rollout.dart'),
          reason: '$path must import the canonical domain authority',
        );
      }
    },
  );

  test(
    'learning screens resolve the composed adapter and never create Legacy',
    () {
      final screens = <String, String>{
        for (final entry in _productionDartSources().entries)
          if (entry.key.startsWith('lib/screens/')) entry.key: entry.value,
      };
      expect(screens, isNotEmpty);
      for (final entry in screens.entries) {
        final path = entry.key;
        final source = entry.value;
        if (!source.contains('CurrentActivityEvidenceAdapter')) continue;
        expect(
          source,
          contains('currentActivityEvidence'),
          reason: '$path must resolve the bootstrap-owned adapter',
        );
        expect(
          RegExp(
            r'\b(?:CurrentActivityEvidenceAdapter|'
            r'(?:Fixed|Context)EvidencePolicyRolloutModeProvider'
            r'(?:\.legacy)?|BaselineCurrentActivityResearchStateProvider)'
            r'\s*\(',
          ).hasMatch(source),
          isFalse,
          reason: '$path must not construct an evidence authority or fallback',
        );
      }
    },
  );

  test('only LearningUseCases can mint owner-bound evidence capabilities', () {
    final production = _productionDartSources();
    const authorityPath =
        'lib/features/learning/application/learning_use_cases.dart';
    const capabilityTypes = <String>[
      'OwnerBoundLearningEvidenceBasis',
      'ResolvedLearningEvidenceRecord',
    ];

    for (final type in capabilityTypes) {
      expect(
        _matchCounts(production, RegExp('\\bfinal\\s+class\\s+$type\\b')),
        const <String, int>{authorityPath: 1},
        reason: '$type must have exactly one canonical definition',
      );
      expect(
        _matchCounts(production, RegExp('\\b$type\\s*\\(')),
        isEmpty,
        reason: '$type must not expose a public constructor',
      );
      expect(
        _matchCounts(production, RegExp('\\b$type\\._\\s*\\(')),
        const <String, int>{authorityPath: 2},
        reason:
            '$type must be declared and minted only inside LearningUseCases',
      );
    }
  });
}
