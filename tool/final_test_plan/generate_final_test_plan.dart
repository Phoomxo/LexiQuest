import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

const _markdownRelativePath = 'docs/generated/alltcas-8-44-final-test-plan.md';
const _jsonRelativePath = 'docs/generated/alltcas-8-44-final-test-plan.json';
const _implementationBaselineCommit =
    'd6be10d2ac6206fb018730449483c33cc4ed04b2';

const _baseSourcePaths = <String>[
  'docs/superpowers/plans/2026-08-14-alltcas-8-44-capability-implementation-master-plan.md',
  'docs/superpowers/specs/2026-08-14-lexiquest-alltcas-idea-integration-feature-contract-design.md',
  'docs/superpowers/plans/2026-08-31-alltcas-ui-evidence-acceptance-delta.md',
  'docs/generated/alltcas-idea-integration-feature-map.md',
  'docs/generated/alltcas-idea-integration-feature-map.json',
  'docs/database/schema_ledger.md',
  'docs/field/2026-08-09-runtime-feature-ledger.md',
  'lib/product/feature_contract/alltcas_idea_integration_catalog.dart',
  'lib/data/local/app_database.dart',
  'test/support/current_database_contract.dart',
  'lib/runtime/registries/feature.dart',
  'lib/runtime/registries/feature_registry.dart',
  'lib/features/sync/domain/sync_entity.dart',
  'lib/features/learning_packs/domain/content_quality_policy.dart',
  'lib/features/assessment/domain/assessment_instrument_catalog.dart',
  'lib/features/companion/domain/companion_reaction_catalog.dart',
  'tool/cli/verify-product-completion.ps1',
  'tool/cli/tests/verify-product-completion.tests.ps1',
  'tool/cli/run-android-smoke.ps1',
  'tool/cli/tests/run-android-smoke.tests.ps1',
  'package.json',
  'pubspec.lock',
  'pubspec.yaml',
  'firebase.json',
  'firestore.rules',
  'android/app/build.gradle.kts',
  'android/build.gradle.kts',
  'android/settings.gradle.kts',
  'android/gradle.properties',
  'android/app/src/main/AndroidManifest.xml',
  'tool/final_test_plan/generate_final_test_plan.dart',
  'test/architecture/final_8_44_test_plan_contract_test.dart',
  'test/architecture/final_8_44_test_plan_review_contract_test.dart',
  'test/database/migration_v1_to_v22_matrix_test.dart',
];

const _requiredGateCategories = <String>{
  'contractDrift',
  'unit',
  'widget',
  'integration',
  'migrationTransition',
  'fullUpgrade',
  'firestoreRules',
  'backendAuth',
  'ownerLifecycle',
  'offlineRestart',
  'featureOff',
  'emergencyOff',
  'exportWithdrawDelete',
  'androidBuild',
  'androidSmoke',
  'rollbackDrill',
};

const _requiredExecutionFields = <String>[
  'sourceCommit',
  'sourceFingerprint',
  'schemaVersion',
  'tableInventory',
  'contractRevision',
  'contractSemanticHash',
  'contentRevisions',
  'runtimeStates',
  'rulesRevisions',
  'command',
  'exitCode',
  'rollbackDrillResult',
];

final class FinalTestPlanArtifacts {
  const FinalTestPlanArtifacts({
    required this.markdown,
    required this.normalizedJson,
    required this.sourceFingerprint,
  });

  final String markdown;
  final String normalizedJson;
  final String sourceFingerprint;
}

final class FinalTestPlanContractFailure implements Exception {
  const FinalTestPlanContractFailure(this.message);

  final String message;

  @override
  String toString() => 'FinalTestPlanContractFailure: $message';
}

