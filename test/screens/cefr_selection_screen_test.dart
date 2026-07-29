import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';

void main() {
  testWidgets(
    'CefrSelectionScreen renders tabs, search bar, and filters by query',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: CefrSelectionScreen()));
      await tester.pumpAndSettle();

      expect(find.text('คลังคำศัพท์ CEFR Multi-Matrix'), findsOneWidget);
      expect(find.text('เริ่มทบทวน SRS'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'achieve');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'achieve'), findsOneWidget);
    },
  );
}
