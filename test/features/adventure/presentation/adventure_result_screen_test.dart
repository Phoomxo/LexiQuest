import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_screen.dart';

void main() {
  testWidgets(
    'renders separate result sections and pending reward truthfully',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdventureResultScreen(result: _result(), onNextAction: () {}),
        ),
      );

      for (final key in <String>[
        'adventure-result-learning',
        'adventure-result-effort',
        'adventure-result-engagement',
        'adventure-result-reward',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      }
      expect(
        find.text('การเรียนบันทึกแล้ว รางวัลหลักกำลังยืนยัน'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          RegExp(
            r'คะแนนรวม|combined score|เชี่ยวชาญแล้ว|ล้มเหลว',
            caseSensitive: false,
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'technical state stays supportive and preserves Review next action',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AdventureResultScreen(
            result: _result(
              technicalMessage: 'ซิงก์ยังไม่สำเร็จ ลองใหม่ภายหลังได้',
            ),
            onNextAction: () => calls += 1,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('adventure-result-technical')),
        findsOneWidget,
      );
      final action = find.byKey(const ValueKey('adventure-result-next-action'));
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pump();
      await tester.tap(action);
      expect(calls, 1);
    },
  );
}

AdventureResult _result({String? technicalMessage}) => AdventureResult(
  ownerId: 'owner:one',
  sessionId: 'session:one',
  learning: const AdventureLearningResult(
    correctCount: 3,
    incorrectCount: 1,
    reviewDueCount: 1,
  ),
  effort: const AdventureEffortResult(
    activeDuration: Duration(minutes: 5),
    completedItems: 4,
  ),
  engagement: const AdventureEngagementResult(
    completedMission: true,
    returnedAfterBreak: false,
  ),
  reward: const AdventureRewardReceiptView(
    state: AdventureCanonicalRewardState.pending,
  ),
  nextAction: AdventureNextAction.reviewCenter,
  technicalMessage: technicalMessage,
);
