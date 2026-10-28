import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_host.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'support.dart';

void main() {
  late Harness h;
  late ValueNotifier<ManagedTutorIdentity?> identity;
  late StreamController<bool> network;
  late ManagedTutorHost host;
  late int cleanups;
  setUp(() {
    h = Harness();
    identity = ValueNotifier(
      const ManagedTutorIdentity('owner-a', 'account-a'),
    );
    network = StreamController<bool>(sync: true);
    cleanups = 0;
    host = ManagedTutorHost(
      controller: h.controller,
      identity: identity,
      network: network.stream,
      enabled: true,
      clearSession: () async {
        cleanups++;
      },
    );
  });
  tearDown(() async {
    host.dispose();
    identity.dispose();
    await network.close();
  });
  Future<void> ready() async {
    final pending = host.connect();
    await flush();
    h.transport.connections.last.complete();
    await pending;
  }

  test('disabled host never connects', () async {
    host.dispose();
    host = ManagedTutorHost(
      controller: Harness().controller,
      identity: identity,
      network: const Stream.empty(),
      clearSession: () async {},
    );
    await host.connect();
    expect(host.controller.state, ManagedTutorState.disconnected);
  });
  test(
    'account transition cancels pending reply and discards late text',
    () async {
      await ready();
      final pending = h.controller.send('bottle');
      await flush();
      identity.value = const ManagedTutorIdentity('owner-a', 'account-b');
      expect(h.controller.state, ManagedTutorState.disconnected);
      expect(h.transport.cancellations.last.isCancelled, isTrue);
      h.transport.replies.last.complete(
        const AiGatewayReply(text: 'private A'),
      );
      await pending;
      expect(h.controller.replyText, isNull);
      await flush();
      expect(cleanups, 1);
    },
  );
  test(
    'offline cancels and recovery does not automatically reconnect',
    () async {
      await ready();
      network.add(false);
      expect(h.controller.state, ManagedTutorState.offline);
      network.add(true);
      await flush();
      expect(h.transport.connections.length, 1);
      expect(h.controller.state, ManagedTutorState.offline);
      expect(cleanups, 1);
    },
  );
  test('route/background/logout fence connect and release sessions', () async {
    await ready();
    host.setVisible(false);
    await host.connect();
    expect(h.transport.connections.length, 1);
    host.setVisible(true);
    host.setForeground(false);
    await host.connect();
    expect(h.transport.connections.length, 1);
    host.setForeground(true);
    identity.value = null;
    await host.connect();
    expect(h.transport.connections.length, 1);
    expect(h.controller.replyText, isNull);
  });
  test(
    'dispose cancels pending connect and ignores subsequent events',
    () async {
      final pending = host.connect();
      await flush();
      host.dispose();
      h.transport.connections.single.complete();
      await pending;
      network.add(false);
      identity.value = null;
      expect(h.controller.state, ManagedTutorState.disconnected);
      await flush();
      expect(cleanups, 1);
    },
  );
}
