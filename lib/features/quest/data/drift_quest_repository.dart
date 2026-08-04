import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

/// Drift-backed implementation of [QuestRepository].
///
/// Write semantics:
/// - Definitions    → [InsertMode.insertOrReplace] (catalog updates overwrite)
/// - Instances      → [InsertMode.insertOrIgnore]  (idempotent; no duplicate)
/// - Progress rows  → [InsertMode.insertOrReplace] (counters advance; upsert)
final class DriftQuestRepository implements QuestRepository {
  DriftQuestRepository(this._database);

  final db.AppDatabase _database;

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
    final row = await (_database.select(_database.questDefinitions)
          ..where((t) => t.questId.equals(questId)))
        .getSingleOrNull();
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
    await (_database.update(_database.questInstances)
          ..where((t) => t.instanceId.equals(instanceId)))
        .write(
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
        )..where((t) => t.instanceId.isIn(instanceIds)))
        .get();

    // Group progress rows by instanceId.
    final progressByInstance =
        <String, List<db.QuestObjectiveProgressData>>{};
    for (final p in progressRows) {
      progressByInstance.putIfAbsent(p.instanceId, () => []).add(p);
    }

    return instanceRows
        .map((r) => _rowToInstance(r, progressByInstance[r.instanceId] ?? []))
        .toList(growable: false);
  }

  // ── Serialisation helpers ─────────────────────────────────────────────────

  QuestDefinition _rowToDefinition(db.QuestDefinition row) {
    final objectivesRaw =
        (jsonDecode(row.objectivesJson) as List).cast<Map<String, dynamic>>();
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
      expiresIn: expiresInMs != null ? Duration(milliseconds: expiresInMs) : null,
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
            sourceEventIds:
                (jsonDecode(p.sourceEventIdsJson) as List).cast<String>(),
          ),
        )
        .toList(growable: false);

    return QuestInstance(
      instanceId: row.instanceId,
      questId: row.questId,
      ownerId: row.ownerId,
      catalogVersion: row.catalogVersion,
      assignedAtUtc:
          DateTime.fromMillisecondsSinceEpoch(row.assignedAtUtcMs, isUtc: true),
      state: QuestInstanceState.values.byName(row.state),
      progress: progress,
      completedAtUtc: row.completedAtUtcMs != null
          ? DateTime.fromMillisecondsSinceEpoch(row.completedAtUtcMs!,
              isUtc: true)
          : null,
      expiredAtUtc: row.expiredAtUtcMs != null
          ? DateTime.fromMillisecondsSinceEpoch(row.expiredAtUtcMs!,
              isUtc: true)
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
