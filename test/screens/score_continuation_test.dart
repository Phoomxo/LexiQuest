import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

void main() {
  testWidgets('all correct uses the supplied completion callback', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          correctAnswers: 2,
          wrongAnswers: 0,
          backLabel: 'กลับหน้าเรียน',
          onBack: () => backs++,
        ),
      ),
    );
    expect(find.text('ตอบถูกทุกข้อ'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'กลับหน้าเรียน'));
    expect(backs, 1);
  });

  testWidgets('wrong answers without repair are not described as all correct', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScoreScreen(
          correctAnswers: 1,
          wrongAnswers: 1,
          languageCode: 'en',
        ),
      ),
    );
    expect(find.text('All answers correct'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
  });

  testWidgets('empty result is honest and works with large English text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const ScoreScreen(
          correctAnswers: 0,
          wrongAnswers: 0,
          languageCode: 'en',
        ),
      ),
    );
    expect(find.text('No answers yet'), findsOneWidget);
    expect(find.text('All answers correct'), findsNothing);
    await tester.ensureVisible(find.text('Done'));
    expect(find.text('Done').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repair retains priority and both callbacks work once', (
    tester,
  ) async {
    var backs = 0;
    var repairs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          correctAnswers: 0,
          wrongAnswers: 1,
          mistakes: const [
            QuizWord(
              id: '1',
              categoryId: 'c',
              spelling: 'word',
              meaning: 'meaning',
              partOfSpeech: 'noun',
            ),
          ],
          onPracticeMistakes: () => repairs++,
          onBack: () => backs++,
          backLabel: 'กลับชุดคำต้นทาง',
        ),
      ),
    );
    await tester.ensureVisible(find.text('ฝึกคำที่ผิด (1)'));
    await tester.tap(find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)'));
    await tester.ensureVisible(find.text('กลับชุดคำต้นทาง'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'กลับชุดคำต้นทาง'));
    expect(repairs, 1);
    expect(backs, 1);
  });
}
