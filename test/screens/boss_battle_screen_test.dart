import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/boss_battle_screen.dart';

void main() {
  testWidgets('only the current correctly spelled word reduces HP', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: BossBattleScreen(onChooseGame: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('พลังคู่ต่อสู้ 100'), findsOneWidget);
    expect(find.text('คำที่ 1 จาก 3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ephemral');
    await tester.tap(find.text('ส่งคำตอบ'));
    await tester.pumpAndSettle();
    expect(find.text('หลังตัว m ยังมีตัว e'), findsOneWidget);
    expect(find.text('พลังคู่ต่อสู้ 100'), findsOneWidget);

    await tester.tap(find.text('แก้คำตอบ'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ephemral',
    );
    await tester.enterText(find.byType(TextField), ' Ephemeral ');
    await tester.tap(find.text('ส่งคำตอบ'));
    await tester.pumpAndSettle();

    expect(find.text('พลังคู่ต่อสู้ 65'), findsOneWidget);
    expect(find.text('คำที่ 2 จาก 3'), findsOneWidget);
    expect(find.text('ผ่านแล้ว 1 จาก 3 คำ'), findsOneWidget);
  });
}
