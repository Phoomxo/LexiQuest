import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_motivation_projection_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_lifecycle_screen.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  testWidgets(
    'learning result stays pending until refresh commits and reads receipt',
    (tester) async {
      final gate = Completer<void>();
      final refresher = _Refresher(gate.future);
      final diagnostics = AdventureDiagnostics();
      final reader = _Reader(<AdventureMotivationSnapshot>[
        _snapshot(
          AdventureProjectionOutcome(
            state: AdventureProjectionReceiptState.committed,
            receiptId:
                'learning-projection:reward:learning-event:evidence:1:v2',
          ),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: AdventureResultLifecycleScreen(
            summary: _summary(),
            motivation: reader,
            receiptBarrier: refresher,
            diagnostics: diagnostics,
            rewardOwnership: _rewardAccount,
            onNextAction: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('รางวัลหลักกำลังยืนยัน'), findsOneWidget);
      expect(find.text('การเรียนบันทึกแล้ว รางวัลกำลังยืนยัน'), findsOneWidget);
      expect(refresher.ownerIds, <String>['owner:one']);
      expect(reader.sessionReads, isEmpty);
      expect(diagnostics.snapshot().counters, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();

      expect(reader.sessionReads, <String>['owner:one/session:one']);
      expect(find.text('รางวัลหลักได้รับการยืนยันแล้ว'), findsOneWidget);
      expect(find.text('Quest: ยืนยันแล้ว'), findsOneWidget);
      expect(find.text('Streak: ยืนยันแล้ว'), findsOneWidget);
      expect(
        find.text('Achievement: ยืนยันแล้ว · first-adventure'),
        findsOneWidget,
      );
      expect(
        find.text('ภารกิจรอบนี้เสร็จแล้ว คุณได้ลงมือเรียนรู้'),
        findsOneWidget,
      );
    },
  );

  testWidgets('refresh failure keeps reward pending and exposes retry truth', (
    tester,
  ) async {
    final diagnostics = AdventureDiagnostics();
    final refresher = _Refresher(
      Future<void>.delayed(Duration.zero, () => throw StateError('offline')),
    );
    final reader = _Reader(const <AdventureMotivationSnapshot>[]);

    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultLifecycleScreen(
          summary: _summary(),
          motivation: reader,
          receiptBarrier: refresher,
          diagnostics: diagnostics,
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('รางวัลหลักกำลังยืนยัน'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adventure-result-technical')),
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.byKey(const ValueKey('adventure-result-technical')),
      findsOneWidget,
    );
    expect(reader.sessionReads, isEmpty);
    expect(
      diagnostics.snapshot().counters,
      <AdventureDiagnosticReasonCode, int>{
        AdventureDiagnosticReasonCode.projectionRetry: 1,
        AdventureDiagnosticReasonCode.projectionRetryExhausted: 1,
      },
    );
  });

  testWidgets('projection retry can recover through the reviewed reaction', (
    tester,
  ) async {
    final diagnostics = AdventureDiagnostics();
    final barrier = _FlakyBarrier();
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultLifecycleScreen(
          summary: _summary(),
          motivation: _Reader(<AdventureMotivationSnapshot>[
            _snapshot(
              const AdventureProjectionOutcome(
                state: AdventureProjectionReceiptState.committed,
                receiptId: 'learning-projection:reward:event:one:v2',
              ),
            ),
          ]),
          receiptBarrier: barrier,
          diagnostics: diagnostics,
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(barrier.calls, 2);
    expect(find.text('กลับมาใช้งานได้แล้ว ไปต่อเมื่อพร้อมนะ'), findsOneWidget);
    expect(
      diagnostics.snapshot().counters,
      <AdventureDiagnosticReasonCode, int>{
        AdventureDiagnosticReasonCode.projectionRetry: 1,
      },
    );
  });

  testWidgets('empty canonical evidence is terminal reward unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultLifecycleScreen(
          summary: _summary(),
          motivation: _Reader(const <AdventureMotivationSnapshot>[]),
          receiptBarrier: _Refresher(Future<void>.value()),
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่สามารถแสดงรางวัลหลักได้'), findsOneWidget);
    expect(find.textContaining('กำลังยืนยัน'), findsNothing);
  });

  testWidgets('mixed committed and pending receipts stay reward pending', (
    tester,
  ) async {
    final reader = _Reader(<AdventureMotivationSnapshot>[
      _snapshot(
        const AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.committed,
          receiptId: 'learning-projection:reward:event:one:v2',
        ),
      ),
      _snapshot(
        const AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.pending,
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultLifecycleScreen(
          summary: _summary(),
          motivation: reader,
          receiptBarrier: _Refresher(Future<void>.value()),
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('รางวัลหลักกำลังยืนยัน'), findsOneWidget);
    expect(find.text('รางวัลหลักได้รับการยืนยันแล้ว'), findsNothing);
  });
}

final class _Refresher implements AdventureProjectionReceiptBarrier {
  _Refresher(this.result);

  final Future<void> result;
  final List<String> ownerIds = <String>[];

  @override
  Future<void> waitForCanonicalProjection(String ownerId) {
    ownerIds.add(ownerId);
    return result;
  }
}

final class _FlakyBarrier implements AdventureProjectionReceiptBarrier {
  var calls = 0;

  @override
  Future<void> waitForCanonicalProjection(String ownerId) async {
    calls += 1;
    if (calls == 1) throw StateError('temporary offline');
  }
}

final class _Reader implements AdventureMotivationProjectionReader {
  _Reader(this.snapshots);

  final List<AdventureMotivationSnapshot> snapshots;
  final List<String> sessionReads = <String>[];

  @override
  Future<AdventureMotivationSnapshot> read(
    AdventureMotivationProjectionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<AdventureMotivationSnapshot> readForEvidence(String evidenceId) =>
      throw UnimplementedError();

  @override
  Future<List<AdventureMotivationSnapshot>> readForSession({
    required String ownerId,
    required String sessionId,
  }) async {
    sessionReads.add('$ownerId/$sessionId');
    return snapshots;
  }
}

AdventureMotivationSnapshot _snapshot(AdventureProjectionOutcome reward) =>
    AdventureMotivationSnapshot(
      sourceEvidenceId: 'evidence:1',
      questOutcome: const AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.committed,
        receiptId: 'learning-projection:quest:learning-event:evidence:1:v2',
      ),
      streakOutcome: const AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.committed,
        receiptId: 'learning-projection:streak:learning-event:evidence:1:v2',
      ),
      achievementOutcomes: const <AdventureProjectionOutcome>[
        AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.committed,
          receiptId: 'achievement-receipt:evidence:1:first-adventure:v1',
          displayCode: 'first-adventure',
        ),
      ],
      rewardOutcome: reward,
      pendingProjection: false,
    );

LearningSessionSummary _summary() => LearningSessionSummary(
  id: 'session:one',
  ownerId: 'owner:one',
  activityType: 'quiz',
  state: 'completed',
  startedAtUtc: DateTime.utc(2026, 9, 4, 10),
  endedAtUtc: DateTime.utc(2026, 9, 4, 10, 5),
  correctCount: 3,
  wrongCount: 1,
  score: 75,
  configurationActiveEffort: const Duration(minutes: 5),
);

const _rewardAccount = RewardAccount(
  coinBalance: 0,
  catalogVersion: RewardCatalog.version,
  ownedItemIds: <String>{},
  equippedBySlot: <String, String>{},
  transactionCount: 0,
);
