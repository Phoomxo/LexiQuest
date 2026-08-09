import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  group('Schema v7→v8 migration — D6.1 Quest persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    // ── Table existence ──────────────────────────────────────────────────────

    test('quest_definitions table exists after fresh onCreate', () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='quest_definitions'",
          )
          .get();
      expect(
        tables,
        hasLength(1),
        reason: 'quest_definitions table must exist',
      );
    });

    test('quest_instances table exists after fresh onCreate', () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='quest_instances'",
          )
          .get();
      expect(tables, hasLength(1), reason: 'quest_instances table must exist');
    });

    test(
      'quest_objective_progress table exists after fresh onCreate',
      () async {
        await db.customSelect('SELECT 1').get();
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type='table' AND name='quest_objective_progress'",
            )
            .get();
        expect(
          tables,
          hasLength(1),
          reason: 'quest_objective_progress table must exist',
        );
      },
    );

    // ── Schema version ───────────────────────────────────────────────────────

    test('fresh database reports schema version 12', () async {
      await db.customSelect('SELECT 1').get();
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(
        version,
        12,
        reason: 'schema v12 deployed (owner-scoped AI usage)',
      );
    });

    // ── Basic CRUD ───────────────────────────────────────────────────────────

    test('can insert and retrieve quest_definitions row', () async {
      await db
          .into(db.questDefinitions)
          .insert(
            QuestDefinitionsCompanion.insert(
              questId: 'q-daily-vocab',
              catalogVersion: 1,
              title: 'Daily Vocabulary',
              description: 'Review 10 words today',
              type: 'daily',
              objectivesJson:
                  '[{"objectiveId":"o1","description":"Review","targetCount":10,'
                  '"eventType":"QuizCompleted","filters":{"correct":true}}]',
              rewardJson: '{"xpAmount":50,"rewardItemId":null}',
            ),
          );

      final rows = await db.select(db.questDefinitions).get();
      expect(rows, hasLength(1));
      expect(rows.first.questId, 'q-daily-vocab');
      expect(rows.first.type, 'daily');
      expect(rows.first.catalogVersion, 1);
    });

    test('can insert quest_instances with FK to local_owners', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-q', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db
          .into(db.questDefinitions)
          .insert(
            QuestDefinitionsCompanion.insert(
              questId: 'q-test',
              catalogVersion: 1,
              title: 'Test',
              description: 'Test quest',
              type: 'milestone',
              objectivesJson: '[]',
              rewardJson: '{"xpAmount":10,"rewardItemId":null}',
            ),
          );

      await db
          .into(db.questInstances)
          .insert(
            QuestInstancesCompanion.insert(
              instanceId: 'inst-01',
              questId: 'q-test',
              ownerId: 'owner-q',
              catalogVersion: 1,
              assignedAtUtcMs: now.millisecondsSinceEpoch,
              state: 'active',
            ),
          );

      final rows = await (db.select(
        db.questInstances,
      )..where((t) => t.instanceId.equals('inst-01'))).get();
      expect(rows, hasLength(1));
      expect(rows.first.state, 'active');
      expect(rows.first.ownerId, 'owner-q');
    });

    // ── Unique constraint ────────────────────────────────────────────────────

    test(
      'unique(owner_id, quest_id) prevents duplicate active instances',
      () async {
        final now = DateTime.now().toUtc();
        await db.customInsert(
          "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
          "VALUES ('owner-dup', 'localGuest', ${now.millisecondsSinceEpoch})",
        );
        await db
            .into(db.questDefinitions)
            .insert(
              QuestDefinitionsCompanion.insert(
                questId: 'q-dup',
                catalogVersion: 1,
                title: 'Dup',
                description: '',
                type: 'daily',
                objectivesJson: '[]',
                rewardJson: '{"xpAmount":0,"rewardItemId":null}',
              ),
            );

        await db
            .into(db.questInstances)
            .insert(
              QuestInstancesCompanion.insert(
                instanceId: 'inst-dup-1',
                questId: 'q-dup',
                ownerId: 'owner-dup',
                catalogVersion: 1,
                assignedAtUtcMs: now.millisecondsSinceEpoch,
                state: 'active',
              ),
            );

        // Second insert with same (owner_id, quest_id) must fail.
        expect(
          () => db
              .into(db.questInstances)
              .insert(
                QuestInstancesCompanion.insert(
                  instanceId: 'inst-dup-2',
                  questId: 'q-dup',
                  ownerId: 'owner-dup',
                  catalogVersion: 1,
                  assignedAtUtcMs: now.millisecondsSinceEpoch,
                  state: 'active',
                ),
              ),
          throwsA(anything),
          reason: 'unique(owner_id, quest_id) must prevent duplicate instances',
        );
      },
    );

    // ── Cascade delete ───────────────────────────────────────────────────────

    test(
      'deleting quest_instance cascades to quest_objective_progress',
      () async {
        final now = DateTime.now().toUtc();
        await db.customInsert(
          "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
          "VALUES ('owner-cascade', 'localGuest', ${now.millisecondsSinceEpoch})",
        );
        await db
            .into(db.questDefinitions)
            .insert(
              QuestDefinitionsCompanion.insert(
                questId: 'q-cascade',
                catalogVersion: 1,
                title: 'Cascade',
                description: '',
                type: 'daily',
                objectivesJson: '[]',
                rewardJson: '{"xpAmount":0,"rewardItemId":null}',
              ),
            );
        await db
            .into(db.questInstances)
            .insert(
              QuestInstancesCompanion.insert(
                instanceId: 'inst-cascade',
                questId: 'q-cascade',
                ownerId: 'owner-cascade',
                catalogVersion: 1,
                assignedAtUtcMs: now.millisecondsSinceEpoch,
                state: 'active',
              ),
            );
        await db
            .into(db.questObjectiveProgress)
            .insert(
              QuestObjectiveProgressCompanion.insert(
                id: 'inst-cascade:obj1',
                instanceId: 'inst-cascade',
                objectiveId: 'obj1',
                targetCount: 5,
              ),
            );

        // Delete instance — progress row should cascade.
        await (db.delete(
          db.questInstances,
        )..where((t) => t.instanceId.equals('inst-cascade'))).go();

        final progressRows = await (db.select(
          db.questObjectiveProgress,
        )..where((t) => t.instanceId.equals('inst-cascade'))).get();
        expect(
          progressRows,
          isEmpty,
          reason: 'Cascade delete must remove orphaned progress rows',
        );
      },
    );
  });
}
