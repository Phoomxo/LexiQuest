import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test('reading an absent streak preserves every owned table', () async {
    final h = await ConfiguredQuizHarness.open();
    addTearDown(h.close);
    final streak = StreakUseCases(
      repository: DriftStreakRepository(h.database),
      nowUtc: () => h.now,
    );
    final before = await h.snapshot();
    final state = await streak.getCurrentStreak();
    expect(state.ownerId, configuredOwnerId);
    expect(state.currentStreakDays, 0);
    expect(state.freezeCount, 0);
    expect(await h.snapshot(), before);
  });
}
