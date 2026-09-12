import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_screen.dart';

void main() {
  testWidgets('R15.8 empty committed quest does not announce goal success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultScreen(
          result: _result(questCodes: const [], completedMission: false),
          onNextAction: () {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adventure-result-engagement')),
      120,
    );
    expect(find.byIcon(Icons.sentiment_satisfied_outlined), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adventure-result-motivation')),
      120,
    );
    expect(find.text('ทำกิจกรรมตามเป้าหมายแล้ว'), findsNothing);
  });

  testWidgets(
    'R15.8 receipt amount survives rebuild and reopen without motion',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final transaction = await tester.runAsync(() async {
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner:one', createdAtUtcMs: 1),
            );
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: 'synthetic-terminal-reward',
                ownerId: 'owner:one',
                idempotencyKey: 'synthetic-terminal-reward',
                transactionType: 'coinGrant',
                amount: 12,
                catalogVersion: 1,
                occurredAtUtcMs: 1,
              ),
            );
        return database.select(database.rewardTransactions).getSingle();
      });
      final result = _result(
        reward: AdventureRewardReceiptView(
          state: AdventureCanonicalRewardState.accepted,
          receiptId: transaction!.id,
          canonicalAmount: transaction.amount,
        ),
      );
      Widget screen() => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AdventureResultScreen(result: result, onNextAction: () {}),
        ),
      );
      for (var opening = 0; opening < 2; opening++) {
        await tester.pumpWidget(screen());
        await tester.pump();
        expect(find.text('รางวัลที่ยืนยันแล้ว 12'), findsOneWidget);
        await tester.pumpWidget(screen());
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('รางวัลที่ยืนยันแล้ว 12'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        final action = find.byKey(
          const ValueKey('adventure-result-next-action'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpWidget(const SizedBox.shrink());
        final rows = await tester.runAsync(
          () => database.select(database.rewardTransactions).get(),
        );
        expect(rows, hasLength(1));
        expect(rows!.single, transaction);
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );

  testWidgets(
    'R15.8 effort reaction and goal completion do not claim mastery',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdventureResultScreen(result: _result(), onNextAction: () {}),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-engagement')),
        120,
      );
      expect(
        find.byIcon(Icons.sentiment_very_satisfied_outlined),
        findsOneWidget,
      );
      expect(
        find.text('เวลาและกิจกรรมสะท้อนความพยายาม ไม่ใช่ระดับความรู้'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-motivation')),
        120,
      );
      expect(find.text('ทำกิจกรรมตามเป้าหมายแล้ว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in AdventureCanonicalRewardState.values) {
    testWidgets(
      'receipt state $state preserves next action and hides technical IDs',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AdventureResultScreen(
              result: _result(rewardState: state),
              onNextAction: () => calls++,
            ),
          ),
        );
        final action = find.byKey(
          const ValueKey('adventure-result-next-action'),
        );
        await tester.ensureVisible(action);
        await tester.pump();
        await tester.tap(action);
        expect(calls, 1);
        // ListView may evict the receipt after aligning the next action at
        // the top; return to the receipt before asserting its visible copy.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('adventure-result-reward')),
          -120,
        );
        await tester.pump();
        expect(find.textContaining('synthetic-receipt'), findsNothing);
        expect(
          find.text('รางวัลหลักได้รับการยืนยันแล้ว'),
          state == AdventureCanonicalRewardState.accepted
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.text('การเรียนบันทึกแล้ว รางวัลหลักกำลังยืนยัน'),
          state == AdventureCanonicalRewardState.pending
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.text('ยังไม่สามารถแสดงรางวัลหลักได้'),
          state == AdventureCanonicalRewardState.unavailable
              ? findsOneWidget
              : findsNothing,
        );
      },
    );
  }
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
        'adventure-result-reward',
        'adventure-result-effort',
        'adventure-result-engagement',
        'adventure-result-motivation',
      ]) {
        await tester.scrollUntilVisible(find.byKey(ValueKey<String>(key)), 160);
        await tester.pump();
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-reward')),
        -160,
      );
      await tester.pump();
      expect(
        find.text('การเรียนบันทึกแล้ว รางวัลหลักกำลังยืนยัน'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-motivation')),
        160,
      );
      expect(find.text('ภารกิจ: ยืนยันแล้ว'), findsOneWidget);
      expect(find.text('ความต่อเนื่อง: ยืนยันแล้ว'), findsOneWidget);
      expect(find.text('ความสำเร็จ: ไม่มีรายการใหม่'), findsOneWidget);
      expect(find.text('daily-quest'), findsNothing);
      final details = find.byKey(const ValueKey('adventure-result-details'));
      await tester.scrollUntilVisible(details, 160);
      await tester.pump();
      await tester.ensureVisible(details);
      await tester.pump();
      expect(details.hitTestable(), findsOneWidget);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('daily-quest'), findsOneWidget);
      expect(find.text('daily-streak'), findsOneWidget);
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
        find.byKey(const ValueKey('adventure-result-details')),
        160,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('adventure-result-details')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('adventure-result-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adventure-result-technical')),
        findsOneWidget,
      );
      final action = find.byKey(const ValueKey('adventure-result-next-action'));
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
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
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
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

AdventureResult _result({
  String? technicalMessage,
  AdventureRewardReceiptView? reward,
  List<String> questCodes = const ['daily-quest'],
  bool completedMission = true,
  AdventureCanonicalRewardState rewardState =
      AdventureCanonicalRewardState.pending,
}) => AdventureResult(
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
  engagement: AdventureEngagementResult(
    completedMission: completedMission,
    returnedAfterBreak: false,
  ),
  motivation: AdventureMotivationReceiptView(
    questState: AdventureCanonicalReceiptState.committed,
    streakState: AdventureCanonicalReceiptState.committed,
    achievementState: AdventureCanonicalReceiptState.notEligible,
    questCodes: questCodes,
    streakCodes: const <String>['daily-streak'],
  ),
  reward:
      reward ??
      AdventureRewardReceiptView(
        state: rewardState,
        canonicalAmount: rewardState == AdventureCanonicalRewardState.accepted
            ? 12
            : null,
        receiptId: rewardState == AdventureCanonicalRewardState.accepted
            ? 'synthetic-receipt'
            : null,
      ),
  nextAction: AdventureNextAction.reviewCenter,
  technicalMessage: technicalMessage,
);
