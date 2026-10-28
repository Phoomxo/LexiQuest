import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';

void main() {
  test('acquires before recovery, owner resolution, and body', () async {
    final gate = _CoordinatorGate();
    final events = <String>[];
    final coordinator = OwnerOperationCoordinator(
      gate: gate,
      activeOwnerId: () async {
        expect(gate.owned, isTrue);
        events.add('owner');
        return 'owner-a';
      },
      generateToken: () => 'token',
      recoverPending: (cutoff, {required recoveredAtUtc}) async {
        expect(gate.owned, isTrue);
        events.add('recover');
        return 0;
      },
    );

    final value = await coordinator.run(AiCancellation(), (ownerId) async {
      events.add('body:$ownerId');
      expect(OwnerOperationCoordinator.currentLeaseToken, 'token');
      return 7;
    });

    expect(value, 7);
    expect(events, <String>['recover', 'owner', 'body:owner-a']);
    expect(gate.releaseCalls, 1);
  });

  test('heartbeat loss cancels then drains body before releasing', () async {
    final gate = _CoordinatorGate(renewResult: false);
    final bodyStarted = Completer<void>();
    final allowBodyToDrain = Completer<void>();
    final cancellation = AiCancellation();
    final coordinator = OwnerOperationCoordinator(
      gate: gate,
      activeOwnerId: () async => 'owner-a',
      generateToken: () => 'token',
      leaseDuration: const Duration(milliseconds: 100),
      heartbeatInterval: const Duration(milliseconds: 5),
    );

    var completed = false;
    final running = coordinator
        .run(cancellation, (_) async {
          bodyStarted.complete();
          await allowBodyToDrain.future;
          throw const AiTutorException(AiFailureCode.cancelled);
        })
        .whenComplete(() => completed = true);
    final expectation = expectLater(
      running,
      throwsA(_aiFailure(AiFailureCode.cancelled)),
    );
    await bodyStarted.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cancellation.isCancelled, isTrue);
    expect(completed, isFalse);
    expect(gate.releaseCalls, 0);
    allowBodyToDrain.complete();
    await expectation;
    expect(gate.releaseCalls, 1);
  });

  test('cancelled heartbeat cannot skip exactly-once release', () async {
    final gate = _CoordinatorGate();
    final cancellation = AiCancellation();
    final coordinator = OwnerOperationCoordinator(
      gate: gate,
      activeOwnerId: () async => 'owner-a',
      generateToken: () => 'token',
    );

    await expectLater(
      coordinator.run(cancellation, (_) async {
        cancellation.cancel();
        throw const AiTutorException(AiFailureCode.cancelled);
      }),
      throwsA(_aiFailure(AiFailureCode.cancelled)),
    );

    expect(gate.releaseCalls, 1);
  });

  test(
    'external cancellation keeps heartbeat alive until body drain',
    () async {
      final gate = _CoordinatorGate();
      final bodyStarted = Completer<void>();
      final allowBodyToDrain = Completer<void>();
      final cancellation = AiCancellation();
      final coordinator = OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => 'owner-a',
        generateToken: () => 'token',
        leaseDuration: const Duration(milliseconds: 100),
        heartbeatInterval: const Duration(milliseconds: 5),
      );

      final running = coordinator.run(cancellation, (_) async {
        bodyStarted.complete();
        await allowBodyToDrain.future;
        return 7;
      });
      final expectation = expectLater(
        running,
        throwsA(_aiFailure(AiFailureCode.cancelled)),
      );
      await bodyStarted.future;
      cancellation.cancel();
      try {
        await gate.firstRenew.future.timeout(const Duration(seconds: 1));
        expect(gate.releaseCalls, 0);
      } finally {
        if (!allowBodyToDrain.isCompleted) allowBodyToDrain.complete();
      }
      await expectation;
      expect(gate.renewCalls, greaterThanOrEqualTo(1));
      expect(gate.releaseCalls, 1);
    },
  );

  test('late lease loss preserves a committed provider result', () async {
    final gate = _CoordinatorGate(renewResult: false);
    final resultCommitted = Completer<void>();
    final allowBodyToReturn = Completer<void>();
    final cancellation = AiCancellation();
    final coordinator = OwnerOperationCoordinator(
      gate: gate,
      activeOwnerId: () async => 'owner-a',
      generateToken: () => 'token',
      leaseDuration: const Duration(milliseconds: 100),
      heartbeatInterval: const Duration(milliseconds: 5),
    );

    final running = coordinator.run(cancellation, (_) async {
      coordinator.markCurrentOperationResultCommitted();
      resultCommitted.complete();
      await allowBodyToReturn.future;
      return 7;
    });
    await resultCommitted.future;
    await gate.firstRenew.future.timeout(const Duration(seconds: 1));
    try {
      await cancellation.whenCancelled.timeout(const Duration(seconds: 1));
    } finally {
      if (!allowBodyToReturn.isCompleted) allowBodyToReturn.complete();
    }

    expect(await running, 7);
    expect(gate.releaseCalls, 1);
  });
}

Matcher _aiFailure(AiFailureCode code) =>
    isA<AiTutorException>().having((error) => error.code, 'code', code);

final class _CoordinatorGate implements OwnerOperationGate {
  _CoordinatorGate({this.renewResult = true});

  final bool renewResult;
  bool owned = false;
  int releaseCalls = 0;
  int renewCalls = 0;
  final Completer<void> firstRenew = Completer<void>();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    owned = true;
    return true;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    renewCalls++;
    if (!firstRenew.isCompleted) firstRenew.complete();
    if (!renewResult) owned = false;
    return renewResult;
  }

  @override
  Future<bool> isOwned({
    required String token,
    required DateTime nowUtc,
  }) async => owned;

  @override
  Future<void> release({required String token}) async {
    releaseCalls++;
    owned = false;
  }
}
