import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import 'support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  setUp(() async {
    h = await QuestHarness.open();
    h.now = DateTime.utc(2026, 10, 29, 16, 58);
  });
  tearDown(() => h.close());

  Future<List<QuestCompletedEvent>> reconcile(
    QuestDefinition def, {
    bool Function()? current,
  }) => h.useCases.reconcile(
    expectedOwnerId: configuredOwnerId,
    catalog: [def],
    stillCurrent: current ?? () => true,
  );

  test(
    'calendar days and weeks preserve real DST boundaries and closed pins',
    () {
      final spring = QuestPeriod.at(
        type: QuestType.daily,
        atUtc: DateTime.utc(2026, 3, 8, 12),
        timezoneId: 'America/New_York',
      );
      final autumn = QuestPeriod.at(
        type: QuestType.daily,
        atUtc: DateTime.utc(2026, 11, 1, 12),
        timezoneId: 'America/New_York',
      );
      final week = QuestPeriod.at(
        type: QuestType.weekly,
        atUtc: DateTime.utc(2026, 3, 8, 12),
        timezoneId: 'America/New_York',
      );
      expect(spring.endUtc!.difference(spring.startUtc!).inHours, 23);
      expect(autumn.endUtc!.difference(autumn.startUtc!).inHours, 25);
      expect(week.endUtc!.difference(week.startUtc!).inHours, 167);
      expect(week.civilLabel, '2026-03-02');
      expect(QuestPeriod.parse(spring.json).json, spring.json);
      expect(spring.contains(spring.endUtc!), isFalse);
      expect(
        () => QuestPeriod.parse(
          jsonEncode({
            ...jsonDecode(spring.json) as Map<String, dynamic>,
            'policyVersion': 2,
          }),
        ),
        throwsStateError,
      );
      expect(
        () => QuestPeriod.parse(
          jsonEncode({
            ...jsonDecode(spring.json) as Map<String, dynamic>,
            'extra': true,
          }),
        ),
        throwsStateError,
      );
      expect(
        () => QuestPeriod.at(
          type: QuestType.daily,
          atUtc: DateTime.utc(2026),
          timezoneId: 'ICT',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'concurrent admission creates exactly one pinned daily instance',
    () async {
      final def = questDefinition();
      final admissions = await Future.wait(
        List.generate(5, (_) => h.useCases.startQuest(def)),
      );
      expect(admissions.whereType<QuestInstance>(), hasLength(1));
      final instance = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(instance.period!.civilLabel, '2026-10-29');
      expect(instance.definition!.catalogVersion, 1);
      expect(instance.definitionSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  for (final type in [QuestType.daily, QuestType.weekly]) {
    test(
      '${type.name} keeps the final civil hour through autumn DST',
      () async {
        h.now = type == QuestType.daily
            ? DateTime.utc(2026, 11, 1, 4)
            : DateTime.utc(2026, 10, 26, 4);
        final source = questDefinition(target: 1);
        final def = QuestDefinition(
          questId: source.questId,
          catalogVersion: source.catalogVersion,
          title: source.title,
          description: source.description,
          type: type,
          objectives: source.objectives,
          reward: source.reward,
          expiresIn: Duration(days: type == QuestType.daily ? 1 : 7),
        );
        final local = QuestUseCases(
          repository: h.repository,
          owners: h.storage.owners,
          generateId: () => 'synthetic-autumn-period',
          nowUtc: () => h.now,
          timezoneId: 'America/New_York',
        );
        final instance = (await local.startQuest(def))!;
        expect(instance.period!.endUtc, DateTime.utc(2026, 11, 2, 5));
        h.now = DateTime.utc(2026, 11, 2, 4, 30);
        final answer = await h.answer();
        expect(
          h.now.isAfter(instance.assignedAtUtc.add(def.expiresIn!)),
          isTrue,
        );
        expect(instance.period!.contains(h.now), isTrue);
        final protected = await h.protectedSnapshot();
        final completed = await local.processEvent(answer, [def]);
        expect(completed.single.completedAtUtc, answer.occurredAtUtc);
        expect(completed.single.objectiveEventIds, [answer.eventId]);
        expect(await h.protectedSnapshot(), protected);
      },
    );
  }

  test(
    'missed callbacks recover in canonical order before stale expiry',
    () async {
      final def = questDefinition(
        target: 2,
        expiry: const Duration(minutes: 1),
      );
      final original = (await h.useCases.startQuest(def))!;
      h.now = h.now.add(const Duration(seconds: 5));
      final first = await h.answer(id: 'synthetic-recovery-b');
      final second = await h.answer(id: 'synthetic-recovery-c');
      final protected = await h.protectedSnapshot();
      h.now = h.now.add(const Duration(days: 2));
      await h.useCases.expireStale();
      final stored = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(stored.instanceId, original.instanceId);
      expect(stored.state, QuestInstanceState.completed);
      expect(stored.completedAtUtc, second.occurredAtUtc);
      expect(stored.progress.single.sourceEventIds, [
        first.eventId,
        second.eventId,
      ]);
      expect(await h.protectedSnapshot(), protected);
      final before = await h.storage.snapshot();
      expect(await reconcile(def), isEmpty);
      expect(await h.storage.snapshot(), before);
      final receipts = await h.database.transaction(
        () => h.repository.readValidatedCompletions(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
      );
      expect(
        receipts.single.instance.definitionSha256,
        original.definitionSha256,
      );
      expect(receipts.single.completion.completedAtUtc, second.occurredAtUtc);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'file restart recovers missing completion without assigning missed days',
    () async {
      final startAt = h.now;
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-quest-recovery-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      var storage = await QuestHarness.open(file: file);
      try {
        storage.now = startAt;
        final def = questDefinition(target: 1, expiry: const Duration(days: 1));
        final original = (await storage.useCases.startQuest(def))!;
        storage.now = storage.now.add(const Duration(seconds: 10));
        final answer = await storage.answer();
        final protected = await storage.protectedSnapshot();
        final restoreAt = storage.now.add(const Duration(days: 10));
        await storage.close();
        storage = await QuestHarness.open(file: file, seed: false);
        storage.now = restoreAt;
        final completed = await storage.useCases.reconcile(
          expectedOwnerId: configuredOwnerId,
          catalog: [def],
          stillCurrent: () => true,
        );
        expect(completed.single.questInstanceId, original.instanceId);
        expect(completed.single.completedAtUtc, answer.occurredAtUtc);
        expect(
          await storage.repository.getAllInstances(configuredOwnerId),
          hasLength(1),
        );
        expect(await storage.protectedSnapshot(), protected);
        final before = await storage.storage.snapshot();
        expect(
          await storage.useCases.reconcile(
            expectedOwnerId: configuredOwnerId,
            catalog: [def],
            stillCurrent: () => true,
          ),
          isEmpty,
        );
        expect(await storage.storage.snapshot(), before);
      } finally {
        await storage.close();
        final resolved = await directory.resolveSymbolicLinks();
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith('$temp${Platform.pathSeparator}lexiquest-quest-recovery-'),
        );
        expect(file.parent.absolute.path, directory.absolute.path);
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'unfinished periods expire after recovery and cannot consume later answers',
    () async {
      final def = questDefinition(target: 2);
      final original = (await h.useCases.startQuest(def))!;
      h.now = h.now.add(const Duration(seconds: 1));
      final inside = await h.answer();
      h.now = original.period!.endUtc!;
      await h.answer(id: 'synthetic-outside-period');
      expect(await reconcile(def), isEmpty);
      final stored = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(stored.state, QuestInstanceState.expired);
      expect(stored.expiredAtUtc, original.period!.endUtc);
      expect(stored.progress.single.sourceEventIds, [inside.eventId]);
      expect(
        await h.repository.readValidatedCompletions(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        isEmpty,
      );
    },
  );

  test(
    'catalog upgrades preserve old targets and use new targets next period',
    () async {
      final firstDef = questDefinition(target: 2);
      final original = (await h.useCases.startQuest(firstDef))!;
      await h.answer();
      final nextDef = questDefinition(version: 2, target: 1);
      await h.repository.upsertDefinition(nextDef);
      expect(await reconcile(nextDef), isEmpty);
      final active = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(active.catalogVersion, 1);
      expect(active.definitionSha256, original.definitionSha256);
      expect(active.progress.single.targetCount, 2);
      h.now = h.now.add(const Duration(seconds: 1));
      final completed = await h.useCases.processEvent(
        await h.answer(id: 'synthetic-old-v1-second'),
        [nextDef],
      );
      expect(completed, hasLength(1));
      h.now = original.period!.endUtc!;
      final next = (await h.useCases.startQuest(nextDef))!;
      expect(next.catalogVersion, 2);
      expect(next.progress.single.targetCount, 1);
      expect(next.definitionSha256, isNot(original.definitionSha256));
    },
  );

  test(
    'timezone changes wait for a non-overlapping future civil period',
    () async {
      var id = 0;
      final elsewhere = QuestUseCases(
        repository: h.repository,
        owners: h.storage.owners,
        generateId: () => 'synthetic-new-zone-${++id}',
        nowUtc: () => h.now,
        timezoneId: 'America/New_York',
      );
      final def = questDefinition();
      final original = (await h.useCases.startQuest(def))!;
      expect(await elsewhere.startQuest(def), isNull);
      h.now = original.period!.endUtc!;
      expect(await elsewhere.startQuest(def), isNull);
      h.now = DateTime.utc(2026, 10, 30, 4);
      final next = (await elsewhere.startQuest(def))!;
      expect(next.period!.timezoneId, 'America/New_York');
      expect(
        next.period!.startUtc!.isBefore(original.period!.endUtc!),
        isFalse,
      );
      expect(
        (await h.repository.getAllInstances(configuredOwnerId)).first.state,
        QuestInstanceState.expired,
      );
    },
  );

  test(
    'retired owner review during timezone resolution creates no assignment',
    () async {
      final waiting = Completer<String>();
      final entered = Completer<void>();
      var current = true;
      final guarded = QuestUseCases(
        repository: h.repository,
        owners: h.storage.owners,
        generateId: () => 'synthetic-retired-quest',
        nowUtc: () => h.now,
        timezoneId: 'UTC',
        resolveTimezoneId: (_) {
          entered.complete();
          return waiting.future;
        },
      );
      final result = guarded.startQuest(
        questDefinition(),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => current,
      );
      await entered.future;
      await h.storage.switchOwner(configuredOtherOwnerId);
      current = false;
      await h.storage.switchOwner(configuredOwnerId);
      final before = await h.storage.snapshot();
      waiting.complete('Asia/Bangkok');
      await expectLater(result, throwsStateError);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'retirement or deletion during recovered progress rolls everything back',
    () async {
      final def = questDefinition(target: 1);
      await h.useCases.startQuest(def);
      await h.answer();
      final before = await h.storage.snapshot();
      var current = true;
      final probe = QuestWriteProbe()
        ..afterProgress = () async {
          current = false;
        };
      await expectLater(
        h.database.runWithInterceptor(
          () => reconcile(def, current: () => current),
          interceptor: probe,
        ),
        throwsA(anything),
      );
      expect(probe.progressWrites, greaterThan(0));
      expect(await h.storage.snapshot(), before);
      final deletion = QuestWriteProbe()
        ..afterProgress = () => h.storage.ownerWrites
            .beginDeletion(
              ownerId: configuredOwnerId,
              firebaseUid: 'synthetic-configured-uid-a',
              idempotencyKey: 'synthetic-recovery-deletion',
            )
            .then((_) {});
      await expectLater(
        h.database.runWithInterceptor(
          () => reconcile(def),
          interceptor: deletion,
        ),
        throwsA(anything),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'grant read rejects changed completion facts without repairing them',
    () async {
      final def = questDefinition(target: 1);
      await h.useCases.startQuest(def);
      await h.useCases.processEvent(await h.answer(), [def]);
      await h.sql(
        'UPDATE quest_instances SET completed_at_utc_ms = completed_at_utc_ms + 1',
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.readValidatedCompletions(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  for (final removedCatalogId in [false, true]) {
    test(
      removedCatalogId
          ? 'unprovable legacy history with a retired catalog ID does not block a current pinned period'
          : 'unprovable legacy history does not block a current pinned period',
      () async {
        final old = removedCatalogId
            ? questDefinition(id: 'synthetic-retired-quest', target: 1)
            : questDefinition(target: 1);
        await h.repository.upsertDefinition(old);
        final legacy = QuestInstance(
          instanceId: 'synthetic-unpinned-legacy',
          questId: old.questId,
          ownerId: configuredOwnerId,
          catalogVersion: 1,
          assignedAtUtc: h.now,
          state: QuestInstanceState.active,
          progress: [
            ObjectiveProgress(
              objectiveId: old.objectives.single.objectiveId,
              currentCount: 0,
              targetCount: 1,
            ),
          ],
        );
        await h.repository.startInstance(legacy);
        Future<Map<String, Object?>> legacyRows() async => {
          'instance':
              (await h.database
                      .customSelect(
                        "SELECT * FROM quest_instances WHERE instance_id='synthetic-unpinned-legacy'",
                      )
                      .getSingle())
                  .data,
          'progress':
              (await h.database
                      .customSelect(
                        "SELECT * FROM quest_objective_progress WHERE instance_id='synthetic-unpinned-legacy' ORDER BY id",
                      )
                      .get())
                  .map((row) => row.data)
                  .toList(),
        };
        final original = await legacyRows();
        final current = questDefinition(version: 2, target: 1);
        final issued = (await h.useCases.startQuest(current))!;
        expect(issued.period, isNotNull);
        expect(issued.catalogVersion, 2);
        final answer = await h.answer();
        final protected = await h.protectedSnapshot();
        final completed = await h.useCases.processEvent(answer, [current]);
        expect(completed.single.questInstanceId, issued.instanceId);
        expect(completed.single.objectiveEventIds, [answer.eventId]);
        expect(await legacyRows(), original);
        expect(await h.protectedSnapshot(), protected);
        final receipts = await h.repository.readValidatedCompletions(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(receipts.single.instance.instanceId, issued.instanceId);
      },
    );
  }

  test('a corrupt pinned definition remains denied without repair', () async {
    final def = questDefinition(target: 1);
    await h.useCases.startQuest(def);
    await h.sql('UPDATE quest_instances SET definition_sha256=?', ['0' * 64]);
    final answer = await h.answer();
    final before = await h.storage.snapshot();
    await expectLater(h.useCases.processEvent(answer, [def]), throwsStateError);
    expect(await h.storage.snapshot(), before);
  });
}
