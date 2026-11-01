import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';

import '../../support/word_scramble_session_harness.dart';

void main() {
  test(
    'History distinguishes the actual native checkpoint from a configured quiz without writes',
    () async {
      final h = await WordScrambleSessionHarness.open();
      addTearDown(h.close);
      final exercise = await h.ready();
      expect(h.database.allTables, hasLength(45));
      final before = await h.storage.snapshot();
      final history = await DriftLearningHistoryQueries(
        h.database,
      ).load(ownerId: configuredOwnerId, nowUtc: h.now);
      final entry = history.entries.single;
      expect(entry.sessionId, exercise.id);
      expect(entry.activityType, 'wordScramble');
      expect(entry.state, 'active');
      expect(entry.hasAcceptedQuiz, isFalse);
      expect(entry.hasAcceptedNative, isTrue);
      expect(await h.storage.snapshot(), before);
    },
  );
}
