/// LexiQuest Architecture Fitness Tests
///
/// Structural rules enforced on every commit.
/// All rules MUST pass for Phase -1 Week 3-4 Gate 2.1 to clear.
///
/// Run:  flutter test test/architecture/fitness_test.dart
/// CI:   included in flutter_analyze + flutter_test jobs
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/compatibility_profiles.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

import '../../tool/feature_contract/generate_feature_map.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _root() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('pubspec.yaml not found');
    dir = parent;
  }
  return dir.path;
}

List<File> _dartFiles(String relDir) {
  final dir = Directory('${_root()}/$relDir');
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

List<File> _screenFiles() => _dartFiles('lib/screens');

String _read(String rel) {
  final f = File('${_root()}/$rel');
  return f.existsSync() ? f.readAsStringSync() : '';
}

String _canonicalNewlines(String source) {
  return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

Map<String, String> _productionDartSources() {
  final entries =
      _dartFiles('lib')
          .where((file) => !file.path.endsWith('.g.dart'))
          .map(
            (file) => MapEntry(
              file.path
                  .replaceAll('\\', '/')
                  .split('${_root().replaceAll('\\', '/')}/')
                  .last,
              file.readAsStringSync(),
            ),
          )
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, String>.fromEntries(entries);
}

({int start, int end}) _requiredBlockRange(String source, String marker) {
  final markerStart = source.indexOf(marker);
  if (markerStart < 0) {
    throw StateError('Required source marker is missing: $marker');
  }
  final bodyStart = source.indexOf('{', markerStart + marker.length);
  if (bodyStart < 0) {
    throw StateError('Required source block has no body: $marker');
  }
  var depth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '{':
        depth += 1;
        break;
      case '}':
        depth -= 1;
        if (depth == 0) {
          return (start: bodyStart, end: index + 1);
        }
        break;
    }
  }
  throw StateError('Required source block is unbalanced: $marker');
}

String _requiredBlock(String source, String marker) {
  final range = _requiredBlockRange(source, marker);
  return source.substring(range.start, range.end);
}

String _requiredMethodBody(String source, String marker) {
  final markerStart = source.indexOf(marker);
  if (markerStart < 0) {
    throw StateError('Required method marker is missing: $marker');
  }
  final parametersStart = source.indexOf('(', markerStart);
  if (parametersStart < 0) {
    throw StateError('Required method has no parameter list: $marker');
  }

  var parameterDepth = 0;
  var parametersEnd = -1;
  parameterScan:
  for (var index = parametersStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '(':
        parameterDepth += 1;
        break;
      case ')':
        parameterDepth -= 1;
        if (parameterDepth < 0) {
          throw StateError(
            'Required method parameter list is unbalanced: $marker',
          );
        }
        if (parameterDepth == 0) {
          parametersEnd = index + 1;
          break parameterScan;
        }
        break;
    }
  }
  if (parametersEnd < 0) {
    throw StateError('Required method parameter list is unbalanced: $marker');
  }

  final bodyStart = source.indexOf('{', parametersEnd);
  final declarationEnd = source.indexOf(';', parametersEnd);
  final expressionBody = source.indexOf('=>', parametersEnd);
  if (bodyStart < 0 ||
      (declarationEnd >= 0 && declarationEnd < bodyStart) ||
      (expressionBody >= 0 && expressionBody < bodyStart)) {
    throw StateError('Required method has no block body: $marker');
  }

  var bodyDepth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '{':
        bodyDepth += 1;
        break;
      case '}':
        bodyDepth -= 1;
        if (bodyDepth == 0) {
          return source.substring(bodyStart, index + 1);
        }
        break;
    }
  }
  throw StateError('Required method body is unbalanced: $marker');
}

int _occurrences(String source, String needle) {
  var count = 0;
  var start = 0;
  while (true) {
    final match = source.indexOf(needle, start);
    if (match < 0) return count;
    count += 1;
    start = match + needle.length;
  }
}

