import 'package:flutter_test/flutter_test.dart';
import 'dart:math';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'pair_matching_source_composer_test.dart' as f;
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';

void main() {
  test(
    'distinct spacing ignores duplicate successes; comparator uses all stable keys',
    () {
      final tickets = PairRepairPolicy.project(
        ['w0', 'w1', 'w2', 'w3'],
        const [
          PairRepairAnswer('wrong', 'w0', false),
          PairRepairAnswer('one', 'w1', true),
          PairRepairAnswer('duplicate', 'w1', true),
        ],
      );
      expect(tickets.single.status, PairRepairStatus.waiting);
      PairRepairTicket ticket(String id, int due, int original) =>
          PairRepairTicket(
            wordId: id,
            sourceOperationId: 'synthetic',
            originalOrdinal: original,
            dueOrdinal: due,
            status: PairRepairStatus.waiting,
          );
      final ordered = [
        ticket('z', 3, 2),
        ticket('b', 2, 1),
        ticket('a', 2, 1),
        ticket('x', 2, 0),
      ]..sort(PairRepairPolicy.compare);
      expect(ordered.map((t) => t.wordId), ['x', 'a', 'b', 'z']);
    },
  );
  for (final count in [4, 6]) {
    test(
      'finite repair reserve dominates 100 seeded valid schedules $count',
      () {
        final plan =
            (f.compose(
                      List.generate(count, f.fixture),
                      launch: f.intent(
                        density: count == 4
                            ? PairDensity.compact4
                            : PairDensity.standard6,
                      ),
                    )
                    as PairPlanReady)
                .plan;
        for (var seed = 0; seed < 100; seed++) {
          final random = Random(seed);
          var s = PairMatchingState.initial(plan);
          var answers = 0;
          while (!s.complete) {
            final before = s.remainingRepairAttemptBound;
            final playable =
                plan.orderedLexicalItems
                    .map((i) => i.wordId)
                    .where(
                      (id) =>
                          !s.matchedWordIds.contains(id) &&
                          s.repairFor(id)?.status != PairRepairStatus.waiting &&
                          s.repairFor(id)?.status !=
                              PairRepairStatus.guidedRequired,
                    )
                    .toList()
                  ..shuffle(random);
            if (playable.isNotEmpty) {
              final prompt = playable.first;
              final target = playable.length > 1 && random.nextBool()
                  ? playable[1]
                  : prompt;
              for (final tile in [
                PairTile(PairTileSide.prompt, prompt),
                PairTile(PairTileSide.target, target),
              ]) {
                s = PairMatchingEngine.reduce(
                  s,
                  PairSelectTile(
                    operationId: '${s.operationRevision}:sample',
                    ownerId: plan.ownerId,
                    sessionId: plan.learningSessionId,
                    roundOrdinal: 0,
                    expectedRevision: s.operationRevision,
                    tile: tile,
                    responseTimeMs: 1,
                  ),
                ).state;
              }
            } else {
              final ticket = s.repairTickets.firstWhere(
                (t) => t.status == PairRepairStatus.guidedRequired,
              );
              s = PairMatchingEngine.reduce(
                s,
                PairConfirmGuidedMapping(
                  operationId: '${s.operationRevision}:confirm',
                  ownerId: plan.ownerId,
                  sessionId: plan.learningSessionId,
                  roundOrdinal: 0,
                  expectedRevision: s.operationRevision,
                  wordId: ticket.wordId,
                  shownSupportRevision: s.supportAtRevision[ticket.wordId]!,
                  responseTimeMs: 1,
                ),
              ).state;
            }
            s = PairMatchingEngine.acknowledge(s, s.pending!.operationId);
            expect(
              before,
              greaterThanOrEqualTo(s.remainingRepairAttemptBound + 1),
              reason: 'seed=$seed answers=$answers',
            );
            s = PairMatchingState.fromJson(plan, s.toJson());
            expect(++answers, lessThanOrEqualTo(count * 3 - count ~/ 2));
          }
          expect(s.attempts.where((a) => a.isCorrect), hasLength(count));
          expect(
            s.repairTickets.map((t) => t.wordId).toSet().length,
            s.repairTickets.length,
          );
        }
      },
    );
  }
  test(
    'engine fences waiting repair and binds separate guided confirmation',
    () {
      final plan =
          (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
      var s = PairMatchingState.initial(plan);
      void tap(String id, PairTileSide side) {
        s = PairMatchingEngine.reduce(
          s,
          PairSelectTile(
            operationId: '${s.operationRevision}:tap',
            ownerId: plan.ownerId,
            sessionId: plan.learningSessionId,
            roundOrdinal: 0,
            expectedRevision: s.operationRevision,
            tile: PairTile(side, id),
            responseTimeMs: 1,
          ),
        ).state;
        if (s.pending != null) {
          s = PairMatchingEngine.acknowledge(s, s.pending!.operationId);
        }
      }

      tap('synthetic-0', PairTileSide.prompt);
      tap('synthetic-1', PairTileSide.target);
      expect(() => tap('synthetic-0', PairTileSide.target), throwsStateError);
      for (final i in [1, 2]) {
        tap('synthetic-$i', PairTileSide.prompt);
        tap('synthetic-$i', PairTileSide.target);
      }
      tap('synthetic-0', PairTileSide.prompt);
      tap('synthetic-3', PairTileSide.target);
      expect(s.matchedWordIds, {'synthetic-1', 'synthetic-2'});
      expect(s.repairTickets.single.status, PairRepairStatus.guidedRequired);
      final confirmation = PairConfirmGuidedMapping(
        operationId: '${s.operationRevision}:confirm',
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: 0,
        expectedRevision: s.operationRevision,
        wordId: 'synthetic-0',
        shownSupportRevision: s.supportAtRevision['synthetic-0']!,
        responseTimeMs: 1,
      );
      final t = PairMatchingEngine.reduce(s, confirmation);
      expect(t.attempt!.role, PairAttemptRole.guidedCompletion);
      expect(t.attempt!.isCorrect, true);
      s = PairMatchingEngine.acknowledge(t.state, confirmation.operationId);
      expect(
        identical(PairMatchingEngine.reduce(s, confirmation).state, s),
        true,
      );
      expect(s.matchedWordIds, contains('synthetic-0'));
      expect(s.attempts.where((a) => !a.isCorrect), hasLength(2));
      expect(
        PairMatchingState.fromJson(plan, s.toJson()).attempts,
        hasLength(5),
      );
    },
  );
  for (final count in [4, 6]) {
    test('PMT-017/018 exact distinct interval $count', () {
      final ids = List.generate(count, (i) => 'w$i');
      final answers = <PairRepairAnswer>[
        const PairRepairAnswer('op0', 'w0', false),
      ];
      List<PairRepairTicket> tickets() =>
          PairRepairPolicy.project(ids, answers);
      expect(tickets().single.status, PairRepairStatus.waiting);
      for (var i = 1; i <= count ~/ 2; i++) {
        answers.add(PairRepairAnswer('op$i', 'w$i', true));
        expect(
          tickets().single.status,
          i == count ~/ 2
              ? PairRepairStatus.available
              : PairRepairStatus.waiting,
        );
      }
      answers.add(const PairRepairAnswer('retry', 'w0', false));
      expect(tickets(), hasLength(1));
      expect(tickets().single.status, PairRepairStatus.guidedRequired);
    });
  }
  test('PMT-019 stable order and PMT-020 finite blocked tail', () {
    final answers = List.generate(
      4,
      (i) => PairRepairAnswer('op$i', 'w$i', false),
    );
    final tickets = PairRepairPolicy.project(['w0', 'w1', 'w2', 'w3'], answers);
    expect(tickets.map((t) => t.wordId), ['w0', 'w1', 'w2', 'w3']);
    expect(
      tickets.where((t) => t.status == PairRepairStatus.guidedRequired),
      isNotEmpty,
    );
    answers.add(const PairRepairAnswer('confirm', 'w0', true));
    expect(
      PairRepairPolicy.project(['w0', 'w1', 'w2', 'w3'], answers).first.status,
      PairRepairStatus.completed,
    );
  });
}
