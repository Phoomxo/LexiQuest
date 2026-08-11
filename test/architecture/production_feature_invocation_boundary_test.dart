import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production composition has one V2 feature authority', () {
    final dependencies = File(
      'lib/runtime/app_dependencies.dart',
    ).readAsStringSync();
    final bootstrap = File('lib/runtime/app_bootstrap.dart').readAsStringSync();
    final legacy = File(
      'lib/runtime/field_feature_registry.dart',
    ).readAsStringSync();

    expect(dependencies, isNot(contains('fieldFeatures')));
    expect(bootstrap, isNot(contains('fieldFeatures')));
    expect(bootstrap, isNot(contains('FeatureRegistryFieldAdapter')));
    expect(legacy, isNot(contains('FeatureRegistryFieldAdapter')));
  });

  test('production UI has no fail-open feature-registry fallback', () {
    for (final path in <String>[
      'lib/screens/main_navigation_screen.dart',
      'lib/screens/choose_mode_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('BuildFieldFeatureRegistry.allEnabled')));
      expect(source, isNot(contains('BuildFeatureRegistry.fieldDefaults')));
      expect(source, contains('ProductionFeatureGate'));
    }
  });

  test(
    'production composes durable quest without the hidden shadow pipeline',
    () {
      final dependencies = File(
        'lib/runtime/app_dependencies.dart',
      ).readAsStringSync();
      final bootstrap = File(
        'lib/runtime/app_bootstrap.dart',
      ).readAsStringSync();

      expect(dependencies, contains('required this.quest'));
      expect(dependencies, contains('final QuestUseCases quest;'));
      expect(bootstrap, isNot(contains('shadow_reward_orchestrator.dart')));
      expect(bootstrap, isNot(contains('ShadowRewardOrchestrator(')));
      expect(bootstrap, isNot(contains('_NoopShadowLogger')));
      expect(bootstrap, isNot(contains('shadowOrchestrator:')));
    },
  );

  test('production Learning has no demo-only campaign entry', () {
    final chooseMode = File(
      'lib/screens/choose_mode_screen.dart',
    ).readAsStringSync();

    expect(chooseMode, isNot(contains('learning_world_map_screen.dart')));
    expect(chooseMode, isNot(contains('cefr_diagnostic_test_screen.dart')));
    expect(chooseMode, isNot(contains("title: 'World Map'")));
    expect(chooseMode, isNot(contains("title: 'CEFR Diagnostic'")));
  });

  test('Task 6 media screens use runtime-owned voice dependencies', () {
    for (final path in <String>[
      'lib/screens/object_scanner_screen.dart',
      'lib/screens/shadowing_challenge_screen.dart',
      'lib/screens/speak_to_text_screen.dart',
      'lib/screens/dictation_quiz_screen.dart',
      'lib/screens/phonetic_explorer_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('VoiceUseCases.createDefault')));
      expect(source, isNot(contains('disposeIfOwned')));
      expect(source, contains('AppDependenciesScope.maybeOf(context)'));
      expect(source, contains('MediaDependencyUnavailable'));
    }

    expect(
      File('lib/screens/object_scanner_screen.dart').readAsStringSync(),
      allOf(
        contains('widget.scanner ?? dependencies?.objectScanner'),
        contains('widget.voice ?? dependencies?.voice'),
      ),
    );
    for (final path in <String>[
      'lib/screens/shadowing_challenge_screen.dart',
      'lib/screens/speak_to_text_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('widget.voice ?? dependencies?.voice'));
      expect(
        source,
        contains('widget.speechPractice ?? dependencies?.speechPractice'),
      );
    }
    for (final path in <String>[
      'lib/screens/dictation_quiz_screen.dart',
      'lib/screens/phonetic_explorer_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('widget.voice ?? dependencies?.voice'),
      );
    }
  });

  test('Speak-to-Text is not a separate production entry', () {
    final navigation = File(
      'lib/screens/main_navigation_screen.dart',
    ).readAsStringSync();
    final contract = File(
      'lib/runtime/production_feature_contract.dart',
    ).readAsStringSync();

    expect(navigation, isNot(contains('SpeakToTextScreen')));
    expect(contract, isNot(contains('speak-to-text')));
    expect(
      contract,
      contains("productionEntryId: 'drawer/practice/shadowing'"),
    );
  });

  test('runtime feature ledger reflects the Task 6 production truth', () {
    final ledger = File(
      'docs/field/2026-08-09-runtime-feature-ledger.md',
    ).readAsStringSync();

    expect(ledger, contains('`drawer/rewards/quests`'));
    expect(ledger, contains('`rewards/quests`'));
    expect(ledger, contains('Production does not construct'));
    expect(
      ledger,
      isNot(contains('Shadow reward orchestrator is internal only')),
    );
    expect(ledger, isNot(contains('Missing: no `FieldFeature` mapping')));
    expect(ledger, isNot(contains('Screen constructs `RankService`')));
    expect(ledger, isNot(contains('`FeatureRegistryFieldAdapter`')));
    expect(ledger, contains('exact frozen `dependencyId`'));
    expect(
      ledger,
      contains('participant state or an output artifact is backed'),
    );
    expect(ledger, contains('The five Task 6 media screens resolve'));
    expect(ledger, contains('injection first and then the runtime scope'));
    expect(ledger, contains('Controller-scoped camera leases'));
    expect(ledger, contains('use-case-scoped speech'));
    expect(ledger, contains('both session and word IDs are present'));
    expect(ledger, contains('There is no Speak-to-Text production entry.'));
  });
}
