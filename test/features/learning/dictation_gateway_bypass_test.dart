import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/dictation_session_harness.dart';

void main() {
  late DictationSessionHarness h;
  setUp(() async => h = await DictationSessionHarness.open());
  tearDown(() => h.close());

  DriftLearningRepository restartedRepository() =>
      DriftLearningRepository(h.database, ownerWrites: h.storage.ownerWrites);

  for (final gateway in ['restarted repository', 'learning use cases']) {
    for (final mutation in ['revision', 'spelling']) {
      test(
        'generic $gateway cannot save newly introduced native session after $mutation changed',
        () async {
          final session = await h.ready();
          final pending = h.answer(session);
          await h.database.customStatement(
            mutation == 'revision'
                ? 'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?'
                : "UPDATE vocabulary_words SET spelling = 'changed-with-same-revision' WHERE id = ?",
            [session.word.id],
          );
          Object? rejected;
          try {
            if (gateway == 'restarted repository') {
              await restartedRepository().recordAnswer(pending);
            } else {
              await h.learning.recordAnswer(
                sessionId: pending.sessionId,
                wordId: pending.wordId,
                promptMode: pending.promptMode,
                isCorrect: pending.isCorrect,
                responseTimeMs: pending.responseTimeMs,
                attemptNumber: pending.attemptNumber,
                attemptId: pending.id,
                occurredAtUtc: pending.occurredAtUtc,
                evidenceContext: pending.evidenceContext,
              );
            }
          } catch (error) {
            rejected = error;
          }
          expect(
            await h.database.select(h.database.answerAttempts).get(),
            isEmpty,
            reason:
                'generic gateway cannot replace the native target/revision capability',
          );
          expect(rejected, isA<StateError>());
          expect(await h.database.select(h.database.srsStates).get(), isEmpty);
          expect(
            await h.database.select(h.database.pointsLedgerEntries).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.achievementUnlocks).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.rewardTransactions).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.outboxOperations).get(),
            isEmpty,
          );
          final stored = await h.database
              .select(h.database.learningSessions)
              .getSingle();
          expect(stored.state, 'active');
          expect(stored.endedAtUtcMs, isNull);
        },
      );
    }

    for (final saved in [false, true]) {
      test(
        'generic $gateway cannot complete native session ${saved ? 'with saved answer but without original close intent' : 'without its original saved answer'}',
        () async {
          final session = await h.ready();
          final answer = h.answer(session);
          if (saved) {
            await h.learning.commitNativeAnswer(
              session,
              answer,
              stillCurrent: () => true,
            );
          }
          final originalClose = h.learning.prepareNativeFinish(session, answer);
          h.now = h.now.add(const Duration(minutes: 5));
          Object? rejected;
          try {
            if (gateway == 'restarted repository') {
              await restartedRepository().finishSession(
                ownerId: session.ownerId,
                sessionId: session.id,
                endedAtUtc: h.now,
              );
            } else {
              await h.learning.finishSession(session.id);
            }
          } catch (error) {
            rejected = error;
          }
          final stored = await h.database
              .select(h.database.learningSessions)
              .getSingle();
          expect(
            stored.state,
            'active',
            reason: 'generic completion has no original native close intent',
          );
          expect(stored.endedAtUtcMs, isNull);
          expect(rejected, isA<StateError>());
          expect(
            await h.database.select(h.database.answerAttempts).get(),
            hasLength(saved ? 1 : 0),
          );
          expect(
            await h.database.select(h.database.achievementUnlocks).get(),
            isEmpty,
          );
          if (saved) {
            final summary = await h.learning.finishNativeExercise(
              originalClose,
              stillCurrent: () => true,
            );
            expect(summary.correctCount, 1);
            final completed = await h.database
                .select(h.database.learningSessions)
                .getSingle();
            expect(
              completed.endedAtUtcMs,
              originalClose.endedAtUtc.millisecondsSinceEpoch,
            );
          }
        },
      );
    }
  }

  for (final activity in ['dictation', 'quiz']) {
    test(
      'legacy inferred $activity retains generic start answer and completion',
      () async {
        final word = (await h.repository.listQuizWords(
          ownerId: configuredOwnerId,
          limit: 1,
        )).single;
        final repository = restartedRepository();
        final session = LearningSessionDraft(
          id: 'legacy-$activity-session',
          ownerId: configuredOwnerId,
          activityType: activity,
          startedAtUtc: h.now,
          appVersion: 'synthetic-legacy',
          buildId: 'legacy-control',
        );
        await repository.startSession(session);
        final command = RecordAnswerCommand(
          id: 'legacy-$activity-answer',
          ownerId: configuredOwnerId,
          sessionId: session.id,
          wordId: word.id,
          promptMode: activity == 'dictation' ? 'dictation' : 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: 1,
          occurredAtUtc: h.now,
        );
        final result = await repository.recordAnswer(command);
        expect(result.inserted, isTrue);
        expect(result.srs, isNotNull);
        final summary = await repository.finishSession(
          ownerId: configuredOwnerId,
          sessionId: session.id,
          endedAtUtc: h.now,
        );
        expect(summary.state, 'completed');
        expect(summary.correctCount, 1);
        expect(summary.score, 100);
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.srsStates).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.pointsLedgerEntries).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.rewardTransactions).get(),
          hasLength(1),
        );
        final awards = await h.database
            .select(h.database.achievementUnlocks)
            .get();
        expect(
          awards.map((award) => award.achievementId),
          unorderedEquals([
            'first_answer',
            'first_correct',
            'first_session',
            'perfect_session',
          ]),
        );
      },
    );
  }
}
