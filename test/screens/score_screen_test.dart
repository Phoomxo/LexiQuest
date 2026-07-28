import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

class _RecordingRepository implements ProgressRepository {
  final List<ProgressSession> recorded = [];
  final Set<String> _sessionIds = {};
  ProgressSnapshot _snapshot = const ProgressSnapshot(
    totalPoints: 0,
    totalCorrectAnswers: 0,
    totalWrongAnswers: 0,
    gamesPlayed: 0,
  );

  @override
  Future<List<ProgressSession>> pendingSessions() async => recorded;

  @override
  Future<ProgressSnapshot> readSnapshot() async => _snapshot;

  @override
  Future<void> recordSession(ProgressSession session) async {
    recorded.add(session);
    if (!_sessionIds.add(session.sessionId)) return;
    _snapshot = ProgressSnapshot(
      totalPoints: _snapshot.totalPoints + session.correctAnswers,
      totalCorrectAnswers:
          _snapshot.totalCorrectAnswers + session.correctAnswers,
      totalWrongAnswers: _snapshot.totalWrongAnswers + session.wrongAnswers,
      gamesPlayed: _snapshot.gamesPlayed + 1,
    );
  }
}

class _FailingRepository implements ProgressRepository {
  const _FailingRepository({required this.failRecord});

  final bool failRecord;

  @override
  Future<List<ProgressSession>> pendingSessions() async => const [];

  @override
  Future<ProgressSnapshot> readSnapshot() async {
    throw StateError('read failed');
  }

  @override
  Future<void> recordSession(ProgressSession session) async {
    if (failRecord) throw StateError('record failed');
  }
}

void main() {
  testWidgets('records the injected session once across rebuilds', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final score = ScoreScreen(
      sessionId: 'quiz-session-123',
      correctAnswers: 4,
      wrongAnswers: 2,
      repository: repository,
    );

    await tester.pumpWidget(MaterialApp(home: score));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: score));
    await tester.pump();

    expect(repository.recorded, hasLength(1));
    expect(repository.recorded.single.sessionId, 'quiz-session-123');
    expect(repository.recorded.single.correctAnswers, 4);
    expect(repository.recorded.single.wrongAnswers, 2);
  });

  testWidgets('replaying a session id leaves injected totals unchanged', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    final score = ScoreScreen(
      sessionId: 'quiz-session-456',
      correctAnswers: 3,
      wrongAnswers: 1,
      repository: repository,
    );

    await tester.pumpWidget(MaterialApp(home: score));
    await tester.pump();
    final before = await repository.readSnapshot();
    await repository.recordSession(
      const ProgressSession(
        sessionId: 'quiz-session-456',
        correctAnswers: 999,
        wrongAnswers: 999,
      ),
    );
    final after = await repository.readSnapshot();

    expect(after.totalPoints, before.totalPoints);
    expect(after.totalCorrectAnswers, before.totalCorrectAnswers);
    expect(after.totalWrongAnswers, before.totalWrongAnswers);
    expect(after.gamesPlayed, before.gamesPlayed);
  });

  testWidgets('successful persistence renders aggregate answer totals', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await repository.recordSession(
      const ProgressSession(
        sessionId: 'existing-session',
        correctAnswers: 10,
        wrongAnswers: 6,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          sessionId: 'aggregate-session',
          correctAnswers: 4,
          wrongAnswers: 2,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correct answers'), findsOneWidget);
    expect(find.text('14'), findsWidgets);
    expect(find.text('Wrong answers'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
  });

  testWidgets('record failure shows session results without invented totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScoreScreen(
          sessionId: 'record-failure',
          correctAnswers: 4,
          wrongAnswers: 2,
          repository: _FailingRepository(failRecord: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local progress totals are unavailable.'), findsOneWidget);
    expect(find.text('This session: 4 correct, 2 wrong'), findsOneWidget);
    expect(find.text('Total points'), findsNothing);
    expect(find.text('Games played'), findsNothing);
  });

  testWidgets('snapshot read failure shows session results without totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScoreScreen(
          sessionId: 'read-failure',
          correctAnswers: 3,
          wrongAnswers: 1,
          repository: _FailingRepository(failRecord: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local progress totals are unavailable.'), findsOneWidget);
    expect(find.text('This session: 3 correct, 1 wrong'), findsOneWidget);
    expect(find.text('Total points'), findsNothing);
    expect(find.text('Games played'), findsNothing);
  });

  testWidgets('no repository settles without rebuilding a new loading future', (
    tester,
  ) async {
    const score = ScoreScreen(
      sessionId: 'no-repository',
      correctAnswers: 2,
      wrongAnswers: 1,
    );

    await tester.pumpWidget(const MaterialApp(home: score));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: score));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Local progress totals are unavailable.'), findsOneWidget);
    expect(find.text('This session: 2 correct, 1 wrong'), findsOneWidget);
  });
}
