import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

/// Optional Quest projection over canonical, already-committed learning answers.
final class DriftQuestRepository implements QuestRepository {
  DriftQuestRepository(
    this._database, {
    required DriftOwnerWriteCoordinator ownerWrites,
    required this.nowUtc,
  }) : _ownerWrites = ownerWrites {
    if (!identical(_database, ownerWrites.database)) {
      throw ArgumentError('Quest and owner coordinator must share a database');
    }
  }

  final db.AppDatabase _database;
  final DriftOwnerWriteCoordinator _ownerWrites;
  final DateTime Function() nowUtc;
  static const _payloadKeys = {
    'wordId',
    'promptMode',
    'correct',
    'score',
    'responseTimeMs',
    'attemptNumber',
    'providerProvenance',
  };

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {
    final supplied = _snapshotDefinition(def);
    await _requireTopLevel();
    await _database.transaction(() async {
      // Lock before inspecting the shared catalog revision.
      await _database.customUpdate(
        'UPDATE quest_definitions SET catalog_version = catalog_version WHERE quest_id = ?',
        variables: [Variable<String>(supplied.questId)],
      );
      final stored = await getDefinition(supplied.questId);
      if (stored != null) {
        if (supplied.catalogVersion < stored.catalogVersion ||
            (supplied.catalogVersion == stored.catalogVersion &&
                _definitionPin(supplied) != _definitionPin(stored))) {
          _deny();
        }
        if (supplied.catalogVersion == stored.catalogVersion) {
          return;
        }
      }
      final values = _definitionValues(supplied);
      if (stored == null) {
        await _database.into(_database.questDefinitions).insert(values);
      } else {
        await (_database.update(
          _database.questDefinitions,
        )..where((row) => row.questId.equals(supplied.questId))).write(values);
      }
    });
  }

  @override
  Future<QuestDefinition?> getDefinition(String questId) async {
    final row = await (_database.select(
      _database.questDefinitions,
    )..where((row) => row.questId.equals(questId))).getSingleOrNull();
    return row == null ? null : _snapshotDefinition(_rowToDefinition(row));
  }

