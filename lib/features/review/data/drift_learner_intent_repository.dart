import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/domain/local_owner_repository.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/learner_intent.dart';
import '../domain/learner_intent_repository.dart';

typedef LearnerIntentUtcNow = DateTime Function();
typedef LearnerIntentMutationNotifier = Future<void> Function();

final class DriftLearnerIntentRepository implements LearnerIntentRepository {
  DriftLearnerIntentRepository(
    this.database, {
    required this.owners,
    required this.nowUtc,
    this.onLocalMutation,
  });

  final db.AppDatabase database;
  final LocalOwnerRepository owners;
  final LearnerIntentUtcNow nowUtc;
  final LearnerIntentMutationNotifier? onLocalMutation;

  @override
  Future<void> save(SaveLearningItemCommand command) async {
    _requireCanonicalText(command.id, 'command.id');
    _requireContentIdentity(command.contentIdentity);
    _requireUtc(command.savedAtUtc, 'command.savedAtUtc');
    await owners.getOrCreateActiveOwner();

    final changed = await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final existing = await _byNaturalKey(ownerId, command.contentIdentity);
      if (existing != null) {
        if (!existing.isDeleted) return false;
        final savedAtMs = command.savedAtUtc.millisecondsSinceEpoch;
        if (savedAtMs < existing.updatedAtUtcMs) {
          throw ArgumentError.value(
            command.savedAtUtc,
            'command.savedAtUtc',
            'must not precede the current tombstone',
          );
        }
        final revision = await _nextLocalRevision(existing);
        await (database.update(
          database.savedLearningItems,
        )..where((row) => row.id.equals(existing.id))).write(
          db.SavedLearningItemsCompanion(
            updatedAtUtcMs: Value(savedAtMs),
            localRevision: Value(revision),
            isDeleted: const Value(false),
          ),
        );
        await _appendOutbox(
          ownerId: ownerId,
          entityId: existing.id,
          operationKind: 'upsert',
          baseRevision: existing.cloudRevision,
          revision: revision,
          occurredAtUtcMs: savedAtMs,
        );
        return true;
      }

      final conflictingId = await (database.select(
        database.savedLearningItems,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (conflictingId != null) {
        throw ArgumentError.value(command.id, 'command.id', 'already in use');
      }
      final savedAtMs = command.savedAtUtc.millisecondsSinceEpoch;
      await database
          .into(database.savedLearningItems)
          .insert(
            db.SavedLearningItemsCompanion.insert(
              id: command.id,
              ownerId: ownerId,
              contentType: command.contentIdentity.type.name,
              contentId: command.contentIdentity.id,
              contentRevision: command.contentIdentity.revision,
              savedAtUtcMs: savedAtMs,
              updatedAtUtcMs: savedAtMs,
            ),
          );
      await _appendOutbox(
        ownerId: ownerId,
        entityId: command.id,
        operationKind: 'upsert',
        baseRevision: 0,
        revision: 1,
        occurredAtUtcMs: savedAtMs,
      );
      return true;
    });
    if (changed) await onLocalMutation?.call();
  }

  @override
  Future<void> unsave(ContentIdentity identity) async {
    _requireContentIdentity(identity);
    final occurredAt = nowUtc();
    _requireUtc(occurredAt, 'nowUtc');
    final occurredAtMs = occurredAt.millisecondsSinceEpoch;
    await owners.getOrCreateActiveOwner();

    final changed = await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final existing = await _byNaturalKey(ownerId, identity);
      if (existing == null || existing.isDeleted) return false;
      if (occurredAtMs < existing.updatedAtUtcMs) {
        throw StateError('learner intent clock moved backwards');
      }
      final revision = await _nextLocalRevision(existing);
      await (database.update(
        database.savedLearningItems,
      )..where((row) => row.id.equals(existing.id))).write(
        db.SavedLearningItemsCompanion(
          updatedAtUtcMs: Value(occurredAtMs),
          localRevision: Value(revision),
          isDeleted: const Value(true),
        ),
      );
      await _appendOutbox(
        ownerId: ownerId,
        entityId: existing.id,
        operationKind: 'delete',
        baseRevision: existing.cloudRevision,
        revision: revision,
        occurredAtUtcMs: occurredAtMs,
      );
      return true;
    });
    if (changed) await onLocalMutation?.call();
  }

  Future<String> _requireSingleActiveOwnerId() async {
    final activeOwners =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (activeOwners.length != 1) {
      throw StateError('exactly one active local owner is required');
    }
    return activeOwners.single.id;
  }

  Future<db.SavedLearningItemRow?> _byNaturalKey(
    String ownerId,
    ContentIdentity identity,
  ) =>
      (database.select(database.savedLearningItems)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.contentType.equals(identity.type.name) &
                row.contentId.equals(identity.id) &
                row.contentRevision.equals(identity.revision),
          ))
          .getSingleOrNull();

  Future<void> _appendOutbox({
    required String ownerId,
    required String entityId,
    required String operationKind,
    required int baseRevision,
    required int revision,
    required int occurredAtUtcMs,
  }) => database
      .into(database.outboxOperations)
      .insert(
        db.OutboxOperationsCompanion.insert(
          operationId: 'savedLearningItem:$entityId:$revision',
          ownerId: ownerId,
          entityType: 'savedLearningItem',
          entityId: entityId,
          operationKind: operationKind,
          baseRevision: Value(baseRevision),
          createdAtUtcMs: occurredAtUtcMs,
        ),
      );

  Future<int> _nextLocalRevision(db.SavedLearningItemRow item) async {
    final operations =
        await (database.select(database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(item.ownerId) &
                  row.entityType.equals('savedLearningItem') &
                  row.entityId.equals(item.id),
            ))
            .get();
    var highestRevision = item.localRevision;
    for (final operation in operations) {
      final parsedRevision = int.tryParse(
        operation.operationId.split(':').last,
      );
      final operationRevision = parsedRevision != null && parsedRevision > 0
          ? parsedRevision
          : operation.baseRevision + 1;
      if (operationRevision > highestRevision) {
        highestRevision = operationRevision;
      }
    }
    return highestRevision + 1;
  }

  void _requireContentIdentity(ContentIdentity identity) {
    _requireCanonicalText(identity.id, 'identity.id');
    if (identity.revision <= 0) {
      throw ArgumentError.value(
        identity.revision,
        'identity.revision',
        'must be positive',
      );
    }
  }

  void _requireCanonicalText(String value, String name) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw ArgumentError.value(value, name, 'must be canonical nonblank text');
    }
  }

  void _requireUtc(DateTime value, String name) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, name, 'must be a nonnegative UTC time');
    }
  }
}
