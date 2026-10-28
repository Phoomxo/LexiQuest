import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

void main() {
  testWidgets(
    'result facts and return action remain reachable at 200% in 240dp',
    (tester) async {
      tester.view.physicalSize = const Size(240, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const ScoreScreen(correctAnswers: 8, wrongAnswers: 2),
                  ),
                ),
                child: const Text('Open result'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open result'));
      await tester.pumpAndSettle();
      expect(find.text('80%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['ตอบถูก', 'ตอบผิด', 'จำนวนตัวอย่าง']) {
        await tester.scrollUntilVisible(find.text(label), 120);
        await Scrollable.ensureVisible(
          tester.element(find.text(label)),
          alignment: 0.5,
        );
        await tester.pump();
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      final returnAction = find.widgetWithText(
        FilledButton,
        'กลับไปเลือกกิจกรรม',
      );
      await tester.scrollUntilVisible(returnAction, 120);
      await Scrollable.ensureVisible(
        tester.element(returnAction),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(returnAction);
      await tester.pumpAndSettle();
      expect(find.byType(ScoreScreen), findsNothing);
      expect(find.text('Open result'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty answer count retains the existing score with context', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScoreScreen(correctAnswers: 0, wrongAnswers: 0)),
    );
    expect(find.text('ยังไม่มีคำตอบในรอบนี้'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('explicit score remains authoritative when counts are empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScoreScreen(correctAnswers: 0, wrongAnswers: 0, score: 42),
      ),
    );
    expect(find.text('42%'), findsOneWidget);
  });
}
