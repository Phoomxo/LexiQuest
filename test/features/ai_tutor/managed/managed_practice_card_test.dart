import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_practice_card.dart';

const word = <String, dynamic>{
  'id': 'w',
  'spelling': 'bottle',
  'meaning': 'ขวด',
  'partOfSpeech': 'noun',
  'revision': 2,
};
Map<String, dynamic> receipt({String status = 'completed', int revision = 2}) =>
    {
      'name': 'create_practice_draft',
      'status': status,
      'data': {
        'draftId': '0123456789abcdef01234567',
        'wordId': 'w',
        'revision': revision,
        'prompt': 'พิมพ์คำภาษาอังกฤษที่หมายถึง: ขวด',
        'expectedAnswer': 'bottle',
        'awardsCredit': false,
      },
    };
void main() {
  testWidgets(
    'verified tool draft opens practice and grades without progress writes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagedPracticeCard(word: word, receipt: receipt()),
          ),
        ),
      );
      await tester.tap(find.text('เปิดแบบฝึก'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('ตรวจคำตอบ'));
      await tester.pump();
      expect(find.text('ยังไม่ถูก ลองอีกครั้ง'), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' BOTTLE ');
      await tester.tap(find.text('ตรวจคำตอบ'));
      await tester.pump();
      expect(find.text('ถูกต้อง · แบบฝึกนี้ไม่เพิ่มคะแนน'), findsOneWidget);
    },
  );
  testWidgets('failed or stale tool cannot offer a practice action', (
    tester,
  ) async {
    for (final r in [receipt(status: 'failed'), receipt(revision: 1)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManagedPracticeCard(word: word, receipt: r),
          ),
        ),
      );
      expect(find.text('เปิดแบบฝึก'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    }
  });
}
