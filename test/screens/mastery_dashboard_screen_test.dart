import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';

void main() {
  testWidgets('MasteryDashboardScreen renders streak card and skill scores', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MasteryDashboardScreen(
          listeningScore: 90.0,
          pronunciationScore: 85.0,
          spellingScore: 95.0,
          retentionScore: 88.0,
          streakDays: 7,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mastery & Analytics Dashboard'), findsOneWidget);
    expect(find.text('7 Days Streak!'), findsOneWidget);
    expect(find.text('Listening (การฟัง)'), findsOneWidget);
    expect(find.text('Pronunciation (การออกเสียง)'), findsOneWidget);
  });
}
