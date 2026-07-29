import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/cefr_collocation_tree_widget.dart';

void main() {
  testWidgets('CefrCollocationTreeWidget renders root word and collocations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CefrCollocationTreeWidget(
            rootWord: 'make',
            cefrLevel: 'B1',
            collocations: ['make a decision', 'make progress'],
          ),
        ),
      ),
    );

    expect(find.text('make'), findsOneWidget);
    expect(find.text('B1'), findsOneWidget);
    expect(find.text('make a decision'), findsOneWidget);
    expect(find.text('make progress'), findsOneWidget);
  });
}