  @override
  Future<void> startInstance(QuestInstance instance) async {
    final supplied = _snapshotInstance(instance);
    await _requireTopLevel();
    await _ownerWrites.writeForActiveOwner(
      expectedOwnerId: supplied.ownerId,
      write: () async {
        final def = await getDefinition(supplied.questId);
        if (def == null || def.catalogVersion != supplied.catalogVersion) {
          _deny();
        }
        final existing =
            await (_database.select(_database.questInstances)
                  ..where((row) => row.instanceId.equals(supplied.instanceId)))
                .getSingleOrNull();
        if (existing != null) {
          if (existing.ownerId != supplied.ownerId ||
              existing.questId != supplied.questId ||
              existing.catalogVersion != supplied.catalogVersion ||
              existing.assignedAtUtcMs !=
                  supplied.assignedAtUtc.millisecondsSinceEpoch) {
            _deny();
          }
          // Replay does not fill missing rows or reset existing progress.
          await _validatedInstance(existing, def);
          return;
        }
        if (supplied.state != QuestInstanceState.active ||
            supplied.completedAtUtc != null ||
            supplied.expiredAtUtc != null ||
            supplied.assignedAtUtc.isAfter(_now())) {
          _deny();
        }
        _validateProgress(supplied, def);
        if (supplied.progress.any((progress) => progress.currentCount != 0)) {
          _deny();
        }
        await _database
            .into(_database.questInstances)
            .insert(
              db.QuestInstancesCompanion.insert(
                instanceId: supplied.instanceId,
                questId: supplied.questId,
                ownerId: supplied.ownerId,
                catalogVersion: supplied.catalogVersion,
                assignedAtUtcMs: supplied.assignedAtUtc.millisecondsSinceEpoch,
                state: 'active',
              ),
            );
        for (final progress in supplied.progress) {
          await _database
              .into(_database.questObjectiveProgress)
              .insert(
                db.QuestObjectiveProgressCompanion.insert(
                  id: '${supplied.instanceId}:${progress.objectiveId}',
                  instanceId: supplied.instanceId,
                  objectiveId: progress.objectiveId,
                  targetCount: progress.targetCount,
                ),
              );
        }
        await _ownerWrites.writeForActiveOwner(
          expectedOwnerId: supplied.ownerId,
          write: () async {
            final current = await getDefinition(supplied.questId);
            if (current == null ||
                _definitionPin(current) != _definitionPin(def)) {
              _deny();
            }
          },
        );
      },
    );
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      _queryInstances(ownerId, stateFilter: 'active');

  @override
  Future<List<QuestInstance>> getAllInstances(String ownerId) =>
      _queryInstances(ownerId);

  @override
  Future<List<QuestCompletedEvent>> applyCanonicalAnswer({
    required String ownerId,
    required EventEnvelopeV2 event,
    required List<QuestDefinition> catalog,
  }) async {
    // Snapshot caller-owned collections before the first asynchronous boundary.
    if (!event.occurredAtUtc.isUtc || !event.recordedAtUtc.isUtc) {
      _deny();
    }
    final suppliedEvent = EventEnvelopeV2.fromJson(
      jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
    );
    final suppliedCatalog = List<QuestDefinition>.unmodifiable(
      catalog.map(_snapshotDefinition),
    );
    if (suppliedCatalog.map((def) => def.questId).toSet().length !=
        suppliedCatalog.length) {
      _deny();
    }
    await _requireTopLevel();
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final now = _now();
        final source = await _loadAnswer(suppliedEvent.eventId, ownerId);
        final canonical = _answerEvent(source.$1, source.$2);
        if (!_sameAdmission(suppliedEvent, canonical) ||
            canonical.occurredAtUtc.isAfter(now)) {
          _deny();
        }
        final sourcePins = <String, String>{source.$1.id: _answerPin(source)};
        final instanceRows =
            await (_database.select(_database.questInstances)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.state.equals('active'),
                ))
                .get();
        final completions = <QuestCompletedEvent>[];
        final expected = <String, String>{};
        final definitionPins = <String, String>{};
        final windows = <QuestInstance, QuestDefinition>{};

        for (final row in instanceRows) {
          final matches = suppliedCatalog.where(
            (def) => def.questId == row.questId,
          );
          if (matches.length != 1) {
            _deny();
          }
          final supplied = matches.single;
          final stored = await getDefinition(row.questId);
          if (stored == null ||
              stored.catalogVersion != row.catalogVersion ||
              _definitionPin(stored) != _definitionPin(supplied)) {
            _deny();
          }
          definitionPins[row.questId] = _definitionPin(stored);
          final instance = await _validatedInstance(row, stored);
          _requireWindow(instance, stored, canonical.occurredAtUtc, now);
          windows[instance] = stored;

          for (final progress in instance.progress) {
            final objective = stored.objectives.singleWhere(
              (objective) => objective.objectiveId == progress.objectiveId,
            );
            for (final id in progress.sourceEventIds) {
              final prior = await _loadAnswer(id, ownerId);
              final priorEvent = _answerEvent(prior.$1, prior.$2);
              _requireWindow(instance, stored, priorEvent.occurredAtUtc, now);
              if (!objective.criteria.matches(priorEvent)) {
                _deny();
              }
              sourcePins[id] = _answerPin(prior);
            }
          }

          final updated = instance.advanceIfMatches(
            canonical,
            stored.objectives,
          );
          if (!identical(instance, updated)) {
            for (final progress in updated.progress) {
              final count =
                  await (_database.update(_database.questObjectiveProgress)
                        ..where(
                          (row) =>
                              row.instanceId.equals(instance.instanceId) &
                              row.objectiveId.equals(progress.objectiveId),
                        ))
                      .write(
                        db.QuestObjectiveProgressCompanion(
                          currentCount: Value(progress.currentCount),
                          sourceEventIdsJson: Value(
                            jsonEncode(progress.sourceEventIds),
                          ),
                        ),
                      );
              if (count != 1) {
                _deny();
              }
            }
          }
          var finalInstance = updated;
          if (!identical(instance, updated) &&
              updated.isAllObjectivesComplete) {
            final completedAt = DateTime.fromMillisecondsSinceEpoch(
              now.millisecondsSinceEpoch,
              isUtc: true,
            );
            final completion = updated.complete(now: completedAt);
            final count =
                await (_database.update(_database.questInstances)..where(
                      (row) =>
                          row.instanceId.equals(instance.instanceId) &
                          row.ownerId.equals(ownerId) &
                          row.state.equals('active'),
                    ))
                    .write(
                      db.QuestInstancesCompanion(
                        state: const Value('completed'),
                        completedAtUtcMs: Value(
                          completedAt.millisecondsSinceEpoch,
                        ),
                      ),
                    );
            if (count != 1) {
              _deny();
            }
            completions.add(completion);
            finalInstance = QuestInstance(
              instanceId: updated.instanceId,
              questId: updated.questId,
              ownerId: updated.ownerId,
              catalogVersion: updated.catalogVersion,
              assignedAtUtc: updated.assignedAtUtc,
              state: QuestInstanceState.completed,
              progress: updated.progress,
              completedAtUtc: completedAt,
            );
          }
          expected[row.instanceId] = _instancePin(finalInstance);
        }

        // All asynchronous work is local SQL under SQLite's acquired writer.
        // Inspect canonical facts after writes, then recheck owner/fence and time.
        for (final pin in sourcePins.entries) {
          if (_answerPin(await _loadAnswer(pin.key, ownerId)) != pin.value) {
            _deny();
          }
        }
        for (final pin in definitionPins.entries) {
          final current = await getDefinition(pin.key);
          if (current == null || _definitionPin(current) != pin.value) {
            _deny();
          }
        }
        for (final pin in expected.entries) {
          final row = await (_database.select(
            _database.questInstances,
          )..where((row) => row.instanceId.equals(pin.key))).getSingleOrNull();
          if (row == null) {
            _deny();
          }
          final current = await _validatedInstance(
            row,
            suppliedCatalog.singleWhere((def) => def.questId == row.questId),
          );
          if (_instancePin(current) != pin.value) {
            _deny();
          }
        }
        await _ownerWrites.writeForActiveOwner(
          expectedOwnerId: ownerId,
          write: () async {
            final finalNow = _now();
            if (finalNow.isBefore(now) ||
                canonical.occurredAtUtc.isAfter(finalNow)) {
              _deny();
            }
            for (final entry in windows.entries) {
              _requireWindow(
                entry.key,
                entry.value,
                canonical.occurredAtUtc,
                finalNow,
              );
            }
          },
        );
        return List<QuestCompletedEvent>.unmodifiable(completions);
      },
    );
  }

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) {
    _requireUtc(expiredAtUtc);
    return _changeActiveState(instanceId, 'expired', expiredAtUtc);
  }

  @override
  Future<void> markAbandoned(String instanceId) =>
      _changeActiveState(instanceId, 'abandoned', null);

  Future<void> _changeActiveState(
    String instanceId,
    String state,
    DateTime? at,
  ) async {
    await _requireTopLevel();
    final original = await (_database.select(
      _database.questInstances,
    )..where((row) => row.instanceId.equals(instanceId))).getSingleOrNull();
    if (original == null) {
      _deny();
    }
    await _ownerWrites.writeForActiveOwner(
      expectedOwnerId: original.ownerId,
      write: () async {
        final current = await (_database.select(
          _database.questInstances,
        )..where((row) => row.instanceId.equals(instanceId))).getSingleOrNull();
        if (current == null || current.ownerId != original.ownerId) {
          _deny();
        }
        if (current.state != 'active') {
          return;
        }
        if (at != null && at.millisecondsSinceEpoch < current.assignedAtUtcMs) {
          _deny();
        }
        await (_database.update(_database.questInstances)..where(
              (row) =>
                  row.instanceId.equals(instanceId) &
                  row.ownerId.equals(original.ownerId) &
                  row.state.equals('active'),
            ))
            .write(
              db.QuestInstancesCompanion(
                state: Value(state),
                expiredAtUtcMs: at == null
                    ? const Value.absent()
                    : Value(at.millisecondsSinceEpoch),
              ),
            );
        await _ownerWrites.writeForActiveOwner(
          expectedOwnerId: original.ownerId,
          write: () async {},
        );
      },
    );
  }

  Future<void> _requireTopLevel() async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      _deny();
    }
  }

  DateTime _now() => _requireUtc(nowUtc());

  DateTime _requireUtc(DateTime time) {
    if (!time.isUtc || time.millisecondsSinceEpoch < 0) {
      _deny();
    }
    return time;
  }

  Future<(db.AnswerAttempt, db.LearningSession)> _loadAnswer(
    String id,
    String ownerId,
  ) async {
    final answer = await (_database.select(
      _database.answerAttempts,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (answer == null ||
        answer.ownerId != ownerId ||
        !LearningEvidenceContract.validAttempt(
          id: answer.id,
          ownerId: answer.ownerId,
          sessionId: answer.sessionId,
          wordId: answer.wordId,
          promptMode: answer.promptMode,
          responseTimeMs: answer.responseTimeMs,
          attemptNumber: answer.attemptNumber,
          occurredAtUtcMs: answer.occurredAtUtcMs,
          providerProvenance: answer.providerProvenance,
          evidenceClass: answer.evidenceClass,
          evidenceContextJson: answer.evidenceContextJson,
        ) ||
        !LearningEvidenceContract.allowsOrdinaryProjection(
          promptMode: answer.promptMode,
          evidenceClass: answer.evidenceClass,
          evidenceContextJson: answer.evidenceContextJson,
          projection: LearningProjection.quest,
        )) {
      _deny();
    }
    final session = await (_database.select(
      _database.learningSessions,
    )..where((row) => row.id.equals(answer.sessionId))).getSingleOrNull();
    if (session == null ||
        session.ownerId != ownerId ||
        session.activityType == 'assessment' ||
        session.activityType.trim().isEmpty ||
        session.appVersion.trim().isEmpty ||
        session.buildId.trim().isEmpty ||
        (session.state != 'active' && session.state != 'completed') ||
        session.startedAtUtcMs < 0 ||
        answer.occurredAtUtcMs < session.startedAtUtcMs ||
        (session.state == 'active' && session.endedAtUtcMs != null) ||
        (session.state == 'completed' &&
            (session.endedAtUtcMs == null ||
                session.endedAtUtcMs! < answer.occurredAtUtcMs))) {
      _deny();
    }
    return (answer, session);
  }

  EventEnvelopeV2 _answerEvent(
    db.AnswerAttempt answer,
    db.LearningSession session,
  ) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      answer.occurredAtUtcMs,
      isUtc: true,
    );
    return EventEnvelopeV2(
      eventId: answer.id,
      eventType: answer.isCorrect ? 'QuizCompleted' : 'QuizAttempted',
      eventVersion: 1,
      occurredAtUtc: at,
      recordedAtUtc: at,
      actorIdentity: answer.ownerId,
      ownerIdentity: answer.ownerId,
      aggregateType: 'LearningSession',
      aggregateId: answer.sessionId,
      idempotencyKey: 'answer-attempt:${answer.id}',
      consentContext: const ConsentContext.none(),
      appVersion: session.appVersion,
      buildId: session.buildId,
      privacyClassification: PrivacyClassification.anonymized,
      payload: {
        'wordId': answer.wordId,
        'promptMode': answer.promptMode,
        'correct': answer.isCorrect,
        'score': answer.isCorrect ? 100 : 0,
        if (answer.responseTimeMs != null)
          'responseTimeMs': answer.responseTimeMs,
        'attemptNumber': answer.attemptNumber,
        if (answer.providerProvenance != null)
          'providerProvenance': answer.providerProvenance,
      },
    );
  }

  bool _sameAdmission(EventEnvelopeV2 actual, EventEnvelopeV2 expected) =>
      actual.eventId == expected.eventId &&
      actual.eventType == expected.eventType &&
      actual.eventVersion == 1 &&
      actual.ownerIdentity == expected.ownerIdentity &&
      actual.actorIdentity == expected.actorIdentity &&
      actual.aggregateType == expected.aggregateType &&
      actual.aggregateId == expected.aggregateId &&
      actual.idempotencyKey == expected.idempotencyKey &&
      actual.occurredAtUtc.isUtc &&
      actual.recordedAtUtc.isUtc &&
      // Canonical SQL facts retain milliseconds, including original ACK retries.
      actual.occurredAtUtc.millisecondsSinceEpoch ==
          expected.occurredAtUtc.millisecondsSinceEpoch &&
      actual.recordedAtUtc.millisecondsSinceEpoch ==
          expected.recordedAtUtc.millisecondsSinceEpoch &&
      _jsonPin(actual.payload) == _jsonPin(expected.payload);

  String _answerPin((db.AnswerAttempt, db.LearningSession) source) =>
      _jsonPin([source.$1.toJson(), source.$2.toJson()]);

  void _requireWindow(
    QuestInstance instance,
    QuestDefinition def,
    DateTime occurred,
    DateTime now,
  ) {
    if (occurred.isBefore(instance.assignedAtUtc) || occurred.isAfter(now)) {
      _deny();
    }
    final expiry = def.expiresIn;
    if (expiry != null) {
      final deadline = instance.assignedAtUtc.add(expiry);
      if (occurred.isAfter(deadline) || now.isAfter(deadline)) {
        _deny();
      }
    }
  }

  Future<QuestInstance> _validatedInstance(
    db.QuestInstance row,
    QuestDefinition def,
  ) async {
    final progress = await (_database.select(
      _database.questObjectiveProgress,
    )..where((progress) => progress.instanceId.equals(row.instanceId))).get();
    final instance = _rowToInstance(row, progress);
    _validateProgress(instance, def);
    return instance;
  }

  void _validateProgress(QuestInstance instance, QuestDefinition def) {
    _text(instance.instanceId);
    _text(instance.ownerId);
    _requireUtc(instance.assignedAtUtc);
    if (instance.questId != def.questId ||
        instance.catalogVersion != def.catalogVersion ||
        instance.progress.length != def.objectives.length ||
        instance.progress
                .map((progress) => progress.objectiveId)
                .toSet()
                .length !=
            instance.progress.length) {
      _deny();
    }
    for (final progress in instance.progress) {
      final matching = def.objectives.where(
        (objective) => objective.objectiveId == progress.objectiveId,
      );
      if (matching.length != 1 ||
          progress.targetCount != matching.single.targetCount ||
          progress.currentCount < 0 ||
          progress.currentCount > progress.targetCount ||
          progress.currentCount != progress.sourceEventIds.length ||
          progress.sourceEventIds.toSet().length !=
              progress.sourceEventIds.length) {
        _deny();
      }
      progress.sourceEventIds.forEach(_text);
    }
    if ((instance.state == QuestInstanceState.active &&
            (instance.completedAtUtc != null ||
                instance.expiredAtUtc != null ||
                instance.isAllObjectivesComplete)) ||
        (instance.state == QuestInstanceState.completed &&
            (!instance.isAllObjectivesComplete ||
                instance.completedAtUtc == null ||
                instance.expiredAtUtc != null))) {
      _deny();
    }
    if (instance.completedAtUtc case final completed?) {
      _requireUtc(completed);
      if (completed.isBefore(instance.assignedAtUtc)) {
        _deny();
      }
    }
  }

  QuestDefinition _snapshotDefinition(QuestDefinition def) {
    _text(def.questId);
    if (def.catalogVersion <= 0 ||
        def.objectives.isEmpty ||
        def.objectives
                .map((objective) => objective.objectiveId)
                .toSet()
                .length !=
            def.objectives.length ||
        (def.expiresIn != null &&
            (def.expiresIn!.inMilliseconds <= 0 ||
                def.expiresIn!.inMicroseconds %
                        Duration.microsecondsPerMillisecond !=
                    0))) {
      _deny();
    }
    final objectives = <QuestObjective>[];
    for (final objective in def.objectives) {
      _text(objective.objectiveId);
      _text(objective.criteria.eventType);
      if (objective.targetCount <= 0) {
        _deny();
      }
      final filters = objective.criteria.filters;
      if (filters != null &&
          filters.entries.any(
            (entry) =>
                !_payloadKeys.contains(entry.key) ||
                (entry.value != null &&
                    entry.value is! String &&
                    entry.value is! bool &&
                    entry.value is! int &&
                    entry.value is! double),
          )) {
        _deny();
      }
      objectives.add(
        QuestObjective(
          objectiveId: objective.objectiveId,
          description: objective.description,
          targetCount: objective.targetCount,
          criteria: ObjectiveCriteria(
            eventType: objective.criteria.eventType,
            filters: filters == null
                ? null
                : Map<String, dynamic>.unmodifiable(filters),
          ),
        ),
      );
    }
    return QuestDefinition(
      questId: def.questId,
      catalogVersion: def.catalogVersion,
      title: def.title,
      description: def.description,
      type: def.type,
      objectives: List.unmodifiable(objectives),
      reward: def.reward,
      expiresIn: def.expiresIn,
      tags: List.unmodifiable(def.tags),
    );
  }

  QuestInstance _snapshotInstance(QuestInstance instance) => QuestInstance(
    instanceId: instance.instanceId,
    questId: instance.questId,
    ownerId: instance.ownerId,
    catalogVersion: instance.catalogVersion,
    assignedAtUtc: instance.assignedAtUtc,
    state: instance.state,
    progress: instance.progress
        .map(
          (progress) => ObjectiveProgress(
            objectiveId: progress.objectiveId,
            currentCount: progress.currentCount,
            targetCount: progress.targetCount,
            sourceEventIds: progress.sourceEventIds,
          ),
        )
        .toList(),
    completedAtUtc: instance.completedAtUtc,
    expiredAtUtc: instance.expiredAtUtc,
  );

  String _definitionPin(QuestDefinition def) => _jsonPin({
    'questId': def.questId,
    'catalogVersion': def.catalogVersion,
    'title': def.title,
    'description': def.description,
    'type': def.type.name,
    'objectives': jsonDecode(_encodeObjectives(def.objectives)),
    'reward': jsonDecode(_encodeReward(def.reward)),
    'expiresInMs': def.expiresIn?.inMilliseconds,
    'tags': def.tags,
  });

  String _instancePin(QuestInstance instance) => _jsonPin({
    'id': instance.instanceId,
    'questId': instance.questId,
    'owner': instance.ownerId,
    'version': instance.catalogVersion,
    'assigned': instance.assignedAtUtc.millisecondsSinceEpoch,
    'state': instance.state.name,
    'completed': instance.completedAtUtc?.millisecondsSinceEpoch,
    'expired': instance.expiredAtUtc?.millisecondsSinceEpoch,
    'progress': {
      for (final progress in instance.progress)
        progress.objectiveId: {
          'count': progress.currentCount,
          'target': progress.targetCount,
          'sources': progress.sourceEventIds,
        },
    },
  });

  String _jsonPin(Object? value) {
    Object? sorted(Object? input) {
      if (input is Map) {
        final keys = input.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: sorted(input[key])};
      }
      if (input is List) {
        return input.map(sorted).toList();
      }
      return input;
    }

    return jsonEncode(sorted(value));
  }

  void _text(String text) {
    if (!LearningEvidenceContract.validIdentifier(text)) {
      _deny();
    }
  }

  Never _deny() => throw StateError('Quest canonical evidence rejected');

  db.QuestDefinitionsCompanion _definitionValues(QuestDefinition def) =>
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
      );

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
    if (instanceRows.isEmpty) {
      return const [];
    }

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
    for (final objective in objectivesRaw) {
      if (objective.length != 5 ||
          !objective.keys.toSet().containsAll({
            'objectiveId',
            'description',
            'targetCount',
            'eventType',
            'filters',
          })) {
        _deny();
      }
    }
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
    if (rewardRaw.length != 2 ||
        !rewardRaw.keys.toSet().containsAll({'xpAmount', 'rewardItemId'})) {
      _deny();
    }
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
