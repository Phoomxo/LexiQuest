import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Adventure file stays behind read-only authority ports', () {
    final files = Directory('lib/features/adventure')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
    expect(files.length, greaterThan(20));

    const forbiddenImports = <String>[
      'quest/application/quest_use_cases.dart',
      'quest/domain/quest_repository.dart',
      'quest/data/drift_quest_repository.dart',
      'motivation/application/streak_use_cases.dart',
      'motivation/data/drift_streak_repository.dart',
      'progress/domain/achievement_policy.dart',
      'rewards/application/reward_use_cases.dart',
      'rewards/application/shadow_reward_orchestrator.dart',
      'rewards/data/drift_reward_repository.dart',
      'rewards/domain/reward_grant_request.dart',
      'learning/data/drift_learning_event_store.dart',
      'learning/application/learning_side_effect_reconciler.dart',
    ];
    final forbiddenCalls = <RegExp>[
      RegExp(r'\.projectEvent\s*\('),
      RegExp(r'\.reconcile(?:Owner|Reward)\s*\('),
      RegExp(r'\.applyProjection\s*\('),
      RegExp(r'\.recordLearningDay(?:ForOwner)?\s*\('),
      RegExp(r'\.grant(?:Coins|QuestXp|QuestXpAndCoins)\s*\('),
      RegExp(r'\.purchase\s*\('),
      RegExp(r'\.equip\s*\('),
      RegExp(r'\.markProjectionOutcome\s*\('),
      RegExp(r'\.ensureDecisionSetForAttempt\s*\('),
      RegExp(r'\bRewardGrantRequest\s*\('),
      RegExp(r'\bAchievementPolicy\s*\('),
      RegExp(r'\bDriftLearningEventStore\s*\('),
    ];
    final violations = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync().replaceAll('\\', '/');
      for (final forbidden in forbiddenImports) {
        if (source.contains(forbidden)) {
          violations.add('${file.path}: import $forbidden');
        }
      }
      for (final pattern in forbiddenCalls) {
        if (pattern.hasMatch(source)) {
          violations.add('${file.path}: ${pattern.pattern}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Adventure may read canonical projections but never mutate them.',
    );
  });

  test(
    'Adventure cannot invoke Quest Streak Achievement or Reward mutation',
    () {
      final adventureFiles = Directory('lib/features/adventure')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final violations = <String>[];
      final forbidden = <RegExp>[RegExp(r'adventure_progress')];
      for (final file in adventureFiles) {
        final source = file.readAsStringSync();
        for (final pattern in forbidden) {
          if (pattern.hasMatch(source)) {
            violations.add('${file.path}: ${pattern.pattern}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Adventure is a read-only projection over canonical authority.',
      );
    },
  );

  test(
    'motivation reader contains no persistence or receipt synthesis calls',
    () {
      final file = File(
        'lib/features/adventure/application/'
        'adventure_motivation_projection_reader.dart',
      );
      expect(file.existsSync(), isTrue, reason: 'Task 4.2 reader is required.');
      if (!file.existsSync()) return;

      final source = file.readAsStringSync();
      for (final forbidden in <RegExp>[
        RegExp(r'\.insert\s*\('),
        RegExp(r'\.insertOnConflictUpdate\s*\('),
        RegExp(r'\.write\s*\('),
        RegExp(r'\.delete\s*\('),
        RegExp(r'\.customInsert\s*\('),
        RegExp(r'\.customUpdate\s*\('),
        RegExp(r'\.customStatement\s*\('),
        RegExp(r'\.markProjectionOutcome\s*\('),
        RegExp(r'\.ensureDecisionSetForAttempt\s*\('),
        RegExp(r'''['"]learning-projection:'''),
        RegExp(r'adventure_progress'),
      ]) {
        expect(source, isNot(matches(forbidden)), reason: forbidden.pattern);
      }
    },
  );

  test(
    'Adventure integration waits passively and exposes no grant callback',
    () {
      final bootstrap = File(
        'lib/runtime/app_bootstrap.dart',
      ).readAsStringSync();
      final start = bootstrap.indexOf('final adventureReceiptBarrier');
      final end = bootstrap.indexOf(
        'ActiveLearningTimeController createActiveLearningTimeController',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final barrierWiring = bootstrap.substring(start, end);
      expect(barrierWiring, contains('learningReconciliation.drain()'));
      expect(barrierWiring, isNot(contains('learningReconciliation.request(')));

      final navigation = File(
        'lib/screens/main_navigation_screen.dart',
      ).readAsStringSync();
      for (final forbidden in <RegExp>[
        RegExp(r'\.grant(?:Coins|QuestXp|QuestXpAndCoins)\s*\('),
        RegExp(r'\.reconcile(?:Owner|Reward)\s*\('),
        RegExp(r'\.request\s*\('),
      ]) {
        expect(
          navigation,
          isNot(matches(forbidden)),
          reason: forbidden.pattern,
        );
      }
    },
  );
}
