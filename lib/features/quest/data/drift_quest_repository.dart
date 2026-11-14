import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/answer_motivation_evidence.dart';
import '../application/quest_catalog_provider.dart';
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

final class TrustedQuestAnswerCatalog {
  TrustedQuestAnswerCatalog._(this._database, this._entries);

  final db.AppDatabase _database;
  final List<_AnswerCatalogEntry> _entries;

  Future<({QuestRevisionPin daily, QuestRevisionPin weekly})>
  pinsForPendingCalendar({
    required db.AppDatabase database,
    required int occurredAtUtcMs,
    required int epochEffectiveUtcUs,
  }) async {
    if (!identical(database, _database) ||
        occurredAtUtcMs < 0 ||
        epochEffectiveUtcUs < 0 ||
        occurredAtUtcMs * Duration.microsecondsPerMillisecond <
            epochEffectiveUtcUs) {
      throw ArgumentError(
        'Catalog database and nonnegative occurrence required',
      );
    }
    _AnswerCatalogEntry soleInitial(QuestType type) {
      final entries = _entries.where((entry) => entry.type == type).toList();
      if (entries.length != 1 || entries.single.activeFromUtcMs != 0) {
        throw StateError('Pending calendar has ambiguous Quest revisions');
      }
      return entries.single;
    }

    final daily = soleInitial(QuestType.daily);
    final weekly = soleInitial(QuestType.weekly);
    return (
      daily: await _verifiedPin(daily),
      weekly: await _verifiedPin(weekly),
    );
  }

  Future<({QuestRevisionPin daily, QuestRevisionPin weekly})> pinsForPeriod({
    required db.AppDatabase database,
    required DateTime dailyStartUtc,
    required DateTime weeklyStartUtc,
  }) async {
    if (!identical(database, _database) ||
        !dailyStartUtc.isUtc ||
        !weeklyStartUtc.isUtc) {
      throw ArgumentError('Catalog database and UTC period starts required');
    }
    Future<QuestRevisionPin> resolve(QuestType type, DateTime start) async {
      final candidates = _entries.where(
        (entry) =>
            entry.type == type &&
            entry.activeFromUtcMs <= start.millisecondsSinceEpoch,
      );
      if (candidates.isEmpty) {
        throw StateError('No authored revision for period');
      }
      final selected = candidates.reduce(
        (a, b) => a.activeFromUtcMs > b.activeFromUtcMs ? a : b,
      );
      return _verifiedPin(selected);
    }

    return (
      daily: await resolve(QuestType.daily, dailyStartUtc),
      weekly: await resolve(QuestType.weekly, weeklyStartUtc),
    );
  }

  Future<QuestRevisionPin> _verifiedPin(_AnswerCatalogEntry entry) async {
    final row =
        await (_database.select(_database.questDefinitionRevisions)..where(
              (row) =>
                  row.questId.equals(entry.pin.questId) &
                  row.catalogVersion.equals(entry.pin.catalogVersion),
            ))
            .getSingleOrNull();
    if (row == null ||
        row.definitionDigest != entry.pin.definitionDigest ||
        row.canonicalDefinition != entry.body) {
      throw StateError('Quest revision archive mismatch');
    }
    return entry.pin;
  }
}

final class _AnswerCatalogEntry {
  const _AnswerCatalogEntry({
    required this.type,
    required this.activeFromUtcMs,
    required this.pin,
    required this.body,
  });
  final QuestType type;
  final int activeFromUtcMs;
  final QuestRevisionPin pin;
  final String body;
}

/// Drift-backed implementation of [QuestRepository].
///
/// Write semantics:
/// - Definitions    → [InsertMode.insertOrReplace] (catalog updates overwrite)
/// - Instances      → [InsertMode.insertOrIgnore]  (idempotent; no duplicate)
/// - Progress rows  → [InsertMode.insertOrReplace] (counters advance; upsert)
final class DriftQuestRepository implements QuestRepository {
  DriftQuestRepository(this._database);

  final db.AppDatabase _database;

