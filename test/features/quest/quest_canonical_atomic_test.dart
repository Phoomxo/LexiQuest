import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import 'support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  setUp(() async => h = await QuestHarness.open());
  tearDown(() => h.close());

  test(
    'same canonical answer and a new repository count once after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-quest-',
      );
      var fileHarness = await QuestHarness.open(
        file: File('${directory.path}/quest.sqlite'),
      );
      try {
        final definition = questDefinition(target: 2);
        await fileHarness.useCases.startQuest(definition);
        final answer = await fileHarness.answer();
        await fileHarness.apply(answer, definition);
        final before = await fileHarness.storage.snapshot();
        final now = fileHarness.now;
        await fileHarness.close();
        fileHarness = await QuestHarness.open(
          file: File('${directory.path}/quest.sqlite'),
          seed: false,
        );
        fileHarness.now = now;
        expect(await fileHarness.apply(answer, definition), isEmpty);
        expect(await fileHarness.storage.snapshot(), before);
        final second = await fileHarness.answer(id: 'synthetic-answer-2');
        expect(await fileHarness.apply(second, definition), hasLength(1));
        final completed = await fileHarness.repository.getAllInstances(
          configuredOwnerId,
        );
        expect(completed.single.progress.single.sourceEventIds, [
          answer.eventId,
          second.eventId,
        ]);
        final time = completed.single.completedAtUtc;
        fileHarness.now = fileHarness.now.add(const Duration(days: 2));
        expect(await fileHarness.apply(second, definition), isEmpty);
        expect(
          (await fileHarness.repository.getAllInstances(
            configuredOwnerId,
          )).single.completedAtUtc,
          time,
        );
      } finally {
        await fileHarness.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'concurrent duplicate and distinct callbacks do not lose or double count',
    () async {
      final definition = questDefinition(target: 3);
      await h.useCases.startQuest(definition);
      final a = await h.answer();
      final b = await h.answer(id: 'synthetic-answer-2');
      final c = await h.answer(id: 'synthetic-answer-3');
      final before = await h.protectedSnapshot();
      final results = await Future.wait([
        h.apply(a, definition),
        h.apply(a, definition),
        h.apply(b, definition),
        h.apply(c, definition),
      ]);
      expect(results.expand((events) => events), hasLength(1));
      final instance = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(instance.progress.single.currentCount, 3);
      expect(instance.progress.single.sourceEventIds.toSet(), {
        a.eventId,
        b.eventId,
        c.eventId,
      });
      expect(await h.protectedSnapshot(), before);
    },
  );

  test(
    'canonical comparison uses actual persisted millisecond precision',
    () async {
      h.now = h.now.add(const Duration(microseconds: 234));
      final definition = questDefinition(target: 1);
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final completed = await h.apply(answer, definition);
      expect(completed, hasLength(1));
      final stored = (await h.repository.getAllInstances(
        configuredOwnerId,
      )).single;
      expect(completed.single.completedAtUtc, stored.completedAtUtc);
      final beforeReplay = await h.storage.snapshot();
      expect(await h.apply(answer, definition), isEmpty);
      expect(await h.storage.snapshot(), beforeReplay);
    },
  );

  test('one answer may satisfy each of two distinct objectives once', () async {
    final definition = questDefinition(
      objectives: [
        for (final id in ['first', 'second'])
          QuestObjective(
            objectiveId: id,
            description: id,
            targetCount: 2,
            criteria: ObjectiveCriteria(
              eventType: 'QuizCompleted',
              filters: {'correct': true},
            ),
          ),
      ],
    );
    await h.useCases.startQuest(definition);
    final answer = await h.answer();
    await h.apply(answer, definition);
    await h.apply(answer, definition);
    final progress = (await h.repository.getActiveInstances(
      configuredOwnerId,
    )).single.progress;
    expect(progress.map((value) => value.currentCount), [1, 1]);
    expect(progress.map((value) => value.sourceEventIds), [
      [answer.eventId],
      [answer.eventId],
    ]);
  });

  test(
    'duplicate catalog or objective identities are rejected without writes',
    () async {
      final definition = questDefinition();
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.upsertDefinition(
          questDefinition(
            objectives: [
              definition.objectives.single,
              definition.objectives.single,
            ],
          ),
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final after = await h.storage.snapshot();
      await expectLater(
        h.repository.applyCanonicalAnswer(
          ownerId: configuredOwnerId,
          event: answer,
          catalog: [definition, definition],
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), after);
    },
  );

  test(
    'failure after progress before completion rolls back every Quest write',
    () async {
      final definition = questDefinition(target: 1);
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final before = await h.storage.snapshot();
      final probe = QuestWriteProbe()..failCompletion = true;
      await expectLater(
        h.database.runWithInterceptor(
          () => h.apply(answer, definition),
          interceptor: probe,
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
      expect(probe.progressWrites, 1);
      expect(probe.completionAttempted, isTrue);
      expect(await h.apply(answer, definition), hasLength(1));
    },
  );

  test(
    'a completed learning session remains valid historical answer evidence',
    () async {
      final definition = questDefinition(target: 1);
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      await h.learning.finishSession(
        ownerId: configuredOwnerId,
        sessionId: answer.aggregateId,
        endedAtUtc: h.now,
      );
      expect(await h.apply(answer, definition), hasLength(1));
    },
  );

  test(
    'absent attempt and forged envelope fields never create progress',
    () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final before = await h.storage.snapshot();
      for (final changes in <Map<String, Object?>>[
        {'eventId': 'missing'},
        {'eventType': 'SrsReviewCompleted'},
        {'eventVersion': 2},
        {'actorIdentity': configuredOtherOwnerId},
        {'ownerIdentity': configuredOtherOwnerId},
        {'aggregateId': 'foreign-session'},
        {'aggregateType': 'QuestInstance'},
        {'idempotencyKey': 'random-retry-id'},
        {
          'occurredAtUtc': h.now
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        },
        {
          'payload': {...answer.payload, 'score': 0},
        },
        {
          'payload': {...answer.payload, 'claimedBonus': true},
        },
      ]) {
        await expectLater(
          h.apply(changedEvent(answer, changes), definition),
          throwsStateError,
          reason: '$changes',
        );
        expect(await h.storage.snapshot(), before);
      }
    },
  );

  test('unknown owner and an active deletion fence deny collection', () async {
    final definition = questDefinition();
    await h.useCases.startQuest(definition);
    final answer = await h.answer();
    await h.storage.switchOwner(configuredOtherOwnerId);
    await expectLater(h.apply(answer, definition), throwsA(isA<Exception>()));
    await h.storage.switchOwner(configuredOwnerId);
    await h.storage.ownerWrites.beginDeletion(
      ownerId: configuredOwnerId,
      firebaseUid: 'synthetic-configured-uid-a',
      idempotencyKey: 'synthetic-delete',
    );
    final before = await h.storage.snapshot();
    await expectLater(h.apply(answer, definition), throwsA(isA<Exception>()));
    expect(await h.storage.snapshot(), before);
  });

  test('ambient transaction is rejected before any Quest mutation', () async {
    final definition = questDefinition();
    await h.useCases.startQuest(definition);
    final answer = await h.answer();
    final before = await h.storage.snapshot();
    await h.database.transaction(() async {
      await expectLater(h.apply(answer, definition), throwsStateError);
    });
    expect(await h.storage.snapshot(), before);
  });

  test(
    'coordinator from another actual database is rejected at construction',
    () async {
      final other = await QuestHarness.open();
      try {
        expect(
          () => DriftQuestRepository(
            h.database,
            ownerWrites: other.storage.ownerWrites,
            nowUtc: () => h.now,
          ),
          throwsArgumentError,
        );
      } finally {
        await other.close();
      }
    },
  );

  test(
    'assignment and deadline are inclusive but future evidence is denied',
    () async {
      final definition = questDefinition(
        target: 3,
        expiry: const Duration(seconds: 1),
      );
      await h.useCases.startQuest(definition);
      final first = await h.answer();
      await h.apply(first, definition);
      h.now = h.now.add(const Duration(seconds: 1));
      final last = await h.answer(id: 'synthetic-answer-last');
      await h.apply(last, definition);
      expect(
        (await h.repository.getActiveInstances(
          configuredOwnerId,
        )).single.progress.single.currentCount,
        2,
      );
      final before = await h.storage.snapshot();
      h.now = h.now.add(const Duration(milliseconds: 1));
      await expectLater(h.apply(last, definition), throwsStateError);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'answer before assignment and future canonical answer are denied',
    () async {
      final old = await h.answer();
      h.now = h.now.add(const Duration(seconds: 1));
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      await expectLater(h.apply(old, definition), throwsStateError);
      final future = await h.answer(
        id: 'synthetic-future',
        at: h.now.add(const Duration(seconds: 1)),
      );
      await expectLater(h.apply(future, definition), throwsStateError);
    },
  );

  test(
    'final clock crossing expiry rolls back the progress already written',
    () async {
      final definition = questDefinition(expiry: const Duration(seconds: 1));
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final before = await h.storage.snapshot();
      final probe = QuestWriteProbe()
        ..afterProgress = () async {
          h.now = h.now.add(const Duration(seconds: 2));
        };
      await expectLater(
        h.database.runWithInterceptor(
          () => h.apply(answer, definition),
          interceptor: probe,
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
      expect(probe.progressWrites, greaterThan(0));
    },
  );

  for (final mutation in ['owner', 'fence', 'attempt', 'catalog']) {
    test(
      'final $mutation mutation during actual progress write rolls back',
      () async {
        final definition = questDefinition();
        await h.useCases.startQuest(definition);
        final answer = await h.answer();
        final before = await h.storage.snapshot();
        final probe = QuestWriteProbe()
          ..afterProgress = () async {
            switch (mutation) {
              case 'owner':
                await h.storage.switchOwner(configuredOtherOwnerId);
              case 'fence':
                await h.storage.ownerWrites.beginDeletion(
                  ownerId: configuredOwnerId,
                  firebaseUid: 'synthetic-configured-uid-a',
                  idempotencyKey: 'synthetic-delete',
                );
              case 'attempt':
                await h.sql(
                  'UPDATE answer_attempts SET is_correct = 0 WHERE id = ?',
                  [answer.eventId],
                );
              case 'catalog':
                await h.sql(
                  'UPDATE quest_definitions SET expires_in_ms = 1 WHERE quest_id = ?',
                  [definition.questId],
                );
            }
          };
        await expectLater(
          h.database.runWithInterceptor(
            () => h.apply(answer, definition),
            interceptor: probe,
          ),
          throwsA(anything),
        );
        expect(await h.storage.snapshot(), before);
        expect(probe.progressWrites, greaterThan(0));
      },
    );
  }

  test(
    'same-version content is immutable and catalog revisions cannot downgrade',
    () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      final before = await h.storage.snapshot();
      await h.repository.upsertDefinition(definition);
      expect(await h.storage.snapshot(), before);
      for (final changed in [
        questDefinition(target: 1),
        questDefinition(expiry: const Duration(hours: 1)),
      ]) {
        await expectLater(h.useCases.startQuest(changed), throwsStateError);
        expect(await h.storage.snapshot(), before);
      }
      await h.repository.upsertDefinition(questDefinition(version: 2));
      await expectLater(
        h.repository.upsertDefinition(definition),
        throwsStateError,
      );
      await expectLater(
        h.apply(await h.answer(), questDefinition(version: 2)),
        throwsStateError,
      );
    },
  );

  for (final corruption in [
    "source_event_ids_json = 'not-json'",
    "source_event_ids_json = '[\"evt_v2_legacy_1\"]', current_count = 1",
    "source_event_ids_json = '[\"synthetic-answer-1\",\"synthetic-answer-1\"]', current_count = 2",
    'current_count = 2',
    'target_count = 0',
  ]) {
    test(
      'malformed stored progress fails closed without repair: $corruption',
      () async {
        final definition = questDefinition();
        await h.useCases.startQuest(definition);
        final first = await h.answer();
        await h.apply(first, definition);
        await h.sql('UPDATE quest_objective_progress SET $corruption');
        final second = await h.answer(id: 'synthetic-answer-2');
        final before = await h.storage.snapshot();
        await expectLater(h.apply(second, definition), throwsA(anything));
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'missing objective rows are rejected without inserting replacements',
    () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      await h.sql('DELETE FROM quest_objective_progress');
      final answer = await h.answer();
      final before = await h.storage.snapshot();
      await expectLater(h.apply(answer, definition), throwsStateError);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'Assessment session and malformed ordinary metadata gain no progress',
    () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      await h.sql("UPDATE learning_sessions SET activity_type = 'assessment'");
      await expectLater(h.apply(answer, definition), throwsStateError);
      await h.sql("UPDATE learning_sessions SET activity_type = 'quiz'");
      await h.sql("UPDATE answer_attempts SET evidence_context_json = '{}'");
      final before = await h.storage.snapshot();
      await expectLater(h.apply(answer, definition), throwsStateError);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'stale expiry and abandonment cannot overwrite a completed instance',
    () async {
      final definition = questDefinition(target: 1);
      final instance = (await h.useCases.startQuest(definition))!;
      await h.apply(await h.answer(), definition);
      final before = await h.storage.snapshot();
      await h.repository.markExpired(
        instance.instanceId,
        h.now.add(const Duration(days: 1)),
      );
      await h.repository.markAbandoned(instance.instanceId);
      expect(await h.storage.snapshot(), before);
    },
  );

  for (final mode in ['dictation', 'clozeTyped', 'clozeChoice']) {
    test('declared assisted native $mode remains ineligible for Quest', () async {
      final definition = questDefinition();
      await h.useCases.startQuest(definition);
      final answer = await h.answer();
      final context = EvidenceContext.forNewEvidence(
        evidenceClass: mode == 'clozeChoice'
            ? EvidenceClass.recognition
            : EvidenceClass.guidedPractice,
        skillId: mode == 'dictation' ? 'listening-recall' : 'cloze-context',
        hintLevel: mode == 'clozeChoice' ? 0 : 1,
        contentRevision: 'synthetic-native-content',
        rolloutMode: EvidencePolicyRolloutMode.legacy,
        engagementAllowed: false,
      );
      await h.sql(
        'UPDATE answer_attempts SET prompt_mode = ?, evidence_class = ?, evidence_context_json = ?',
        [mode, context.evidenceClass.name, jsonEncode(context.toJson())],
      );
      final before = await h.storage.snapshot();
      final event = changedEvent(answer, {
        'payload': {...answer.payload, 'promptMode': mode},
      });
      await expectLater(h.apply(event, definition), throwsStateError);
      expect(await h.storage.snapshot(), before);
    });
  }
}
