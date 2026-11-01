import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/matching_quiz_screen.dart';

void main() {
  testWidgets(
    'small dark board at 200 percent supports selection, wrong feedback, and canonical result',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      addTearDown(h.owners.close);
      await tester.pumpWidget(h.app(textScale: 2));
      await tester.pumpAndSettle();
      expect(h.repository.commits, 0);
      Future<void> tap(String key) async {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap('matching-word-0');
      await tap('matching-meaning-1');
      await tap('matching-check');
      expect(find.text('คู่นี้ยังไม่ตรงกัน ลองเลือกใหม่'), findsOneWidget);
      expect(h.repository.commits, 1);
      await tap('matching-continue');
      for (var index = 0; index < 2; index++) {
        await tap('matching-word-$index');
        await tap('matching-meaning-$index');
        await tap('matching-check');
        expect(find.text('จับคู่ถูกแล้ว'), findsOneWidget);
        await tap('matching-continue');
      }
      expect(find.text('67%'), findsOneWidget);
      expect(h.repository.commits, 3);
      expect(h.repository.finishes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'retained check callback is retired when another route covers the board',
    (tester) async {
      final h = _Harness();
      addTearDown(h.owners.close);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('matching-word-0')));
      await tester.tap(find.byKey(const ValueKey('matching-meaning-0')));
      await tester.pump();
      final check = tester
          .widget<FilledButton>(find.byKey(const ValueKey('matching-check')))
          .onPressed!;
      unawaited(
        h.navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('synthetic-cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      check();
      await tester.pumpAndSettle();
      expect(h.repository.saves, 0);
      expect(h.repository.commits, 0);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      check();
      await tester.pumpAndSettle();
      expect(h.repository.saves, 0);
      expect(h.repository.commits, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'keyboard selection and a lost commit acknowledgement retry the original pair',
    (tester) async {
      final h = _Harness();
      h.repository.loseNextCommitAck = true;
      addTearDown(h.owners.close);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      for (var index = 0; index < 3; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('matching-check')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('matching-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('matching-error')), findsOneWidget);
      expect(h.repository.commits, 1);
      final original = h.repository.lastAttempt;
      await tester.tap(find.byKey(const ValueKey('matching-retry')));
      await tester.pumpAndSettle();
      expect(find.text('จับคู่ถูกแล้ว'), findsOneWidget);
      expect(h.repository.lastAttempt, original);
      expect(h.repository.commits, 1);
      h.owners.add('synthetic-another-owner');
      h.owners.add('synthetic-matching-screen-owner');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('matching-unavailable')),
        findsOneWidget,
      );
      expect(find.text('station'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

final class _Harness {
  _Harness() {
    matching = MatchingUseCases(
      repository: repository,
      generateId: () => 'synthetic-ui',
      nowUtc: () => DateTime.utc(2026, 11),
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-ui',
      ),
    );
  }
  final repository = _Repository();
  final owners = StreamController<String?>.broadcast(sync: true);
  final navigator = GlobalKey<NavigatorState>();
  late final MatchingUseCases matching;
  Widget app({double textScale = 1}) => MaterialApp(
    navigatorKey: navigator,
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: MatchingQuizScreen(
      matching: matching,
      expectedOwnerId: 'synthetic-matching-screen-owner',
      ownerChanges: owners.stream,
      preparedPlan: repository.plan,
    ),
  );
}

final class _Repository implements MatchingRepository {
  final plan = MatchingPlan(
    session: LearningSessionDraft(
      id: '${MatchingPlan.sessionPrefix}synthetic-screen',
      ownerId: 'synthetic-matching-screen-owner',
      activityType: MatchingPlan.activityType,
      startedAtUtc: DateTime.utc(2026, 11),
      appVersion: 'synthetic',
      buildId: 'synthetic',
    ),
    words: const [
      QuizWord(
        id: 'synthetic-station',
        categoryId: 'synthetic-category',
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      ),
      QuizWord(
        id: 'synthetic-ticket',
        categoryId: 'synthetic-category',
        spelling: 'ticket',
        meaning: 'ตั๋ว',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      ),
    ],
  );
  _State? current;
  int saves = 0;
  int commits = 0;
  int wrong = 0;
  int finishes = 0;
  bool loseNextCommitAck = false;
  String? lastAttempt;
  @override
  Future<MatchingPlan?> prepare({
    required LearningSessionDraft session,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
    required bool Function() stillCurrent,
  }) async => plan;
  @override
  Future<MatchingState> start(
    MatchingPlan plan, {
    required bool Function() stillCurrent,
  }) async => current ??= _State(
    plan,
    MatchingCheckpoint(
      phase: MatchingPhase.selecting,
      attemptCount: 0,
      matched: [],
    ),
    1,
  );
  @override
  Future<MatchingState> resume({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async => current!;
  @override
  Future<MatchingState> save(
    MatchingState state,
    MatchingCheckpoint next, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) throw StateError('retired');
    next.validate(plan);
    saves++;
    return current = _State(plan, next, state.revision + 1);
  }

  @override
  Future<MatchingState> commit(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) throw StateError('retired');
    final answer = state.checkpoint.answer!;
    if (lastAttempt == answer.id) return current!;
    lastAttempt = answer.id;
    commits++;
    if (!answer.isCorrect) wrong++;
    final matched = [
      ...state.checkpoint.matched,
      if (answer.isCorrect) answer.wordIndex,
    ]..sort();
    current = _State(
      plan,
      MatchingCheckpoint(
        phase: MatchingPhase.answered,
        attemptCount: state.checkpoint.attemptCount + 1,
        matched: matched,
        answer: answer,
      ),
      state.revision + 1,
    );
    if (loseNextCommitAck) {
      loseNextCommitAck = false;
      throw StateError('synthetic lost ACK');
    }
    return current!;
  }

  @override
  Future<MatchingState> finish(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) throw StateError('retired');
    finishes++;
    final correct = commits - wrong;
    return current = _State(
      plan,
      MatchingCheckpoint(
        phase: MatchingPhase.completed,
        attemptCount: commits,
        matched: state.checkpoint.matched,
        endedAtUtcMs: state.checkpoint.endedAtUtcMs,
      ),
      state.revision + 1,
      LearningSessionSummary(
        id: plan.session.id,
        state: 'completed',
        correctCount: correct,
        wrongCount: wrong,
        score: ((correct * 100) / commits).round(),
      ),
    );
  }
}

final class _State implements MatchingState {
  const _State(
    this.plan,
    this.checkpoint,
    this.revision, [
    this.completedSummary,
  ]);
  @override
  final MatchingPlan plan;
  @override
  final MatchingCheckpoint checkpoint;
  @override
  final int revision;
  @override
  final LearningSessionSummary? completedSummary;
}
