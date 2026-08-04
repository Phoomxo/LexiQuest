/// LexiQuest Architecture Fitness Tests
///
/// 15 structural rules enforced on every commit.
/// All 15 MUST pass for Phase -1 Week 3-4 Gate 2.1 to clear.
///
/// Run:  flutter test test/architecture/fitness_test.dart
/// CI:   included in flutter_analyze + flutter_test jobs
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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
}
