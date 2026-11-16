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
    if (timestampComparison < 0 ||
        (timestampComparison == 0 &&
            cursor.documentId.compareTo(last.entityId) < 0)) {
      throw ArgumentError.value(
        nextCursor,
        'nextCursor',
        'must not regress behind the final change',
      );
    }
  }

  final List<SyncEntity> changes;
  final SyncCursor? nextCursor;
  final bool hasMore;
}
