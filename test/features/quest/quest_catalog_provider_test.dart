import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

void main() {
  group('QuestCatalogProvider — D8.2', () {
    test(
      'answer manifests preserve every authored field and fixed policies',
      () {
        final revisions = QuestCatalogProvider.authoredRevisions;
        expect(
          revisions.map((r) => r.definition.questId),
          QuestCatalogProvider.allQuests.map((q) => q.questId),
        );
        for (final revision in revisions) {
          final def = revision.definition;
          final body = QuestCatalogProvider.canonicalAnswerManifest(revision);
          final manifest = jsonDecode(body) as Map<String, dynamic>;
          expect(body, canonicalJson(manifest));
          expect(manifest, {
            'questId': def.questId,
            'catalogVersion': def.catalogVersion,
            'title': def.title,
            'description': def.description,
            'type': def.type.name,
            'objectives': [
              for (final objective in def.objectives)
                {
                  'objectiveId': objective.objectiveId,
                  'description': objective.description,
                  'targetCount': objective.targetCount,
                  'eventType': objective.criteria.eventType,
                  'filters': objective.criteria.filters,
                },
            ],
            'reward': {
              'xpAmount': def.reward.xpAmount,
              'rewardItemId': def.reward.rewardItemId,
            },
            'expiresInMs': def.expiresIn?.inMilliseconds,
            'tags': def.tags,
            'definitionSchemaVersion': 1,
            'criteriaPolicyVersion': 1,
            'calendarPolicyVersion': TimezonePolicy.version,
            'occurrencePolicy': 'civil-segments-v1',
            'activeFromUtcMs': 0,
          });
          expect(revision.activeFromUtcMs, 0);
        }
        expect(revisions.first.definition.objectives.single.targetCount, 5);
        expect(revisions.first.definition.reward.xpAmount, 50);
        expect(revisions.last.definition.objectives.single.targetCount, 20);
        expect(revisions.last.definition.reward.xpAmount, 200);
      },
    );

    test('catalog version is defined', () {
      expect(QuestCatalogProvider.version, greaterThan(0));
    });

    test('daily quests are non-empty and well-formed', () {
      final daily = QuestCatalogProvider.dailyQuests;
      expect(daily, isNotEmpty);
      for (final def in daily) {
        expect(def.questId, isNotEmpty);
        expect(def.objectives, isNotEmpty);
        expect(def.type, QuestType.daily);
        expect(
          def.expiresIn,
          isNotNull,
          reason: 'daily quests must expire after 24 h',
        );
        expect(def.reward.xpAmount, greaterThan(0));
      }
    });

    test('weekly quests are non-empty and well-formed', () {
      final weekly = QuestCatalogProvider.weeklyQuests;
      expect(weekly, isNotEmpty);
      for (final def in weekly) {
        expect(def.questId, isNotEmpty);
        expect(def.objectives, isNotEmpty);
        expect(def.type, QuestType.weekly);
        expect(
          def.expiresIn,
          isNotNull,
          reason: 'weekly quests must expire after 7 days',
        );
        expect(def.reward.xpAmount, greaterThan(0));
      }
    });

    test('no duplicate questIds across allQuests', () {
      final ids = QuestCatalogProvider.allQuests.map((d) => d.questId).toList();
      final uniqueIds = ids.toSet();
      expect(
        uniqueIds.length,
        ids.length,
        reason: 'each quest must have a unique ID in the catalog',
      );
    });

    test('weekly reward > daily reward (incentive ordering)', () {
      final dailyXp = QuestCatalogProvider.dailyQuests
          .map((d) => d.reward.xpAmount)
          .reduce((a, b) => a + b);
      final weeklyXp = QuestCatalogProvider.weeklyQuests
          .map((d) => d.reward.xpAmount)
          .reduce((a, b) => a + b);
      expect(
        weeklyXp,
        greaterThan(dailyXp),
        reason: 'weekly quests must offer more XP than daily quests',
      );
    });

    test('objectives use correct V2 event type', () {
      for (final def in QuestCatalogProvider.allQuests) {
        for (final obj in def.objectives) {
          expect(
            obj.criteria.eventType,
            'QuizCompleted',
            reason: 'catalog objectives must target V2 QuizCompleted events',
          );
        }
      }
    });
  });
}
