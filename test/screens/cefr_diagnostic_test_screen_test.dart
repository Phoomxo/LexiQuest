import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/cefr_diagnostic_test_screen.dart';

void main() {
  testWidgets('the sample survey opens with the pinned first question', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CefrDiagnosticTestScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('ลองตอบก่อนเลือกระดับ'), findsOneWidget);
    expect(find.text('ข้อ 1 จาก 5'), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);

    await tester.tap(find.text('แอปเปิล'));
    await tester.pumpAndSettle();

    expect(find.text('ข้อ 2 จาก 5'), findsOneWidget);
    expect(find.text('journey'), findsOneWidget);
  });

  const correct = [
    'แอปเปิล',
    'Trip',
    'บรรลุเป้าหมาย',
    'ที่นำเสนอสิ่งใหม่',
    'Present everywhere',
  ];
  const incorrect = ['กล้วย', 'Food', 'ล้มเหลว', 'โบราณ', 'Rare'];
  const recommendedLevels = ['A1', 'A1', 'A2', 'B1', 'B2', 'C1'];

  for (var score = 0; score <= 5; score++) {
    testWidgets(
      'score $score offers the corresponding sample deck and reader',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CefrDiagnosticTestScreen(
              suggestedDeckBuilder: (_, level) =>
                  Scaffold(appBar: AppBar(title: Text('Sample deck $level'))),
              suggestedArticleBuilder: (_, level) => Scaffold(
                appBar: AppBar(title: Text('Sample article $level')),
              ),
            ),
          ),
        );

        for (var question = 0; question < correct.length; question++) {
          final response = question < score
              ? correct[question]
              : incorrect[question];
          await tester.tap(find.text(response));
          await tester.pumpAndSettle();
        }

        final deckLevel = recommendedLevels[score];
        final displayLevel = score == 5 ? 'C1 หรือ C2' : deckLevel;
        final readingLevel = score < 2 ? 'A1' : 'A2';
        final scoreText = find.text('$score / 5');
        expect(find.text('ผลที่ลองตอบ'), findsOneWidget);
        expect(scoreText, findsOneWidget);
        expect(find.text('ผลการวัดระดับ CEFR ของคุณ'), findsNothing);
        await tester.tap(find.text('ระดับคำที่แนะนำ · $displayLevel'));
        await tester.pumpAndSettle();
        expect(find.text('Sample deck $deckLevel'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(scoreText, findsOneWidget);

        await tester.tap(find.text('ดูบทอ่านที่แนะนำ'));
        await tester.pumpAndSettle();
        expect(find.text('บทอ่าน $readingLevel'), findsOneWidget);
        await tester.tap(find.text('เริ่มอ่านเรื่องนี้'));
        await tester.pumpAndSettle();
        expect(find.text('Sample article $readingLevel'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('กลับไปดูผลเดิม'));
        await tester.pumpAndSettle();
        expect(scoreText, findsOneWidget);
      },
    );
  }

  testWidgets('double tap before rebuild answers only the visible question', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CefrDiagnosticTestScreen()),
    );
    final option = find.text('แอปเปิล');
    await tester.tap(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(find.text('ข้อ 2 จาก 5'), findsOneWidget);
  });
}
