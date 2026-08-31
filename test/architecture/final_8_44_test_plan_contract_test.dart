import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

import '../../tool/final_test_plan/generate_final_test_plan.dart';
import '../support/current_database_contract.dart';

const _fixtureSourceCommit = '0123456789abcdef0123456789abcdef01234567';

const _requiredSourcePaths = <String>{
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
  'tool/cli/verify-product-completion.ps1',
  'tool/cli/tests/verify-product-completion.tests.ps1',
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
};

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

const _requiredExecutionEvidenceFields = <String>{
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
};

const _currentRulesRevisions = <String, String>{
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

void main() {
  group('final 8/44 Test Plan contract', () {
    test('renders deterministically from canonical contracts and ledgers', () {
      final first = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      final second = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      final metadataOnlyCommit = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: 'fedcba9876543210fedcba9876543210fedcba98',
      );

      expect(second.markdown, first.markdown);
      expect(second.normalizedJson, first.normalizedJson);
      expect(second.sourceFingerprint, first.sourceFingerprint);
      expect(metadataOnlyCommit.sourceFingerprint, first.sourceFingerprint);
      expect(first.sourceFingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      for (final output in <String>[first.markdown, first.normalizedJson]) {
        expect(output, isNot(contains('\r')));
        expect(output.endsWith('\n'), isTrue);
        expect(output.endsWith('\n\n'), isFalse);
      }

      final manifest = _decode(first.normalizedJson);
      expect(manifest['schemaVersion'], 1);
      expect(manifest['sourceCommit'], _fixtureSourceCommit);
      expect(manifest['sourceFingerprint'], first.sourceFingerprint);

      final sources = _maps(manifest['sources']);
      final sourcePaths = sources
          .map((source) => source['path'] as String)
          .toList(growable: false);
      expect(sourcePaths.toSet(), containsAll(_requiredSourcePaths));
      expect(sourcePaths.toSet().length, sourcePaths.length);
      for (final source in sources) {
        expect(source['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      }

      expect(
        manifest['productContract'],
        containsPair('revision', featureContractRevision),
      );
      expect(
        manifest['productContract'],
        containsPair(
          'semanticHash',
          catalogSemanticSha256(allTcasIdeaIntegrationCatalog),
        ),
      );
      expect(
        manifest['productContract'],
        containsPair('capabilityCount', FeatureContractId.values.length),
      );
      expect(
        manifest['productContract'],
        containsPair(
          'completionContractCount',
          CompletionContractId.values.length,
        ),
      );
      final database = manifest['database'] as Map<String, dynamic>;
      expect(
        database,
        containsPair('schemaVersion', AppDatabase.currentSchemaVersion),
      );
      expect(
        database,
        containsPair('tableCount', currentDatabaseTableInventory.length),
      );
      expect(
        (database['tables'] as List<dynamic>).toSet(),
        currentDatabaseTableInventory,
      );
    });

    test('hashes pubspec lock and rejects lock-only source drift', () {
      final artifacts = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      final manifest = _decode(artifacts.normalizedJson);
      final sources = _maps(manifest['sources']);
      final lockSource = sources.singleWhere(
        (source) => source['path'] == 'pubspec.lock',
      );
      expect(
        lockSource['sha256'],
        sha256.convert(File('pubspec.lock').readAsBytesSync()).toString(),
      );

      final stale = _clone(manifest);
      final staleLock = _maps(
        stale['sources'],
      ).singleWhere((source) => source['path'] == 'pubspec.lock');
      staleLock['sha256'] = sha256
          .convert(utf8.encode('lock-only-drift'))
          .toString();
      stale['sourceFingerprint'] = sha256
          .convert(
            utf8.encode(
              jsonEncode(<String, Object?>{'sources': stale['sources']}),
            ),
          )
          .toString();
      expect(
        () => validateFinalTestPlanManifest(
          stale,
          repositoryRoot: Directory.current,
          expectedSourceCommit: _fixtureSourceCommit,
        ),
        throwsA(isA<FinalTestPlanContractFailure>()),
      );

      final outputRoot = Directory.systemTemp.createTempSync(
        'lexiquest-final-test-plan-lock-drift-',
      );
      addTearDown(() => outputRoot.deleteSync(recursive: true));
      _markdownFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync(artifacts.markdown);
      _jsonFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(stale)}\n',
        );
      expect(
        runFinalTestPlanGenerator(
          const <String>['--check', '--source-commit', _fixtureSourceCommit],
          repositoryRoot: Directory.current,
          outputRoot: outputRoot,
        ),
        1,
      );
    });

    test(
      'covers every required gate and every forward migration exactly once',
      () {
        final manifest = _currentManifest();
        final gates = _maps(manifest['gates']);
        final ids = gates.map((gate) => gate['id'] as String).toList();
        final commands = gates
            .map((gate) => gate['command'] as String)
            .toList(growable: false);

        expect(ids.toSet().length, ids.length);
        expect(commands.toSet().length, commands.length);
        expect(
          gates.map((gate) => gate['category']).toSet(),
          containsAll(_requiredGateCategories),
        );
        for (final gate in gates) {
          expect(gate['expectedExitCode'], 0, reason: '${gate['id']}');
          expect(gate['sourceRefs'], isNotEmpty, reason: '${gate['id']}');
        }

        final expectedTransitions = <String>{
          for (var from = 1; from < AppDatabase.currentSchemaVersion; from += 1)
            'v$from-to-v${from + 1}',
        };
        final migrationGates = gates
            .where((gate) => gate['category'] == 'migrationTransition')
            .toList(growable: false);
        expect(
          migrationGates.map((gate) => gate['transition']).toSet(),
          expectedTransitions,
        );
        expect(migrationGates.length, expectedTransitions.length);
        for (final gate in migrationGates) {
          final command = gate['command']! as String;
          expect(command, startsWith('flutter test --no-pub '));
          expect(command, isNot(contains('Select-String')));
          final refs = (gate['sourceRefs']! as List<dynamic>).cast<String>();
          if (refs.contains(
            'test/database/migration_v1_to_v22_matrix_test.dart',
          )) {
            expect(command, contains('--plain-name'));
          }
        }
        expect(
          gates.where((gate) => gate['category'] == 'fullUpgrade'),
          hasLength(1),
        );

        expect(
          gates.where((gate) => gate['category'] == 'firestoreRules'),
          hasLength(1),
        );
        expect(
          gates.where((gate) => gate['category'] == 'backendAuth'),
          hasLength(1),
        );
        expect(
          gates.where((gate) => gate['category'] == 'androidBuild'),
          hasLength(1),
        );
        expect(
          gates.where((gate) => gate['category'] == 'androidSmoke'),
          hasLength(1),
        );
        expect(commands, contains('flutter test --no-pub test/architecture'));
        expect(commands, contains('flutter analyze'));
        expect(
          commands.any(
            (command) =>
                RegExp(
                  r'(^|[\s/\\])ios([\s/\\]|$)',
                  caseSensitive: false,
                ).hasMatch(command) ||
                command.toLowerCase().contains('flutter build ios') ||
                command.toLowerCase().contains('pod install'),
          ),
          isFalse,
        );
      },
    );

    test('pins rollout separation and complete execution evidence', () {
      final manifest = _currentManifest();
      final runtime = manifest['runtime'] as Map<String, dynamic>;
      final platform = manifest['platform'] as Map<String, dynamic>;
      final evidence = manifest['executionEvidence'] as Map<String, dynamic>;

      expect(runtime['featureCount'], Feature.values.length);
      expect(runtime['ledgerFeatureCount'], Feature.values.length);
      expect(runtime['states'], _currentRuntimeStates());
      expect(runtime['codePresenceEnablesRuntime'], isFalse);
      expect(runtime['runtimeVisibilityAssignsCohort'], isFalse);
      expect(runtime['missingDependencyFailsClosed'], isTrue);
      expect(manifest['rulesRevisions'], _currentRulesRevisions);
      expect(
        (evidence['requiredFields'] as List<dynamic>).toSet(),
        _requiredExecutionEvidenceFields,
      );
      expect(platform['androidBuildRequired'], isTrue);
      expect(platform['androidSmokeRequired'], isTrue);
      expect(platform['iosExcludedByOwner'], isTrue);
      expect(
        _maps(
          manifest['gates'],
        ).where((gate) => gate['category'] == 'rollbackDrill'),
        isNotEmpty,
      );
    });

    test('rejects missing stale and duplicate gate manifests', () {
      final artifacts = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      final valid = _decode(artifacts.normalizedJson);

      final missing = _clone(valid);
      (missing['gates'] as List<dynamic>).removeWhere(
        (gate) => (gate as Map<String, dynamic>)['category'] == 'androidSmoke',
      );
      expect(
        () => validateFinalTestPlanManifest(
          missing,
          repositoryRoot: Directory.current,
          expectedSourceCommit: _fixtureSourceCommit,
        ),
        throwsA(isA<FinalTestPlanContractFailure>()),
      );

      final stale = _clone(valid)..['sourceFingerprint'] = ''.padLeft(64, '0');
      expect(
        () => validateFinalTestPlanManifest(
          stale,
          repositoryRoot: Directory.current,
          expectedSourceCommit: _fixtureSourceCommit,
        ),
        throwsA(isA<FinalTestPlanContractFailure>()),
      );

      final duplicate = _clone(valid);
      final duplicateGates = duplicate['gates'] as List<dynamic>;
      duplicateGates.add(_clone(duplicateGates.first as Map<String, dynamic>));
      expect(
        () => validateFinalTestPlanManifest(
          duplicate,
          repositoryRoot: Directory.current,
          expectedSourceCommit: _fixtureSourceCommit,
        ),
        throwsA(isA<FinalTestPlanContractFailure>()),
      );
    });

    test('--check detects missing and tampered artifacts without writing', () {
      final outputRoot = Directory.systemTemp.createTempSync(
        'lexiquest-final-test-plan-',
      );
      addTearDown(() => outputRoot.deleteSync(recursive: true));
      final errors = <String>[];

      expect(
        runFinalTestPlanGenerator(
          const <String>['--check', '--source-commit', _fixtureSourceCommit],
          repositoryRoot: Directory.current,
          outputRoot: outputRoot,
          stderr: errors.add,
        ),
        1,
      );
      expect(errors.join('\n'), contains('missing'));
      expect(_markdownFile(outputRoot).existsSync(), isFalse);
      expect(_jsonFile(outputRoot).existsSync(), isFalse);

      final artifacts = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      _markdownFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync(artifacts.markdown);
      _jsonFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync('${artifacts.normalizedJson}tampered');
      final beforeMarkdown = _markdownFile(outputRoot).readAsBytesSync();
      final beforeJson = _jsonFile(outputRoot).readAsBytesSync();

      expect(
        runFinalTestPlanGenerator(
          const <String>['--check', '--source-commit', _fixtureSourceCommit],
          repositoryRoot: Directory.current,
          outputRoot: outputRoot,
        ),
        1,
      );
      expect(_markdownFile(outputRoot).readAsBytesSync(), beforeMarkdown);
      expect(_jsonFile(outputRoot).readAsBytesSync(), beforeJson);
    });

    test('--write rejects a source commit that differs from checkout HEAD', () {
      final outputRoot = Directory.systemTemp.createTempSync(
        'lexiquest-final-test-plan-write-',
      );
      addTearDown(() => outputRoot.deleteSync(recursive: true));
      final errors = <String>[];

      expect(
        runFinalTestPlanGenerator(
          const <String>['--write', '--source-commit', _fixtureSourceCommit],
          repositoryRoot: Directory.current,
          outputRoot: outputRoot,
          stderr: errors.add,
          checkoutCommitResolverForTesting: (_) =>
              'fedcba9876543210fedcba9876543210fedcba98',
        ),
        1,
      );
      expect(errors.join('\n'), contains('checkout HEAD'));
      expect(_markdownFile(outputRoot).existsSync(), isFalse);
      expect(_jsonFile(outputRoot).existsSync(), isFalse);
    });

    test('--check rejects artifacts for a different explicit commit', () {
      final outputRoot = Directory.systemTemp.createTempSync(
        'lexiquest-final-test-plan-check-commit-',
      );
      addTearDown(() => outputRoot.deleteSync(recursive: true));
      final artifacts = buildFinalTestPlanArtifacts(
        repositoryRoot: Directory.current,
        sourceCommit: _fixtureSourceCommit,
      );
      _markdownFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync(artifacts.markdown);
      _jsonFile(outputRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync(artifacts.normalizedJson);

      expect(
        runFinalTestPlanGenerator(
          const <String>[
            '--check',
            '--source-commit',
            'fedcba9876543210fedcba9876543210fedcba98',
          ],
          repositoryRoot: Directory.current,
          outputRoot: outputRoot,
        ),
        1,
      );
    });
  });
}

Map<String, dynamic> _currentManifest() {
  return _decode(
    buildFinalTestPlanArtifacts(
      repositoryRoot: Directory.current,
      sourceCommit: _fixtureSourceCommit,
    ).normalizedJson,
  );
}

Map<String, dynamic> _decode(String source) {
  return jsonDecode(source) as Map<String, dynamic>;
}

Map<String, dynamic> _clone(Map<String, dynamic> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _maps(Object? value) {
  return (value as List<dynamic>).cast<Map<String, dynamic>>();
}

Map<String, String> _currentRuntimeStates() {
  const registry = BuildFeatureRegistry.fieldDefaults();
  return <String, String>{
    for (final feature in Feature.values)
      feature.name: registry.stateOf(feature).name,
  };
}

File _markdownFile(Directory root) =>
    File('${root.path}/docs/generated/alltcas-8-44-final-test-plan.md');

File _jsonFile(Directory root) =>
    File('${root.path}/docs/generated/alltcas-8-44-final-test-plan.json');
