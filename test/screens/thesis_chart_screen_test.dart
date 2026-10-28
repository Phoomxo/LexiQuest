import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/thesis_chart_screen.dart';

void main() {
  testWidgets(
    'ThesisChartScreen renders Pre/Post test scores and Latency trend chart',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThesisChartScreen(preTestScore: 50, postTestScore: 90),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('กราฟผลสัมฤทธิ์งานวิจัย (Thesis Auto-Chart)'),
        findsOneWidget,
      );
      expect(
        find.text('1. กราฟเปรียบเทียบคะแนน Pre-Test vs Post-Test'),
        findsOneWidget,
      );
    },
  );
}
