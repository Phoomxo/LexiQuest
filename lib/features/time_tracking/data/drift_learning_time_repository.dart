import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/domain/local_owner_repository.dart';
import '../domain/learning_time_repository.dart';
import '../domain/learning_time_segment.dart';

typedef LearningTimeMutationNotifier = Future<void> Function();

final class DriftLearningTimeRepository implements LearningTimeRepository {
  DriftLearningTimeRepository(
    this.database, {
    required this.owners,
    this.onLocalMutation,
  });

  final db.AppDatabase database;
  final LocalOwnerRepository owners;
  final LearningTimeMutationNotifier? onLocalMutation;

  @override
  Future<void> append(LearningTimeSegment segment) async {
    await owners.getOrCreateActiveOwner();
    final changed = await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final session = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(segment.sessionId))).getSingleOrNull();
      if (session == null || session.ownerId != ownerId) {
        throw StateError('learning-time session is not owned by active owner');
      }

      final existing = await (database.select(
        database.learningTimeSegments,
      )..where((row) => row.id.equals(segment.id))).getSingleOrNull();
      if (existing != null) {
        if (!_matches(existing, ownerId, segment)) {
          throw StateError(
            'learning-time identity was reused with different semantics',
          );
        }
        return false;
      }

      final expectedOffset = await _activeDurationMs(segment.sessionId);
      if (segment.activeStartOffset.inMilliseconds != expectedOffset) {
        throw StateError('learning-time segment is noncontiguous or overlaps');
      }
      final start = segment.activeStartOffset.inMilliseconds;
      final end = start + segment.activeDuration.inMilliseconds;
      final overlap = await database
          .customSelect(
            'SELECT 1 AS present FROM learning_time_segments '
            'WHERE session_id = ? '
            'AND active_start_offset_ms < ? '
            'AND active_start_offset_ms + active_duration_ms > ? LIMIT 1',
            variables: <Variable<Object>>[
              Variable<String>(segment.sessionId),
              Variable<int>(end),
              Variable<int>(start),
            ],
            readsFrom: {database.learningTimeSegments},
          )
          .getSingleOrNull();
      if (overlap != null) {
        throw StateError('learning-time segments must not overlap');
      }

      await database
          .into(database.learningTimeSegments)
          .insert(
            db.LearningTimeSegmentsCompanion.insert(
              id: segment.id,
              ownerId: ownerId,
              sessionId: segment.sessionId,
              activeStartOffsetMs: start,
              activeDurationMs: segment.activeDuration.inMilliseconds,
              startedAtUtcMs: segment.startedAtUtc.millisecondsSinceEpoch,
              endedAtUtcMs: segment.endedAtUtc.millisecondsSinceEpoch,
              timezoneId: segment.timezone.timezoneId,
              timezoneOffsetMinutes: segment.timezone.utcOffsetMinutes,
              captureSource: segment.captureSource.name,
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: LearningTimeSegment.canonicalOperationId(segment.id),
              ownerId: ownerId,
              entityType: 'learningTimeSegment',
              entityId: segment.id,
              operationKind: 'upsert',
              createdAtUtcMs: segment.endedAtUtc.millisecondsSinceEpoch,
            ),
          );
      return true;
    });
    if (changed) await onLocalMutation?.call();
  }

  @override
  Future<Duration> activeDuration(String sessionId) async {
    _requireCanonicalId(sessionId);
    return database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final session = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
      if (session == null || session.ownerId != ownerId) {
        throw StateError('learning-time session is not owned by active owner');
      }
      return Duration(milliseconds: await _activeDurationMs(sessionId));
    });
  }

  Future<int> _activeDurationMs(String sessionId) async {
    final rows = await database
        .customSelect(
          'SELECT active_start_offset_ms, active_duration_ms '
          'FROM learning_time_segments WHERE session_id = ? '
          'ORDER BY active_start_offset_ms, id',
          variables: [Variable<String>(sessionId)],
          readsFrom: {database.learningTimeSegments},
        )
        .get();
    var contiguousDurationMs = 0;
    for (final row in rows) {
      final offset = row.read<int>('active_start_offset_ms');
      final duration = row.read<int>('active_duration_ms');
      if (offset != contiguousDurationMs ||
          duration <= 0 ||
          duration > LearningTimeSegment.maximumActiveDuration.inMilliseconds) {
        throw StateError('learning-time history is not contiguous');
      }
      contiguousDurationMs += duration;
    }
    return contiguousDurationMs;
  }

  Future<String> _requireSingleActiveOwnerId() async {
    final owners =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1) {
      throw StateError('exactly one active local owner is required');
    }
    return owners.single.id;
  }

  bool _matches(
    db.LearningTimeSegmentRow row,
    String ownerId,
    LearningTimeSegment segment,
  ) =>
      row.ownerId == ownerId &&
      row.sessionId == segment.sessionId &&
      row.activeStartOffsetMs == segment.activeStartOffset.inMilliseconds &&
      row.activeDurationMs == segment.activeDuration.inMilliseconds &&
      row.startedAtUtcMs == segment.startedAtUtc.millisecondsSinceEpoch &&
      row.endedAtUtcMs == segment.endedAtUtc.millisecondsSinceEpoch &&
      row.timezoneId == segment.timezone.timezoneId &&
      row.timezoneOffsetMinutes == segment.timezone.utcOffsetMinutes &&
      row.captureSource == segment.captureSource.name;

  void _requireCanonicalId(String value) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw ArgumentError.value(value, 'sessionId', 'must be canonical text');
    }
  }
}
