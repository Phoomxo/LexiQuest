import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';
import '../domain/quest_definition_codec.dart';
import '../domain/quest_period.dart';

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
    QuestDefinitionCodec.validate(def);
    await _database
        .into(_database.questDefinitions)
        .insert(
          db.QuestDefinitionsCompanion.insert(
            questId: def.questId,
            catalogVersion: def.catalogVersion,
            title: def.title,
            description: def.description,
            type: def.type.name,
            objectivesJson: jsonEncode(
              QuestDefinitionCodec.objectivesMap(def.objectives),
            ),
            rewardJson: jsonEncode(QuestDefinitionCodec.rewardMap(def.reward)),
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
      await _insertInstance(instance);
    });
  }

  Future<bool> _insertInstance(QuestInstance instance) async {
    final period = instance.period;
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
            completedAtUtcMs: Value(
              instance.completedAtUtc?.millisecondsSinceEpoch,
            ),
            expiredAtUtcMs: Value(
              instance.expiredAtUtc?.millisecondsSinceEpoch,
            ),
            periodPolicy: Value(period?.policy.name ?? 'legacyDuration'),
            periodKey: Value(period?.key ?? 'legacy:${instance.instanceId}'),
            periodTimezoneId: Value(period?.timezoneId),
            periodStartAtUtcMs: Value(
              period?.startAtUtc.millisecondsSinceEpoch ??
                  instance.assignedAtUtc.millisecondsSinceEpoch,
            ),
            periodEndAtUtcMs: Value(period?.endAtUtc?.millisecondsSinceEpoch),
            deadlineAtUtcMs: Value(
              period?.deadlineAtUtc?.millisecondsSinceEpoch,
            ),
            isCanonical: Value(instance.isCanonical),
            definitionSnapshotJson: Value(
              instance.definitionSnapshot == null
                  ? null
                  : QuestDefinitionCodec.encode(instance.definitionSnapshot!),
            ),
          ),
          mode: InsertMode.insertOrIgnore,
        );

    final inserted =
        (await _database.customSelect('SELECT changes() AS count').getSingle())
            .read<int>('count') ==
        1;
    if (!inserted) return false;

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
    return true;
  }

  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) => _database.transaction(() async {
    final period = instance.period;
    if (period == null || instance.definitionSnapshot == null || !nowUtc.isUtc)
      throw StateError('quest assignment lacks durable period or definition');
    final activeOwners =
        await (_database.select(_database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (activeOwners.length != 1 ||
        activeOwners.single.id != instance.ownerId) {
      throw QuestOwnerChanged();
    }
    await expireStaleInstances(ownerId: instance.ownerId, nowUtc: nowUtc);
    final ownerId = instance.ownerId;
    final questId = instance.questId;
    final candidates = await _database
        .customSelect(
          '''SELECT instance_id FROM quest_instances
      WHERE owner_id = ? AND quest_id = ? AND is_canonical = 1 AND
      (period_key = ? OR state = 'active' OR period_policy = 'legacyDuration')''',
          variables: [
            Variable(ownerId),
            Variable(questId),
            Variable(period.key),
          ],
        )
        .get();
    if (candidates.isNotEmpty) {
      final ids = candidates
          .map((row) => row.read<String>('instance_id'))
          .toList();
      final rows = await (_database.select(
        _database.questInstances,
      )..where((row) => row.instanceId.isIn(ids))).get();
      final decoded = await _instancesFromRows(rows);
      final occupiedIds = <String>{};
      for (final candidate in decoded) {
        final snapshot = candidate.definitionSnapshot?.definition;
        if (snapshot != null &&
            (snapshot.questId != candidate.questId ||
                snapshot.catalogVersion != candidate.catalogVersion ||
                !QuestDefinitionCodec.matchesProgress(
                  snapshot,
                  candidate.progress,
                ))) {
          throw StateError('quest snapshot does not match durable instance');
        }
        final legacy =
            candidate.period!.policy == QuestPeriodPolicy.legacyDuration;
        final deadline = candidate.period!.deadlineAtUtc;
        final unbound = candidate.period!.key.startsWith('legacy:');
        final historicalOnce =
            snapshot?.type == QuestType.milestone ||
            snapshot?.type == QuestType.story;
        // Unknown metadata does not identify the past quest type. A requested
        // one-shot quest conservatively treats unknown legacy history as used.
        final conservativeOnce = snapshot == null && period.key == 'once';
        if (candidate.period!.key == period.key ||
            candidate.state == QuestInstanceState.active ||
            (legacy &&
                (historicalOnce ||
                    conservativeOnce ||
                    (deadline != null && deadline.isAfter(nowUtc)) ||
                    (deadline == null && unbound)))) {
          occupiedIds.add(candidate.instanceId);
        }
      }
      for (final row in rows.where(
        (row) => occupiedIds.contains(row.instanceId),
      )) {
        if (row.state == 'active') {
          final stored = await getDefinition(questId);
          final snapshot = row.definitionSnapshotJson == null
              ? null
              : QuestDefinitionCodec.decode(
                  row.definitionSnapshotJson!,
                ).definition;
          if (row.catalogVersion != definition.catalogVersion ||
              stored == null ||
              !QuestDefinitionCodec.sameDefinition(stored, definition) ||
              (snapshot != null &&
                  !QuestDefinitionCodec.sameDefinition(snapshot, definition))) {
            throw StateError(
              'quest catalog pin does not match active instance',
            );
          }
        }
        if (row.periodPolicy == 'legacyDuration' &&
            row.deadlineAtUtcMs == null &&
            (row.periodKey.isEmpty || row.periodKey.startsWith('legacy:'))) {
          await (_database.update(
            _database.questInstances,
          )..where((item) => item.instanceId.equals(row.instanceId))).write(
            db.QuestInstancesCompanion(
              periodKey: Value(period.key),
              periodEndAtUtcMs: Value(period.endAtUtc?.millisecondsSinceEpoch),
              deadlineAtUtcMs: Value(
                period.deadlineAtUtc?.millisecondsSinceEpoch,
              ),
            ),
          );
        }
      }
      if (occupiedIds.isNotEmpty) return false;
    }
    await upsertDefinition(definition);
    return _insertInstance(instance);
  });

  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    await _database.customStatement(
      "UPDATE quest_instances SET state = 'expired', expired_at_utc_ms = ? WHERE owner_id = ? AND state = 'active' AND deadline_at_utc_ms <= ?",
      [nowUtc.millisecondsSinceEpoch, ownerId, nowUtc.millisecondsSinceEpoch],
    );
  }

  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) async {
    final ids = questIds.toSet().toList();
    if (ids.length > 64)
      throw StateError('quest projection catalog exceeds 64');
    final rows =
        await (_database.select(_database.questInstances)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.isCanonical.equals(true) &
                    row.state.isIn(['active', 'expired']) &
                    row.assignedAtUtcMs.isSmallerOrEqualValue(
                      occurredAtUtc.millisecondsSinceEpoch,
                    ) &
                    (row.deadlineAtUtcMs.isNull() |
                        row.deadlineAtUtcMs.isBiggerThanValue(
                          occurredAtUtc.millisecondsSinceEpoch,
                        )),
              )
              ..limit(65))
            .get();
    if (rows.length > 64)
      throw StateError('quest event window candidates exceed 64');
    final seen = <String>{};
    if (rows.any((row) => !seen.add(row.questId)))
      throw StateError('overlapping canonical quest windows');
    return _instancesFromRows(rows);
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      _queryInstances(ownerId, stateFilter: 'active');

  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    return _queryInstances(ownerId, limit: limit);
  }

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) async {
    if (limit < 1 || limit > 64) {
      throw RangeError.range(limit, 1, 64, 'limit');
    }
    final boundedQuestIds = questIds.toSet().toList(growable: false);
    if (boundedQuestIds.length > 64) {
      throw StateError('quest completion recovery catalog exceeds 64');
    }
    // Exact owner/source identity selects history independently of the live
    // catalog. A removed definition cannot strand an earned receipt.
    final matches = await _database
        .customSelect(
          '''
      SELECT instance.instance_id FROM quest_instances AS instance
      WHERE instance.owner_id = ? AND instance.state = 'completed'
        AND EXISTS (SELECT 1 FROM quest_objective_progress AS progress,
          json_each(CASE WHEN json_valid(progress.source_event_ids_json)
            THEN progress.source_event_ids_json ELSE '[]' END) AS source
          WHERE progress.instance_id = instance.instance_id
            AND source.type = 'text' AND source.value = ?)
      ORDER BY instance.completed_at_utc_ms, instance.instance_id LIMIT ?
    ''',
          variables: [
            Variable(ownerId),
            Variable(sourceEventId),
            Variable(limit + 1),
          ],
        )
        .get();
    if (matches.length > limit)
      throw StateError('quest source recovery exceeds bound');
    if (matches.isEmpty) return const [];
    final instanceRows =
        await (_database.select(_database.questInstances)..where(
              (row) => row.instanceId.isIn(
                matches.map((row) => row.read<String>('instance_id')).toList(),
              ),
            ))
            .get();
    return _instancesFromRows(instanceRows);
  }

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
    int? limit,
  }) async {
    final instanceQuery = _database.select(_database.questInstances)
      ..where(
        (t) => stateFilter != null
            ? t.ownerId.equals(ownerId) &
                  t.state.equals(stateFilter) &
                  t.isCanonical.equals(true)
            : t.ownerId.equals(ownerId),
      )
      ..orderBy(
        stateFilter == null
            ? [
                (t) => OrderingTerm.desc(t.state.equals('active')),
                (t) => OrderingTerm.desc(t.assignedAtUtcMs),
                (t) => OrderingTerm.asc(t.instanceId),
              ]
            : [
                (t) => OrderingTerm.asc(t.assignedAtUtcMs),
                (t) => OrderingTerm.asc(t.instanceId),
              ],
      );
    if (limit != null) instanceQuery.limit(limit);

    final instanceRows = await instanceQuery.get();
    return _instancesFromRows(instanceRows);
  }

  Future<List<QuestInstance>> _instancesFromRows(
    List<db.QuestInstance> instanceRows,
  ) async {
    if (instanceRows.isEmpty) return const [];

    final instanceIds = instanceRows.map((r) => r.instanceId).toList();
    final progressRows =
        await (_database.select(_database.questObjectiveProgress)
              ..where((t) => t.instanceId.isIn(instanceIds))
              ..orderBy([(t) => OrderingTerm.asc(t.objectiveId)]))
            .get();

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
    return QuestDefinitionCodec.fromStorage({
      'quest_id': row.questId,
      'catalog_version': row.catalogVersion,
      'title': row.title,
      'description': row.description,
      'type': row.type,
      'objectives_json': row.objectivesJson,
      'reward_json': row.rewardJson,
      'expires_in_ms': row.expiresInMs,
      'tags_json': row.tagsJson,
    });
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
      period: QuestPeriod(
        policy: QuestPeriodPolicy.values.byName(row.periodPolicy),
        key: row.periodKey.isEmpty ? 'legacy:${row.instanceId}' : row.periodKey,
        timezoneId: row.periodTimezoneId,
        startAtUtc: _utc(
          row.periodStartAtUtcMs == 0
              ? row.assignedAtUtcMs
              : row.periodStartAtUtcMs,
        ),
        endAtUtc: row.periodEndAtUtcMs == null
            ? null
            : _utc(row.periodEndAtUtcMs!),
        deadlineAtUtc: row.deadlineAtUtcMs == null
            ? null
            : _utc(row.deadlineAtUtcMs!),
      ),
      isCanonical: row.isCanonical,
      definitionSnapshot: row.definitionSnapshotJson == null
          ? null
          : QuestDefinitionCodec.decode(row.definitionSnapshotJson!),
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

  DateTime _utc(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
