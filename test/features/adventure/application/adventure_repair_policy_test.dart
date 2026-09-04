import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

void main() {
  test(
    'incorrect item returns after 3 to 5 intervening items at most once',
    () {
      for (final count in <int>[3, 4, 5, 8]) {
        final queue = _queue(count + 1);
        final original = queue.first.identity;
        final policy = AdventureRepairPolicy(isModeEligible: (_) => true);

        expect(
          policy.schedule(
            queue: queue,
            completedIndex: 0,
            outcome: AdventureAttemptOutcome.incorrect,
          ),
          isTrue,
        );
        final repairIndex = queue.indexWhere(
          (item) => item.isRepair && item.identity == original,
        );
        expect(repairIndex - 1, inInclusiveRange(3, 5));
        expect(
          policy.schedule(
            queue: queue,
            completedIndex: 0,
            outcome: AdventureAttemptOutcome.incorrect,
          ),
          isFalse,
        );
        expect(queue.where((item) => item.isRepair), hasLength(1));
      }
    },
  );

  test('does not pad or repeat immediately when fewer than three remain', () {
    for (final count in <int>[1, 2, 3]) {
      final queue = _queue(count);
      final before = List<AdventureRepairItem>.of(queue);
      final policy = AdventureRepairPolicy(isModeEligible: (_) => true);
      final decision = policy.scheduleDecision(
        queue: queue,
        completedIndex: 0,
        outcome: AdventureAttemptOutcome.incorrect,
      );
      expect(decision, AdventureRepairDisposition.deferredToCanonicalReview);
      expect(queue, before);
    }
  });

  test('non-learning outcomes and guided attempts do not schedule repair', () {
    for (final outcome in <AdventureAttemptOutcome>[
      AdventureAttemptOutcome.correct,
      AdventureAttemptOutcome.skipped,
      AdventureAttemptOutcome.technical,
      AdventureAttemptOutcome.guided,
    ]) {
      final queue = _queue(6);
      expect(
        AdventureRepairPolicy(
          isModeEligible: (_) => true,
        ).schedule(queue: queue, completedIndex: 0, outcome: outcome),
        isFalse,
      );
    }
  });

  test('multiple wrong identities receive independent bounded repairs', () {
    final queue = _queue(10);
    final policy = AdventureRepairPolicy(isModeEligible: (_) => true);
    expect(
      policy.schedule(
        queue: queue,
        completedIndex: 0,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      isTrue,
    );
    expect(
      policy.schedule(
        queue: queue,
        completedIndex: 1,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      isTrue,
    );
    expect(queue.where((item) => item.isRepair), hasLength(2));
    for (final repair in queue.where((item) => item.isRepair)) {
      final originalIndex = queue.indexWhere(
        (item) => !item.isRepair && item.identity == repair.identity,
      );
      final repairIndex = queue.indexOf(repair);
      final originalsBetween = queue
          .sublist(originalIndex + 1, repairIndex)
          .where((item) => !item.isRepair)
          .length;
      expect(originalsBetween, inInclusiveRange(3, 5));
    }
  });

  test('support ladder skips unavailable modes and reaches active recall', () {
    final queue = _queue(6, mode: LessonMode.flashcard);
    final policy = AdventureRepairPolicy(
      isModeEligible: (mode) =>
          mode == LessonMode.cloze || mode == LessonMode.typedRecall,
    );
    expect(
      policy.schedule(
        queue: queue,
        completedIndex: 0,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      isTrue,
    );
    expect(queue.singleWhere((item) => item.isRepair).mode, LessonMode.cloze);
  });

  test('failed repair defers once to canonical Review without recursion', () {
    final queue = _queue(6);
    final policy = AdventureRepairPolicy(isModeEligible: (_) => true);
    expect(
      policy.schedule(
        queue: queue,
        completedIndex: 0,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      isTrue,
    );
    final repairIndex = queue.indexWhere((item) => item.isRepair);

    expect(
      policy.scheduleDecision(
        queue: queue,
        completedIndex: repairIndex,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      AdventureRepairDisposition.deferredToCanonicalReview,
    );
    expect(queue.where((item) => item.isRepair), hasLength(1));
  });
}

List<AdventureRepairItem> _queue(
  int count, {
  LessonMode mode = LessonMode.flashcard,
}) => <AdventureRepairItem>[
  for (var index = 0; index < count; index += 1)
    AdventureRepairItem(
      identity: ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: 'word:$index',
        revision: 1,
      ),
      mode: mode,
    ),
];
