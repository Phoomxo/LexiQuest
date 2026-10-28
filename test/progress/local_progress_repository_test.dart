import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/progress/local_progress_repository.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalProgressRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repository = LocalProgressRepository(prefs);
  });

  group('LocalProgressRepository boundary', () {
    test('implements the ProgressRepository contract', () {
      expect(repository, isA<ProgressRepository>());
    });

    test('starts from a clean zero snapshot with an empty outbox', () async {
      final snapshot = await repository.readSnapshot();
      expect(snapshot.totalPoints, 0);
      expect(snapshot.totalCorrectAnswers, 0);
      expect(snapshot.totalWrongAnswers, 0);
      expect(snapshot.gamesPlayed, 0);
      expect(await repository.pendingSessions(), isEmpty);
    });
  });

  group('recordSession accumulation', () {
    test(
      'one session raises totalPoints by correctAnswers and gamesPlayed once',
      () async {
        await repository.recordSession(
          const ProgressSession(
            sessionId: 'session-1',
            correctAnswers: 7,
            wrongAnswers: 3,
          ),
        );

        final snapshot = await repository.readSnapshot();
        expect(snapshot.totalPoints, 7);
        expect(snapshot.gamesPlayed, 1);
      },
    );

    test('a distinct session accumulates all four counters', () async {
      await repository.recordSession(
        const ProgressSession(
          sessionId: 'session-1',
          correctAnswers: 7,
          wrongAnswers: 3,
        ),
      );
      await repository.recordSession(
        const ProgressSession(
          sessionId: 'session-2',
          correctAnswers: 5,
          wrongAnswers: 1,
        ),
      );

      final snapshot = await repository.readSnapshot();
      expect(snapshot.totalPoints, 12);
      expect(snapshot.totalCorrectAnswers, 12);
      expect(snapshot.totalWrongAnswers, 4);
      expect(snapshot.gamesPlayed, 2);

      final pending = await repository.pendingSessions();
      expect(pending.map((s) => s.sessionId).toSet(), {
        'session-1',
        'session-2',
      });
    });
  });

  group('recordSession idempotency', () {
    test(
      're-recording the same sessionId leaves totals and outbox unchanged',
      () async {
        const session = ProgressSession(
          sessionId: 'session-1',
          correctAnswers: 7,
          wrongAnswers: 3,
        );

        await repository.recordSession(session);
        final before = await repository.readSnapshot();
        final outboxBefore = await repository.pendingSessions();

        // A second call with the same id, even with different counts, is a no-op.
        await repository.recordSession(session);
        await repository.recordSession(
          const ProgressSession(
            sessionId: 'session-1',
            correctAnswers: 999,
            wrongAnswers: 999,
          ),
        );

        final after = await repository.readSnapshot();
        expect(after.totalPoints, before.totalPoints);
        expect(after.totalCorrectAnswers, before.totalCorrectAnswers);
        expect(after.totalWrongAnswers, before.totalWrongAnswers);
        expect(after.gamesPlayed, before.gamesPlayed);

        final outboxAfter = await repository.pendingSessions();
        expect(outboxAfter.length, outboxBefore.length);
        expect(
          outboxAfter.map((s) => s.sessionId).toSet(),
          outboxBefore.map((s) => s.sessionId).toSet(),
        );
      },
    );
  });

  group('recordSession validation', () {
    test('rejects invalid sessions without mutating stored state', () async {
      // Seed known state so we can prove invalid writes do not corrupt it.
      await repository.recordSession(
        const ProgressSession(
          sessionId: 'seed',
          correctAnswers: 4,
          wrongAnswers: 2,
        ),
      );
      final seeded = await repository.readSnapshot();
      final seededOutbox = await repository.pendingSessions();

      final invalid = <ProgressSession>[
        const ProgressSession(
          sessionId: '',
          correctAnswers: 1,
          wrongAnswers: 1,
        ),
        const ProgressSession(
          sessionId: 'negative-correct',
          correctAnswers: -1,
          wrongAnswers: 0,
        ),
        const ProgressSession(
          sessionId: 'negative-wrong',
          correctAnswers: 0,
          wrongAnswers: -5,
        ),
        const ProgressSession(
          sessionId: 'huge-correct',
          correctAnswers: 1000000,
          wrongAnswers: 0,
        ),
        const ProgressSession(
          sessionId: 'huge-wrong',
          correctAnswers: 0,
          wrongAnswers: 1000000,
        ),
      ];

      for (final session in invalid) {
        await expectLater(
          repository.recordSession(session),
          throwsArgumentError,
        );
      }

      final after = await repository.readSnapshot();
      expect(after.totalPoints, seeded.totalPoints);
      expect(after.totalCorrectAnswers, seeded.totalCorrectAnswers);
      expect(after.totalWrongAnswers, seeded.totalWrongAnswers);
      expect(after.gamesPlayed, seeded.gamesPlayed);

      final outboxAfter = await repository.pendingSessions();
      expect(
        outboxAfter.map((s) => s.sessionId).toSet(),
        seededOutbox.map((s) => s.sessionId).toSet(),
      );
    });
  });

  group('offline persistence', () {
    test(
      'a fresh instance over the same SharedPreferences restores state',
      () async {
        await repository.recordSession(
          const ProgressSession(
            sessionId: 'session-1',
            correctAnswers: 7,
            wrongAnswers: 3,
          ),
        );
        await repository.recordSession(
          const ProgressSession(
            sessionId: 'session-2',
            correctAnswers: 5,
            wrongAnswers: 1,
          ),
        );

        // Simulate a process restart: brand-new repository, same storage.
        final restored = LocalProgressRepository(prefs);

        final snapshot = await restored.readSnapshot();
        expect(snapshot.totalPoints, 12);
        expect(snapshot.totalCorrectAnswers, 12);
        expect(snapshot.totalWrongAnswers, 4);
        expect(snapshot.gamesPlayed, 2);

        final pending = await restored.pendingSessions();
        expect(pending.map((s) => s.sessionId).toSet(), {
          'session-1',
          'session-2',
        });
      },
    );
  });

  group('canonical session id', () {
    test(
      'trims surrounding whitespace and dedupes a replayed canonical id',
      () async {
        await repository.recordSession(
          const ProgressSession(
            sessionId: '  session-1  ',
            correctAnswers: 7,
            wrongAnswers: 3,
          ),
        );
        final before = await repository.readSnapshot();
        final outboxBefore = await repository.pendingSessions();

        // Replay with the canonical (trimmed) id but different counts.
        await repository.recordSession(
          const ProgressSession(
            sessionId: 'session-1',
            correctAnswers: 4,
            wrongAnswers: 1,
          ),
        );

        final after = await repository.readSnapshot();
        expect(after.totalPoints, before.totalPoints);
        expect(after.totalCorrectAnswers, before.totalCorrectAnswers);
        expect(after.totalWrongAnswers, before.totalWrongAnswers);
        expect(after.gamesPlayed, before.gamesPlayed);

        final outboxAfter = await repository.pendingSessions();
        expect(outboxAfter.length, outboxBefore.length);
        expect(outboxAfter.single.sessionId, 'session-1');
      },
    );
  });

  group('persisted invariant validation', () {
    test('readSnapshot fails closed on a negative counter', () async {
      await repository.recordSession(
        const ProgressSession(
          sessionId: 'session-1',
          correctAnswers: 2,
          wrongAnswers: 1,
        ),
      );

      // Discover the single private key dynamically; never hard-code it.
      final key = prefs.getKeys().single;
      final envelope =
          jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final snapshot = envelope['snapshot'] as Map<String, dynamic>;
      snapshot['gamesPlayed'] = -1;
      await prefs.setString(key, jsonEncode(envelope));

      await expectLater(repository.readSnapshot(), throwsStateError);
    });

    test('pendingSessions fails closed on an empty session id', () async {
      await repository.recordSession(
        const ProgressSession(
          sessionId: 'session-1',
          correctAnswers: 2,
          wrongAnswers: 1,
        ),
      );

      final key = prefs.getKeys().single;
      final envelope =
          jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final pending = envelope['pending'] as List;
      (pending.first as Map<String, dynamic>)['sessionId'] = '';
      await prefs.setString(key, jsonEncode(envelope));

      await expectLater(repository.pendingSessions(), throwsStateError);
    });
  });

  group('concurrent recordSession', () {
    test('serialized concurrent calls apply exactly once each', () async {
      const count = 20;
      final writes = [
        for (var i = 0; i < count; i++)
          repository.recordSession(
            ProgressSession(
              sessionId: 'concurrent-$i',
              correctAnswers: 1,
              wrongAnswers: 1,
            ),
          ),
      ];
      await Future.wait(writes);

      final snapshot = await repository.readSnapshot();
      expect(snapshot.totalPoints, count);
      expect(snapshot.totalCorrectAnswers, count);
      expect(snapshot.totalWrongAnswers, count);
      expect(snapshot.gamesPlayed, count);

      final pending = await repository.pendingSessions();
      expect(pending.map((s) => s.sessionId).toSet(), hasLength(count));
    });
  });
}
