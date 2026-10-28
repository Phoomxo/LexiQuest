import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/review/application/pair_review_deferral.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;

void main() {
  for (final direction in PairDirection.values) {
    for (final boundary in ['pending', 'answer', 'clear']) {
      for (final after in [false, true]) {
        test(
          'PMT-021/023 guided exact $direction $boundary after=$after preserves Review/SRS',
          () async {
            final h = PairHarness(direction: direction);
            addTearDown(h.db.close);
            await h.initialize();
            await h.db
                .into(h.db.srsStates)
                .insert(
                  SrsStatesCompanion.insert(
                    id: 'synthetic-due',
                    ownerId: h.owner,
                    wordId: 'synthetic-0',
                    dueAtUtcMs: 1,
                    algorithmVersion: 1,
                  ),
                );
            final due = (await h.db.select(h.db.srsStates).get()).single;
            var c = await h.restore();
            await h.tap(c, 'synthetic-0', PairTileSide.target);
            await h.tap(c, 'synthetic-1', PairTileSide.prompt);
            // Prompt identity is synthetic-1 even when the target was tapped first.
            await c.dispatch(
              PairRevealMapping(
                operationId: '${c.state.operationRevision}:reveal',
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
                roundOrdinal: 0,
                expectedRevision: c.state.operationRevision,
                wordId: 'synthetic-1',
              ),
            );
            for (final i in [0, 2]) {
              await h.tap(c, 'synthetic-$i', PairTileSide.target);
              await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
            }
            await h.tap(c, 'synthetic-3', PairTileSide.target);
            await h.tap(c, 'synthetic-1', PairTileSide.prompt);
            final wrong = (await h.db.select(h.db.answerAttempts).get())
                .where((a) => !a.isCorrect)
                .toList();
            expect(wrong.map((a) => a.wordId), ['synthetic-1', 'synthetic-1']);
            expect(wrong.map((a) => a.evidenceClass), [
              'recognition',
              'guidedPractice',
            ]);
            expect(c.state.attempts.last.role, PairAttemptRole.delayedRepair);
            final adapter = PairReviewDeferral(h.db);
            final eventCount = (await h.db.select(h.db.eventsV2).get()).length;
            final needs = await c.deferredReview(adapter);
            expect(needs, hasLength(1));
            expect(
              needs.single.provenance.map((p) => p.sourceId),
              containsAll(wrong.map((a) => a.id)),
            );
            expect((await h.db.select(h.db.eventsV2).get()).length, eventCount);
            final beforeIds = h.nextId;
            h.repository.afterWrite = after;
            if (boundary == 'answer') {
              h.repository.answerFault = true;
            } else {
              h.repository.checkpointFault =
                  c.checkpointRevision + (boundary == 'pending' ? 1 : 2);
            }
            await expectLater(h.confirm(c, 'synthetic-1'), throwsStateError);
            if (boundary != 'pending' || after) {
              c.dispose();
              c = await h.restore();
            }
            await c.retryPending();
            expect(h.nextId, beforeIds + 1);
            expect(c.state.matchedWordIds, contains('synthetic-1'));
            expect(c.state.repairTickets, hasLength(1));
            expect(await c.deferredReview(adapter), hasLength(1));
            expect(
              (await h.db.select(h.db.answerAttempts).get()).where(
                (a) => a.wordId == 'synthetic-1',
              ),
              hasLength(3),
            );
            expect((await h.db.select(h.db.srsStates).get()).single, due);
            for (final checkpoint in h.repository.checkpoints) {
              expect(
                utf8.encode(jsonEncode(checkpoint.state)).length,
                lessThanOrEqualTo(65536),
              );
              final frozen = checkpoint.state['frozenEvidence'];
              if (frozen != null) {
                expect(
                  jsonEncode(frozen),
                  isNot(
                    contains(
                      h.operation.plan.orderedLexicalItems.first.spelling,
                    ),
                  ),
                );
              }
            }
            expect(
              await adapter.expose(
                ownerId: h.owner,
                sessionId: 'other',
                wordId: 'synthetic-1',
                contentRevision: 1,
                answerId: wrong.first.id,
              ),
              isNull,
            );
            expect(
              await adapter.expose(
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
                wordId: 'synthetic-1',
                contentRevision: 2,
                answerId: wrong.first.id,
              ),
              isNull,
            );
            expect(
              await adapter.expose(
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
                wordId: 'synthetic-0',
                contentRevision: 1,
                answerId: wrong.first.id,
              ),
              isNull,
            );
            await (h.db.delete(h.db.eventsV2)..where(
                  (e) => e.eventId.equals('learning-event:${wrong.first.id}'),
                ))
                .go();
            expect(
              await adapter.expose(
                ownerId: h.owner,
                sessionId: h.operation.plan.learningSessionId,
                wordId: 'synthetic-1',
                contentRevision: 1,
                answerId: wrong.first.id,
              ),
              isNull,
            );
          },
        );
      }
    }
  }
  test(
    'PMT-020 real guided tail exposes same canonical Review need without writes',
    () async {
      final h = PairHarness();
      await h.initialize();
      addTearDown(h.db.close);
      var c = await h.restore();
      for (final i in [0, 1]) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await h.tap(c, 'synthetic-2', PairTileSide.prompt);
      await h.tap(c, 'synthetic-3', PairTileSide.target);
      expect(c.state.matchedWordIds, hasLength(2));
      final adapter = PairReviewDeferral(h.db);
      final before = await h.db.select(h.db.answerAttempts).get();
      final first = await c.deferredReview(adapter);
      expect(first, hasLength(1));
      expect(first.single.identity.id, 'synthetic-2');
      expect(
        first.single.provenance.map((p) => p.sourceId),
        contains(before.last.id),
      );
      c = await h.restore();
      expect(await c.deferredReview(adapter), hasLength(1));
      await c.dispatch(
        PairConfirmGuidedMapping(
          operationId: '${c.state.operationRevision}:confirm',
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: c.state.operationRevision,
          wordId: 'synthetic-2',
          shownSupportRevision: c.state.supportAtRevision['synthetic-2']!,
          responseTimeMs: 1,
        ),
      );
      final answers = await h.db.select(h.db.answerAttempts).get();
      expect(answers, hasLength(before.length + 1));
      expect(answers.last.evidenceClass, 'guidedPractice');
      expect(await c.deferredReview(adapter), hasLength(1));
      expect(await h.db.select(h.db.srsStates).get(), isEmpty);
      expect(
        await adapter.expose(
          ownerId: 'other',
          sessionId: h.operation.plan.learningSessionId,
          wordId: 'synthetic-2',
          contentRevision: 1,
          answerId: before.last.id,
        ),
        isNull,
      );
    },
  );
}
