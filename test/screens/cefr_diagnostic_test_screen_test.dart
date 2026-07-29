import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/cefr_diagnostic_test_screen.dart';

void main() {
  testWidgets('CefrDiagnosticTestScreen allows answering placement questions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CefrDiagnosticTestScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('แบบทดสอบวัดระดับ CEFR (1/5)'), findsOneWidget);
    expect(find.text('What is the meaning of "apple"?'), findsOneWidget);

    await tester.tap(find.text('แอปเปิ้ล'));
    await tester.pumpAndSettle();

    expect(find.text('แบบทดสอบวัดระดับ CEFR (2/5)'), findsOneWidget);
  });
}
