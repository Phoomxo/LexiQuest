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
        'adventure-result-motivation',
        'adventure-result-reward',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      }
      expect(
        find.text('การเรียนบันทึกแล้ว รางวัลหลักกำลังยืนยัน'),
        findsOneWidget,
      );
      expect(find.text('Quest: ยืนยันแล้ว · daily-quest'), findsOneWidget);
      expect(find.text('Streak: ยืนยันแล้ว · daily-streak'), findsOneWidget);
      expect(find.text('Achievement: ไม่มีรายการใหม่'), findsOneWidget);
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-technical')),
        160,
        scrollable: find.byType(Scrollable),
      );
      expect(
        find.byKey(const ValueKey('adventure-result-technical')),
        findsOneWidget,
      );
      final action = find.byKey(const ValueKey('adventure-result-next-action'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      expect(calls, 1);
    },
  );

  testWidgets(
    'narrow 200 percent text keeps every truthful result section reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            highContrast: true,
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: ThemeData(colorScheme: const ColorScheme.dark()),
            home: AdventureResultScreen(result: _result(), onNextAction: () {}),
          ),
        ),
      );

      for (final key in <String>[
        'adventure-result-learning',
        'adventure-result-effort',
        'adventure-result-engagement',
        'adventure-result-motivation',
        'adventure-result-reward',
        'adventure-result-next-action',
      ]) {
        final finder = find.byKey(ValueKey<String>(key));
        await tester.scrollUntilVisible(
          finder,
          120,
          scrollable: find.byType(Scrollable),
        );
        expect(finder, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
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
  motivation: AdventureMotivationReceiptView(
    questState: AdventureCanonicalReceiptState.committed,
    streakState: AdventureCanonicalReceiptState.committed,
    achievementState: AdventureCanonicalReceiptState.notEligible,
    questCodes: const <String>['daily-quest'],
    streakCodes: const <String>['daily-streak'],
  ),
  reward: const AdventureRewardReceiptView(
    state: AdventureCanonicalRewardState.pending,
  ),
  nextAction: AdventureNextAction.reviewCenter,
  technicalMessage: technicalMessage,
);
