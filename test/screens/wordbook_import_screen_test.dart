import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/wordbook_import_screen.dart';

void main() {
  testWidgets('WordbookImportScreen imports CSV text and displays word items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WordbookImportScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text('นำเข้าสมุดคำศัพท์ส่วนตัว (Import Wordbook)'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      'word,translation\nbanana,กล้วย',
    );
    await tester.tap(find.text('ประมวลผลนำเข้าคำศัพท์'));
    await tester.pumpAndSettle();

    expect(find.text('banana'), findsOneWidget);
    expect(find.text('เริ่มเรียนรู้คำศัพท์ชุดนี้ทันที'), findsOneWidget);
  });
}
