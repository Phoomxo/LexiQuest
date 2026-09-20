import 'dart:async';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/managed_tutor_transport.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';

class TestGate implements OwnerOperationGate {
  final firstRelease = Completer<void>();
  String? token;
  bool lost = false;
  int releases = 0;
  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    if (this.token != null) return false;
    this.token = token;
    return true;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => !lost && this.token == token;
  @override
  Future<bool> isOwned({
    required String token,
    required DateTime nowUtc,
  }) async => !lost && this.token == token;
  @override
  Future<void> release({required String token}) async {
    if (this.token == token) this.token = null;
    releases++;
    if (!firstRelease.isCompleted) firstRelease.complete();
  }
}

class TestTransport implements ManagedTutorTransport {
  Completer<void> _connectionChanged = Completer<void>();
  Future<void> waitConnections(int count) async {
    while (connections.length < count) {
      await _connectionChanged.future;
    }
  }

  final connections = <Completer<void>>[];
  final replies = <Completer<AiGatewayReply>>[];
  final bindings = <ManagedTutorBinding>[];
  final cancellations = <AiCancellation>[];
  @override
  Future<void> connect({
    required ManagedTutorBinding binding,
    required AiCancellation cancellation,
  }) {
    bindings.add(binding);
    cancellations.add(cancellation);
    final value = Completer<void>();
    connections.add(value);
    _connectionChanged.complete();
    _connectionChanged = Completer<void>();
    return value.future;
  }

  @override
  Future<AiGatewayReply> reply({
    required ManagedTutorBinding binding,
    required String learnerMessage,
    required AiCancellation cancellation,
  }) {
    bindings.add(binding);
    cancellations.add(cancellation);
    final value = Completer<AiGatewayReply>();
    replies.add(value);
    return value.future;
  }
}

class Harness {
  String owner = 'owner-a';
  final gate = TestGate();
  final transport = TestTransport();
  late final controller = ManagedTutorController(
    transport: transport,
    ownerCoordinator: OwnerOperationCoordinator(
      gate: gate,
      activeOwnerId: () async => owner,
    ),
    operationTimeout: const Duration(milliseconds: 100),
  );
  Future<void> ready() async {
    final work = controller.connect(ownerId: owner, accountId: 'account-a');
    await flush();
    transport.connections.last.complete();
    await work;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
