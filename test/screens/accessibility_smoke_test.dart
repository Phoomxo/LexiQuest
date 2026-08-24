import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final screen in <Widget>[
      const LoginScreen(),
      const RegisterScreen(),
    ]) {
      testWidgets(
        '${screen.runtimeType} supports 200% text in ${brightness.name} mode',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: M3Theme.lightTheme,
              darkTheme: M3Theme.darkTheme,
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: screen,
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsWidgets);
          final context = tester.element(find.byType(Scaffold));
          expect(Theme.of(context).brightness, brightness);
        },
      );
    }

    testWidgets(
      'AnswerFeedbackPanel supports 200% text in ${brightness.name} mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: M3Theme.lightTheme,
            darkTheme: M3Theme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnswerFeedbackPanel(
                  feedback: AnswerFeedback.fromCommittedResult(
                    result: const AnswerRecordResult(
                      inserted: true,
                      isCorrect: false,
                      srs: null,
                    ),
                    context: const AnswerFeedbackContext(
                      canonicalCorrectAnswer: 'station',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Not quite'), findsOneWidget);
        expect(find.text('Correct answer: station'), findsOneWidget);
      },
    );
  }
}
