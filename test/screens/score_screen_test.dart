import 'dart:async';
import 'dart:io';

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

class _BlockingRepository implements ProgressRepository {
  final Completer<void> recordCompleter = Completer<void>();
  final List<ProgressSession> recorded = [];

  @override
  Future<List<ProgressSession>> pendingSessions() async => recorded;

  @override
  Future<ProgressSnapshot> readSnapshot() async => const ProgressSnapshot(
    totalPoints: 4,
    totalCorrectAnswers: 4,
    totalWrongAnswers: 2,
    gamesPlayed: 1,
  );

  @override
  Future<void> recordSession(ProgressSession session) {
    recorded.add(session);
    return recordCompleter.future;
  }
}

void main() {
  test('sessionId is required and ScoreScreen never generates one', () {
    final source = File('lib/screens/score_screen.dart').readAsStringSync();

    expect(source, contains('required this.sessionId'));
    expect(source, isNot(contains('_newLegacySessionId')));
    expect(source, isNot(contains('Random.secure')));
  });

  testWidgets('renders result shell immediately while persistence is pending', (
    tester,
  ) async {
    final repository = _BlockingRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          sessionId: 'pending-session',
          correctAnswers: 4,
          wrongAnswers: 2,
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ผลลัพธ์ของคุณ'), findsOneWidget);
    expect(find.text('รอบนี้: ตอบถูก 4 • ตอบผิด 2'), findsOneWidget);
    expect(find.text('เล่นใหม่'), findsOneWidget);
    expect(find.text('กลับหน้าหลัก'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(repository.recorded, hasLength(1));
  });

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

  testWidgets('successful persistence renders four scoped aggregate totals', (
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

    expect(
      find.textContaining('เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้'),
      findsNWidgets(4),
    );
    expect(find.text('14'), findsWidgets);
    expect(find.text('8'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(
      find.text('บันทึกผลแล้ว: ความคืบหน้าการฝึกอยู่เฉพาะอุปกรณ์นี้'),
      findsOneWidget,
    );
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

    expect(find.text('ยังไม่ได้บันทึกผลรอบนี้ในอุปกรณ์'), findsOneWidget);
    expect(find.text('รอบนี้: ตอบถูก 4 • ตอบผิด 2'), findsOneWidget);
    expect(
      find.textContaining('เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้'),
      findsNothing,
    );
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

    expect(
      find.text('บันทึกผลรอบนี้แล้ว แต่ยังอ่านยอดรวมจากอุปกรณ์ไม่ได้'),
      findsOneWidget,
    );
    expect(find.text('รอบนี้: ตอบถูก 3 • ตอบผิด 1'), findsOneWidget);
    expect(
      find.textContaining('เฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้'),
      findsNothing,
    );
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
    expect(find.text('ยังไม่ได้บันทึกผลรอบนี้ในอุปกรณ์'), findsOneWidget);
    expect(find.text('รอบนี้: ตอบถูก 2 • ตอบผิด 1'), findsOneWidget);
  });
}