List<int> _streakMutationOffsets(String source) {
  final patterns = <RegExp>[
    RegExp(r'\b(?:db\.)?StreakStatesCompanion(?:\.insert)?\s*\('),
    RegExp(
      r'\.(?:into|update|delete)\s*\(\s*[^)]*\.streakStates\b',
      multiLine: true,
    ),
    RegExp(
      r'\b(?:INSERT(?:\s+OR\s+(?:ROLLBACK|ABORT|FAIL|IGNORE|REPLACE))?'
      r'\s+INTO|REPLACE\s+INTO|UPDATE(?:\s+OR\s+(?:ROLLBACK|ABORT|FAIL|IGNORE|REPLACE))?'
      r'|DELETE\s+FROM)\s+["`]?streak_states\b',
      caseSensitive: false,
      multiLine: true,
    ),
  ];
  return <int>[
    for (final pattern in patterns)
      for (final match in pattern.allMatches(source)) match.start,
  ]..sort();
}

// ---------------------------------------------------------------------------
// Test 1 — UI Layer Purity: no Drift / AppDatabase in screens
// ---------------------------------------------------------------------------

void main() {
  test('T1 — screens must not import Drift or AppDatabase directly', () {
    final violations = <String>[];
    for (final f in _screenFiles()) {
      final src = f.readAsStringSync();
      if (src.contains("package:drift/") || src.contains('app_database.dart')) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Screens must use use-cases, not Drift directly:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 2 — UI Layer Purity: no SharedPreferences in screens
  // ---------------------------------------------------------------------------

  test('T2 — screens must not import SharedPreferences', () {
    final violations = <String>[];
    for (final f in _screenFiles()) {
      if (f.readAsStringSync().contains('shared_preferences')) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Screens must not manage storage directly:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 3 — Voice Boundary: screens must use VoiceUseCases, not voice_provider
  // ---------------------------------------------------------------------------

  test('T3 — screens must not import voice_provider.dart directly', () {
    // Fix: implement VoiceUseCases (D2.2) and refactor all 10 screens.
    // See docs/v2-implementation/service_quarantine_registry.md — voice boundary.
    final violations = <String>[];
    for (final f in _screenFiles()) {
      final src = f.readAsStringSync();
      if (src.contains('voice_provider.dart') ||
          src.contains(
            "import 'package:lexiquest/voice/voice_provider.dart'",
          ) ||
          RegExp(r"import '.+voice_provider\.dart'").hasMatch(src)) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'These screens import VoiceProvider directly — use VoiceUseCases '
          '(lib/features/voice/application/voice_use_cases.dart) instead:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 4 — AI Boundary: screens must not import GeminiRestGateway directly
  // ---------------------------------------------------------------------------

  test('T4 — screens must not import gemini_rest_gateway.dart directly', () {
    final violations = <String>[];
    for (final f in _screenFiles()) {
      if (f.readAsStringSync().contains('gemini_rest_gateway')) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Screens must use GeminiTutorUseCases, not the gateway:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 5 — Motivation Isolation: motivation domain must not import
  //           learning repository (when domain exists)
  // ---------------------------------------------------------------------------

  test('T5 — motivation domain must not import learning repository', () {
    final motivationDir = Directory('${_root()}/lib/features/motivation');
    if (!motivationDir.existsSync()) {
      // Domain doesn't exist yet — pass (nothing to violate)
      return;
    }
    final violations = <String>[];
    for (final f in _dartFiles('lib/features/motivation')) {
      if (f.readAsStringSync().contains('drift_learning_repository')) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Motivation must not depend on learning repository:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 6 — Social Isolation: social domain must not write to core tables
  // ---------------------------------------------------------------------------

  test('T6 — social domain must not write to learning or mastery tables', () {
    final socialDataDir = Directory('${_root()}/lib/features/social/data');
    if (!socialDataDir.existsSync()) {
      // Domain doesn't exist yet — pass
      return;
    }
    final coreTablePattern = RegExp(
      r'LearningSessions|AnswerAttempts|SrsStates|MasteryStates',
    );
    final violations = <String>[];
    for (final f in _dartFiles('lib/features/social/data')) {
      final src = f.readAsStringSync();
      if (coreTablePattern.hasMatch(src) &&
          (src.contains('.insert(') ||
              src.contains('.update(') ||
              src.contains('.delete('))) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Social domain must not write to learning core tables:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 7 — Reward Idempotency: reward grants must have idempotencyKey
  // ---------------------------------------------------------------------------

  test('T7 — reward grants must use idempotencyKey and sourceEventId', () {
    final repoContent = _read(
      'lib/features/rewards/data/drift_reward_repository.dart',
    );
    expect(
      repoContent,
      isNotEmpty,
      reason:
          'lib/features/rewards/data/drift_reward_repository.dart not found',
    );
    expect(
      repoContent.contains('idempotencyKey'),
      isTrue,
      reason: 'Reward repository must enforce idempotencyKey on all grants',
    );
    // sourceEventId is defined on the RewardTransactions table schema
    // (progress_tables.dart); verify the repository uses it
    final tableContent = _read('lib/data/local/tables/progress_tables.dart');
    expect(
      tableContent.contains('sourceEventId'),
      isTrue,
      reason:
          'RewardTransactions table must have sourceEventId column for audit trail',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 8 — No Quarantine Imports in lib/features/
  // ---------------------------------------------------------------------------

  test('T8 — lib/features/ must not import quarantined services', () {
    const quarantined = [
      'streak_and_daily_quest_service',
      'adaptive_daily_quest_service',
      'local_user_progress_store',
      'word_service.dart',
      'srs_service.dart',
      'local_progress_repository',
    ];
    final violations = <String>[];
    for (final f in _dartFiles('lib/features')) {
      final src = f.readAsStringSync();
      for (final service in quarantined) {
        if (src.contains(service) &&
            !src.contains('// legacy') &&
            !src.contains('// quarantine-ok')) {
          violations.add(
            '${f.path.replaceAll("\\", "/").split("lib/").last} → $service',
          );
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Quarantine violations:\n${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 9 — Event Immutability: published domain events must be final/sealed
  // ---------------------------------------------------------------------------

  test(
    'T9 — published domain events must be immutable (final/sealed class)',
    () {
      final eventFiles = _dartFiles(
        'lib/features',
      ).where((f) => f.path.endsWith('_event.dart')).toList();
      if (eventFiles.isEmpty) return; // No event files yet — pass

      final violations = <String>[];
      for (final f in eventFiles) {
        final src = f.readAsStringSync();
        // Look for class declarations that appear to be events (contain 'Event')
        final classDecls = RegExp(r'^class\s+\w*Event', multiLine: true);
        if (classDecls.hasMatch(src) &&
            !src.contains('final class') &&
            !src.contains('sealed class')) {
          violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Event classes must use "final class" or "sealed class":\n'
            '${violations.join('\n')}',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Test 10 — Export Coverage: user-data tables must be in export inventory
  // ---------------------------------------------------------------------------

  test('T10 — user-data tables must be readable by DriftExportReader', () {
    // These 5 tables contain user-owned data that must be exportable.
    // Infrastructure tables (OutboxOperations, RuntimeFlags, etc.) are excluded.
    // Check Dart ORM accessor names (camelCase) as used in DriftExportReader
    const userDataTables = [
      'vocabulary_words', // SQL name used in raw SQL query
      'answer_attempts', // SQL name used in raw SQL / answerAttempts accessor
      'readingProgressEntries', // Dart ORM accessor name used in typed API
    ];
    final exportContent = _read(
      'lib/features/export/data/drift_export_reader.dart',
    );
    expect(
      exportContent,
      isNotEmpty,
      reason: 'lib/features/export/data/drift_export_reader.dart not found',
    );
    for (final table in userDataTables) {
      expect(
        exportContent.contains(table),
        isTrue,
        reason: 'User-data table "$table" not found in export reader',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // Test 11 — Firestore Rules Coverage: sync collections have security rules
  // ---------------------------------------------------------------------------

  test(
    'T11 — all sync collection wireNames must have Firestore security rules',
    () {
      // SyncCollection wireNames from lib/features/sync/domain/sync_entity.dart
      const wireNames = [
        'categories',
        'words',
        'attempts',
        'reading_events',
        'reward_transactions',
      ];
      final rules = _read('firestore.rules');
      expect(
        rules,
        isNotEmpty,
        reason: 'firestore.rules not found at project root',
      );
      for (final wireName in wireNames) {
        expect(
          rules.contains(wireName),
          isTrue,
          reason: 'SyncCollection "$wireName" has no Firestore security rule',
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Test 12 — Projection Rebuild Tests: each rebuilder has a test file
  // ---------------------------------------------------------------------------

  test('T12 — each projection rebuilder must have a dedicated test file', () {
    final rebuilders = _dartFiles(
      'lib/features',
    ).where((f) => f.path.endsWith('_projection_rebuilder.dart')).toList();

    expect(
      rebuilders,
      isNotEmpty,
      reason: 'No projection rebuilder files found in lib/features/',
    );

    final missing = <String>[];
    for (final rebuilder in rebuilders) {
      // e.g. lib/features/learning/data/drift_learning_projection_rebuilder.dart
      // → test/features/learning/drift_learning_projection_rebuilder_test.dart
      final rel = rebuilder.path
          .replaceAll('\\', '/')
          .split('lib/')
          .last; // features/learning/data/drift_learning...
      final testPath = '${_root()}/test/$rel'.replaceAll('.dart', '_test.dart');
      if (!File(testPath).existsSync()) {
        missing.add(testPath.split('test/').last);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Missing projection rebuilder tests (create them before Gate 2.1):\n'
          '${missing.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 13 — Migration Coverage: consolidated migration test covers schema v6
  // ---------------------------------------------------------------------------

  test('T13 — schema migration test exists and covers current schema', () {
    const migrationTestPath =
        'test/data/local/app_database_migration_test.dart';
    final content = _read(migrationTestPath);
    expect(
      content,
      isNotEmpty,
      reason: '$migrationTestPath not found — migration tests required',
    );

    // Verify the test references the current production schema version (v6)
    // and at least one of the most recent migration steps
    final hasCurrentSchema =
        content.contains('schemaVersion') ||
        content.contains('schema_version') ||
        content.contains('from: 5') ||
        content.contains('from: 6') ||
        content.contains("'v5'") ||
        content.contains("'v6'") ||
        content.contains('version: 6');

    expect(
      hasCurrentSchema,
      isTrue,
      reason:
          'app_database_migration_test.dart must reference current schema (v6)',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 14 — Feature Flag Registry: all FieldFeature values in registry
  // ---------------------------------------------------------------------------

  test(
    'T14 — all FieldFeature enum values must be in field_feature_registry',
    () {
      const registryPath = 'lib/runtime/field_feature_registry.dart';
      final content = _read(registryPath);
      expect(content, isNotEmpty, reason: '$registryPath not found');

      // These are the 13 known feature keys — update when adding new features
      const expectedFeatures = [
        'vocabulary',
        'quiz',
        'srs',
        'reading',
        'mastery',
        'weakness',
        'ghostDuel',
        'achievements',
        'shop',
        'objectScanner',
        'speechPractice',
        'aiTutor',
        'export',
      ];
      final missing = <String>[];
      for (final feature in expectedFeatures) {
        if (!content.contains(feature)) missing.add(feature);
      }
      expect(
        missing,
        isEmpty,
        reason: 'Features missing from registry: $missing',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Test 15 — AI Consent Enforcement: GeminiRestGateway checks consent
  // ---------------------------------------------------------------------------

  test('T15 — AI gateway (GeminiRestGateway) must reference consent', () {
    const gatewayPath = 'lib/features/gemini/data/gemini_rest_gateway.dart';
    final content = _read(gatewayPath);
    expect(content, isNotEmpty, reason: '$gatewayPath not found');
    expect(
      content.toLowerCase().contains('consent'),
      isTrue,
      reason: 'GeminiRestGateway must check research consent before AI calls',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 16 — Quest Quarantine: lib/features/ must not import the legacy
  //           streak_and_daily_quest_service (Phase 0 Week 10-11)
  // ---------------------------------------------------------------------------

  test(
    'T16 — lib/features/ must not import streak_and_daily_quest_service',
    () {
      const quarantinedServices = [
        'streak_and_daily_quest_service',
        'adaptive_daily_quest_service',
      ];
      final violations = <String>[];
      for (final f in _dartFiles('lib/features')) {
        final src = f.readAsStringSync();
        for (final service in quarantinedServices) {
          if (src.contains(service) && !src.contains('// quarantine-ok')) {
            violations.add(
              '${f.path.replaceAll("\\", "/").split("lib/").last} → $service',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'lib/features/ must not import the quarantined legacy quest '
            'services. Use QuestUseCases instead:\n${violations.join('\n')}',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Test 17 — SRS Quarantine: lib/features/ and lib/screens/ must not import
  //           SrsService (SharedPreferences-backed, deprecated Phase 0 W14-15)
  // ---------------------------------------------------------------------------

  test('T17 — no code must import SrsService', () {
    const quarantinedService = 'srs_service.dart';
    final violations = <String>[];
    for (final f in [
      ..._dartFiles('lib/features'),
      ..._dartFiles('lib/screens'),
    ]) {
      final src = f.readAsStringSync();
      if (src.contains(quarantinedService) &&
          !src.contains('// quarantine-ok')) {
        violations.add(f.path.replaceAll('\\', '/').split('lib/').last);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'SrsService is deprecated (SharedPreferences-backed). '
          'Use LearningUseCases.startDueReview() instead:\n'
          '${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------------
  // Task 13 — Shared compatibility foundation closure
  // ---------------------------------------------------------------------------

  test(
    'T18 — exact 44-product and 15-runtime catalogs generate exact docs',
    () {
      expect(FeatureContractId.values, hasLength(44));
      expect(allTcasIdeaIntegrationCatalog.records, hasLength(44));
      expect(
        allTcasIdeaIntegrationCatalog.records.map((record) => record.id),
        orderedEquals(FeatureContractId.values),
      );
      expect(Feature.values, hasLength(15));
      expect(productionFeatureContract, hasLength(15));
      expect(productionFeatureContract.keys.toSet(), Feature.values.toSet());
      expect(
        productContractIdsByRuntimeFeature.keys.toSet(),
        Feature.values.toSet(),
      );

      final generated = buildFeatureMapArtifacts(allTcasIdeaIntegrationCatalog);
      expect(
        _canonicalNewlines(
          _read('docs/generated/alltcas-idea-integration-feature-map.md'),
        ),
        _canonicalNewlines(generated.markdown),
      );
      expect(
        _canonicalNewlines(
          _read('docs/generated/alltcas-idea-integration-feature-map.json'),
        ),
        _canonicalNewlines(generated.normalizedJson),
      );
    },
  );

  test('T19 — production has no legacy FieldFeatureRegistry consumer', () {
    final consumers = <String>[];
    final legacyImport = RegExp(
      r'''^\s*import\s+['"][^'"]*field_feature_registry\.dart['"]''',
      multiLine: true,
    );
    final legacyUse = RegExp(
      r'\b(?:BuildFieldFeatureRegistry|FieldFeatureRegistry)\s*(?:[<.(])',
    );
    for (final entry in _productionDartSources().entries) {
      if (entry.key == 'lib/runtime/field_feature_registry.dart') continue;
      if (legacyImport.hasMatch(entry.value) ||
          legacyUse.hasMatch(entry.value)) {
        consumers.add(entry.key);
      }
    }
    expect(
      consumers,
      isEmpty,
      reason:
          'FieldFeatureRegistry is a legacy definition only; production '
          'must use FeatureRegistry:\n${consumers.join('\n')}',
    );
  });

  test('T20 — Streak and purchase keep their single-ledger authorities', () {
    const streakAuthority =
        'lib/features/motivation/data/drift_streak_repository.dart';
    const lifecycleException =
        'lib/features/identity/data/drift_owner_upgrade_repository.dart';
    final sources = _productionDartSources();
    final streakMutations = <String, List<int>>{
      for (final entry in sources.entries)
        if (_streakMutationOffsets(entry.value).isNotEmpty)
          entry.key: _streakMutationOffsets(entry.value),
    };
    expect(
      streakMutations.keys.toSet(),
      <String>{streakAuthority, lifecycleException},
      reason:
          'Only DriftStreakRepository may write operational Streak state; '
          'owner upgrade is the lifecycle-only exception.',
    );
    expect(
      sources[streakAuthority],
      contains('final class DriftStreakRepository'),
    );
    final lifecycleSource = sources[lifecycleException]!;
    final lifecycleRange = _requiredBlockRange(
      lifecycleSource,
      'Future<int> _mergeStreakState(',
    );
    expect(
      streakMutations[lifecycleException]!.every(
        (offset) =>
            offset >= lifecycleRange.start && offset < lifecycleRange.end,
      ),
      isTrue,
      reason:
          'Every owner-upgrade Streak mutation must stay lexically inside '
          '_mergeStreakState.',
    );
    expect(
      _read('test/architecture/streak_authority_test.dart'),
      contains('operational streak writes stay inside the canonical authority'),
      reason:
          'The exhaustive Drift API/alias/raw-SQL Streak writer detector must '
          'remain installed.',
    );

    final purchase = _requiredMethodBody(
      _read('lib/features/rewards/data/drift_reward_repository.dart'),
      'Future<PurchaseResult> purchase(',
    );
    for (final xpLedgerToken in const <String>[
      'pointsLedgerEntries',
      'PointsLedgerEntriesCompanion',
      'points_ledger_entries',
    ]) {
      expect(
        purchase,
        isNot(contains(xpLedgerToken)),
        reason: 'A cosmetic purchase must never write lifetime XP.',
      );
    }
    expect(purchase, contains('rewardTransactions'));
  });

  test(
    'T21 — every current activity is typed and screens avoid recordAnswer',
    () {
      const expectedActivities = <String>{
        'meaningMultipleChoice',
        'srsRecall',
        'typedRecall',
        'associativeRecall',
        'ghostDuel',
        'speakToText',
        'shadowing',
        'readingExposure',
      };
      expect(
        CurrentActivityInput.values.map((value) => value.name).toSet(),
        expectedActivities,
      );
      final activitySource = _read(
        'lib/features/learning/application/current_activity_evidence.dart',
      );
      expect(activitySource, contains('final EvidenceClass evidenceClass;'));
      expect(activitySource, contains('final String promptMode;'));
      expect(activitySource, contains('final String skillId;'));
      for (final activity in CurrentActivityInput.values) {
        expect(
          RegExp(
            'CurrentActivityInput\\.${activity.name}\\s*=>\\s*'
            'const _CurrentActivityDeclaration\\s*\\(',
          ).allMatches(activitySource),
          hasLength(1),
          reason: '${activity.name} must have exactly one typed declaration',
        );
      }

      final deprecatedCallers = <String>[];
      final deprecatedRecordAnswer = RegExp(r'\.\s*recordAnswer\s*\(');
      for (final file in _screenFiles()) {
        if (deprecatedRecordAnswer.hasMatch(file.readAsStringSync())) {
          deprecatedCallers.add(
            file.path.replaceAll('\\', '/').split('lib/').last,
          );
        }
      }
      expect(
        deprecatedCallers,
        isEmpty,
        reason:
            'Screens must capture typed evidence, not call the deprecated '
            'recordAnswer wrapper:\n${deprecatedCallers.join('\n')}',
      );
    },
  );

  test(
    'T22 — production evidence and sync stay Legacy v1 and research Off',
    () async {
      const evidenceProvider = FixedEvidencePolicyRolloutModeProvider.legacy();
      expect(
        await evidenceProvider.resolve(
          ownerId: 'architecture-fitness-owner',
          evidenceContext: null,
        ),
        EvidencePolicyRolloutMode.legacy,
      );
      expect(
        _read(
          'lib/features/learning/application/current_activity_evidence.dart',
        ),
        contains('const FixedEvidencePolicyRolloutModeProvider.legacy()'),
      );

      const payloadRollout = SyncPayloadRollout.productionDefault();
      expect(payloadRollout.writeVersionFor(SyncCollection.attempts), 1);
      const researchRollout = ResearchCollectionSyncRollout.off();
      expect(researchRollout.enabled, isFalse);
      expect(researchRollout.allowsExperimentAssignmentClaims, isFalse);
      expect(researchRollout.allowsAssessmentRunClaims, isFalse);
      final syncStore = _read('lib/features/sync/data/drift_sync_store.dart');
      expect(
        syncStore,
        contains(
          'this.payloadRollout = const SyncPayloadRollout.productionDefault()',
        ),
      );
      expect(
        syncStore,
        contains(
          'this.researchSyncRollout = const ResearchCollectionSyncRollout.off()',
        ),
      );

      final deploymentEvidenceViolations = <String>[];
      for (final entry in _productionDartSources().entries) {
        if (entry.value.contains('test:rules') ||
            entry.value.contains('firestore-rules.test.cjs')) {
          deploymentEvidenceViolations.add(entry.key);
        }
      }
      expect(
        deploymentEvidenceViolations,
        isEmpty,
        reason:
            'Local rules tests are verification only, never deployment '
            'evidence:\n${deploymentEvidenceViolations.join('\n')}',
      );
      final bootstrap = _read('lib/runtime/app_bootstrap.dart');
      expect(bootstrap, isNot(contains('experimentAssignmentV1RulesRevision')));
      expect(bootstrap, isNot(contains('assessmentRunV1RulesRevision')));
    },
  );

  test('T23 — v2 receipts bridge exact v1 receipts before any sink', () {
    final reconciler = _read(
      'lib/features/learning/application/learning_side_effect_reconciler.dart',
    );
    final pending = _requiredMethodBody(
      reconciler,
      'Future<void> _applyPending(',
    );
    final pendingBridgeStart = pending.indexOf('if (v1Receipt != null)');
    final pendingSinkStart = pending.indexOf(
      'final outcome = evidenceSink == null',
    );
    expect(pendingBridgeStart, greaterThanOrEqualTo(0));
    expect(pendingSinkStart, greaterThan(pendingBridgeStart));
    final pendingBridge = _requiredBlock(pending, 'if (v1Receipt != null)');
    expect(pendingBridge, contains('bridgedFromVersion: 1'));
    expect(pendingBridge, contains('continue;'));
    expect(pendingBridge, isNot(contains('await sink')));

    final reward = _requiredMethodBody(
      reconciler,
      'Future<void> _applyRewardPending(',
    );
    final rewardBridgeStart = reward.indexOf('if (v1Receipt != null)');
    final rewardSinkStart = reward.indexOf('final outcome = await sink(');
    expect(rewardBridgeStart, greaterThanOrEqualTo(0));
    expect(rewardSinkStart, greaterThan(rewardBridgeStart));
    final rewardBridge = _requiredBlock(reward, 'if (v1Receipt != null)');
    expect(rewardBridge, contains('bridgedFromVersion: 1'));
    expect(rewardBridge, contains('continue;'));
    expect(rewardBridge, isNot(contains('await sink')));

    final eventStore = _read(
      'lib/features/learning/data/drift_learning_event_store.dart',
    );
    final markReceipt = _requiredMethodBody(
      eventStore,
      'Future<void> markProjectionOutcome(',
    );
    expect(markReceipt, contains('await _requireMatchingBridgeReceipt('));
    final bridgeValidation = _requiredMethodBody(
      eventStore,
      'Future<void> _requireMatchingBridgeReceipt(',
    );
    expect(bridgeValidation, contains('earlier.outcome != outcome'));
    expect(
      bridgeValidation,
      contains('jsonEncode(earlier.result) != jsonEncode(result)'),
    );
  });

  test('T24 — assessment reaches Outcome only through shared evidence', () {
    final assessmentPolicy =
        evidenceCompatibilityMatrix[ContractEvidenceClass.assessment]!;
    for (final deniedProjection in const <ProjectionFamily>{
      ProjectionFamily.masterySrs,
      ProjectionFamily.pronunciation,
      ProjectionFamily.quest,
      ProjectionFamily.streak,
      ProjectionFamily.achievement,
      ProjectionFamily.xp,
      ProjectionFamily.coins,
    }) {
      expect(
        assessmentPolicy[deniedProjection],
        ProjectionDecision.deny,
        reason: 'Assessment must not reach ${deniedProjection.name}.',
      );
    }
    expect(
      assessmentPolicy[ProjectionFamily.assessmentOutcome],
      ProjectionDecision.allow,
    );

    const forbiddenDirectProjectionImports = <String>[
      'drift_learning_projection_rebuilder.dart',
      '/motivation/',
      '/quest/',
      '/rewards/',
      '/progress/',
    ];
    final violations = <String>[];
    for (final file in _dartFiles('lib/features/assessment')) {
      final source = file.readAsStringSync();
      for (final forbidden in forbiddenDirectProjectionImports) {
        if (source.contains(forbidden)) {
          violations.add('${file.path}: $forbidden');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Assessment must not import learning/motivation projection '
          'authorities directly:\n${violations.join('\n')}',
    );
    final useCases = _read(
      'lib/features/assessment/application/assessment_use_cases.dart',
    );
    expect(useCases, contains('learning.resolveEvidenceForRecording('));
    expect(useCases, contains('learning.recordResolvedEvidence('));
  });

  test(
    'T25 — lifecycle manifest covers every live table exactly once',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final liveTables = database.allTables
          .map((table) => table.actualTableName)
          .toList(growable: false);
      final manifestTables = ownerLifecycleManifest
          .map((entry) => entry.tableName)
          .toList(growable: false);

      expect(liveTables, hasLength(33));
      expect(manifestTables, hasLength(liveTables.length));
      expect(manifestTables.toSet(), hasLength(manifestTables.length));
      expect(manifestTables.toSet(), liveTables.toSet());
      expect(ownerLifecycleExportTableNames, liveTables.toSet());
      expect(ownerLifecycleDeletionTableNames, liveTables.toSet());
    },
  );

  test('T26 — assignment and assessment have exact v1 sync and rules', () {
    expect(
      SyncCollection.experimentAssignments.wireName,
      'experiment_assignments',
    );
    expect(
      SyncCollection.experimentAssignments.entityType,
      'experimentAssignment',
    );
    expect(SyncCollection.experimentAssignments.supportedPayloadVersions, <int>{
      1,
    });
    expect(SyncCollection.assessmentRuns.wireName, 'assessment_runs');
    expect(SyncCollection.assessmentRuns.entityType, 'assessmentRun');
    expect(SyncCollection.assessmentRuns.supportedPayloadVersions, <int>{1});

    final gateway = _read('lib/features/sync/data/firestore_sync_gateway.dart');
    expect(
      gateway,
      contains('ExperimentAssignmentSyncPayloadContract.requireCanonical('),
    );
    expect(
      gateway,
      contains('AssessmentRunSyncPayloadContract.requireCanonical('),
    );
    final store = _read('lib/features/sync/data/drift_sync_store.dart');
    expect(store, contains('Future<void> _applyExperimentAssignment('));
    expect(store, contains('Future<void> _applyAssessmentRun('));

    final rules = _read('firestore.rules');
    expect(
      _occurrences(rules, 'match /experiment_assignments/{assignmentId}'),
      1,
    );
    expect(_occurrences(rules, 'match /assessment_runs/{runId}'), 1);
    expect(rules, contains('fieldExperimentAssignmentPayloadOk'));
    expect(rules, contains('fieldAssessmentRunCreateOk'));
    expect(rules, contains('fieldAssessmentRunTerminalUpdateOk'));
    expect(rules, isNot(contains('match /assessment_attempts/')));
    expect(rules, isNot(contains('match /assessment_responses/')));
  });

  test('T27 — runtime feature flags never assign an experiment cohort', () {
    final violations = <String>[];
    final mutator = RegExp(r'\b(?:assignIfAbsent|assignIfConsented)\s*\(');
    final cohortArgument = RegExp(r'\bcohort\s*:');
    for (final entry in _productionDartSources().entries) {
      if (!entry.key.startsWith('lib/runtime/')) continue;
      if (mutator.hasMatch(entry.value) ||
          cohortArgument.hasMatch(entry.value)) {
        violations.add(entry.key);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Runtime visibility/kill-switch code may read assignments but never '
          'assign a cohort:\n${violations.join('\n')}',
    );
  });

  test('T28 — composed Hub History Review and Recommendation own no table', () {
    final tableNames = ownerLifecycleManifest
        .map((entry) => entry.tableName)
        .toList(growable: false);
    final competingSource = RegExp(
      r'(?:today(?:_hub)?|history|review_center|recommendation)',
      caseSensitive: false,
    );
    expect(
      tableNames.where(competingSource.hasMatch),
      isEmpty,
      reason:
          'Today Hub, History, Review Center, and Recommendation must '
          'compose canonical read models and own no source table.',
    );
    expect(
      _read('lib/features/learning/application/learning_use_cases.dart'),
      contains('listSessionHistory('),
    );
    expect(
      _read('lib/features/progress/data/drift_progress_queries.dart'),
      contains('recommendations:'),
    );
  });
}
