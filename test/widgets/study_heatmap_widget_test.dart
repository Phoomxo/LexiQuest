import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/study_heatmap_widget.dart';

void main() {
  testWidgets('StudyHeatmapWidget renders 28 day activity squares', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activity = {today: 10};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StudyHeatmapWidget(dailyActivity: activity)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ปฏิทินความถี่การเรียนรู้ (28 วันล่าสุด)'),
      findsOneWidget,
    );
    expect(find.byType(Tooltip), findsNWidgets(28));
  });
}
