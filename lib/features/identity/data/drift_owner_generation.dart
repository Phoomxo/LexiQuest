import '../../../data/local/app_database.dart';
import '../../../runtime/runtime_flag_namespaces.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Device-global opaque epoch, updated in the same transaction as every
/// canonical owner transition. No owner ID, credential or research data.
final class DriftOwnerGeneration {
  const DriftOwnerGeneration(this.database);
  final AppDatabase database;
  Future<String> read() async {
    final row =
        await (database.select(database.runtimeFlags)..where(
              (r) => r.key.equals(RuntimeFlagNamespaces.ownerGeneration),
            ))
            .getSingleOrNull();
    if (row == null) return 'initial';
    if (!row.source.startsWith('owner-generation-v1:') ||
        row.source.length != 56 ||
        !row.boolValue ||
        row.expiresAtUtcMs != null) {
      throw StateError('Invalid durable owner generation');
    }
    return row.source;
  }

  /// Caller holds the canonical owner lease and an owner mutation transaction.
  Future<void> advance() => database
      .into(database.runtimeFlags)
      .insertOnConflictUpdate(
        RuntimeFlagsCompanion.insert(
          key: RuntimeFlagNamespaces.ownerGeneration,
          boolValue: true,
          source: Value('owner-generation-v1:${const Uuid().v4()}'),
          updatedAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          expiresAtUtcMs: const Value(null),
        ),
      )
      .then((_) {});
}