  Future<TrustedQuestAnswerCatalog> installAnswerCatalog({
    List<QuestCatalogRevision>? authoredRevisions,
  }) async {
    final revisions =
        authoredRevisions ?? QuestCatalogProvider.authoredRevisions;
    final entries = <_AnswerCatalogEntry>[];
    for (final revision in revisions) {
      final body = QuestCatalogProvider.canonicalAnswerManifest(revision);
      final def = revision.definition;
      final digest = sha256.convert(utf8.encode(body)).toString();
      entries.add(
        _AnswerCatalogEntry(
          type: def.type,
          activeFromUtcMs: revision.activeFromUtcMs,
          body: body,
          pin: QuestRevisionPin(
            questId: def.questId,
            catalogVersion: def.catalogVersion,
            definitionDigest: digest,
          ),
        ),
      );
    }
    for (final type in [QuestType.daily, QuestType.weekly]) {
      final group = entries.where((entry) => entry.type == type).toList()
        ..sort((a, b) => a.activeFromUtcMs.compareTo(b.activeFromUtcMs));
      if (group.isEmpty ||
          group.first.activeFromUtcMs != 0 ||
          group.any((entry) => entry.pin.questId != group.first.pin.questId)) {
        throw ArgumentError('Invalid answer Quest family');
      }
      for (var i = 1; i < group.length; i++) {
        if (group[i].activeFromUtcMs <= group[i - 1].activeFromUtcMs ||
            group[i].pin.catalogVersion <= group[i - 1].pin.catalogVersion) {
          throw ArgumentError('Invalid answer Quest activation schedule');
        }
      }
    }
    final dailyId = entries
        .firstWhere((entry) => entry.type == QuestType.daily)
        .pin
        .questId;
    final weeklyId = entries
        .firstWhere((entry) => entry.type == QuestType.weekly)
        .pin
        .questId;
    if (dailyId == weeklyId) {
      throw StateError('Daily and weekly Quest families must differ');
    }
    await _database.transaction(() async {
      for (final entry in entries) {
        await _database
            .into(_database.questDefinitionRevisions)
            .insert(
              db.QuestDefinitionRevisionsCompanion.insert(
                questId: entry.pin.questId,
                catalogVersion: entry.pin.catalogVersion,
                definitionDigest: entry.pin.definitionDigest,
                canonicalDefinition: entry.body,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final row =
            await (_database.select(_database.questDefinitionRevisions)..where(
                  (row) =>
                      row.questId.equals(entry.pin.questId) &
                      row.catalogVersion.equals(entry.pin.catalogVersion),
                ))
                .getSingleOrNull();
        if (row == null ||
            row.definitionDigest != entry.pin.definitionDigest ||
            row.canonicalDefinition != entry.body) {
          throw StateError('Quest revision archive mismatch');
        }
      }
    });
    return TrustedQuestAnswerCatalog._(_database, List.unmodifiable(entries));
  }

  // ── Definitions ────────────────────────────────────────────────────────────

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {
    await _database
        .into(_database.questDefinitions)
        .insert(
          db.QuestDefinitionsCompanion.insert(
            questId: def.questId,
            catalogVersion: def.catalogVersion,
            title: def.title,
            description: def.description,
            type: def.type.name,
            objectivesJson: _encodeObjectives(def.objectives),
            rewardJson: _encodeReward(def.reward),
            expiresInMs: Value(def.expiresIn?.inMilliseconds),
            tagsJson: Value(jsonEncode(def.tags)),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<QuestDefinition?> getDefinition(String questId) async {
    final row = await (_database.select(
      _database.questDefinitions,
    )..where((t) => t.questId.equals(questId))).getSingleOrNull();
    return row == null ? null : _rowToDefinition(row);
  }

  // ── Instances ──────────────────────────────────────────────────────────────

  @override
  Future<void> startInstance(QuestInstance instance) async {
    await _database.transaction(() async {
      await _database
          .into(_database.questInstances)
          .insert(
            db.QuestInstancesCompanion.insert(
              instanceId: instance.instanceId,
              questId: instance.questId,
              ownerId: instance.ownerId,
              catalogVersion: instance.catalogVersion,
              assignedAtUtcMs: instance.assignedAtUtc.millisecondsSinceEpoch,
              state: instance.state.name,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      // Insert initial progress rows for each objective (currentCount = 0).
      for (final p in instance.progress) {
        await _database
            .into(_database.questObjectiveProgress)
            .insert(
              db.QuestObjectiveProgressCompanion.insert(
                id: '${instance.instanceId}:${p.objectiveId}',
                instanceId: instance.instanceId,
                objectiveId: p.objectiveId,
                targetCount: p.targetCount,
                currentCount: Value(p.currentCount),
                sourceEventIdsJson: Value(jsonEncode(p.sourceEventIds)),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      _queryInstances(ownerId, stateFilter: 'active');

  @override
  Future<List<QuestInstance>> getAllInstances(String ownerId) =>
      _queryInstances(ownerId);

  // ── Progress ───────────────────────────────────────────────────────────────

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {
    await _database.transaction(() async {
      for (final p in progress) {
        await _database
            .into(_database.questObjectiveProgress)
            .insert(
              db.QuestObjectiveProgressCompanion.insert(
                id: '$instanceId:${p.objectiveId}',
                instanceId: instanceId,
                objectiveId: p.objectiveId,
                targetCount: p.targetCount,
                currentCount: Value(p.currentCount),
                sourceEventIdsJson: Value(jsonEncode(p.sourceEventIds)),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });
  }

  // ── State transitions ─────────────────────────────────────────────────────

  @override
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc) =>
      _updateState(
        instanceId,
        state: 'completed',
        completedAtUtcMs: completedAtUtc.millisecondsSinceEpoch,
      );

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) =>
      _updateState(
        instanceId,
        state: 'expired',
        expiredAtUtcMs: expiredAtUtc.millisecondsSinceEpoch,
      );

  @override
  Future<void> markAbandoned(String instanceId) =>
      _updateState(instanceId, state: 'abandoned');

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _updateState(
    String instanceId, {
    required String state,
    int? completedAtUtcMs,
    int? expiredAtUtcMs,
  }) async {
    await (_database.update(
      _database.questInstances,
    )..where((t) => t.instanceId.equals(instanceId))).write(
      db.QuestInstancesCompanion(
        state: Value(state),
        completedAtUtcMs: completedAtUtcMs != null
            ? Value(completedAtUtcMs)
            : const Value.absent(),
        expiredAtUtcMs: expiredAtUtcMs != null
            ? Value(expiredAtUtcMs)
            : const Value.absent(),
      ),
    );
  }

  Future<List<QuestInstance>> _queryInstances(
    String ownerId, {
    String? stateFilter,
  }) async {
    final instanceQuery = _database.select(_database.questInstances)
      ..where(
        (t) => stateFilter != null
            ? t.ownerId.equals(ownerId) & t.state.equals(stateFilter)
            : t.ownerId.equals(ownerId),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.assignedAtUtcMs)]);

    final instanceRows = await instanceQuery.get();
    if (instanceRows.isEmpty) return const [];

    final instanceIds = instanceRows.map((r) => r.instanceId).toList();
    final progressRows = await (_database.select(
      _database.questObjectiveProgress,
    )..where((t) => t.instanceId.isIn(instanceIds))).get();

    // Group progress rows by instanceId.
    final progressByInstance = <String, List<db.QuestObjectiveProgressData>>{};
    for (final p in progressRows) {
      progressByInstance.putIfAbsent(p.instanceId, () => []).add(p);
    }

    return instanceRows
        .map((r) => _rowToInstance(r, progressByInstance[r.instanceId] ?? []))
        .toList(growable: false);
  }

  // ── Serialisation helpers ─────────────────────────────────────────────────

  QuestDefinition _rowToDefinition(db.QuestDefinition row) {
    final objectivesRaw = (jsonDecode(row.objectivesJson) as List)
        .cast<Map<String, dynamic>>();
    final objectives = objectivesRaw
        .map(
          (o) => QuestObjective(
            objectiveId: o['objectiveId'] as String,
            description: o['description'] as String,
            targetCount: o['targetCount'] as int,
            criteria: ObjectiveCriteria(
              eventType: o['eventType'] as String,
              filters: (o['filters'] as Map?)?.cast(),
            ),
          ),
        )
        .toList(growable: false);

    final rewardRaw = jsonDecode(row.rewardJson) as Map<String, dynamic>;
    final reward = RewardSpec(
      xpAmount: rewardRaw['xpAmount'] as int,
      rewardItemId: rewardRaw['rewardItemId'] as String?,
    );

    final tags = (jsonDecode(row.tagsJson) as List).cast<String>();
    final expiresInMs = row.expiresInMs;

    return QuestDefinition(
      questId: row.questId,
      catalogVersion: row.catalogVersion,
      title: row.title,
      description: row.description,
      type: QuestType.values.byName(row.type),
      objectives: objectives,
      reward: reward,
      expiresIn: expiresInMs != null
          ? Duration(milliseconds: expiresInMs)
          : null,
      tags: tags,
    );
  }

  QuestInstance _rowToInstance(
    db.QuestInstance row,
    List<db.QuestObjectiveProgressData> progressRows,
  ) {
    final progress = progressRows
        .map(
          (p) => ObjectiveProgress(
            objectiveId: p.objectiveId,
            currentCount: p.currentCount,
            targetCount: p.targetCount,
            sourceEventIds: (jsonDecode(p.sourceEventIdsJson) as List)
                .cast<String>(),
          ),
        )
        .toList(growable: false);

    return QuestInstance(
      instanceId: row.instanceId,
      questId: row.questId,
      ownerId: row.ownerId,
      catalogVersion: row.catalogVersion,
      assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.assignedAtUtcMs,
        isUtc: true,
      ),
      state: QuestInstanceState.values.byName(row.state),
      progress: progress,
      completedAtUtc: row.completedAtUtcMs != null
          ? DateTime.fromMillisecondsSinceEpoch(
              row.completedAtUtcMs!,
              isUtc: true,
            )
          : null,
      expiredAtUtc: row.expiredAtUtcMs != null
          ? DateTime.fromMillisecondsSinceEpoch(
              row.expiredAtUtcMs!,
              isUtc: true,
            )
          : null,
    );
  }

  String _encodeObjectives(List<QuestObjective> objectives) => jsonEncode(
    objectives
        .map(
          (o) => <String, dynamic>{
            'objectiveId': o.objectiveId,
            'description': o.description,
            'targetCount': o.targetCount,
            'eventType': o.criteria.eventType,
            'filters': o.criteria.filters,
          },
        )
        .toList(),
  );

  String _encodeReward(RewardSpec reward) => jsonEncode(<String, dynamic>{
    'xpAmount': reward.xpAmount,
    'rewardItemId': reward.rewardItemId,
  });
}
