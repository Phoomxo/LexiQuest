import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';

void main() {
  testWidgets(
    'ObjectScannerScreen renders camera preview box and scans objects',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ObjectScannerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('สแกนวัตถุคำศัพท์ (Object Scanner)'), findsOneWidget);

      await tester.tap(find.text('จำลองสแกนวัตถุตรงหน้า'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.textContaining('สแกนพบ:'), findsOneWidget);
    },
  );
}
