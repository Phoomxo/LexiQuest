import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

QuestDefinition _dailyVocabDef({int catalogVersion = 1, String questId = 'q-daily-vocab'}) => QuestDefinition(
      questId: questId,
      catalogVersion: catalogVersion,
      title: 'Daily Vocabulary',
      description: 'Review 10 words today',
      type: QuestType.daily,
      objectives: const [
        QuestObjective(
          objectiveId: 'obj-review',
          description: 'Review words',
          targetCount: 3,
          criteria: ObjectiveCriteria(
            eventType: 'QuizCompleted',
            filters: {'correct': true},
          ),
        ),
      ],
      reward: const RewardSpec(xpAmount: 50),
    );

QuestInstance _newInstance({
  String instanceId = 'inst-001',
  String ownerId = 'owner-test',
  String? questId,
  QuestInstanceState state = QuestInstanceState.active,
}) {
  final def = _dailyVocabDef();
  final qid = questId ?? def.questId;
  return QuestInstance(
    instanceId: instanceId,
    questId: qid,
    ownerId: ownerId,
    catalogVersion: def.catalogVersion,
    assignedAtUtc: DateTime.utc(2026, 8, 4, 8, 0),
    state: state,
    progress: [
      const ObjectiveProgress(
        objectiveId: 'obj-review',
        currentCount: 0,
        targetCount: 3,
      ),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late db.AppDatabase database;
  late DriftQuestRepository repo;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = DriftQuestRepository(database);
    // Seed required owner FK.
    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('owner-test', 'localGuest', 1722758400000)",
    );
  });

  tearDown(() async => database.close());

  group('DriftQuestRepository', () {
    // ── Definition CRUD ──────────────────────────────────────────────────────

    test('upsertDefinition persists catalog row', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      final def = await repo.getDefinition('q-daily-vocab');
      expect(def, isNotNull);
      expect(def!.title, 'Daily Vocabulary');
      expect(def.type, QuestType.daily);
      expect(def.objectives, hasLength(1));
      expect(def.objectives.first.targetCount, 3);
      expect(def.reward.xpAmount, 50);
    });

    test('upsertDefinition with higher catalogVersion overwrites', () async {
      await repo.upsertDefinition(_dailyVocabDef(catalogVersion: 1));
      await repo.upsertDefinition(_dailyVocabDef(catalogVersion: 2));
      final def = await repo.getDefinition('q-daily-vocab');
      expect(def!.catalogVersion, 2);
    });

    test('getDefinition returns null for unknown questId', () async {
      final def = await repo.getDefinition('does-not-exist');
      expect(def, isNull);
    });

    // ── Instance CRUD ────────────────────────────────────────────────────────

    test('startInstance persists instance with initial progress', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());

      final active = await repo.getActiveInstances('owner-test');
      expect(active, hasLength(1));
      expect(active.first.instanceId, 'inst-001');
      expect(active.first.state, QuestInstanceState.active);
      expect(active.first.progress, hasLength(1));
      expect(active.first.progress.first.currentCount, 0);
      expect(active.first.progress.first.targetCount, 3);
    });

    test('startInstance is idempotent — duplicate call is ignored', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());
      await repo.startInstance(_newInstance()); // second call — no-op
      final active = await repo.getActiveInstances('owner-test');
      expect(active, hasLength(1));
    });

    test('getActiveInstances excludes completed instances', () async {
      // Two separate quest definitions so unique(owner_id, quest_id) is satisfied.
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.upsertDefinition(_dailyVocabDef(questId: 'q-daily-vocab-2'));

      await repo.startInstance(_newInstance(instanceId: 'inst-active'));
      await repo.startInstance(
          _newInstance(instanceId: 'inst-done', questId: 'q-daily-vocab-2'));
      await repo.markCompleted('inst-done', DateTime.utc(2026, 8, 4, 12));

      final active = await repo.getActiveInstances('owner-test');
      expect(active, hasLength(1));
      expect(active.first.instanceId, 'inst-active');
    });

    test('getAllInstances returns all states', () async {
      // Two separate quest definitions so unique(owner_id, quest_id) is satisfied.
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.upsertDefinition(_dailyVocabDef(questId: 'q-daily-vocab-b'));

      await repo.startInstance(_newInstance(instanceId: 'inst-a'));
      await repo.startInstance(
          _newInstance(instanceId: 'inst-b', questId: 'q-daily-vocab-b'));
      await repo.markExpired('inst-b', DateTime.utc(2026, 8, 5));

      final all = await repo.getAllInstances('owner-test');
      expect(all, hasLength(2));
    });

    // ── Progress updates ─────────────────────────────────────────────────────

    test('saveProgress updates objective counters', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());

      final updated = [
        const ObjectiveProgress(
          objectiveId: 'obj-review',
          currentCount: 2,
          targetCount: 3,
          sourceEventIds: ['evt-a', 'evt-b'],
        ),
      ];
      await repo.saveProgress('inst-001', updated);

      final instances = await repo.getActiveInstances('owner-test');
      final progress = instances.first.progress.first;
      expect(progress.currentCount, 2);
      expect(progress.sourceEventIds, ['evt-a', 'evt-b']);
    });

    // ── State transitions ────────────────────────────────────────────────────

    test('markCompleted sets state and completedAtUtc', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());

      final completedAt = DateTime.utc(2026, 8, 4, 14, 30);
      await repo.markCompleted('inst-001', completedAt);

      final all = await repo.getAllInstances('owner-test');
      expect(all.first.state, QuestInstanceState.completed);
      expect(all.first.completedAtUtc, completedAt);
    });

    test('markExpired sets state and expiredAtUtc', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());

      final expiredAt = DateTime.utc(2026, 8, 5, 0, 0);
      await repo.markExpired('inst-001', expiredAt);

      final all = await repo.getAllInstances('owner-test');
      expect(all.first.state, QuestInstanceState.expired);
      expect(all.first.expiredAtUtc, expiredAt);
    });

    test('markAbandoned sets state to abandoned', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      await repo.startInstance(_newInstance());
      await repo.markAbandoned('inst-001');

      final all = await repo.getAllInstances('owner-test');
      expect(all.first.state, QuestInstanceState.abandoned);
    });
  });
}
