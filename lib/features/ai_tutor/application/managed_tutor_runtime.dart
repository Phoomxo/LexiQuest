import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../data/local/app_database.dart';
import '../../../runtime/runtime_flag_namespaces.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../domain/managed_tutor_transport.dart';
import 'managed_tutor_controller.dart';
import 'managed_tutor_host.dart';
import 'owner_operation_coordinator.dart';

/// Opt-in host bound to canonical owner/account and durable owner epoch watches.
/// Does not own the database or register itself in production dependencies.
final class ManagedTutorRuntime {
  ManagedTutorRuntime({
    required AppDatabase database,
    required ManagedTutorTransport transport,
    required Stream<bool> network,
    required Future<void> Function() clearSession,
    Duration operationTimeout = const Duration(seconds: 30),
  }) {
    final query = database.select(database.localOwners)
      ..where((row) => row.isActive.equals(true));
    final controller = ManagedTutorController(
      operationTimeout: operationTimeout,
      transport: transport,
      ownerCoordinator: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(database),
        activeOwnerId: () async {
          final owners = await query.get();
          if (owners.length != 1) throw StateError('Active owner unavailable');
          return owners.single.id;
        },
      ),
    );
    host = ManagedTutorHost(
      controller: controller,
      identity: identity,
      network: network,
      enabled: true,
      clearSession: clearSession,
    );
    _owners = query.watch().listen(
      (rows) {
        final previous = identity.value;
        final owner = rows.length == 1 ? rows.single : null;
        final account = owner?.firebaseUid ?? owner?.id;
        if (previous?.ownerId != owner?.id || previous?.accountId != account) {
          identity.value = owner == null
              ? null
              : ManagedTutorIdentity(owner.id, account!);
        }
      },
      onError: (Object _) {
        identity.value = null;
      },
    );
    _epoch =
        (database.select(database.runtimeFlags)..where(
              (r) => r.key.equals(RuntimeFlagNamespaces.ownerGeneration),
            ))
            .watchSingleOrNull()
            .distinct()
            .listen(
              (_) {
                final current = identity.value;
                if (current != null) {
                  identity.value = ManagedTutorIdentity(
                    current.ownerId,
                    current.accountId,
                  );
                }
              },
              onError: (Object _) {
                identity.value = null;
              },
            );
  }
  final identity = ValueNotifier<ManagedTutorIdentity?>(null);
  late final ManagedTutorHost host;
  late final StreamSubscription<Object?> _owners, _epoch;
  Future<void> dispose() async {
    host.dispose();
    await _owners.cancel();
    await _epoch.cancel();
    identity.dispose();
  }
}
