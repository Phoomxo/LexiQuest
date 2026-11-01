import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/domain/motivation_snapshot.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';

import '../features/quest/support/quest_repository_harness.dart';
import '../support/measurement_opportunity_harness.dart';
import '../support/populated_owner_migration_fixture.dart'
    show ownerMigrationRows;

void main() {
  late QuestHarness h;
  MotivationRuntime? runtime;
  var id = 0;
  setUp(() async {
    h = await QuestHarness.open();
    id = 0;
  });
  tearDown(() async {
    await runtime?.dispose();
    runtime = null;
    await h.close();
  });

  MotivationRuntime compose({
    Stream<String?>? ownerChanges,
    LocalOwnerRepository? owners,
  }) => MotivationRuntime(
    database: h.database,
    ownerWrites: h.storage.ownerWrites,
    owners: owners ?? h.storage.owners,
    ownerChanges: ownerChanges,
    nowUtc: () => h.now,
    generateId: () => 'synthetic-motivation-runtime-${++id}',
  );

  test(
    'construction and guarded load create no motivation or learning facts',
    () async {
      final before = await h.storage.snapshot();
      runtime = compose();
      expect(await h.storage.snapshot(), before);
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(view.ownerId, configuredOwnerId);
      expect(view.lease.isCurrent, isFalse);
      expect(view.history, isEmpty);
      expect(view.motivation.questXp, 0);
      expect(view.motivation.state.freezeCount, 0);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'explicit owner activation seeds two real periods without learning or Research writes',
    () async {
      runtime = compose();
      final before = await h.protectedSnapshot();
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(view.history, hasLength(2));
      expect(view.history.map((row) => row.period!.kind).toSet(), {
        'daily',
        'weekly',
      });
      expect(
        view.history.every(
          (row) =>
              row.ownerId == configuredOwnerId && row.definitionSha256 != null,
        ),
        isTrue,
      );
      expect(
        view.history.every(
          (row) =>
              row.progress.every((objective) => objective.currentCount == 0),
        ),
        isTrue,
      );
      expect(await h.protectedSnapshot(), before);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'a foreign owner coordinator is rejected before either database changes',
    () async {
      final other = await QuestHarness.open();
      try {
        final before = await h.storage.snapshot();
        final otherBefore = await other.storage.snapshot();
        expect(
          () => MotivationRuntime(
            database: h.database,
            ownerWrites: other.storage.ownerWrites,
            owners: h.storage.owners,
            nowUtc: () => h.now,
            generateId: () => 'synthetic-invalid-runtime',
          ),
          throwsArgumentError,
        );
        expect(await h.storage.snapshot(), before);
        expect(await other.storage.snapshot(), otherBefore);
      } finally {
        await other.close();
      }
    },
  );

  test(
    'foreground activation is eager and repeated calls retain one real period',
    () async {
      runtime = compose();
      runtime!.setForeground(true);
      MotivationView? observed;
      for (var attempt = 0; attempt < 100; attempt++) {
        observed = await runtime!.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        if (observed.history.length == 2 && !runtime!.isActivating) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(observed!.history, hasLength(2));
      final before = await h.storage.snapshot();
      await Future.wait(
        List.generate(
          5,
          (_) => runtime!.activate(
            ownerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
        ),
      );
      expect(await h.storage.snapshot(), before);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'the actual clock may carry microseconds while durable boundaries retain milliseconds',
    () async {
      h.now = h.now.add(const Duration(microseconds: 234));
      runtime = compose();
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(
        view.evaluatedAtUtc.millisecondsSinceEpoch,
        h.now.millisecondsSinceEpoch,
      );
      expect(view.evaluatedAtUtc.microsecondsSinceEpoch % 1000, 0);
    },
  );

  test(
    'actual ordinary callbacks complete the shipped daily and weekly catalog once',
    () async {
      runtime = compose();
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      for (var index = 0; index < 20; index++) {
        h.now = h.now.add(const Duration(seconds: 1));
        await h.answer(
          id: 'synthetic-catalog-answer-$index',
          sessionId: 'synthetic-catalog-session-$index',
        );
        if (index < 5) {
          await runtime!.afterLearningAnswer(
            ownerId: configuredOwnerId,
            sessionId: 'synthetic-catalog-session-$index',
            stillCurrent: () => true,
          );
        }
      }
      await runtime!.afterLearningAnswer(
        ownerId: configuredOwnerId,
        sessionId: 'synthetic-catalog-session-19',
        stillCurrent: () => true,
      );
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(
        view.history.every((row) => row.state.name == 'completed'),
        isTrue,
      );
      expect(view.motivation.questXp, 250);
      expect(view.motivation.state.freezeCount, 1);
      expect(await h.storage.count('answer_attempts'), 20);
      final before = await h.storage.snapshot();
      await runtime!.afterLearningAnswer(
        ownerId: configuredOwnerId,
        sessionId: 'synthetic-catalog-session-19',
        stillCurrent: () => true,
      );
      expect(await h.storage.snapshot(), before);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'background retires existing leases and cannot activate or mutate',
    () async {
      runtime = compose();
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(view.lease.isCurrent, isTrue);
      runtime!.setForeground(false);
      final before = await h.storage.snapshot();
      expect(view.lease.isCurrent, isFalse);
      await expectLater(
        runtime!.activate(ownerId: configuredOwnerId, stillCurrent: () => true),
        throwsA(isA<MotivationException>()),
      );
      final read = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(read.lease.isCurrent, isFalse);
      expect(await h.storage.snapshot(), before);
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(view.lease.isCurrent, isFalse);
    },
  );

  for (final closed in [false, true]) {
    test(
      'owner observer ${closed ? 'completion' : 'error'} permanently retires runtime',
      () async {
        final owners = StreamController<String?>.broadcast(sync: true);
        runtime = compose(ownerChanges: owners.stream);
        owners.add(configuredOwnerId);
        runtime!.setForeground(true);
        await runtime!.activate(
          ownerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        final view = await runtime!.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        if (closed) {
          await owners.close();
        } else {
          owners.addError(StateError('synthetic-owner-observer'));
        }
        await Future<void>.delayed(Duration.zero);
        final before = await h.storage.snapshot();
        expect(runtime!.isRetired, isTrue);
        expect(view.lease.isCurrent, isFalse);
        runtime!.setForeground(false);
        runtime!.setForeground(true);
        if (!closed) owners.add(configuredOwnerId);
        await expectLater(
          runtime!.load(
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
          throwsA(isA<MotivationException>()),
        );
        expect(await h.storage.snapshot(), before);
        if (!closed) await owners.close();
      },
    );
  }

  test(
    'queued owner A-B-A retires the old action and activates only the current lease',
    () async {
      final observations = StreamController<String?>.broadcast(sync: true);
      final paused = _PausedOwners(h.storage.owners);
      runtime = compose(ownerChanges: observations.stream, owners: paused);
      observations.add(configuredOwnerId);
      runtime!.setForeground(true);
      await paused.entered.future;
      final old = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      await h.storage.switchOwner(configuredOtherOwnerId);
      observations.add(configuredOtherOwnerId);
      await h.storage.switchOwner(configuredOwnerId);
      observations.add(configuredOwnerId);
      h.now = h.now.add(const Duration(seconds: 1));
      paused.release.complete();
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(old.lease.isCurrent, isFalse);
      final current = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(current.history, hasLength(2));
      expect(
        current.history.every((row) => row.assignedAtUtc == h.now),
        isTrue,
      );
      expect(
        await runtime!.questRepository.getAllInstances(configuredOtherOwnerId),
        isEmpty,
      );
      await runtime!.dispose();
      await observations.close();
    },
  );

  test(
    'a canonical transaction skips optional projection without deadlock or rows',
    () async {
      final owners = StreamController<String?>.broadcast(sync: true);
      await h.learning.startSession(
        LearningSessionDraft(
          id: 'synthetic-ambient-session',
          ownerId: configuredOwnerId,
          activityType: 'quiz',
          startedAtUtc: h.now,
          appVersion: 'synthetic',
          buildId: 'motivation-runtime',
        ),
      );
      runtime = compose(ownerChanges: owners.stream);
      runtime!.setForeground(true);
      final before = await h.storage.snapshot();
      await h.database.transaction(
        () => runtime!.beforeLearningAnswer(
          ownerId: configuredOwnerId,
          sessionId: 'synthetic-ambient-session',
          stillCurrent: () => true,
        ),
      );
      expect(await h.storage.snapshot(), before);
      await runtime!.dispose();
      await owners.close();
    },
  );

  test(
    'actual Study hooks skip seeding and rewards while foreground and scope observer is pending',
    () async {
      await h.close();
      final fixture = await OpportunityFixture.open(longLived: true);
      final owners = StreamController<String?>.broadcast(sync: true);
      try {
        await fixture.ready();
        await fixture.accept();
        runtime = MotivationRuntime(
          database: fixture.database,
          ownerWrites: fixture.participation.ownerWrites,
          owners: DriftLocalOwnerRepository(
            fixture.database,
            generateId: () => 'synthetic-study-owner',
            nowUtc: () => fixture.participation.clock.now,
          ),
          ownerChanges: owners.stream,
          nowUtc: () => fixture.participation.clock.now,
          generateId: () => 'synthetic-study-motivation',
        );
        runtime!.setForeground(true);
        expect(runtime!.isForeground, isTrue);
        final before = await fixture.database
            .customSelect('SELECT COUNT(*) AS n FROM quest_instances')
            .getSingle();
        expect(before.read<int>('n'), 0);
        final facts = await ownerMigrationRows(fixture.database);
        await runtime!.beforeLearningAnswer(
          ownerId: 'owner-a',
          sessionId: 'first-session',
          stillCurrent: () => true,
        );
        await runtime!.afterLearningAnswer(
          ownerId: 'owner-a',
          sessionId: 'first-session',
          stillCurrent: () => true,
        );
        expect(await ownerMigrationRows(fixture.database), facts);
      } finally {
        await runtime?.dispose();
        runtime = null;
        await owners.close();
        await fixture.database.close();
      }
    },
  );

  test(
    'cold restart recovers original completion and grants without creating missed-day periods',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-motivation-runtime-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      h = await QuestHarness.open(file: file);
      h.now = DateTime.utc(2026, 10, 26, 12);
      runtime = compose();
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      for (var index = 0; index < 5; index++) {
        h.now = h.now.add(const Duration(seconds: 1));
        await h.answer(
          id: 'synthetic-lost-callback-$index',
          sessionId: 'synthetic-lost-session-$index',
        );
      }
      final completedAt = h.now;
      final facts = await h.storage.snapshot();
      final restoreAt = h.now.add(const Duration(days: 17));
      await runtime!.dispose();
      await h.close();
      h = await QuestHarness.open(file: file, seed: false);
      h.now = restoreAt;
      runtime = compose();
      runtime!.setForeground(true);
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final view = await runtime!.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(view.history, hasLength(4));
      expect(
        view.history
            .singleWhere((row) => row.state.name == 'completed')
            .completedAtUtc,
        completedAt,
      );
      expect(view.motivation.questXp, 50);
      expect(view.motivation.state.freezeCount, 0);
      final after = await h.storage.snapshot();
      for (final table in facts.keys) {
        if (!{
          'quest_definitions',
          'quest_instances',
          'quest_objective_progress',
          'reward_transactions',
        }.contains(table)) {
          expect(after[table], facts[table], reason: table);
        }
      }
      final stable = await h.storage.snapshot();
      await runtime!.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(await h.storage.snapshot(), stable);
      await runtime!.dispose();
      await h.close();
      final resolved = await directory.resolveSymbolicLinks();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      expect(
        resolved,
        startsWith(
          '$temp${Platform.pathSeparator}lexiquest-motivation-runtime-',
        ),
      );
      expect(file.parent.absolute.path, directory.absolute.path);
      await directory.delete(recursive: true);
    },
  );
}

final class _PausedOwners implements LocalOwnerRepository {
  _PausedOwners(this.delegate);
  final LocalOwnerRepository delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  var paused = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (!paused) {
      paused = true;
      entered.complete();
      await release.future;
    }
    return delegate.getOrCreateActiveOwner();
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      delegate.bindFirebaseUid(ownerId, uid);
}
