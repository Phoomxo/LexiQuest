import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../domain/ai_tutor_contracts.dart';

typedef ActiveOwnerIdProvider = Future<String> Function();
typedef ActiveOwnerLeaseToken = String? Function();

final class DriftAiUsageRepository implements AiUsageRepository {
  DriftAiUsageRepository(
    this._database, {
    required this.activeOwnerId,
    this.activeOwnerLeaseToken,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? _defaultNowUtc;

  static const retention = Duration(days: 90);

  final AppDatabase _database;
  final ActiveOwnerIdProvider activeOwnerId;
  final ActiveOwnerLeaseToken? activeOwnerLeaseToken;
  final DateTime Function() _nowUtc;

  @override
  Future<void> beginForOwner(String ownerId, AiUsageAttempt attempt) async {
    await _database.transaction(() async {
      await _requireOwnedLease();
      await _database
          .into(_database.aiUsageEvents)
          .insert(
            AiUsageEventsCompanion.insert(
              eventId: attempt.eventId,
              ownerId: _requireOwnerId(ownerId),
              occurredAtUtcMs: attempt.occurredAtUtc.millisecondsSinceEpoch,
              providerId: attempt.providerId.name,
              model: attempt.model,
              requestType: attempt.requestType,
              outcome: 'pending',
              errorCategory: const Value<String?>(null),
              latencyMs: 0,
              inputTokens: const Value<int?>(null),
              outputTokens: const Value<int?>(null),
              totalTokens: const Value<int?>(null),
              cachedTokens: const Value<int?>(null),
              providerReportedCostMicrosUsd: const Value<int?>(null),
              schemaVersion: Value(attempt.schemaVersion),
            ),
          );
    });
  }

  @override
  Future<AiUsageFinalizeResult> finalizeForOwner(
    String ownerId,
    AiUsageCompletion completion,
  ) {
    final normalizedOwnerId = _requireOwnerId(ownerId);
    return _database.transaction(() async {
      await _requireOwnedLease();
      final changed =
          await (_database.update(_database.aiUsageEvents)..where(
                (row) =>
                    row.ownerId.equals(normalizedOwnerId) &
                    row.eventId.equals(completion.eventId) &
                    row.outcome.equals('pending'),
              ))
              .write(_completionCompanion(completion));
      if (changed == 1) return AiUsageFinalizeResult.finalized;

      final existing =
          await (_database.select(_database.aiUsageEvents)..where(
                (row) =>
                    row.ownerId.equals(normalizedOwnerId) &
                    row.eventId.equals(completion.eventId),
              ))
              .getSingleOrNull();
      if (existing != null && _matches(existing, completion)) {
        return AiUsageFinalizeResult.alreadyFinalized;
      }
      throw StateError(
        existing == null
            ? 'AI usage attempt does not exist.'
            : 'AI usage attempt has a contradictory terminal outcome.',
      );
    });
  }

  @override
  Future<int> recoverPendingStartedBefore(
    DateTime cutoffUtc, {
    required DateTime recoveredAtUtc,
  }) async {
    _requireUtc(cutoffUtc, 'cutoffUtc');
    _requireUtc(recoveredAtUtc, 'recoveredAtUtc');
    if (recoveredAtUtc.isBefore(cutoffUtc)) {
      throw ArgumentError.value(
        recoveredAtUtc,
        'recoveredAtUtc',
        'must not precede cutoffUtc',
      );
    }
    final ownerId = _requireOwnerId(await activeOwnerId());
    return _database.transaction(() async {
      await _requireOwnedLease();
      return _database.customUpdate(
        '''
      UPDATE ai_usage_events
      SET outcome = 'indeterminate',
          error_category = 'processInterrupted',
          latency_ms = CASE
            WHEN ? > occurred_at_utc_ms THEN ? - occurred_at_utc_ms
            ELSE 0
          END
      WHERE outcome = 'pending'
        AND owner_id = ?
        AND occurred_at_utc_ms < ?
      ''',
        variables: <Variable<Object>>[
          Variable<int>(recoveredAtUtc.millisecondsSinceEpoch),
          Variable<int>(recoveredAtUtc.millisecondsSinceEpoch),
          Variable<String>(ownerId),
          Variable<int>(cutoffUtc.millisecondsSinceEpoch),
        ],
        updates: <TableInfo<Table, Object?>>{_database.aiUsageEvents},
      );
    });
  }

  @override
  Future<int> purgeExpired(DateTime nowUtc) async {
    return purgeExpiredForOwner(await activeOwnerId(), nowUtc);
  }

  @override
  Future<int> purgeExpiredForOwner(String ownerId, DateTime nowUtc) async {
    _requireUtc(nowUtc, 'nowUtc');
    final normalizedOwnerId = _requireOwnerId(ownerId);
    final cutoff = nowUtc.subtract(retention).millisecondsSinceEpoch;
    return _database.transaction(() async {
      await _requireOwnedLease();
      return (_database.delete(_database.aiUsageEvents)..where(
            (row) =>
                row.ownerId.equals(normalizedOwnerId) &
                row.outcome.isNotValue('pending') &
                row.occurredAtUtcMs.isSmallerThanValue(cutoff),
          ))
          .go();
    });
  }

  @override
  Future<List<AiUsageSummary>> summarize() async {
    return summarizeForOwner(await activeOwnerId());
  }

  @override
  Future<List<AiUsageSummary>> summarizeForOwner(String ownerId) async {
    final normalizedOwnerId = _requireOwnerId(ownerId);
    final rows = await _database.transaction(() async {
      await _requireOwnedLease();
      return (_database.select(_database.aiUsageEvents)..where(
            (row) =>
                row.ownerId.equals(normalizedOwnerId) &
                row.outcome.isNotValue('pending'),
          ))
          .get();
    });
    final buckets = <(AiProviderId, String), _UsageAccumulator>{};
    for (final row in rows) {
      final provider = AiProviderId.values
          .where((value) => value.name == row.providerId)
          .firstOrNull;
      if (provider == null) continue;
      final bucket = buckets.putIfAbsent((
        provider,
        row.model,
      ), _UsageAccumulator.new);
      bucket
        ..requestCount += 1
        ..totalLatencyMs += row.latencyMs
        ..totalTokens += row.totalTokens ?? 0
        ..providerReportedCostMicrosUsd +=
            row.providerReportedCostMicrosUsd ?? 0;
      if (row.providerReportedCostMicrosUsd != null) {
        bucket.providerReportedCostCount += 1;
      }
      if (row.outcome == 'success') {
        bucket.successCount += 1;
      } else if (row.outcome == 'failure') {
        bucket.failureCount += 1;
      } else if (row.outcome == 'indeterminate') {
        bucket.indeterminateCount += 1;
      }
    }
    final summaries =
        buckets.entries
            .map(
              (entry) => AiUsageSummary(
                providerId: entry.key.$1,
                model: entry.key.$2,
                requestCount: entry.value.requestCount,
                successCount: entry.value.successCount,
                failureCount: entry.value.failureCount,
                indeterminateCount: entry.value.indeterminateCount,
                totalTokens: entry.value.totalTokens,
                totalLatencyMs: entry.value.totalLatencyMs,
                providerReportedCostMicrosUsd:
                    entry.value.providerReportedCostCount ==
                        entry.value.requestCount
                    ? entry.value.providerReportedCostMicrosUsd
                    : null,
              ),
            )
            .toList()
          ..sort((left, right) {
            final provider = left.providerId.name.compareTo(
              right.providerId.name,
            );
            return provider != 0 ? provider : left.model.compareTo(right.model);
          });
    return summaries;
  }

  @override
  Future<void> clear() async {
    await clearForOwner(await activeOwnerId());
  }

  @override
  Future<void> clearForOwner(String ownerId) async {
    final normalizedOwnerId = _requireOwnerId(ownerId);
    await _database.transaction(() async {
      await _requireOwnedLease();
      await (_database.delete(_database.aiUsageEvents)..where(
            (row) =>
                row.ownerId.equals(normalizedOwnerId) &
                row.outcome.isNotValue('pending'),
          ))
          .go();
    });
  }

  @override
  Future<String> exportAggregateJson({required bool researchConsent}) async {
    if (!researchConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
    }
    final summaries = await summarize();
    return jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'kind': 'ai_usage_aggregate',
      'providers': <Map<String, Object?>>[
        for (final item in summaries)
          <String, Object?>{
            'providerId': item.providerId.name,
            'model': item.model,
            'requestCount': item.requestCount,
            'successCount': item.successCount,
            'failureCount': item.failureCount,
            'indeterminateCount': item.indeterminateCount,
            'totalTokens': item.totalTokens,
            'totalLatencyMs': item.totalLatencyMs,
            'providerReportedCostMicrosUsd': item.providerReportedCostMicrosUsd,
          },
      ],
    });
  }

