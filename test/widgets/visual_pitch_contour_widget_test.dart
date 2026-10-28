import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/visual_pitch_contour_widget.dart';

void main() {
  testWidgets('VisualPitchContourWidget renders CustomPaint cleanly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VisualPitchContourWidget(
            referencePitchPoints: [0.2, 0.8, 0.5, 0.9],
            userPitchPoints: [0.3, 0.7, 0.4, 0.8],
          ),
        ),
      ),
    );

    expect(find.byType(VisualPitchContourWidget), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
