import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';

void main() {
  testWidgets('CefrSelectionScreen renders CEFR levels and scrolls to C2',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CefrSelectionScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลังคำศัพท์มาตรฐาน CEFR (A1 - C2)'), findsOneWidget);
    expect(find.text('A1 - Beginner (ผู้เริ่มต้น)'), findsOneWidget);

    final itemFinder = find.text('C2 - Proficiency (เชี่ยวชาญ)');
    await tester.scrollUntilVisible(itemFinder, 200.0);
    await tester.pumpAndSettle();

    expect(itemFinder, findsOneWidget);
  });
}
