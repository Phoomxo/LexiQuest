import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/ai_tutor_contracts.dart';

typedef ActiveOwnerIdProvider = Future<String> Function();

final class DriftAiUsageRepository implements AiUsageRepository {
  DriftAiUsageRepository(
    this._database, {
    required this.activeOwnerId,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static const retention = Duration(days: 90);

  final AppDatabase _database;
  final ActiveOwnerIdProvider activeOwnerId;
  final DateTime Function() _nowUtc;

  @override
  Future<void> record(AiUsageEvent event) async {
    await recordForOwner(await _requireActiveOwnerId(), event);
  }

  @override
  Future<void> recordForOwner(String ownerId, AiUsageEvent event) async {
    final normalizedOwnerId = _requireOwnerId(ownerId);
    await _database
        .into(_database.aiUsageEvents)
        .insert(
          AiUsageEventsCompanion.insert(
            eventId: event.eventId,
            ownerId: normalizedOwnerId,
            occurredAtUtcMs: event.occurredAtUtc.millisecondsSinceEpoch,
            providerId: event.providerId.name,
            model: event.model,
            requestType: event.requestType,
            outcome: event.outcome,
            errorCategory: Value(event.errorCategory),
            latencyMs: event.latencyMs,
            inputTokens: Value(event.inputTokens),
            outputTokens: Value(event.outputTokens),
            totalTokens: Value(event.totalTokens),
            cachedTokens: Value(event.cachedTokens),
            providerReportedCostMicrosUsd: Value(
              event.providerReportedCostMicrosUsd,
            ),
            schemaVersion: Value(event.schemaVersion),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await _purgeExpiredForOwner(normalizedOwnerId, _nowUtc());
  }

  @override
  Future<int> purgeExpired(DateTime nowUtc) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    return _purgeExpiredForActiveOwner(nowUtc);
  }

  Future<int> _purgeExpiredForActiveOwner(DateTime nowUtc) async {
    return _purgeExpiredForOwner(await _requireActiveOwnerId(), nowUtc);
  }

  Future<int> _purgeExpiredForOwner(String ownerId, DateTime nowUtc) async {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final cutoff = nowUtc.subtract(retention).millisecondsSinceEpoch;
    return (_database.delete(_database.aiUsageEvents)..where(
          (table) =>
              table.ownerId.equals(ownerId) &
              table.occurredAtUtcMs.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  @override
  Future<List<AiUsageSummary>> summarize() async {
    final ownerId = await _requireActiveOwnerId();
    final rows = await (_database.select(
      _database.aiUsageEvents,
    )..where((table) => table.ownerId.equals(ownerId))).get();
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
        bucket.hasProviderReportedCost = true;
      }
      if (row.outcome == 'success') {
        bucket.successCount += 1;
      } else {
        bucket.failureCount += 1;
      }
    }
    final result =
        buckets.entries
            .map(
              (entry) => AiUsageSummary(
                providerId: entry.key.$1,
                model: entry.key.$2,
                requestCount: entry.value.requestCount,
                successCount: entry.value.successCount,
                failureCount: entry.value.failureCount,
                totalTokens: entry.value.totalTokens,
                totalLatencyMs: entry.value.totalLatencyMs,
                providerReportedCostMicrosUsd:
                    entry.value.hasProviderReportedCost
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
    return result;
  }

  @override
  Future<void> clear() async {
    final ownerId = await _requireActiveOwnerId();
    await (_database.delete(
      _database.aiUsageEvents,
    )..where((table) => table.ownerId.equals(ownerId))).go();
  }

  @override
  Future<String> exportAggregateJson({required bool researchConsent}) async {
    if (!researchConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
    }
    final summaries = await summarize();
    return jsonEncode({
      'schemaVersion': 1,
      'kind': 'ai_usage_aggregate',
      'providers': [
        for (final item in summaries)
          {
            'providerId': item.providerId.name,
            'model': item.model,
            'requestCount': item.requestCount,
            'successCount': item.successCount,
            'failureCount': item.failureCount,
            'totalTokens': item.totalTokens,
            'totalLatencyMs': item.totalLatencyMs,
            'providerReportedCostMicrosUsd': item.providerReportedCostMicrosUsd,
          },
      ],
    });
  }

  Future<String> _requireActiveOwnerId() async {
    return _requireOwnerId(await activeOwnerId());
  }

  String _requireOwnerId(String value) {
    final ownerId = value.trim();
    if (ownerId.isEmpty) {
      throw StateError('Active owner id must not be empty.');
    }
    return ownerId;
  }
}

final class _UsageAccumulator {
  int requestCount = 0;
  int successCount = 0;
  int failureCount = 0;
  int totalTokens = 0;
  int totalLatencyMs = 0;
  int providerReportedCostMicrosUsd = 0;
  bool hasProviderReportedCost = false;
}