  AiUsageEventsCompanion _completionCompanion(AiUsageCompletion completion) =>
      AiUsageEventsCompanion(
        outcome: Value(completion.outcome),
        errorCategory: Value(completion.errorCategory),
        latencyMs: Value(completion.latencyMs),
        inputTokens: Value(completion.inputTokens),
        outputTokens: Value(completion.outputTokens),
        totalTokens: Value(completion.totalTokens),
        cachedTokens: Value(completion.cachedTokens),
        providerReportedCostMicrosUsd: Value(
          completion.providerReportedCostMicrosUsd,
        ),
      );

  bool _matches(AiUsageEventRow row, AiUsageCompletion completion) =>
      row.outcome == completion.outcome &&
      row.errorCategory == completion.errorCategory &&
      row.latencyMs == completion.latencyMs &&
      row.inputTokens == completion.inputTokens &&
      row.outputTokens == completion.outputTokens &&
      row.totalTokens == completion.totalTokens &&
      row.cachedTokens == completion.cachedTokens &&
      row.providerReportedCostMicrosUsd ==
          completion.providerReportedCostMicrosUsd;

  String _requireOwnerId(String value) {
    final ownerId = value.trim();
    if (ownerId.isEmpty) throw StateError('Active owner id must not be empty.');
    return ownerId;
  }

  void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, name, 'must be UTC');
    }
  }

  Future<void> _requireOwnedLease() async {
    final readToken = activeOwnerLeaseToken;
    if (readToken == null) return;
    final token = readToken()?.trim() ?? '';
    final now = _nowUtc();
    _requireUtc(now, 'nowUtc');
    if (token.isEmpty) throw StateError('Owner-operation lease is missing.');
    // This conditional no-op UPDATE is deliberately the first statement of
    // every repository transaction. It establishes SQLite's write lock while
    // validating the exact Task 5 token and expiry, closing the SELECT/write
    // takeover window across multiple database handles.
    await DriftOwnerOperationGate(
      _database,
    ).requireOwned(token: token, nowUtc: now);
  }
}

final class _UsageAccumulator {
  int requestCount = 0;
  int successCount = 0;
  int failureCount = 0;
  int indeterminateCount = 0;
  int totalTokens = 0;
  int totalLatencyMs = 0;
  int providerReportedCostMicrosUsd = 0;
  int providerReportedCostCount = 0;
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();