FinalTestPlanArtifacts buildFinalTestPlanArtifacts({
  required io.Directory repositoryRoot,
  required String sourceCommit,
}) {
  _requireSourceCommit(sourceCommit);
  final schemaVersion = _readSchemaVersion(repositoryRoot);
  final tableInventory = _readTableInventory(repositoryRoot);
  final runtimeStates = _runtimeStates(repositoryRoot);
  final gates = _buildGates(repositoryRoot, sourceCommit, schemaVersion);
  _validateGateSources(repositoryRoot, gates);
  final sources = _readSources(repositoryRoot, gates);
  final sourceFingerprint = _sourceFingerprint(sources);
  final manifest = <String, Object>{
    'schemaVersion': 1,
    'sourceCommit': sourceCommit,
    'sourceFingerprint': sourceFingerprint,
    'sources': sources,
    'productContract': <String, Object>{
      'revision': featureContractRevision,
      'semanticHash': catalogSemanticSha256(allTcasIdeaIntegrationCatalog),
      'capabilityCount': FeatureContractId.values.length,
      'completionContractCount': CompletionContractId.values.length,
    },
    'database': <String, Object>{
      'schemaVersion': schemaVersion,
      'tableCount': tableInventory.length,
      'tables': tableInventory,
      'migrationTransitions': <String>[
        for (var from = 1; from < schemaVersion; from += 1)
          'v$from-to-v${from + 1}',
      ],
    },
    'runtime': <String, Object>{
      'featureCount': Feature.values.length,
      'ledgerFeatureCount': runtimeStates.length,
      'states': runtimeStates,
      'codePresenceEnablesRuntime': false,
      'runtimeVisibilityAssignsCohort': false,
      'missingDependencyFailsClosed': true,
    },
    'rulesRevisions': _rulesRevisions,
    'contentRevisionAuthorities': const <Map<String, String>>[
      <String, String>{
        'authority': 'contentManifests',
        'source':
            'lib/features/learning_packs/domain/content_quality_policy.dart',
      },
      <String, String>{
        'authority': 'assessmentInstrumentCatalog',
        'source':
            'lib/features/assessment/domain/assessment_instrument_catalog.dart',
      },
      <String, String>{
        'authority': 'companionReactionCatalog',
        'source':
            'lib/features/companion/domain/companion_reaction_catalog.dart',
      },
    ],
    'platform': const <String, Object>{
      'androidBuildRequired': true,
      'androidSmokeRequired': true,
      'iosExcludedByOwner': true,
      'iosExclusionReason':
          'Owner-directed Android-first final verification scope.',
    },
    'executionEvidence': const <String, Object>{
      'requiredFields': _requiredExecutionFields,
      'codePresenceIsNotRolloutEvidence': true,
      'localRulesSuccessIsNotDeploymentEvidence': true,
    },
    'gates': gates,
  };
  _validateManifestShape(manifest);
  final normalizedJson =
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  return FinalTestPlanArtifacts(
    markdown: _buildMarkdown(manifest),
    normalizedJson: normalizedJson,
    sourceFingerprint: sourceFingerprint,
  );
}

void validateFinalTestPlanManifest(
  Map<String, dynamic> manifest, {
  required io.Directory repositoryRoot,
  required String expectedSourceCommit,
}) {
  _requireSourceCommit(expectedSourceCommit);
  _validateManifestShape(manifest);
  final expected = jsonDecode(
    buildFinalTestPlanArtifacts(
      repositoryRoot: repositoryRoot,
      sourceCommit: expectedSourceCommit,
    ).normalizedJson,
  );
  if (_canonicalJson(manifest) != _canonicalJson(expected)) {
    throw const FinalTestPlanContractFailure(
      'Manifest is stale or differs from its canonical sources.',
    );
  }
}

int runFinalTestPlanGenerator(
  List<String> arguments, {
  io.Directory? repositoryRoot,
  io.Directory? outputRoot,
  void Function(String message)? stdout,
  void Function(String message)? stderr,
  String Function(io.Directory repositoryRoot)?
  checkoutCommitResolverForTesting,
}) {
  final writeOutput = stdout ?? (message) => io.stdout.writeln(message);
  final writeError = stderr ?? (message) => io.stderr.writeln(message);
  if (arguments.length != 3 ||
      (arguments.first != '--write' && arguments.first != '--check') ||
      arguments[1] != '--source-commit') {
    writeError(
      'Usage: dart run tool/final_test_plan/generate_final_test_plan.dart '
      '<--write|--check> --source-commit <40-char-sha>',
    );
    return 64;
  }

  final sourceRoot = repositoryRoot ?? io.Directory.current;
  final destinationRoot = outputRoot ?? sourceRoot;
  if (arguments.first == '--write') {
    late final String checkoutCommit;
    try {
      checkoutCommit =
          (checkoutCommitResolverForTesting ?? _resolveCheckoutCommit)(
            sourceRoot,
          );
      _requireSourceCommit(checkoutCommit);
    } on FinalTestPlanContractFailure catch (error) {
      writeError(error.message);
      return 1;
    }
    if (arguments[2] != checkoutCommit) {
      writeError(
        'Refusing to write a Test Plan for ${arguments[2]}; '
        'checkout HEAD is $checkoutCommit.',
      );
      return 1;
    }
  }
  late final FinalTestPlanArtifacts artifacts;
  try {
    artifacts = buildFinalTestPlanArtifacts(
      repositoryRoot: sourceRoot,
      sourceCommit: arguments[2],
    );
  } on FinalTestPlanContractFailure catch (error) {
    writeError(error.message);
    return 1;
  }

  final markdownFile = io.File(
    _join(destinationRoot.path, _markdownRelativePath),
  );
  final jsonFile = io.File(_join(destinationRoot.path, _jsonRelativePath));
  if (arguments.first == '--check') {
    final markdownDrift = _checkArtifact(
      markdownFile,
      artifacts.markdown,
      _markdownRelativePath,
      writeError,
    );
    final jsonDrift = _checkArtifact(
      jsonFile,
      artifacts.normalizedJson,
      _jsonRelativePath,
      writeError,
    );
    if (markdownDrift || jsonDrift) return 1;
    writeOutput(
      'Final 8/44 Test Plan is current '
      '(${artifacts.sourceFingerprint}, source ${arguments[2]}).',
    );
    return 0;
  }

  markdownFile.parent.createSync(recursive: true);
  _writeUtf8(markdownFile, artifacts.markdown);
  _writeUtf8(jsonFile, artifacts.normalizedJson);
  writeOutput(
    'Wrote $_markdownRelativePath and $_jsonRelativePath '
    '(${artifacts.sourceFingerprint}, source ${arguments[2]}).',
  );
  return 0;
}

