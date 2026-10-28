import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/learning_world_map_screen.dart';

void main() {
  testWidgets('LearningWorldMapScreen renders CEFR campaign nodes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LearningWorldMapScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text('แผนที่ท่องโลกคำศัพท์ (World Map Campaign)'),
      findsOneWidget,
    );
    expect(find.textContaining('A1 Starter Island'), findsOneWidget);
  });
}
