import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';

import '../support/review_center_harness.dart';

void main() {
  testWidgets(
    'Quiz records confirmed input, excludes idle and returns its actual session',
    (tester) async {
      final h = await _TimeHarness.open(tester);
      try {
        final quiz = (await tester.runAsync(() async {
          final launch = await h.base.learning.prepareConfiguredQuiz(
            configuration: QuizConfiguration.sourcePractice(
              wordIds: [configuredWordIds.first],
            ),
            expectedOwnerId: configuredOwnerId,
          );
          return h.base.learning.startConfiguredQuiz(launch);
        }))!;
        await tester.pumpWidget(
          MaterialApp(
            home: QuizScreen(
              learning: h.base.learning,
              learningTime: h.time,
              resumeSessionId: quiz.sessionId,
              expectedOwnerId: configuredOwnerId,
              ownerChanges: h.base.ownerChanges,
            ),
          ),
        );
        await _until(tester, () => h.accepting);
        expect(await tester.runAsync(h.segments), isEmpty);
        h.advance(const Duration(seconds: 2));
        await tester.tap(find.text(quiz.plan.questions.single.word.meaning));
        await _until(
          tester,
          () => find.text('ดูผลการเรียน').evaluate().isNotEmpty,
        );
        await tester.runAsync(h.time.retryPending);
        final records = (await tester.runAsync(h.segments))!;
        expect(records, hasLength(1));
        expect(records.single['active_duration_us'], 2000000);
        h.advance(const Duration(minutes: 5));
        await tester.ensureVisible(find.text('ดูผลการเรียน'));
        await tester.tap(find.text('ดูผลการเรียน'));
        await _until(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final result = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(result.resultOwnerId, configuredOwnerId);
        expect(result.resultSessionId, quiz.sessionId);
        expect(await tester.runAsync(h.segments), records);
        expect(
          await tester.runAsync(
            () => h.base.database.select(h.base.database.answerAttempts).get(),
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'Study caller cannot collect ordinary time even without a Study row',
    (tester) async {
      final h = await _TimeHarness.open(tester);
      try {
        final quiz = (await tester.runAsync(() async {
          final launch = await h.base.learning.prepareConfiguredQuiz(
            configuration: QuizConfiguration.sourcePractice(
              wordIds: [configuredWordIds.first],
            ),
            expectedOwnerId: configuredOwnerId,
          );
          return h.base.learning.startConfiguredQuiz(launch);
        }))!;
        await tester.pumpWidget(
          MaterialApp(
            home: QuizScreen(
              learning: h.base.learning,
              learningTime: h.time,
              timeCallerContext: LearningTimeCallerContext.researchControlled,
              resumeSessionId: quiz.sessionId,
              expectedOwnerId: configuredOwnerId,
              ownerChanges: h.base.ownerChanges,
            ),
          ),
        );
        await _until(
          tester,
          () => find
              .text(quiz.plan.questions.single.word.spelling)
              .evaluate()
              .isNotEmpty,
        );
        h.advance(const Duration(seconds: 3));
        await tester.tap(find.text(quiz.plan.questions.single.word.meaning));
        await _until(
          tester,
          () => find.text('ดูผลการเรียน').evaluate().isNotEmpty,
        );
        await tester.runAsync(h.time.retryPending);
        expect(h.time.liveLease, isNull);
        expect(await tester.runAsync(h.segments), isEmpty);
        expect(
          await tester.runAsync(
            () => h.base.database
                .select(h.base.database.learningTimeScopes)
                .get(),
          ),
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () => h.base.database.select(h.base.database.answerAttempts).get(),
          ),
          hasLength(1),
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'owned SRS records front and reveal separately; Done returns null',
    (tester) async {
      final h = await _TimeHarness.open(tester);
      Object? returned = 'not-returned';
      try {
        await tester.runAsync(() => h.base.seedDue(configuredWordIds.first));
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    returned = await Navigator.of(context).push<Object?>(
                      MaterialPageRoute(
                        builder: (_) => SrsFlashcardsScreen(
                          learning: h.base.learning,
                          learningTime: h.time,
                          expectedOwnerId: configuredOwnerId,
                          ownerChanges: h.base.ownerChanges,
                          languageCode: 'en',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open review'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open review'));
        await _until(
          tester,
          () =>
              h.accepting &&
              find.byKey(const Key('srs-flip')).evaluate().isNotEmpty,
        );
        h.advance(const Duration(seconds: 2));
        await tester.ensureVisible(find.text('Show meaning'));
        await tester.tap(find.text('Show meaning'));
        await _until(
          tester,
          () =>
              h.accepting &&
              find.byKey(const Key('srs-got')).evaluate().isNotEmpty,
        );
        h.advance(const Duration(seconds: 3));
        await tester.ensureVisible(find.byKey(const Key('srs-got')));
        await tester.tap(find.byKey(const Key('srs-got')));
        await _until(
          tester,
          () => find.byKey(const Key('srs-next')).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byKey(const Key('srs-next')));
        await tester.tap(find.byKey(const Key('srs-next')));
        await _until(
          tester,
          () => find.byKey(const Key('srs-done')).evaluate().isNotEmpty,
        );
        await tester.runAsync(h.time.retryPending);
        final records = (await tester.runAsync(h.segments))!;
        expect(records, hasLength(2));
        expect(records.map((r) => r['active_duration_us']), [2000000, 3000000]);
        expect(
          await tester.runAsync(
            () => h.base.database.select(h.base.database.answerAttempts).get(),
          ),
          hasLength(1),
        );
        expect(returned, 'not-returned');
        await tester.ensureVisible(find.byKey(const Key('srs-done')));
        await tester.tap(find.byKey(const Key('srs-done')));
        await _until(tester, () => returned == null);
        expect(find.text('Open review'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('SRS preview cannot create time or learning facts', (
    tester,
  ) async {
    final h = await _TimeHarness.open(tester);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            wordList: const [
              {'word': 'synthetic', 'translation': 'example'},
            ],
            learningTime: h.time,
            expectedOwnerId: configuredOwnerId,
            ownerChanges: h.base.ownerChanges,
            languageCode: 'en',
          ),
        ),
      );
      await _until(
        tester,
        () => find.text('Show meaning').evaluate().isNotEmpty,
      );
      h.advance(const Duration(seconds: 2));
      await tester.tap(find.text('Show meaning'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('srs-got')));
      await tester.tap(find.byKey(const Key('srs-got')));
      await tester.pumpAndSettle();
      await tester.runAsync(h.time.retryPending);
      expect(h.time.liveLease, isNull);
      expect(await tester.runAsync(h.segments), isEmpty);
      expect(
        await tester.runAsync(
          () => h.base.database.select(h.base.database.learningSessions).get(),
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => h.base.database.select(h.base.database.answerAttempts).get(),
        ),
        isEmpty,
      );
    } finally {
      await h.close(tester);
    }
  });
}

final class _TimeHarness {
  _TimeHarness(this.base, this.ioZone) {
    time = LearningTimeUseCases(
      repository: DriftLearningTimeRepository(
        database: base.database,
        ownerWrites: base.ownerWrites,
        learning: base.learningRepository,
      ),
      ownerChanges: base.ownerChanges,
      monotonicMicros: () => micros,
      nowUtc: () => base.now,
      generateId: () => 'synthetic-screen-time-${++sequence}',
    );
  }

  final ReviewCenterHarness base;
  final Zone ioZone;
  late final LearningTimeUseCases time;
  int micros = 0;
  int sequence = 0;
  bool get accepting =>
      time.liveLease != null && time.acceptsInteraction(time.liveLease!);

  static Future<_TimeHarness> open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final result = (await tester.runAsync(() async {
      final harness = _TimeHarness(
        await ReviewCenterHarness.open(),
        Zone.current,
      );
      if (harness.time.preference?.ownerId != configuredOwnerId) {
        await harness.time.changes
            .firstWhere(
              (_) => harness.time.preference?.ownerId == configuredOwnerId,
            )
            .timeout(const Duration(seconds: 5));
      }
      expect(
        (await harness.time.setEnabled(
          true,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ))?.enabled,
        isTrue,
      );
      return harness;
    }))!;
    return result;
  }

  void advance(Duration elapsed) {
    micros += elapsed.inMicroseconds;
    base.now = base.now.add(elapsed);
  }

  Future<List<Map<String, Object?>>> segments() async => [
    for (final row
        in await base.database
            .customSelect(
              'SELECT * FROM learning_time_segments ORDER BY ordinal',
            )
            .get())
      row.data,
  ];

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => ioZone.run(() async {
        await time.retryPending();
        await time.dispose();
        await base.close();
      }),
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Quiz/SRS time boundary did not reach the required state');
}
