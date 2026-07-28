import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/thesis_chart_screen.dart';

void main() {
  testWidgets(
    'ThesisChartScreen renders labels from caller-supplied observations',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThesisChartScreen(
            preTestScore: 50,
            postTestScore: 90,
            latencyTrend: [2000, 1000],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pre-Test (50.0%)'), findsOneWidget);
      expect(find.text('Post-Test (90.0%)'), findsOneWidget);

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

  test('ThesisChartScreen has no fabricated constructor defaults', () {
    final source = File(
      'lib/screens/thesis_chart_screen.dart',
    ).readAsStringSync();

    expect(source, contains('required this.preTestScore'));
    expect(source, contains('required this.postTestScore'));
    expect(source, contains('required this.latencyTrend'));
    expect(source, isNot(contains('this.preTestScore =')));
    expect(source, isNot(contains('this.postTestScore =')));
    expect(source, isNot(contains('this.latencyTrend =')));
  });
}
