import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

QuestDefinition _dailyVocabDef({
  int catalogVersion = 1,
  String questId = 'q-daily-vocab',
}) => QuestDefinition(
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
    test(
      'period starting one microsecond before activation is ineligible',
      () async {
        final catalog = await repo.installAnswerCatalog();
        final beforeEpoch = DateTime.fromMicrosecondsSinceEpoch(
          -1,
          isUtc: true,
        );
        await expectLater(
          catalog.pinsForPeriod(
            database: database,
            dailyStartUtc: beforeEpoch,
            weeklyStartUtc: beforeEpoch,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'answer catalog rejects a Quest family shared by daily and weekly',
      () async {
        final daily = QuestCatalogProvider.dailyCorrectAnswers;
        final weekly = QuestCatalogProvider.weeklyCorrectAnswers;
        final shared = QuestDefinition(
          questId: daily.questId,
          catalogVersion: 2,
          title: weekly.title,
          description: weekly.description,
          type: weekly.type,
          objectives: weekly.objectives,
          reward: weekly.reward,
          expiresIn: weekly.expiresIn,
          tags: weekly.tags,
        );
        await expectLater(
          repo.installAnswerCatalog(
            authoredRevisions: [
              QuestCatalogRevision(definition: daily, activeFromUtcMs: 0),
              QuestCatalogRevision(definition: shared, activeFromUtcMs: 0),
            ],
          ),
          throwsStateError,
        );
        expect(
          await database.select(database.questDefinitionRevisions).get(),
          isEmpty,
        );
        expect(await database.select(database.questInstances).get(), isEmpty);
      },
    );

    test('pending calendar uses the sole archived initial revision', () async {
      final catalog = await repo.installAnswerCatalog();
      final pins = await catalog.pinsForPendingCalendar(
        database: database,
        occurredAtUtcMs: DateTime.utc(2026, 8, 4).millisecondsSinceEpoch,
        epochEffectiveUtcUs: 0,
      );
      expect(
        pins.daily.questId,
        QuestCatalogProvider.dailyCorrectAnswers.questId,
      );
      expect(pins.daily.catalogVersion, 1);
      expect(
        pins.weekly.questId,
        QuestCatalogProvider.weeklyCorrectAnswers.questId,
      );
      expect(pins.weekly.catalogVersion, 1);
      expect(await database.select(database.questInstances).get(), isEmpty);
    });

    test(
      'pending calendar rejects another database, negative time and archive tampering',
      () async {
        final catalog = await repo.installAnswerCatalog();
        final other = db.AppDatabase(NativeDatabase.memory());
        addTearDown(other.close);
        await expectLater(
          catalog.pinsForPendingCalendar(
            database: other,
            occurredAtUtcMs: 1,
            epochEffectiveUtcUs: 0,
          ),
          throwsA(isA<Object>()),
        );
        await expectLater(
          catalog.pinsForPendingCalendar(
            database: database,
            occurredAtUtcMs: -1,
            epochEffectiveUtcUs: 0,
          ),
          throwsA(isA<Object>()),
        );
        await database.customStatement(
          'UPDATE quest_definition_revisions SET canonical_definition=? WHERE quest_id=?',
          ['{}', QuestCatalogProvider.weeklyCorrectAnswers.questId],
        );
        await expectLater(
          catalog.pinsForPendingCalendar(
            database: database,
            occurredAtUtcMs: 1,
            epochEffectiveUtcUs: 0,
          ),
          throwsA(isA<Object>()),
        );
      },
    );

    test('pending calendar rejects ambiguous authored revisions', () async {
      final authored = [...QuestCatalogProvider.authoredRevisions];
      final daily = QuestCatalogProvider.dailyCorrectAnswers;
      authored.add(
        QuestCatalogRevision(
          definition: QuestDefinition(
            questId: daily.questId,
            catalogVersion: 2,
            title: daily.title,
            description: daily.description,
            type: daily.type,
            objectives: daily.objectives,
            reward: daily.reward,
            expiresIn: daily.expiresIn,
            tags: daily.tags,
          ),
          activeFromUtcMs: DateTime.utc(2026, 8, 4, 12).millisecondsSinceEpoch,
        ),
      );
      final catalog = await repo.installAnswerCatalog(
        authoredRevisions: authored,
      );
      await expectLater(
        catalog.pinsForPendingCalendar(
          database: database,
          occurredAtUtcMs: DateTime.utc(2026, 8, 5).millisecondsSinceEpoch,
          epochEffectiveUtcUs: 0,
        ),
        throwsStateError,
      );
    });

    test(
      'pending calendar rejects epochs that cannot prove original eligibility',
      () async {
        final catalog = await repo.installAnswerCatalog();
        await expectLater(
          catalog.pinsForPendingCalendar(
            database: database,
            occurredAtUtcMs: 0,
            epochEffectiveUtcUs: -1,
          ),
          throwsA(isA<Object>()),
        );
        await expectLater(
          catalog.pinsForPendingCalendar(
            database: database,
            occurredAtUtcMs: 1,
            epochEffectiveUtcUs: 1001,
          ),
          throwsA(isA<Object>()),
        );
      },
    );

    test(
      'answer catalog archives exact canonical bytes without seeding legacy quests',
      () async {
        final catalog = await repo.installAnswerCatalog();
        final rows = await database
            .select(database.questDefinitionRevisions)
            .get();
        expect(rows, hasLength(2));
        for (final revision in QuestCatalogProvider.authoredRevisions) {
          final row = rows.singleWhere(
            (r) =>
                r.questId == revision.definition.questId &&
                r.catalogVersion == revision.definition.catalogVersion,
          );
          final body = QuestCatalogProvider.canonicalAnswerManifest(revision);
          expect(row.canonicalDefinition, body);
          expect(
            row.definitionDigest,
            sha256.convert(utf8.encode(body)).toString(),
          );
        }
        final pins = await catalog.pinsForPeriod(
          database: database,
          dailyStartUtc: DateTime.utc(2026, 8, 4),
          weeklyStartUtc: DateTime.utc(2026, 8, 3),
        );
        expect(
          pins.daily.questId,
          QuestCatalogProvider.dailyCorrectAnswers.questId,
        );
        expect(
          pins.weekly.questId,
          QuestCatalogProvider.weeklyCorrectAnswers.questId,
        );
        expect(await database.select(database.questDefinitions).get(), isEmpty);
        expect(await database.select(database.questInstances).get(), isEmpty);
        expect(
          await database.select(database.questClaimReceipts).get(),
          isEmpty,
        );
        expect(await database.select(database.outboxOperations).get(), isEmpty);
        expect(await database.select(database.eventsV2).get(), isEmpty);
        expect(await database.select(database.researchConsents).get(), isEmpty);
        await repo.installAnswerCatalog();
        expect(
          await database.select(database.questDefinitionRevisions).get(),
          hasLength(2),
        );
      },
    );

    test('catalog conflicts roll back and preserve legacy definitions', () async {
      await repo.upsertDefinition(_dailyVocabDef());
      final original = await database.select(database.questDefinitions).get();
      final authored = QuestCatalogProvider.authoredRevisions;
      final first = authored.first;
      await database.customStatement(
        'INSERT INTO quest_definition_revisions '
        '(quest_id,catalog_version,definition_digest,canonical_definition) VALUES (?,?,?,?)',
        [
          first.definition.questId,
          first.definition.catalogVersion,
          'wrong',
          '{}',
        ],
      );
      await expectLater(repo.installAnswerCatalog(), throwsA(isA<Object>()));
      final revisions = await database
          .select(database.questDefinitionRevisions)
          .get();
      expect(revisions, hasLength(1));
      expect(revisions.single.definitionDigest, 'wrong');
      expect(revisions.single.canonicalDefinition, '{}');
      expect(await database.select(database.questDefinitions).get(), original);
      expect(await database.select(database.questInstances).get(), isEmpty);
    });

    test(
      'pins select fixed authored versions at each first period start',
      () async {
        final authored = [...QuestCatalogProvider.authoredRevisions];
        final oldDaily = QuestCatalogProvider.dailyCorrectAnswers;
        final futureObjectives = [...oldDaily.objectives];
        final future = QuestDefinition(
          questId: oldDaily.questId,
          catalogVersion: 2,
          title: oldDaily.title,
          description: oldDaily.description,
          type: oldDaily.type,
          objectives: futureObjectives,
          reward: oldDaily.reward,
          expiresIn: oldDaily.expiresIn,
          tags: oldDaily.tags,
        );
        final activation = DateTime.utc(2026, 8, 4, 12);
        authored.add(
          QuestCatalogRevision(
            definition: future,
            activeFromUtcMs: activation.millisecondsSinceEpoch,
          ),
        );
        final catalog = await repo.installAnswerCatalog(
          authoredRevisions: authored,
        );
        authored.clear();
        futureObjectives.clear();
        final before = await catalog.pinsForPeriod(
          database: database,
          dailyStartUtc: DateTime.utc(2026, 8, 4),
          weeklyStartUtc: DateTime.utc(2026, 8, 3),
        );
        final after = await catalog.pinsForPeriod(
          database: database,
          dailyStartUtc: DateTime.utc(2026, 8, 5),
          weeklyStartUtc: DateTime.utc(2026, 8, 3),
        );
        expect(before.daily.catalogVersion, 1);
        expect(after.daily.catalogVersion, 2);
        expect(before.weekly.catalogVersion, 1);
        expect(after.weekly.catalogVersion, 1);
        expect(
          before.daily.definitionDigest,
          isNot(after.daily.definitionDigest),
        );
      },
    );

    test('catalog rejects another database and changed archived pins', () async {
      final catalog = await repo.installAnswerCatalog();
      final other = db.AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      Future<Object> pins(db.AppDatabase target) => catalog.pinsForPeriod(
        database: target,
        dailyStartUtc: DateTime.utc(2026, 8, 4),
        weeklyStartUtc: DateTime.utc(2026, 8, 3),
      );
      await expectLater(pins(other), throwsA(isA<Object>()));
      await database.customStatement(
        'UPDATE quest_definition_revisions SET canonical_definition=? WHERE quest_id=?',
        ['{}', QuestCatalogProvider.dailyCorrectAnswers.questId],
      );
      await expectLater(pins(database), throwsA(isA<Object>()));
      expect(await database.select(database.questInstances).get(), isEmpty);
    });

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
        _newInstance(instanceId: 'inst-done', questId: 'q-daily-vocab-2'),
      );
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
        _newInstance(instanceId: 'inst-b', questId: 'q-daily-vocab-b'),
      );
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
