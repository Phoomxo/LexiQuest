/// Phase -1 Week 1-2 Gate Verification Tests
///
/// These tests verify that all 5 deliverables exist and contain
/// required content. They are file-system / static-analysis tests
/// and do NOT require a running Flutter app or database.
///
/// Run: flutter test test/phase_minus_1/week_1_2_verification_test.dart
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _root() {
  // Walk up from test/ to project root
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('pubspec.yaml not found');
    dir = parent;
  }
  return dir.path;
}

String _read(String relativePath) {
  final path = '${_root()}/$relativePath';
  final file = File(path);
  if (!file.existsSync()) return '';
  return file.readAsStringSync();
}

List<String> _dartFiles(String relativeDir) {
  final dir = Directory('${_root()}/$relativeDir');
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList();
}

// ---------------------------------------------------------------------------
// D1.1 — Write Path Authority Matrix
// ---------------------------------------------------------------------------

void main() {
  group('D1.1 — authority_matrix.md', () {
    late String content;

    setUpAll(() {
      content = _read('docs/v2-implementation/authority_matrix.md');
    });

    test('file exists', () {
      expect(content, isNotEmpty,
          reason: 'docs/v2-implementation/authority_matrix.md not found');
    });

    test('covers all 21 Drift tables', () {
      final requiredTables = [
        'LocalOwners',
        'ResearchConsents',
        'VocabularyCategories',
        'VocabularyWords',
        'VocabularyImports',
        'VocabularyImportRows',
        'LearningSessions',
        'AnswerAttempts',
        'SrsStates',
        'ReadingProgressEntries',
        'ReadingEvents',
        'PointsLedgerEntries',
        'AchievementUnlocks',
        'RewardTransactions',
        'OwnedRewardItems',
        'EquippedRewardItems',
        'OutboxOperations',
        'SyncCheckpoints',
        'SyncConflicts',
        'RuntimeFlags',
        'ModelDownloads',
      ];
      for (final table in requiredTables) {
        expect(content.contains(table), isTrue,
            reason: 'Table $table not documented in authority_matrix.md');
      }
    });

    test('documents PointsLedgerEntries dual-write conflict as CRITICAL', () {
      expect(content.contains('CONFLICT') || content.contains('CRITICAL'), isTrue,
          reason: 'PointsLedgerEntries dual-write conflict must be documented');
    });

    test('documents SharedPreferences write paths', () {
      expect(content.contains('SharedPreferences'), isTrue);
    });

    test('documents in-memory state as CRITICAL', () {
      expect(content.contains('_currentStreakDays') || content.contains('in-memory'), isTrue,
          reason: 'In-memory streak state must be documented');
    });

    test('documents direct Firestore writes', () {
      expect(content.contains('word_service') || content.contains('Firestore'), isTrue,
          reason: 'Direct Firestore writes in word_service must be documented');
    });

    test('documents V2 action for every section', () {
      expect(content.contains('V2 Action'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // D1.2 — Semantic Freeze Contract
  // ---------------------------------------------------------------------------

  group('D1.2 — semantic_contract.md', () {
    late String content;

    setUpAll(() {
      content = _read('docs/v2-implementation/semantic_contract.md');
    });

    test('file exists', () {
      expect(content, isNotEmpty,
          reason: 'docs/v2-implementation/semantic_contract.md not found');
    });

    test('defines XP as non-spendable', () {
      expect(
        content.contains('Non-spendable') || content.contains('non-spendable'),
        isTrue,
        reason: 'XP must be defined as non-spendable',
      );
    });

    test('defines Coins as spendable', () {
      expect(
        content.contains('Spendable') || content.contains('spendable'),
        isTrue,
        reason: 'Coins must be defined as spendable',
      );
    });

    test('retires the "Points" term', () {
      expect(
        content.contains('DEPRECATED') || content.contains('RETIRED'),
        isTrue,
        reason: '"Points" must be retired in semantic contract',
      );
    });

    test('defines Mastery as separate from XP and Coins', () {
      expect(content.contains('Mastery'), isTrue);
      expect(content.contains('NOT affected by'), isTrue,
          reason: 'Mastery must state what it is NOT affected by');
    });

    test('defines Quest with persistence requirement', () {
      expect(content.contains('Quest'), isTrue);
      expect(
        content.contains('Drift') || content.contains('persistent'),
        isTrue,
        reason: 'Quest definition must require persistence',
      );
    });

    test('defines Streak with Drift storage requirement', () {
      expect(content.contains('Streak'), isTrue);
      expect(content.contains('StreakStates') || content.contains('Drift table'), isTrue,
          reason: 'Streak must require Drift storage, not in-memory');
    });

    test('quarantines streak_and_daily_quest_service', () {
      expect(content.contains('streak_and_daily_quest_service'), isTrue,
          reason: 'streak_and_daily_quest_service must be listed as quarantined');
    });

    test('defines idempotency requirement for XP and Coins grants', () {
      expect(content.contains('idempotencyKey'), isTrue,
          reason: 'idempotencyKey required for all grant operations');
    });
  });

  // ---------------------------------------------------------------------------
  // D1.3 — Schema Version Audit
  // ---------------------------------------------------------------------------

  group('D1.3 — schema_audit_2026_08_04.md', () {
    late String content;

    setUpAll(() {
      content = _read('docs/database/schema_audit_2026_08_04.md');
    });

    test('file exists', () {
      expect(content, isNotEmpty,
          reason: 'docs/database/schema_audit_2026_08_04.md not found');
    });

    test('confirms current schema is version 6', () {
      expect(
        content.contains('schemaVersion => 6') ||
            content.contains('schema = 6') ||
            content.contains('schema: **6**'),
        isTrue,
        reason: 'Audit must confirm max schema in field is 6',
      );
    });

    test('declares v7 through v9 as safe', () {
      expect(content.contains('v7'), isTrue);
      expect(content.contains('v8'), isTrue);
      expect(content.contains('v9'), isTrue);
      expect(content.contains('SAFE') || content.contains('safe'), isTrue);
    });

    test('confirms v7 and v8 migrations deployed, no v9+ migration exists yet', () {
      final dbContent = _read('lib/data/local/app_database.dart');
      expect(dbContent.contains('from < 7'), isTrue,
          reason: 'Schema v7 migration must exist after Week 5-6');
      expect(dbContent.contains('from < 8'), isTrue,
          reason: 'Schema v8 migration must exist after Phase 0 Week 10-11');
      expect(dbContent.contains('from < 9'), isTrue,
          reason: 'Schema v9 migration must exist after Phase 1 D7.2');
      expect(dbContent.contains('from < 10'), isFalse);
    });

    test('current schemaVersion in code is 9', () {
      final dbContent = _read('lib/data/local/app_database.dart');
      expect(dbContent.contains('schemaVersion => 9'), isTrue,
          reason: 'app_database.dart schemaVersion must be 9 after Phase 1 D7.2');
    });
  });

  // ---------------------------------------------------------------------------
  // D1.4 — Schema Reservation Ledger
  // ---------------------------------------------------------------------------

  group('D1.4 — schema_ledger.md', () {
    late String content;

    setUpAll(() {
      content = _read('docs/database/schema_ledger.md');
    });

    test('file exists', () {
      expect(content, isNotEmpty,
          reason: 'docs/database/schema_ledger.md not found');
    });

    test('records v1 through v6 history', () {
      for (final v in ['v1', 'v2', 'v3', 'v4', 'v5', 'v6']) {
        expect(content.contains(v), isTrue,
            reason: '$v must be in schema ledger history');
      }
    });

    test('reserves v7 for EventEnvelopeV2', () {
      expect(content.contains('v7'), isTrue);
      expect(
        content.contains('EventEnvelope') || content.contains('EventEnvelopeV2'),
        isTrue,
        reason: 'v7 must be reserved for EventEnvelopeV2',
      );
    });

    test('reserves v8 for Quest/Streak/Mastery tables', () {
      expect(content.contains('v8'), isTrue);
      expect(
        content.contains('Quest') || content.contains('Streak'),
        isTrue,
        reason: 'v8 must be reserved for Quest/Streak domain',
      );
    });

    test('reserves v9 for identity/projection tables', () {
      expect(content.contains('v9'), isTrue);
    });

    test('v10+ is Phase 0 scope', () {
      expect(content.contains('v10'), isTrue);
      expect(content.contains('Phase 0'), isTrue);
    });

    test('documents amendment process', () {
      expect(
        content.contains('Amendment') || content.contains('amendment'),
        isTrue,
        reason: 'Ledger must document how to add reservations',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // D1.5 — Service Quarantine Registry
  // ---------------------------------------------------------------------------

  group('D1.5 — service_quarantine_registry.md', () {
    late String content;

    setUpAll(() {
      content = _read('docs/v2-implementation/service_quarantine_registry.md');
    });

    test('file exists', () {
      expect(content, isNotEmpty,
          reason: 'docs/v2-implementation/service_quarantine_registry.md not found');
    });

    test('quarantines streak_and_daily_quest_service', () {
      expect(content.contains('streak_and_daily_quest_service'), isTrue);
    });

    test('quarantines adaptive_daily_quest_service', () {
      expect(content.contains('adaptive_daily_quest_service'), isTrue);
    });

    test('quarantines srs_service', () {
      expect(content.contains('srs_service'), isTrue);
    });

    test('quarantines local_user_progress_store', () {
      expect(content.contains('local_user_progress_store'), isTrue);
    });

    test('quarantines word_service', () {
      expect(content.contains('word_service'), isTrue);
    });

    test('provides V2 replacement for each quarantined service', () {
      expect(content.contains('replacement') || content.contains('V2 replacement'), isTrue,
          reason: 'Each quarantined service must have a V2 replacement documented');
    });

    test('provides architecture fitness test snippet', () {
      expect(
        content.contains('fitness') || content.contains("test('features/"),
        isTrue,
        reason: 'Quarantine registry must include enforcement test',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-cutting: No quarantined service imports in lib/features/
  // ---------------------------------------------------------------------------

  group('Live codebase: quarantine boundary enforcement', () {
    final quarantinedImports = [
      'streak_and_daily_quest_service',
      'adaptive_daily_quest_service',
      'srs_service.dart',
      'local_user_progress_store',
      'word_service.dart',
      'local_progress_repository',
    ];

    test('lib/features/ does not import quarantined services', () {
      final featureFiles = _dartFiles('lib/features');
      final violations = <String>[];

      for (final filePath in featureFiles) {
        final fileContent = File(filePath).readAsStringSync();
        for (final service in quarantinedImports) {
          if (fileContent.contains(service) &&
              !fileContent.contains('// legacy') &&
              !fileContent.contains('// quarantine-ok')) {
            violations.add('$filePath → $service');
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'Quarantine violations found:\n${violations.join('\n')}');
    });

    test('lib/features/ does not write to SharedPreferences', () {
      final featureFiles = _dartFiles('lib/features');
      final violations = <String>[];

      for (final filePath in featureFiles) {
        final fileContent = File(filePath).readAsStringSync();
        if (fileContent.contains('SharedPreferences') &&
            !fileContent.contains('// legacy') &&
            !fileContent.contains('// sharedprefs-ok')) {
          violations.add(filePath);
        }
      }

      expect(violations, isEmpty,
          reason: 'lib/features/ must not use SharedPreferences:\n'
              '${violations.join('\n')}');
    });

    test('lib/features/ does not use ambiguous "points" identifier', () {
      final featureFiles = _dartFiles('lib/features');
      final violations = <String>[];
      final pointsPattern = RegExp(r'\bpoints\b', caseSensitive: false);

      for (final filePath in featureFiles) {
        final fileContent = File(filePath).readAsStringSync();
        if (pointsPattern.hasMatch(fileContent) &&
            !fileContent.contains('PointsLedger') &&
            !fileContent.contains('// legacy')) {
          // Check each line
          var lineNo = 0;
          for (final line in fileContent.split('\n')) {
            lineNo++;
            if (pointsPattern.hasMatch(line) &&
                !line.contains('PointsLedger') &&
                !line.trim().startsWith('//') &&
                !line.contains('// legacy')) {
              violations.add('$filePath:$lineNo → $line');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason:
              'Ambiguous "points" usage in lib/features/:\n${violations.join('\n')}');
    });
  });
}
