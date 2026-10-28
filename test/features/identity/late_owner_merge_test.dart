import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    var conflictId = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 10, 28),
      generateConflictId: () => 'late-conflict-${++conflictId}',
      generateOwnerId: () => 'unused',
    );
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'guest',
            createdAtUtcMs: 1,
            isActive: const Value(true),
          ),
        );
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'account',
            createdAtUtcMs: 1,
            firebaseUid: const Value('synthetic-firebase'),
          ),
        );
  });
  tearDown(() => database.close());

  test(
    'late natural-key collisions keep target state and archive all guest evidence',
    () async {
      for (final quest in ['shared-quest', 'guest-only-quest']) {
        await database
            .into(database.questDefinitions)
            .insert(
              QuestDefinitionsCompanion.insert(
                questId: quest,
                catalogVersion: 1,
                title: 'Synthetic quest',
                description: '',
                type: 'daily',
                objectivesJson: '[]',
                rewardJson: '{}',
              ),
            );
      }
      for (final owner in ['guest', 'account']) {
        final guest = owner == 'guest';
        await database
            .into(database.streakStates)
            .insert(
              StreakStatesCompanion.insert(
                ownerId: owner,
                currentStreakDays: Value(guest ? 9 : 4),
                longestStreakDays: Value(guest ? 12 : 6),
                freezeCount: Value(guest ? 3 : 1),
                updatedAtUtcMs: 10,
              ),
            );
        await database
            .into(database.learningDayLog)
            .insert(
              LearningDayLogCompanion.insert(
                id: '$owner-day',
                ownerId: owner,
                learningDay: '2026-10-27',
                firstSessionAtUtcMs: guest ? 5 : 10,
              ),
            );
        await database
            .into(database.questInstances)
            .insert(
              QuestInstancesCompanion.insert(
                instanceId: '$owner-instance',
                questId: 'shared-quest',
                ownerId: owner,
                catalogVersion: 1,
                assignedAtUtcMs: 1,
                state: 'active',
              ),
            );
        await database
            .into(database.questObjectiveProgress)
            .insert(
              QuestObjectiveProgressCompanion.insert(
                id: '$owner-objective',
                instanceId: '$owner-instance',
                objectiveId: 'read',
                currentCount: Value(guest ? 5 : 1),
                targetCount: 10,
                sourceEventIdsJson: Value('["synthetic-$owner-event"]'),
              ),
            );
        await database
            .into(database.associationRecords)
            .insert(
              AssociationRecordsCompanion.insert(
                id: '$owner-cue',
                ownerId: owner,
                wordKey: 'station',
                type: 'keyword',
                content: '$owner cue',
                createdAtUtcMs: 1,
              ),
            );
        await database
            .into(database.associativeMemoryStates)
            .insert(
              AssociativeMemoryStatesCompanion.insert(
                id: '$owner-memory',
                ownerId: owner,
                wordKey: 'station',
                stability: Value(guest ? 9.0 : 2.0),
                nextDueAtUtcMs: 20,
                algorithmVersion: 'synthetic-v1',
              ),
            );
      }
      await database
          .into(database.learningDayLog)
          .insert(
            LearningDayLogCompanion.insert(
              id: 'guest-only-day',
              ownerId: 'guest',
              learningDay: '2026-10-26',
              firstSessionAtUtcMs: 3,
            ),
          );
      await database
          .into(database.questInstances)
          .insert(
            QuestInstancesCompanion.insert(
              instanceId: 'guest-only-instance',
              questId: 'guest-only-quest',
              ownerId: 'guest',
              catalogVersion: 1,
              assignedAtUtcMs: 1,
              state: 'active',
            ),
          );
      await database
          .into(database.questObjectiveProgress)
          .insert(
            QuestObjectiveProgressCompanion.insert(
              id: 'guest-only-objective',
              instanceId: 'guest-only-instance',
              objectiveId: 'read',
              currentCount: const Value(2),
              targetCount: 10,
            ),
          );
      await database
          .into(database.associationRecords)
          .insert(
            AssociationRecordsCompanion.insert(
              id: 'guest-only-cue',
              ownerId: 'guest',
              wordKey: 'ticket',
              type: 'keyword',
              content: 'preserved cue',
              createdAtUtcMs: 1,
            ),
          );
      await database
          .into(database.associativeMemoryStates)
          .insert(
            AssociativeMemoryStatesCompanion.insert(
              id: 'guest-only-memory',
              ownerId: 'guest',
              wordKey: 'ticket',
              nextDueAtUtcMs: 30,
              algorithmVersion: 'synthetic-v1',
            ),
          );

      final result = await repository.upgrade(
        activeOwnerId: 'guest',
        firebaseUid: 'synthetic-firebase',
      );
      expect(result.targetOwnerId, 'account');
      expect(result.conflictCount, 5);
      final streak = await database.select(database.streakStates).getSingle();
      expect(streak.ownerId, 'account');
      expect(streak.currentStreakDays, 4);
      expect(streak.freezeCount, 1);
      expect(
        (await database.select(database.associationRecords).get())
            .firstWhere((row) => row.wordKey == 'station')
            .content,
        'account cue',
      );
      for (final table in [
        'quest_instances',
        'streak_states',
        'learning_day_log',
        'association_records',
        'associative_memory_states',
      ]) {
        final count = await database
            .customSelect(
              'SELECT COUNT(*) AS n FROM $table WHERE owner_id = ?',
              variables: const [Variable<String>('guest')],
            )
            .getSingle();
        expect(count.read<int>('n'), 0, reason: table);
      }
      expect(
        await database.select(database.learningDayLog).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.questInstances).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.associationRecords).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.associativeMemoryStates).get(),
        hasLength(2),
      );
      final objectives = await database
          .select(database.questObjectiveProgress)
          .get();
      expect(objectives.map((row) => row.id).toSet(), {
        'account-objective',
        'guest-only-objective',
      });
      final conflicts = await database.select(database.syncConflicts).get();
      expect(conflicts, hasLength(5));
      expect(conflicts.every((row) => row.ownerId == 'account'), isTrue);
      final snapshots = conflicts
          .map(
            (row) => jsonDecode(row.localSnapshotJson!) as Map<String, dynamic>,
          )
          .toList();
      expect(
        snapshots.singleWhere(
          (row) =>
              row['owner_id'] == 'guest' && row.containsKey('freeze_count'),
        )['freeze_count'],
        3,
      );
      expect(
        snapshots.singleWhere(
          (row) => row['content'] == 'guest cue',
        )['word_key'],
        'station',
      );
      final questSnapshot = snapshots.singleWhere(
        (row) => row['instance_id'] == 'guest-instance',
      );
      final archivedObjectives =
          questSnapshot['objectiveProgress'] as List<dynamic>;
      expect(archivedObjectives.single['current_count'], 5);
      expect(
        archivedObjectives.single['source_event_ids_json'],
        '["synthetic-guest-event"]',
      );

      final replay = await repository.upgrade(
        activeOwnerId: 'account',
        firebaseUid: 'synthetic-firebase',
      );
      expect(replay.conflictCount, 0);
      expect(await database.select(database.syncConflicts).get(), hasLength(5));
    },
  );

  test(
    'owner merge remaps canonical alias targets but preserves incoming identities',
    () async {
      for (final owner in ['guest', 'account']) {
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: '$owner-category',
                ownerId: owner,
                name: 'Travel',
                normalizedName: 'travel',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: '$owner-word',
                ownerId: owner,
                categoryId: '$owner-category',
                spelling: 'station',
                normalizedSpelling: 'station',
                meaning: 'synthetic',
                normalizedMeaning: 'synthetic',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
      }
      for (final kind in ['category', 'word']) {
        await database
            .into(database.syncConflicts)
            .insert(
              SyncConflictsCompanion.insert(
                id: '$kind-alias',
                ownerId: 'guest',
                entityType: kind,
                entityId: 'guest-$kind',
                localRevision: 1,
                cloudRevision: 1,
                resolutionPolicy: 'naturalKeyLocalTarget',
                outcome: 'localRetained',
                localSnapshotJson: Value(
                  jsonEncode({
                    'canonicalEntityId': 'guest-$kind',
                    'note': 'synthetic retained metadata',
                  }),
                ),
                cloudSnapshotJson: Value(
                  jsonEncode({'incomingId': 'guest-$kind'}),
                ),
                resolvedAtUtcMs: 1,
              ),
            );
      }

      await repository.upgrade(
        activeOwnerId: 'guest',
        firebaseUid: 'synthetic-firebase',
      );

      for (final kind in ['category', 'word']) {
        final alias = await (database.select(
          database.syncConflicts,
        )..where((row) => row.id.equals('$kind-alias'))).getSingle();
        expect(alias.ownerId, 'account');
        expect(alias.entityId, 'guest-$kind');
        expect(jsonDecode(alias.localSnapshotJson!), {
          'canonicalEntityId': 'account-$kind',
          'note': 'synthetic retained metadata',
        });
        expect(jsonDecode(alias.cloudSnapshotJson!), {
          'incomingId': 'guest-$kind',
        });
      }
    },
  );
}
