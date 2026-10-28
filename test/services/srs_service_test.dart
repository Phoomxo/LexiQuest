import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/models/srs_item.dart';
import 'package:vocab_learning_app/services/srs_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SrsItem initial state starts at Box 1', () {
    final now = DateTime.utc(2026, 7, 24, 10, 0, 0);
    final item = SrsItem.initial('apple', now: now);

    expect(item.word, 'apple');
    expect(item.boxLevel, 1);
    expect(item.intervalDays, 1);
    expect(item.isDue(now: now), true);
  });

  test('Correct review advances box level and calculates new interval', () {
    final now = DateTime.utc(2026, 7, 24, 10, 0, 0);
    final item = SrsItem.initial('apple', now: now);
    final reviewed = item.processReview(isCorrect: true, now: now);

    expect(reviewed.boxLevel, 2);
    expect(reviewed.intervalDays, 2);
    expect(reviewed.nextReviewAt, now.add(const Duration(days: 2)));
    expect(reviewed.isDue(now: now), false);
    expect(reviewed.isDue(now: now.add(const Duration(days: 2))), true);
  });

  test('Incorrect review resets box level to 1', () {
    final now = DateTime.utc(2026, 7, 24, 10, 0, 0);
    final item = SrsItem(
      word: 'apple',
      boxLevel: 4,
      intervalDays: 10,
      lastReviewedAt: now,
      nextReviewAt: now.add(const Duration(days: 10)),
    );

    final reset = item.processReview(isCorrect: false, now: now);

    expect(reset.boxLevel, 1);
    expect(reset.intervalDays, 1);
    expect(reset.nextReviewAt, now.add(const Duration(days: 1)));
  });

  test('SrsService persists items and filters due items', () async {
    final service = SrsService();
    final now = DateTime.utc(2026, 7, 24, 10, 0, 0);

    await service.recordReview('cat', true, now: now);
    await service.recordReview('dog', false, now: now);

    // Tomorrow 'dog' (box 1, interval 1) is due, but 'cat' (box 2, interval 2) is not due yet
    final tomorrow = now.add(const Duration(days: 1));
    final dueItems = await service.getDueItems(now: tomorrow);
    expect(dueItems.length, 1);
    expect(dueItems.first.word, 'dog');
  });
}
