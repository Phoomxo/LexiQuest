import 'sync_entity.dart';

sealed class PushResult {
  const PushResult();
}

final class PushAcknowledged extends PushResult {
  PushAcknowledged({
    required String operationId,
    required this.resultingRevision,
    required this.acknowledgedAtUtc,
  }) : operationId = operationId.trim() {
    if (this.operationId.isEmpty) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'must not be blank',
      );
    }
    if (resultingRevision < 0) {
      throw ArgumentError.value(
        resultingRevision,
        'resultingRevision',
        'must not be negative',
      );
    }
    if (!acknowledgedAtUtc.isUtc) {
      throw ArgumentError.value(
        acknowledgedAtUtc,
        'acknowledgedAtUtc',
        'must be UTC',
      );
    }
  }

  final String operationId;
  final int resultingRevision;
  final DateTime acknowledgedAtUtc;
}

final class PushConflict extends PushResult {
  const PushConflict(this.cloudEntity);

  final SyncEntity cloudEntity;
}

final class PullPage {
  PullPage({
    required List<SyncEntity> changes,
    required this.nextCursor,
    required this.hasMore,
  }) : changes = List<SyncEntity>.unmodifiable(changes) {
    if (this.changes.isEmpty) return;
    final entityIds = <String>{};
    SyncEntity? previous;
    for (final change in this.changes) {
      if (!entityIds.add(change.entityId)) {
        throw ArgumentError.value(
          changes,
          'changes',
          'must contain unique entity ids',
        );
      }
      final preceding = previous;
      if (preceding != null) {
        final timestampComparison = change.serverUpdatedAtUtc.compareTo(
          preceding.serverUpdatedAtUtc,
        );
        final followsPreceding =
            timestampComparison > 0 ||
            (timestampComparison == 0 &&
                change.entityId.compareTo(preceding.entityId) > 0);
        if (!followsPreceding) {
          throw ArgumentError.value(
            changes,
            'changes',
            'must be strictly ordered by server timestamp and entity id',
          );
        }
      }
      previous = change;
    }
    final cursor = nextCursor;
    if (cursor == null) {
      throw ArgumentError.value(
        nextCursor,
        'nextCursor',
        'must be present when changes are returned',
      );
    }
    final last = this.changes.last;
    final timestampComparison = cursor.serverUpdatedAtUtc.compareTo(
      last.serverUpdatedAtUtc,
    );
    if (timestampComparison != 0 || cursor.documentId != last.entityId) {
      throw ArgumentError.value(
        nextCursor,
        'nextCursor',
        'must equal the final delivered change tuple',
      );
    }
  }

  final List<SyncEntity> changes;
  final SyncCursor? nextCursor;
  final bool hasMore;
}
