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
}
