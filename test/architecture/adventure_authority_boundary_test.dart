import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Adventure motivation reader exists and imports no grant authority', () {
    final file = File(
      'lib/features/adventure/application/'
      'adventure_motivation_projection_reader.dart',
    );
    expect(file.existsSync(), isTrue, reason: 'Task 4.2 reader is required.');
    if (!file.existsSync()) return;

    final source = file.readAsStringSync();
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
    ];
    for (final forbidden in forbiddenImports) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test(
    'Adventure cannot invoke Quest Streak Achievement or Reward mutation',
    () {
      final adventureFiles = Directory('lib/features/adventure')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final violations = <String>[];
      final forbidden = <RegExp>[
        RegExp(r'\.projectEvent\s*\('),
        RegExp(r'\.reconcileReward\s*\('),
        RegExp(r'\.applyProjection\s*\('),
        RegExp(r'\.recordLearningDay(?:ForOwner)?\s*\('),
        RegExp(r'\.grant(?:Coins|QuestXp|QuestXpAndCoins)\s*\('),
        RegExp(r'\.purchase\s*\('),
        RegExp(r'\.equip\s*\('),
        RegExp(r'\bRewardGrantRequest\s*\('),
        RegExp(r'\bAchievementPolicy\s*\('),
      ];
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
        RegExp(r'adventure_progress'),
      ]) {
        expect(source, isNot(matches(forbidden)), reason: forbidden.pattern);
      }
    },
  );
}
