import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_motivation_projection_reader.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_result_next_action_reader.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_lifecycle_screen.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_screen.dart';
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
            nextActionReader: _NextActionReader.value(AdventureNextAction.none),
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
          nextActionReader: _NextActionReader.value(AdventureNextAction.none),
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
          nextActionReader: _NextActionReader.value(AdventureNextAction.none),
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
          nextActionReader: _NextActionReader.value(AdventureNextAction.none),
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
          nextActionReader: _NextActionReader.value(AdventureNextAction.none),
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('รางวัลหลักกำลังยืนยัน'), findsOneWidget);
    expect(find.text('รางวัลหลักได้รับการยืนยันแล้ว'), findsNothing);
  });

  testWidgets('SRS action survives exhausted reward projection retries', (
    tester,
  ) async {
    final diagnostics = AdventureDiagnostics();
    final actionReader = _NextActionReader.value(
      AdventureNextAction.spacedRepetition,
    );
    final refresher = _Refresher(
      Future<void>.delayed(Duration.zero, () => throw StateError('offline')),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdventureResultLifecycleScreen(
          summary: _summary(),
          motivation: _Reader(const <AdventureMotivationSnapshot>[]),
          receiptBarrier: refresher,
          nextActionReader: actionReader,
          diagnostics: diagnostics,
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(actionReader.ownerIds, <String>['owner:one']);
    expect(find.textContaining('รางวัลหลักกำลังยืนยัน'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('adventure-result-next-action')),
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.text('ซิงก์รางวัลยังไม่สำเร็จ ลองใหม่ภายหลังได้'),
      findsOneWidget,
    );
    expect(find.text('ไปทบทวนแบบเว้นระยะ'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('adventure-result-next-action')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'next-action failure preserves a committed reward and disables action',
    (tester) async {
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
            receiptBarrier: _Refresher(Future<void>.value()),
            nextActionReader: _NextActionReader.error(
              StateError('review unavailable'),
            ),
            rewardOwnership: _rewardAccount,
            onNextAction: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('รางวัลหลักได้รับการยืนยันแล้ว'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('adventure-result-next-action')),
        160,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('เสร็จแล้ว'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('adventure-result-next-action')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'late results are fenced by owner session and reader identity updates',
    (tester) async {
      final oldResult = Completer<AdventureNextAction>();
      final replacedReaderResult = Completer<AdventureNextAction>();
      final oldReader = _NextActionReader.future(oldResult.future);
      final replacedReader = _NextActionReader.future(
        replacedReaderResult.future,
      );
      final currentReader = _NextActionReader.value(
        AdventureNextAction.reviewCenter,
      );
      final motivation = _Reader(<AdventureMotivationSnapshot>[
        _snapshot(
          const AdventureProjectionOutcome(
            state: AdventureProjectionReceiptState.committed,
            receiptId: 'learning-projection:reward:event:one:v2',
          ),
        ),
      ]);
      final barrier = _Refresher(Future<void>.value());
      Widget app(
        LearningSessionSummary summary,
        AdventureResultNextActionReader nextActionReader,
      ) => MaterialApp(
        home: AdventureResultLifecycleScreen(
          key: const ValueKey('result-lifecycle'),
          summary: summary,
          motivation: motivation,
          receiptBarrier: barrier,
          nextActionReader: nextActionReader,
          rewardOwnership: _rewardAccount,
          onNextAction: () {},
        ),
      );

      await tester.pumpWidget(app(_summary(), oldReader));
      await tester.pump();
      expect(oldReader.ownerIds, <String>['owner:one']);
      expect(
        tester
            .widget<AdventureResultScreen>(find.byType(AdventureResultScreen))
            .result
            .nextAction,
        AdventureNextAction.none,
      );

      final replacementSummary = _summary(
        ownerId: 'owner:two',
        sessionId: 'session:two',
      );
      await tester.pumpWidget(app(replacementSummary, replacedReader));
      await tester.pump();
      expect(replacedReader.ownerIds, <String>['owner:two']);
      expect(
        tester
            .widget<AdventureResultScreen>(find.byType(AdventureResultScreen))
            .result
            .nextAction,
        AdventureNextAction.none,
      );

      await tester.pumpWidget(app(replacementSummary, currentReader));
      await tester.pumpAndSettle();
      expect(currentReader.ownerIds, <String>['owner:two']);
      expect(
        tester
            .widget<AdventureResultScreen>(find.byType(AdventureResultScreen))
            .result
            .nextAction,
        AdventureNextAction.reviewCenter,
      );

      oldResult.complete(AdventureNextAction.spacedRepetition);
      replacedReaderResult.complete(AdventureNextAction.spacedRepetition);
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<AdventureResultScreen>(find.byType(AdventureResultScreen))
            .result
            .nextAction,
        AdventureNextAction.reviewCenter,
      );
    },
  );

  testWidgets('none action cannot invoke its navigation callback', (
    tester,
  ) async {
    var callbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => AdventureResultLifecycleScreen(
            summary: _summary(),
            motivation: _Reader(const <AdventureMotivationSnapshot>[]),
            receiptBarrier: _Refresher(Future<void>.value()),
            nextActionReader: _NextActionReader.value(AdventureNextAction.none),
            rewardOwnership: _rewardAccount,
            onNextAction: () {
              callbacks += 1;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Text('review destination'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('adventure-result-next-action'));
    await tester.scrollUntilVisible(
      action,
      160,
      scrollable: find.byType(Scrollable),
    );
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(callbacks, 0);
    expect(find.text('review destination'), findsNothing);
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

final class _NextActionReader implements AdventureResultNextActionReader {
  _NextActionReader.value(AdventureNextAction value)
    : _read = (() async => value);

  _NextActionReader.error(Object error)
    : _read = (() => Future<AdventureNextAction>.error(error));

  _NextActionReader.future(Future<AdventureNextAction> future)
    : _read = (() => future);

  final Future<AdventureNextAction> Function() _read;
  final List<String> ownerIds = <String>[];

  @override
  Future<AdventureNextAction> read({required String ownerId}) {
    ownerIds.add(ownerId);
    return _read();
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

LearningSessionSummary _summary({
  String ownerId = 'owner:one',
  String sessionId = 'session:one',
}) => LearningSessionSummary(
  id: sessionId,
  ownerId: ownerId,
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
