import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/services/interleaved_srs_scheduler.dart';

void main() {
  test('interleave returns empty list when given empty input', () {
    expect(InterleavedSrsScheduler.interleave([]), isEmpty);
  });

  test('interleave returns single item when given list of 1', () {
    final item = SrsItem.initial('apple');
    expect(InterleavedSrsScheduler.interleave([item]), equals([item]));
  });

  test('interleave mixes items from different box levels', () {
    final now = DateTime.now();
    final items = <SrsItem>[
      SrsItem(
        word: 'apple',
        boxLevel: 1,
        intervalDays: 1,
        lastReviewedAt: now,
        nextReviewAt: now,
      ),
      SrsItem(
        word: 'banana',
        boxLevel: 1,
        intervalDays: 1,
        lastReviewedAt: now,
        nextReviewAt: now,
      ),
      SrsItem(
        word: 'cat',
        boxLevel: 2,
        intervalDays: 2,
        lastReviewedAt: now,
        nextReviewAt: now,
      ),
    ];

    final result = InterleavedSrsScheduler.interleave(items);
    expect(result.length, 3);
    expect(result[0].boxLevel != result[1].boxLevel, isTrue);
  });
}
