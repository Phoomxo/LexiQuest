import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/lexical_quiz_setup_dialog.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../support/authored_lexical_pack.dart';
import '../support/populated_owner_migration_fixture.dart';
import 'learning_pack_test_support.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'canceling pack Definition configuration creates no learning facts',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        await _open(tester, h);
        final before = await tester.runAsync(
          () => ownerMigrationRows(h.database),
        );
        await tapPackUi(tester, 'pack-definition-0');
        await untilPackUi(
          tester,
          () => find.byType(LexicalQuizSetupDialog).evaluate().isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        await tester.tap(find.text('ยกเลิก'));
        await idlePackUi(tester);
        expect(
          await tester.runAsync(() => ownerMigrationRows(h.database)),
          before,
        );
        expect(find.byType(QuizScreen), findsNothing);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'installed authored pack configures a real Definition round through canonical Score',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        await _open(tester, h);
        await tapPackUi(tester, 'pack-definition-0');
        await untilPackUi(
          tester,
          () => find.byType(LexicalQuizSetupDialog).evaluate().isNotEmpty,
        );
        final count = find.byKey(
          const ValueKey((
            'definition-item-count',
            LexicalQuizInput.definitionChoice,
          )),
        );
        await tester.ensureVisible(count);
        await tester.tap(count);
        await untilPackUi(
          tester,
          () => find.text('1 คำ').last.hitTestable().evaluate().isNotEmpty,
        );
        await tester.tap(find.text('1 คำ').last);
        await untilPackUi(
          tester,
          () =>
              find.text('1 คำ').evaluate().length == 1 &&
              find
                  .descendant(of: count, matching: find.text('1 คำ'))
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        await tester.tap(find.byKey(const ValueKey('definition-start')));
        await untilPackUi(
          tester,
          () =>
              find.byType(QuizScreen).evaluate().isNotEmpty &&
              find.text('อ่านนิยามแล้วเลือกคำศัพท์').evaluate().isNotEmpty,
        );
        final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(screen.preparedLaunch!.configuration.lexical!.limit, 1);
        expect(screen.expectedOwnerId, 'synthetic-actions-owner');
        final question = screen.preparedLaunch!.preparedPlan!.questions.single;
        expect(find.text(question.prompt), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, question.correctAnswer),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(FilledButton, question.correctAnswer),
        );
        await untilPackUi(
          tester,
          () => find.text('ถูกต้อง').evaluate().isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('answer_attempts')), 1);
        final resultAction = find.text('ดูผลการเรียน');
        await tester.ensureVisible(resultAction);
        await tester.pump();
        await tester.tap(resultAction);
        await untilPackUi(
          tester,
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(score.correctAnswers, 1);
        expect(score.wrongAnswers, 0);
        final answer = (await tester.runAsync(h.canonicalAnswer))!;
        expect(answer.read<String>('prompt_mode'), 'definitionChoice');
        expect(answer.read<String>('state'), 'completed');
        expect(await tester.runAsync(() => h.count('answer_attempts')), 1);
        expect(h.voice.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );
}

Future<void> _open(WidgetTester tester, LearningPackUiHarness h) async {
  await tester.runAsync(() => h.seed(authoredLexicalPack()));
  await tester.pumpWidget(h.app());
  await packUiReady(tester);
  final row = find.widgetWithText(
    ListTile,
    'Synthetic authored definition deck',
  );
  await tester.ensureVisible(row);
  await tester.tap(row);
  await idlePackUi(tester);
}