void main(List<String> arguments) {
  io.exitCode = runFinalTestPlanGenerator(arguments);
}

List<Map<String, String>> _readSources(
  io.Directory root,
  List<Map<String, Object>> gates,
) {
  final canonicalPaths = <String>{
    ..._baseSourcePaths,
    for (final gate in gates) ...(gate['sourceRefs']! as List<String>),
  }.toList(growable: false)..sort();
  final sources = <Map<String, String>>[];
  for (final path in canonicalPaths) {
    final type = io.FileSystemEntity.typeSync(_join(root.path, path));
    if (type == io.FileSystemEntityType.notFound) {
      throw FinalTestPlanContractFailure('Canonical source is missing: $path');
    }
    sources.add(<String, String>{
      'path': path,
      'sha256': _hashSourcePath(root, path, type),
    });
  }
  return List<Map<String, String>>.unmodifiable(sources);
}

String _sourceFingerprint(List<Map<String, String>> sources) {
  final canonical = jsonEncode(<String, Object>{'sources': sources});
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _hashSourcePath(
  io.Directory root,
  String relativePath,
  io.FileSystemEntityType type,
) {
  final absolutePath = _join(root.path, relativePath);
  if (type == io.FileSystemEntityType.file) {
    return sha256.convert(io.File(absolutePath).readAsBytesSync()).toString();
  }
  if (type != io.FileSystemEntityType.directory) {
    throw FinalTestPlanContractFailure(
      'Canonical source must be a file or directory: $relativePath',
    );
  }
  final directory = io.Directory(absolutePath);
  final files =
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<io.File>()
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  if (files.isEmpty) {
    throw FinalTestPlanContractFailure(
      'Canonical source directory is empty: $relativePath',
    );
  }
  final entries = <String>[];
  for (final file in files) {
    final childPath = file.path
        .substring(directory.path.length + 1)
        .replaceAll('\\', '/');
    entries.add('$childPath\u0000${sha256.convert(file.readAsBytesSync())}');
  }
  return sha256.convert(utf8.encode(entries.join('\n'))).toString();
}

String _resolveCheckoutCommit(io.Directory repositoryRoot) {
  final result = io.Process.runSync('git', const <String>[
    'rev-parse',
    'HEAD',
  ], workingDirectory: repositoryRoot.path);
  final commit = result.stdout is String
      ? (result.stdout as String).trim()
      : '';
  if (result.exitCode != 0 || !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
    throw const FinalTestPlanContractFailure(
      'Unable to resolve an exact checkout HEAD commit.',
    );
  }
  return commit;
}

List<String> _readTableInventory(io.Directory root) {
  const path = 'test/support/current_database_contract.dart';
  final source = io.File(_join(root.path, path)).readAsStringSync();
  const marker = 'const currentDatabaseTableInventory = <String>{';
  final start = source.indexOf(marker);
  final end = source.indexOf('};', start + marker.length);
  if (start < 0 || end < 0) {
    throw const FinalTestPlanContractFailure(
      'Current database table inventory is not structurally readable.',
    );
  }
  final block = source.substring(start + marker.length, end);
  final tables =
      RegExp("'([^']+)'")
          .allMatches(block)
          .map((match) => match.group(1)!)
          .toList(growable: false)
        ..sort();
  if (tables.length != tables.toSet().length || tables.length != 44) {
    throw FinalTestPlanContractFailure(
      'Current database table inventory is duplicate or stale: '
      '${tables.length}.',
    );
  }
  return List<String>.unmodifiable(tables);
}

int _readSchemaVersion(io.Directory root) {
  const path = 'lib/data/local/app_database.dart';
  final source = io.File(_join(root.path, path)).readAsStringSync();
  final match = RegExp(
    r'static const int currentSchemaVersion = (\d+);',
  ).firstMatch(source);
  final value = match == null ? null : int.tryParse(match.group(1)!);
  if (value == null || value < 1) {
    throw const FinalTestPlanContractFailure(
      'Current schema version is not structurally readable.',
    );
  }
  return value;
}

Map<String, String> _runtimeStates(io.Directory root) {
  const registryPath = 'lib/runtime/registries/feature_registry.dart';
  final registry = io.File(_join(root.path, registryPath)).readAsStringSync();
  const marker = 'const BuildFeatureRegistry.fieldDefaults()';
  final start = registry.indexOf(marker);
  final statesStart = registry.indexOf('_states = const {', start);
  final end = registry.indexOf('};', statesStart);
  if (start < 0 || statesStart < 0 || end < 0) {
    throw const FinalTestPlanContractFailure(
      'Production field-default runtime states are not structurally readable.',
    );
  }
  final block = registry.substring(statesStart, end);
  final parsed = <String, String>{
    for (final match in RegExp(
      r'Feature\.([A-Za-z0-9]+): FeatureState\.([A-Za-z0-9]+)',
    ).allMatches(block))
      match.group(1)!: match.group(2)!,
  };
  final states = <String, String>{
    for (final feature in Feature.values)
      if (parsed.containsKey(feature.name)) feature.name: parsed[feature.name]!,
  };
  if (states.length != Feature.values.length ||
      parsed.length != Feature.values.length) {
    throw const FinalTestPlanContractFailure(
      'Production field-default runtime states are incomplete or duplicate.',
    );
  }
  const ledgerPath = 'docs/field/2026-08-09-runtime-feature-ledger.md';
  final ledger = io.File(_join(root.path, ledgerPath)).readAsStringSync();
  if (!ledger.contains('all ${Feature.values.length} members of')) {
    throw FinalTestPlanContractFailure(
      'Runtime feature ledger count is stale; expected '
      '${Feature.values.length}.',
    );
  }
  for (final feature in Feature.values) {
    if (!ledger.contains('Feature.${feature.name}')) {
      throw FinalTestPlanContractFailure(
        'Runtime feature ledger omits Feature.${feature.name}.',
      );
    }
  }
  if (!ledger.contains(_implementationBaselineCommit) ||
      ledger.contains('only declared final-metadata commits may follow it')) {
    throw const FinalTestPlanContractFailure(
      'Runtime feature ledger implementation provenance is stale.',
    );
  }
  return Map<String, String>.unmodifiable(states);
}

const _rulesRevisions = <String, String>{
  'legacy': legacyFirestoreRulesRevision,
  'answerAttemptV2': answerAttemptV2RulesRevision,
  'vocabularyWordV2': vocabularyWordV2RulesRevision,
  'experimentAssignmentV1': experimentAssignmentV1RulesRevision,
  'assessmentRunV1': assessmentRunV1RulesRevision,
  'savedLearningItemV1': savedLearningItemV1RulesRevision,
  'contentQualityReportV1': contentQualityReportV1RulesRevision,
  'learningTimeSegmentV1': learningTimeSegmentV1RulesRevision,
  'learningGoalV1': learningGoalV1RulesRevision,
  'learnerPreferenceV1': learnerPreferenceV1RulesRevision,
};

List<Map<String, Object>> _buildGates(
  io.Directory root,
  String sourceCommit,
  int schemaVersion,
) {
  final gates = <Map<String, Object>>[
    _gate(
      'contract-feature-map-drift',
      'contractDrift',
      'dart run tool/feature_contract/generate_feature_map.dart --check',
      const <String>[
        'tool/feature_contract/generate_feature_map.dart',
        'docs/generated/alltcas-idea-integration-feature-map.json',
      ],
    ),
    _gate(
      'contract-final-plan-drift',
      'contractDrift',
      'dart run tool/final_test_plan/generate_final_test_plan.dart '
          '--check --source-commit $sourceCommit',
      const <String>['tool/final_test_plan/generate_final_test_plan.dart'],
    ),
    _gate(
      'architecture-contracts',
      'contractDrift',
      'flutter test --no-pub test/architecture',
      const <String>['test/architecture'],
    ),
    _gate('static-analysis', 'contractDrift', 'flutter analyze', const <String>[
      'lib',
      'test',
      'tool',
    ]),
    _gate(
      'unit-domain-suites',
      'unit',
      'flutter test --no-pub '
          'test/features/accessibility test/features/account '
          'test/features/achievements test/features/ai_tutor '
          'test/features/assessment test/features/companion '
          'test/features/consent test/features/device_model '
          'test/features/events test/features/gemini test/features/goals '
          'test/features/history test/features/learning '
          'test/features/learning_packs test/features/media_practice '
          'test/features/motivation test/features/preferences '
          'test/features/progress test/features/quest '
          'test/features/recommendation test/features/reminders '
          'test/features/research test/features/review '
          'test/features/rewards test/features/session test/features/sync '
          'test/features/time_tracking test/features/today_hub '
          'test/features/vocabulary test/features/voice --reporter compact',
      const <String>[
        'test/features/accessibility',
        'test/features/account',
        'test/features/achievements',
        'test/features/ai_tutor',
        'test/features/assessment',
        'test/features/companion',
        'test/features/consent',
        'test/features/device_model',
        'test/features/events',
        'test/features/gemini',
        'test/features/goals',
        'test/features/history',
        'test/features/learning',
        'test/features/learning_packs',
        'test/features/media_practice',
        'test/features/motivation',
        'test/features/preferences',
        'test/features/progress',
        'test/features/quest',
        'test/features/recommendation',
        'test/features/reminders',
        'test/features/research',
        'test/features/review',
        'test/features/rewards',
        'test/features/session',
        'test/features/sync',
        'test/features/time_tracking',
        'test/features/today_hub',
        'test/features/vocabulary',
        'test/features/voice',
      ],
    ),
    _gate(
      'widget-surface-suites',
      'widget',
      'flutter test --no-pub test/screens test/widgets --reporter compact',
      const <String>['test/screens', 'test/widgets'],
    ),
    _gate(
      'integration-feature-controls',
      'integration',
      'flutter test -d flutter-tester --no-pub --reporter compact '
          'integration_test/field_trial_feature_controls_test.dart',
      const <String>['integration_test/field_trial_feature_controls_test.dart'],
    ),
    _gate(
      'integration-media-smoke',
      'integration',
      'flutter test -d flutter-tester --no-pub --reporter compact '
          'integration_test/field_trial_media_smoke_test.dart',
      const <String>['integration_test/field_trial_media_smoke_test.dart'],
    ),
  ];

  for (var from = 1; from < schemaVersion; from += 1) {
    final to = from + 1;
    final transition = 'v$from-to-v$to';
    final dedicated = 'test/database/migration_v${from}_to_v${to}_test.dart';
    final hasDedicated = io.File(_join(root.path, dedicated)).existsSync();
    final matrix = 'test/database/migration_v1_to_v22_matrix_test.dart';
    final matrixCase =
        'final test plan migration matrix: frozen v$from fixture reaches '
        'current with data intact';
    gates.add(<String, Object>{
      ..._gate(
        'migration-$transition',
        'migrationTransition',
        hasDedicated
            ? 'flutter test --no-pub $dedicated --reporter compact'
            : 'flutter test --no-pub $matrix '
                  '--plain-name "$matrixCase" --reporter compact',
        hasDedicated
            ? <String>[dedicated, 'docs/database/schema_ledger.md']
            : <String>[matrix, 'docs/database/schema_ledger.md'],
      ),
      'transition': transition,
      'coverage': hasDedicated
          ? 'dedicatedTransitionTest'
          : 'frozenSourceFixture',
    });
  }

  gates.addAll(<Map<String, Object>>[
    _gate(
      'migration-full-upgrade',
      'fullUpgrade',
      'flutter test --no-pub '
          'test/data/local/app_database_migration_test.dart --reporter compact',
      const <String>['test/data/local/app_database_migration_test.dart'],
    ),
    _gate(
      'firestore-rules-local-emulator',
      'firestoreRules',
      'npm run test:rules',
      const <String>['test/security/firestore-rules.test.cjs'],
    ),
    _gate(
      'backend-auth-local-emulator',
      'backendAuth',
      'npm run test:auth',
      const <String>['test/security/firebase-auth-emulator.test.cjs'],
    ),
    _gate(
      'owner-lifecycle-upgrade-restart',
      'ownerLifecycle',
      'flutter test --no-pub '
          'test/features/identity test/scenarios/guest_upgrade_restart_test.dart '
          '--reporter compact',
      const <String>[
        'test/features/identity',
        'test/scenarios/guest_upgrade_restart_test.dart',
      ],
    ),
    _gate(
      'offline-restart-recovery',
      'offlineRestart',
      'flutter test --no-pub test/features/offline_content '
          'test/scenarios/file_backed_sync_recovery_test.dart '
          'test/scenarios/production_learning_restart_test.dart '
          '--reporter compact',
      const <String>[
        'test/features/offline_content',
        'test/scenarios/file_backed_sync_recovery_test.dart',
        'test/scenarios/production_learning_restart_test.dart',
      ],
    ),
    _gate(
      'feature-default-off',
      'featureOff',
      'flutter test --no-pub '
          'test/runtime/runtime_feature_controls_test.dart '
          '--plain-name "durable feature decision epochs distinguish off and clear" '
          '--reporter compact',
      const <String>['test/runtime/runtime_feature_controls_test.dart'],
    ),
    _gate(
      'feature-emergency-off',
      'emergencyOff',
      'flutter test --no-pub '
          'test/scenarios/runtime_kill_switch_journey_test.dart '
          '--plain-name "production entry live route direct route and restart all fail closed" '
          '--reporter compact',
      const <String>['test/scenarios/runtime_kill_switch_journey_test.dart'],
    ),
    _gate(
      'owner-export-withdraw-delete',
      'exportWithdrawDelete',
      'flutter test --no-pub test/features/export '
          'test/scenarios/complete_owner_export_delete_test.dart '
          '--reporter compact',
      const <String>[
        'test/features/export',
        'test/scenarios/complete_owner_export_delete_test.dart',
      ],
    ),
    _gate(
      'android-debug-build',
      'androidBuild',
      'flutter build apk --debug --no-pub',
      const <String>['android/app/build.gradle.kts'],
    ),
    _gate(
      'android-bounded-core-smoke',
      'androidSmoke',
      'powershell -NoProfile -ExecutionPolicy Bypass '
          '-File tool/cli/run-android-smoke.ps1',
      const <String>[
        'tool/cli/run-android-smoke.ps1',
        'tool/cli/tests/run-android-smoke.tests.ps1',
        'integration_test/field_trial_core_journey_test.dart',
      ],
    ),
    _gate(
      'rollback-forward-only-drills',
      'rollbackDrill',
      'flutter test --no-pub '
          'test/scenarios/runtime_kill_switch_journey_test.dart '
          '--plain-name "file-backed permanent clear and TTL controls converge across restart" '
          '--reporter compact',
      const <String>['test/scenarios/runtime_kill_switch_journey_test.dart'],
    ),
  ]);
  return List<Map<String, Object>>.unmodifiable(gates);
}

Map<String, Object> _gate(
  String id,
  String category,
  String command,
  List<String> sourceRefs,
) => <String, Object>{
  'id': id,
  'category': category,
  'command': command,
  'expectedExitCode': 0,
  'sourceRefs': sourceRefs,
};

void _validateGateSources(io.Directory root, List<Map<String, Object>> gates) {
  for (final gate in gates) {
    final command = gate['command']! as String;
    final lowerCommand = command.toLowerCase();
    if (lowerCommand.contains('verify-product-completion.ps1')) {
      throw FinalTestPlanContractFailure(
        'Final Test Plan must not invoke the release verifier: '
        '${gate['id']}.',
      );
    }
    if (RegExp(r'(^|[\s/\\])ios([\s/\\]|$)').hasMatch(lowerCommand) ||
        lowerCommand.contains('flutter build ios') ||
        lowerCommand.contains('pod install')) {
      throw FinalTestPlanContractFailure(
        'Owner-excluded iOS work appears in gate ${gate['id']}.',
      );
    }
    for (final sourceRef in (gate['sourceRefs']! as List<String>)) {
      if (io.FileSystemEntity.typeSync(_join(root.path, sourceRef)) ==
          io.FileSystemEntityType.notFound) {
        throw FinalTestPlanContractFailure(
          'Gate ${gate['id']} references a missing path: $sourceRef',
        );
      }
    }
  }
}

void _validateManifestShape(Map<Object?, Object?> manifest) {
  final gatesValue = manifest['gates'];
  if (gatesValue is! List) {
    throw const FinalTestPlanContractFailure('Manifest gates are missing.');
  }
  final gates = gatesValue.cast<Map<Object?, Object?>>();
  final ids = <String>{};
  final commands = <String>{};
  final categories = <String>{};
  final transitions = <String>[];
  for (final gate in gates) {
    final id = gate['id'];
    final category = gate['category'];
    final command = gate['command'];
    if (id is! String || id.isEmpty || !ids.add(id)) {
      throw const FinalTestPlanContractFailure(
        'Gate IDs must be present and unique.',
      );
    }
    if (command is! String || command.isEmpty || !commands.add(command)) {
      throw const FinalTestPlanContractFailure(
        'Gate commands must be present and unique.',
      );
    }
    if (category is! String) {
      throw FinalTestPlanContractFailure('Gate $id has no category.');
    }
    categories.add(category);
    if (gate['expectedExitCode'] != 0) {
      throw FinalTestPlanContractFailure('Gate $id must expect exit zero.');
    }
    final refs = gate['sourceRefs'];
    if (refs is! List || refs.isEmpty) {
      throw FinalTestPlanContractFailure('Gate $id has no source refs.');
    }
    final isFlutterTester = RegExp(
      r'(?:^|\s)-d\s+flutter-tester(?:\s|$)',
    ).hasMatch(command);
    if (isFlutterTester) {
      final targets = _flutterTestCoverage(command).toList(growable: false);
      if (targets.length != 1 ||
          !targets.single.path.startsWith('integration_test/')) {
        throw const FinalTestPlanContractFailure(
          'flutter-tester integration gates must execute exactly one '
          'integration test file.',
        );
      }
    }
    if (category == 'migrationTransition') {
      final transition = gate['transition'];
      if (transition is! String) {
        throw FinalTestPlanContractFailure(
          'Migration gate $id has no transition.',
        );
      }
      transitions.add(transition);
    }
  }
  if (!categories.containsAll(_requiredGateCategories)) {
    throw const FinalTestPlanContractFailure(
      'Manifest omits one or more required gate categories.',
    );
  }
  final database = manifest['database'];
  if (database is! Map || database['schemaVersion'] is! int) {
    throw const FinalTestPlanContractFailure(
      'Database identity or table inventory is stale.',
    );
  }
  final schemaVersion = database['schemaVersion']! as int;
  final expectedTransitions = <String>[
    for (var from = 1; from < schemaVersion; from += 1)
      'v$from-to-v${from + 1}',
  ];
  if (_canonicalJson(transitions) != _canonicalJson(expectedTransitions)) {
    throw const FinalTestPlanContractFailure(
      'Every forward migration must appear exactly once in order.',
    );
  }
  if (gates.where((gate) => gate['category'] == 'fullUpgrade').length != 1) {
    throw const FinalTestPlanContractFailure(
      'Exactly one full-upgrade gate is required.',
    );
  }
  _validateExecutableGateCoverage(gates);

  if (!commands.contains('flutter test --no-pub test/architecture') ||
      !commands.contains('flutter analyze')) {
    throw const FinalTestPlanContractFailure(
      'Exact architecture and analyzer gates are required.',
    );
  }
  for (final gate in gates.where(
    (candidate) => candidate['category'] == 'migrationTransition',
  )) {
    final command = gate['command']! as String;
    if (!command.startsWith('flutter test --no-pub ') ||
        command.contains('Select-String') ||
        command.contains('rg ') ||
        command.contains('grep ')) {
      throw FinalTestPlanContractFailure(
        'Migration transition ${gate['id']} must execute a fixture test.',
      );
    }
    final refs = (gate['sourceRefs']! as List).cast<String>();
    final usesSharedMatrix = refs.contains(
      'test/database/migration_v1_to_v22_matrix_test.dart',
    );
    if (usesSharedMatrix && !command.contains('--plain-name')) {
      throw FinalTestPlanContractFailure(
        'Shared migration fixture gate ${gate['id']} must isolate one case.',
      );
    }
  }
  final rollbackGates = gates
      .where((gate) => gate['category'] == 'rollbackDrill')
      .toList(growable: false);
  if (rollbackGates.isEmpty ||
      rollbackGates.any(
        (gate) => !(gate['command']! as String).contains('--plain-name'),
      )) {
    throw const FinalTestPlanContractFailure(
      'Rollback drills must target independent named cases.',
    );
  }
  final androidSmoke = gates.singleWhere(
    (gate) => gate['category'] == 'androidSmoke',
  );
  final androidCommand = androidSmoke['command']! as String;
  final androidSources = (androidSmoke['sourceRefs']! as List).cast<String>();
  if (androidCommand !=
          'powershell -NoProfile -ExecutionPolicy Bypass '
              '-File tool/cli/run-android-smoke.ps1' ||
      !androidSources.contains('tool/cli/run-android-smoke.ps1') ||
      !androidSources.contains('tool/cli/tests/run-android-smoke.tests.ps1') ||
      !androidSources.contains(
        'integration_test/field_trial_core_journey_test.dart',
      )) {
    throw const FinalTestPlanContractFailure(
      'Android smoke must use its repository-owned executable contract.',
    );
  }

  if (database['tableCount'] is! int ||
      database['tables'] is! List ||
      database['tableCount'] != (database['tables'] as List).length ||
      (database['tables'] as List).toSet().length !=
          (database['tables'] as List).length) {
    throw const FinalTestPlanContractFailure(
      'Database identity or table inventory is stale.',
    );
  }
  final product = manifest['productContract'];
  if (product is! Map ||
      product['revision'] != featureContractRevision ||
      product['semanticHash'] !=
          catalogSemanticSha256(allTcasIdeaIntegrationCatalog) ||
      product['capabilityCount'] != FeatureContractId.values.length ||
      product['completionContractCount'] !=
          CompletionContractId.values.length) {
    throw const FinalTestPlanContractFailure(
      'Product contract identity is stale.',
    );
  }
  final runtime = manifest['runtime'];
  if (runtime is! Map ||
      runtime['featureCount'] != Feature.values.length ||
      runtime['ledgerFeatureCount'] != Feature.values.length ||
      runtime['codePresenceEnablesRuntime'] != false ||
      runtime['runtimeVisibilityAssignsCohort'] != false ||
      runtime['missingDependencyFailsClosed'] != true) {
    throw const FinalTestPlanContractFailure(
      'Runtime rollout identity or separation is stale.',
    );
  }
  if (_canonicalJson(manifest['rulesRevisions']) !=
      _canonicalJson(_rulesRevisions)) {
    throw const FinalTestPlanContractFailure('Rules revisions are stale.');
  }
  final evidence = manifest['executionEvidence'];
  if (evidence is! Map ||
      evidence['requiredFields'] is! List ||
      !_setEquals(
        (evidence['requiredFields'] as List).cast<String>().toSet(),
        _requiredExecutionFields.toSet(),
      )) {
    throw const FinalTestPlanContractFailure(
      'Execution evidence fields are incomplete.',
    );
  }
  final platform = manifest['platform'];
  if (platform is! Map ||
      platform['androidBuildRequired'] != true ||
      platform['androidSmokeRequired'] != true ||
      platform['iosExcludedByOwner'] != true) {
    throw const FinalTestPlanContractFailure(
      'Owner-directed platform scope is incomplete.',
    );
  }
}

void _validateExecutableGateCoverage(List<Map<Object?, Object?>> gates) {
  final coverage = <({String gateId, String path, String? plainName})>[];
  for (final gate in gates) {
    final gateId = gate['id']! as String;
    final command = gate['command']! as String;
    for (final target in _flutterTestCoverage(command)) {
      coverage.add((
        gateId: gateId,
        path: target.path,
        plainName: target.plainName,
      ));
    }
  }
  for (var left = 0; left < coverage.length; left += 1) {
    for (var right = left + 1; right < coverage.length; right += 1) {
      final a = coverage[left];
      final b = coverage[right];
      if (_coverageOverlaps(a, b)) {
        throw FinalTestPlanContractFailure(
          'Executable coverage overlaps between ${a.gateId} (${a.path}) '
          'and ${b.gateId} (${b.path}).',
        );
      }
    }
  }
}

Iterable<({String path, String? plainName})> _flutterTestCoverage(
  String command,
) sync* {
  final commandMatch = RegExp(
    r'flutter test(?:\s+-d\s+\S+)?\s+([^;&]+)',
  ).firstMatch(command);
  if (commandMatch == null) return;
  final invocation = commandMatch.group(0)!;
  final plainNameMatch = RegExp(
    r'''--plain-name\s+(?:"([^"]+)"|'([^']+)'|(\S+))''',
  ).firstMatch(invocation);
  final plainName = plainNameMatch == null
      ? null
      : (plainNameMatch.group(1) ??
            plainNameMatch.group(2) ??
            plainNameMatch.group(3));
  for (final token in invocation.split(RegExp(r'\s+'))) {
    final normalized = token.replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (normalized.startsWith('test/') ||
        normalized.startsWith('integration_test/')) {
      yield (
        path: normalized.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), ''),
        plainName: plainName,
      );
    }
  }
}

