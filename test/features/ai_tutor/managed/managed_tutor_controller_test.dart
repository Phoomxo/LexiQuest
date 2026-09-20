import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'support.dart';

void main() {
  test('deadline remains visible while owner lookup is delayed', () async {
    final owner = Completer<String>();
    final gate = TestGate();
    final transport = TestTransport();
    final controller = ManagedTutorController(
      transport: transport,
      ownerCoordinator: OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () => owner.future,
      ),
      operationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    final work = controller.connect(ownerId: 'owner-a', accountId: 'a');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final stateAtDeadline = controller.state;
    owner.complete('owner-a');
    await work;
    await flush();
    expect(stateAtDeadline, ManagedTutorState.expired);
    expect(transport.connections, isEmpty);
    expect(gate.token, isNull);
  });
  test(
    'pending connection can be cancelled without waiting for transport',
    () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      final work = h.controller.connect(
        ownerId: h.owner,
        accountId: 'account-a',
      );
      expect(h.controller.state, ManagedTutorState.pending);
      await flush();
      h.controller.cancel();
      await work;
      expect(h.controller.state, ManagedTutorState.cancelled);
      expect(h.transport.cancellations.single.isCancelled, isTrue);
      await h.gate.firstRelease.future;
      expect(h.gate.token, isNull);
      h.transport.connections.single.complete();
      await flush();
      expect(h.controller.state, ManagedTutorState.cancelled);
    },
  );
  test('ready reply is published only after owner lease release', () async {
    final h = Harness();
    addTearDown(h.controller.dispose);
    await h.ready();
    final work = h.controller.send('bottle');
    await flush();
    expect(h.controller.state, ManagedTutorState.replying);
    h.transport.replies.single.complete(
      const AiGatewayReply(text: 'A bottle.'),
    );
    await work;
    expect(h.controller.replyText, 'A bottle.');
    expect(h.controller.state, ManagedTutorState.ready);
    expect(h.gate.token, isNull);
  });
  for (final duringReply in [false, true]) {
    test(
      'timeout expires ${duringReply ? 'reply' : 'connection'} and ignores late error',
      () async {
        final h = Harness();
        addTearDown(h.controller.dispose);
        if (duringReply) await h.ready();
        final work = duringReply
            ? h.controller.send('bottle')
            : h.controller.connect(ownerId: h.owner, accountId: 'a');
        await work;
        expect(h.controller.state, ManagedTutorState.expired);
        expect(h.transport.cancellations.last.isCancelled, isTrue);
        if (duringReply) {
          h.transport.replies.last.completeError(StateError('secret'));
        } else {
          h.transport.connections.last.completeError(StateError('secret'));
        }
        await flush();
        expect(h.controller.replyText, isNull);
        expect(h.gate.token, isNull);
      },
    );
  }
  for (final code in [
    AiFailureCode.offline,
    AiFailureCode.quota,
    AiFailureCode.providerUnavailable,
    AiFailureCode.cancelled,
    AiFailureCode.timeout,
  ]) {
    test('typed $code is terminal with no retry or fallback', () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await h.ready();
      final work = h.controller.send('bottle');
      await flush();
      h.transport.replies.single.completeError(AiTutorException(code));
      await work;
      final expected = switch (code) {
        AiFailureCode.offline => ManagedTutorState.offline,
        AiFailureCode.quota => ManagedTutorState.quotaExhausted,
        AiFailureCode.cancelled => ManagedTutorState.cancelled,
        AiFailureCode.timeout => ManagedTutorState.expired,
        _ => ManagedTutorState.providerUnavailable,
      };
      expect(h.controller.state, expected);
      await h.controller.send('retry');
      expect(h.transport.replies.length, 1);
      expect(h.controller.replyText, isNull);
    });
  }
  test('unknown exception never exposes provider details', () async {
    final h = Harness();
    addTearDown(h.controller.dispose);
    await h.ready();
    final work = h.controller.send('bottle');
    await flush();
    h.transport.replies.single.completeError(StateError('credential-secret'));
    await work;
    expect(h.controller.state, ManagedTutorState.providerUnavailable);
    expect(h.controller.replyText, isNull);
  });
  for (final action in [
    'cancel',
    'offline',
    'disconnect',
    'dispose',
    'account',
    'generation',
  ]) {
    test('$action fences a late reply and clears visible data', () async {
      final h = Harness();
      await h.ready();
      final oldGeneration = h.transport.bindings.first.generation;
      final work = h.controller.send('bottle');
      await flush();
      Future<void>? next;
      switch (action) {
        case 'cancel':
          h.controller.cancel();
        case 'offline':
          h.controller.setOffline();
        case 'disconnect':
          h.controller.disconnect();
        case 'dispose':
          h.controller.dispose();
        case 'account':
          next = h.controller.connect(ownerId: h.owner, accountId: 'account-b');
        case 'generation':
          next = h.controller.connect(ownerId: h.owner, accountId: 'account-a');
      }
      await work;
      await flush();
      h.transport.replies.single.complete(const AiGatewayReply(text: 'STALE'));
      await flush();
      expect(h.controller.replyText, isNull);
      if (next != null) {
        await h.transport.waitConnections(2);
        h.transport.connections.last.complete();
        await next;
        expect(
          h.transport.bindings.last.generation,
          greaterThan(oldGeneration),
        );
        expect(h.controller.state, ManagedTutorState.ready);
      }
      if (action != 'dispose') h.controller.dispose();
    });
  }
  test(
    'unannounced active owner switch rejects reply and future dispatch',
    () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await h.ready();
      final work = h.controller.send('bottle');
      await flush();
      h.owner = 'owner-b';
      h.transport.replies.single.complete(const AiGatewayReply(text: 'STALE'));
      await work;
      expect(h.controller.replyText, isNull);
      expect(h.controller.state, ManagedTutorState.cancelled);
      await h.controller.connect(ownerId: 'owner-a', accountId: 'a');
      expect(h.transport.connections.length, 1);
    },
  );
  test(
    'owner notification immediately clears old display and cancels pending work',
    () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await h.ready();
      final work = h.controller.send('bottle');
      await flush();
      h.controller.ownerChanged();
      await work;
      expect(h.controller.state, ManagedTutorState.disconnected);
      expect(h.controller.replyText, isNull);
    },
  );
  test('lease loss prevents result publication', () async {
    final h = Harness();
    addTearDown(h.controller.dispose);
    await h.ready();
    final work = h.controller.send('bottle');
    await flush();
    h.gate.lost = true;
    h.transport.replies.single.complete(const AiGatewayReply(text: 'STALE'));
    await work;
    expect(h.controller.state, ManagedTutorState.cancelled);
    expect(h.controller.replyText, isNull);
  });
  test(
    'empty input and concurrent send do not dispatch additional requests',
    () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await h.ready();
      await h.controller.send(' ');
      expect(h.transport.replies, isEmpty);
      final work = h.controller.send('bottle');
      await flush();
      await h.controller.send('second');
      expect(h.transport.replies.length, 1);
      h.controller.cancel();
      await work;
    },
  );
  test('disposed controller cannot reconnect or send', () async {
    final h = Harness();
    h.controller.dispose();
    await h.controller.connect(ownerId: h.owner, accountId: 'a');
    await h.controller.send('bottle');
    expect(h.transport.connections, isEmpty);
    expect(h.transport.replies, isEmpty);
  });
  test('empty or oversized reply fails closed', () async {
    for (final text in ['', 'x' * 16001]) {
      final h = Harness();
      await h.ready();
      final work = h.controller.send('bottle');
      await flush();
      h.transport.replies.single.complete(AiGatewayReply(text: text));
      await work;
      expect(h.controller.state, ManagedTutorState.providerUnavailable);
      expect(h.controller.replyText, isNull);
      h.controller.dispose();
    }
  });
}