bool _coverageOverlaps(
  ({String gateId, String path, String? plainName}) left,
  ({String gateId, String path, String? plainName}) right,
) {
  final pathsOverlap =
      left.path == right.path ||
      left.path.startsWith('${right.path}/') ||
      right.path.startsWith('${left.path}/');
  if (!pathsOverlap) return false;
  return left.plainName == null ||
      right.plainName == null ||
      left.plainName == right.plainName;
}

String _buildMarkdown(Map<String, Object> manifest) {
  final product = manifest['productContract']! as Map<String, Object>;
  final database = manifest['database']! as Map<String, Object>;
  final runtime = manifest['runtime']! as Map<String, Object>;
  final sources = (manifest['sources']! as List).cast<Map<String, String>>();
  final gates = (manifest['gates']! as List).cast<Map<String, Object>>();
  final buffer = StringBuffer()
    ..writeln('# Final AllTCAS 8/44 Machine-Verifiable Test Plan')
    ..writeln()
    ..writeln(
      '<!-- Generated by tool/final_test_plan/generate_final_test_plan.dart. -->',
    )
    ..writeln()
    ..writeln('- Source commit: `${manifest['sourceCommit']}`')
    ..writeln('- Source fingerprint: `${manifest['sourceFingerprint']}`')
    ..writeln('- Product contract revision: `${product['revision']}`')
    ..writeln('- Product contract SHA-256: `${product['semanticHash']}`')
    ..writeln(
      '- Database: v${database['schemaVersion']} / '
      '${database['tableCount']} tables',
    )
    ..writeln('- Runtime features: ${runtime['featureCount']}')
    ..writeln()
    ..writeln(
      'Code presence is not rollout enablement or participant assignment.',
    )
    ..writeln()
    ..writeln('## Canonical sources')
    ..writeln()
    ..writeln('| Path | SHA-256 |')
    ..writeln('| --- | --- |');
  for (final source in sources) {
    buffer.writeln('| `${source['path']}` | `${source['sha256']}` |');
  }
  buffer
    ..writeln()
    ..writeln('## Ordered gates')
    ..writeln()
    ..writeln('| ID | Category | Expected | Command |')
    ..writeln('| --- | --- | ---: | --- |');
  for (final gate in gates) {
    buffer.writeln(
      '| `${gate['id']}` | `${gate['category']}` | '
      '${gate['expectedExitCode']} | `${_markdownCell(gate['command']! as String)}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Required execution evidence')
    ..writeln()
    ..writeln(_requiredExecutionFields.map((field) => '- `$field`').join('\n'))
    ..writeln()
    ..writeln('## Platform decision')
    ..writeln()
    ..writeln('- Android debug build and bounded Android smoke are required.')
    ..writeln('- iOS is excluded by explicit owner direction.')
    ..writeln(
      '- Local Firestore Rules success is not deployment evidence; this plan '
      'does not deploy or invoke the release verifier.',
    );
  return '${buffer.toString().trimRight()}\n';
}

bool _checkArtifact(
  io.File file,
  String expected,
  String relativePath,
  void Function(String message) writeError,
) {
  if (!file.existsSync()) {
    writeError('Generated final Test Plan artifact is missing: $relativePath');
    return true;
  }
  final actual = _canonicalizeLineEndings(file.readAsBytesSync());
  final expectedBytes = utf8.encode(expected);
  if (!_bytesEqual(actual, expectedBytes)) {
    writeError('Generated final Test Plan artifact has drifted: $relativePath');
    return true;
  }
  return false;
}

void _requireSourceCommit(String sourceCommit) {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceCommit)) {
    throw const FinalTestPlanContractFailure(
      'Source commit must be an exact lowercase 40-character SHA-1.',
    );
  }
}

String _canonicalJson(Object? value) => jsonEncode(value);

bool _setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _markdownCell(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\r', ' ').replaceAll('\n', ' ');

void _writeUtf8(io.File file, String contents) {
  file.writeAsBytesSync(utf8.encode(contents), flush: true);
}

List<int> _canonicalizeLineEndings(List<int> bytes) {
  final canonical = <int>[];
  for (var index = 0; index < bytes.length; index += 1) {
    if (bytes[index] != 0x0d) {
      canonical.add(bytes[index]);
      continue;
    }
    canonical.add(0x0a);
    if (index + 1 < bytes.length && bytes[index + 1] == 0x0a) {
      index += 1;
    }
  }
  return canonical;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _join(String root, String relativePath) =>
    '$root${io.Platform.pathSeparator}${relativePath.replaceAll('/', io.Platform.pathSeparator)}';
