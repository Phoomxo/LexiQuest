import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../progress/data/drift_review_center_queries.dart';
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
  db.AppDatabase get database => _database;
  DriftOwnerWriteCoordinator get ownerWrites => _ownerWrites;
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
      await _upsertDefinition(supplied);
    });
  }

  Future<void> _upsertDefinition(QuestDefinition supplied) async {
    final stored = await getDefinition(supplied.questId);
    if (stored != null) {
      if (supplied.catalogVersion < stored.catalogVersion ||
          (supplied.catalogVersion == stored.catalogVersion &&
              _definitionPin(supplied) != _definitionPin(stored))) {
        _deny();
      }
      if (supplied.catalogVersion == stored.catalogVersion) return;
    }
    final values = _definitionValues(supplied);
    if (stored == null) {
      await _database.into(_database.questDefinitions).insert(values);
    } else {
      await (_database.update(
        _database.questDefinitions,
      )..where((row) => row.questId.equals(supplied.questId))).write(values);
    }
  }

  @override
  Future<QuestInstance?> assignCurrentPeriod({
    required String ownerId,
    required QuestDefinition definition,
    required String instanceId,
    required DateTime assignedAtUtc,
    required String timezoneId,
    required bool Function() stillCurrent,
  }) async {
    final supplied = _snapshotDefinition(definition);
    _text(ownerId);
    _text(instanceId);
    _requireUtc(assignedAtUtc);
    final period = QuestPeriod.at(
      type: supplied.type,
      atUtc: assignedAtUtc,
      timezoneId: timezoneId,
    );
    final definitionJson = _definitionSnapshot(supplied);
    final digest = sha256.convert(utf8.encode(definitionJson)).toString();
    if (!stillCurrent()) _deny();
    await _requireTopLevel();
    return _guardOwner(
      ownerId,
      stillCurrent,
      (current) => _ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: () async {
          if (!current() || assignedAtUtc.isAfter(_now())) _deny();
          await _upsertDefinition(supplied);
          await _reconcileOwned(ownerId, [supplied], current);
          final existing =
              await (_database.select(_database.questInstances)..where(
                    (row) =>
                        row.ownerId.equals(ownerId) &
                        row.questId.equals(supplied.questId),
                  ))
                  .get();
          for (final row in existing) {
            final pinned = _rowPeriod(row);
            if (pinned != null) {
              if (row.periodKey == period.key || pinned.contains(assignedAtUtc)) {
                return null;
              }
              if (pinned.endUtc != null &&
                  period.startUtc != null &&
                  period.startUtc!.isBefore(pinned.endUtc!)) {
                return null;
              }
            } else if (row.state == 'active') {
              final legacy = await getDefinition(row.questId);
              if (legacy != null &&
                  legacy.catalogVersion == row.catalogVersion) {
                final expiry = legacy.expiresIn;
                if (expiry == null ||
                    !assignedAtUtc.isAfter(
                      DateTime.fromMillisecondsSinceEpoch(
                        row.assignedAtUtcMs,
                        isUtc: true,
                      ).add(expiry),
                    )) {
                  return null;
                }
              }
            }
          }
          final instance = QuestInstance(
            instanceId: instanceId,
            questId: supplied.questId,
            ownerId: ownerId,
            catalogVersion: supplied.catalogVersion,
            assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              assignedAtUtc.millisecondsSinceEpoch,
              isUtc: true,
            ),
            state: QuestInstanceState.active,
            progress: supplied.objectives
                .map(
                  (objective) => ObjectiveProgress(
                    objectiveId: objective.objectiveId,
                    currentCount: 0,
                    targetCount: objective.targetCount,
                  ),
                )
                .toList(),
            period: period,
            definition: supplied,
            definitionSha256: digest,
          );
          await _insertInitial(instance);
          if (!current()) _deny();
          await _ownerWrites.writeForActiveOwner(
            expectedOwnerId: ownerId,
            write: () async {
              final stored = await getDefinition(supplied.questId);
              if (!current() ||
                  stored == null ||
                  _definitionPin(stored) != _definitionPin(supplied)) {
                _deny();
              }
            },
          );
          return instance;
        },
      ),
    );
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
                  supplied.assignedAtUtc.millisecondsSinceEpoch ||
              existing.periodKey !=
                  (supplied.period?.key ?? 'legacy:${supplied.instanceId}') ||
              existing.periodJson != supplied.period?.json ||
              existing.definitionSnapshotJson !=
                  (supplied.definition == null
                      ? null
                      : _definitionSnapshot(supplied.definition!)) ||
              existing.definitionSha256 != supplied.definitionSha256) {
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
        await _insertInitial(supplied);
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

  Future<void> _insertInitial(QuestInstance instance) async {
    await _database
        .into(_database.questInstances)
        .insert(
          db.QuestInstancesCompanion.insert(
            instanceId: instance.instanceId,
            questId: instance.questId,
            ownerId: instance.ownerId,
            catalogVersion: instance.catalogVersion,
            assignedAtUtcMs: instance.assignedAtUtc.millisecondsSinceEpoch,
            state: 'active',
            periodKey: Value(
              instance.period?.key ?? 'legacy:${instance.instanceId}',
            ),
            periodJson: Value(instance.period?.json),
            definitionSnapshotJson: Value(
              instance.definition == null
                  ? null
                  : _definitionSnapshot(instance.definition!),
            ),
            definitionSha256: Value(instance.definitionSha256),
          ),
        );
    for (final progress in instance.progress) {
      await _database
          .into(_database.questObjectiveProgress)
          .insert(
            db.QuestObjectiveProgressCompanion.insert(
              id: '${instance.instanceId}:${progress.objectiveId}',
              instanceId: instance.instanceId,
              objectiveId: progress.objectiveId,
              targetCount: progress.targetCount,
            ),
          );
    }
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) =>
      _queryInstances(ownerId, stateFilter: 'active');

  @override
  Future<List<QuestInstance>> getAllInstances(String ownerId) =>
      _queryInstances(ownerId);

  @override
  Future<List<QuestCompletedEvent>> reconcile({
    required String expectedOwnerId,
    required List<QuestDefinition> catalog,
    required bool Function() stillCurrent,
  }) async {
    final definitions = List<QuestDefinition>.unmodifiable(
      catalog.map(_snapshotDefinition),
    );
    if (definitions.map((def) => def.questId).toSet().length !=
        definitions.length) {
      _deny();
    }
    return _guardOwner(expectedOwnerId, stillCurrent, (current) async {
      await _requireTopLevel();
      return _ownerWrites.writeForActiveOwner(
        expectedOwnerId: expectedOwnerId,
        write: () => _reconcileOwned(expectedOwnerId, definitions, current),
      );
    });
  }

  Future<List<QuestCompletedEvent>> _reconcileOwned(
    String expectedOwnerId,
    List<QuestDefinition> definitions,
    bool Function() current,
  ) async {
    final now = _now();
    for (final def in definitions) {
      await _upsertDefinition(def);
    }
    final rows =
        await (_database.select(_database.questInstances)
              ..where(
                (row) =>
                    row.ownerId.equals(expectedOwnerId) &
                    row.state.equals('active'),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.assignedAtUtcMs),
                (row) => OrderingTerm.asc(row.instanceId),
              ]))
            .get();
    final completions = <QuestCompletedEvent>[];
    final sourcePins = <String, String>{};
    final finalPins = <String, String>{};
    for (final row in rows) {
      if (!current()) _deny();
      if (!definitions.any((def) => def.questId == row.questId)) continue;
      final pinnedDefinition = _pinnedDefinition(row);
      final def = pinnedDefinition ?? await getDefinition(row.questId);
      if (def == null || def.catalogVersion != row.catalogVersion) continue;
      var instance = await _validatedInstance(row, def);
      await _validateSources(instance, def, now, sourcePins);
      final end = _expirationAt(instance, def);
      final lastEligibleMs = end != null && !end.isAfter(now)
          ? end.millisecondsSinceEpoch - 1
          : now.millisecondsSinceEpoch;
      final answers =
          await (_database.select(_database.answerAttempts)
                ..where(
                  (answer) =>
                      answer.ownerId.equals(expectedOwnerId) &
                      answer.occurredAtUtcMs.isBiggerOrEqualValue(
                        instance.assignedAtUtc.millisecondsSinceEpoch,
                      ) &
                      answer.occurredAtUtcMs.isSmallerOrEqualValue(
                        lastEligibleMs,
                      ),
                )
                ..orderBy([
                  (answer) => OrderingTerm.asc(answer.occurredAtUtcMs),
                  (answer) => OrderingTerm.asc(answer.id),
                ]))
              .get();
      for (final answer in answers) {
        final at = DateTime.fromMillisecondsSinceEpoch(
          answer.occurredAtUtcMs,
          isUtc: true,
        );
        if (!_withinWindow(instance, def, at) ||
            !_eligibleAnswer(answer) ||
            await _isResearchControlledSession(answer.sessionId)) {
          continue;
        }
        final source = await _loadAnswer(answer.id, expectedOwnerId);
        final pin = _answerPin(source);
        if (sourcePins[answer.id] != null && sourcePins[answer.id] != pin) {
          _deny();
        }
        sourcePins[answer.id] = pin;
        completions.addAll(
          await _applyOwnedEvent(
            ownerId: expectedOwnerId,
            suppliedEvent: _answerEvent(source.$1, source.$2),
            suppliedCatalog: definitions,
            historical: true,
            onlyInstanceId: instance.instanceId,
          ),
        );
        final actual =
            await (_database.select(_database.questInstances)..where(
                  (value) => value.instanceId.equals(instance.instanceId),
                ))
                .getSingle();
        instance = await _validatedInstance(actual, def);
        if (instance.state != QuestInstanceState.active) break;
      }
      if (instance.state == QuestInstanceState.active &&
          _isExpired(instance, def, now)) {
        final expiry = _expirationAt(instance, def)!;
        final count =
            await (_database.update(_database.questInstances)..where(
                  (value) =>
                      value.instanceId.equals(instance.instanceId) &
                      value.ownerId.equals(expectedOwnerId) &
                      value.state.equals('active'),
                ))
                .write(
                  db.QuestInstancesCompanion(
                    state: const Value('expired'),
                    expiredAtUtcMs: Value(expiry.millisecondsSinceEpoch),
                  ),
                );
        if (count != 1) _deny();
      }
      final finalRow =
          await (_database.select(
                _database.questInstances,
              )..where((value) => value.instanceId.equals(instance.instanceId)))
              .getSingle();
      instance = await _validatedInstance(finalRow, def);
      await _validateSources(instance, def, now, sourcePins);
      finalPins[instance.instanceId] = _instancePin(instance);
    }
    for (final entry in sourcePins.entries) {
      if (_answerPin(await _loadAnswer(entry.key, expectedOwnerId)) !=
          entry.value) {
        _deny();
      }
    }
    for (final entry in finalPins.entries) {
      final row = await (_database.select(
        _database.questInstances,
      )..where((value) => value.instanceId.equals(entry.key))).getSingle();
      final def = _pinnedDefinition(row) ?? await getDefinition(row.questId);
      if (def == null ||
          _instancePin(await _validatedInstance(row, def)) != entry.value) {
        _deny();
      }
    }
    for (final definition in definitions) {
      final actual = await getDefinition(definition.questId);
      if (actual == null ||
          _definitionPin(actual) != _definitionPin(definition)) {
        _deny();
      }
    }
    if (!current() || _now().isBefore(now)) _deny();
    await _requireReadOwner(expectedOwnerId, current);
    return List<QuestCompletedEvent>.unmodifiable(completions);
  }

  @override
  Future<List<QuestCompletionReceipt>> readValidatedCompletions({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _guardOwner(expectedOwnerId, stillCurrent, (current) async {
    final result = await readValidatedCompletionsForProjection(
      ownerId: expectedOwnerId,
      nowUtc: _now(),
    );
    await _requireReadOwner(expectedOwnerId, current);
    return result;
  });

  Future<List<QuestCompletionReceipt>> readValidatedCompletionsForProjection({
    required String ownerId,
    required DateTime nowUtc,
  }) => _database.transaction(() async {
    _text(ownerId);
    final now = _requireUtc(nowUtc);
    final rows =
        await (_database.select(_database.questInstances)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.state.equals('completed'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.instanceId)]))
            .get();
    final result = <QuestCompletionReceipt>[];
    final pins = <String, String>{};
    for (final row in rows) {
      final def = _pinnedDefinition(row);
      if (def == null) continue;
      final instance = await _validatedInstance(row, def);
      await _validateSources(instance, def, now, pins);
      result.add(
        QuestCompletionReceipt(
          instance: instance,
          definition: def,
          completion: instance.complete(),
        ),
      );
    }
    for (final pin in pins.entries) {
      if (_answerPin(await _loadAnswer(pin.key, ownerId)) != pin.value) _deny();
    }
    for (final receipt in result) {
      final row =
          await (_database.select(_database.questInstances)..where(
                (value) => value.instanceId.equals(receipt.instance.instanceId),
              ))
              .getSingle();
      final def = _pinnedDefinition(row);
      if (def == null ||
          _instancePin(await _validatedInstance(row, def)) !=
              _instancePin(receipt.instance)) {
        _deny();
      }
    }
    return List<QuestCompletionReceipt>.unmodifiable(result);
  });

  Future<T> _guardOwner<T>(
    String ownerId,
    bool Function() stillCurrent,
    Future<T> Function(bool Function()) operation,
  ) async {
    var valid = true;
    final subscription = _database
        .tableUpdates(TableUpdateQuery.onTable(_database.localOwners))
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    try {
      await _requireReadOwner(ownerId, current);
      final result = await operation(current);
      await _requireReadOwner(ownerId, current);
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _requireReadOwner(
    String ownerId,
    bool Function() current,
  ) async {
    await requireReviewReadOwner(
      _database,
      expectedOwnerId: ownerId,
      stillCurrent: current,
    );
    final fence = await _ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(ownerId) ||
            (fence.cloudReceipt != null &&
                ownerId ==
                    accountDeletionReplacementGuestOwnerId(
                      fence.cloudReceipt!,
                    )))) {
      _deny();
    }
    if (!current()) _deny();
  }

  bool _eligibleAnswer(db.AnswerAttempt answer) =>
      LearningEvidenceContract.validAttempt(
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
      ) &&
      LearningEvidenceContract.allowsOrdinaryProjection(
        promptMode: answer.promptMode,
        evidenceClass: answer.evidenceClass,
        evidenceContextJson: answer.evidenceContextJson,
        projection: LearningProjection.quest,
      );

  bool _withinWindow(QuestInstance instance, QuestDefinition def, DateTime at) {
    final expiry = _customExpiry(instance, def);
    return !at.isBefore(instance.assignedAtUtc) &&
        (instance.period?.contains(at) ?? true) &&
        (expiry == null || !at.isAfter(instance.assignedAtUtc.add(expiry)));
  }

  Duration? _customExpiry(QuestInstance instance, QuestDefinition def) {
    final standard = switch (def.type) {
      QuestType.daily => const Duration(days: 1),
      QuestType.weekly => const Duration(days: 7),
      QuestType.milestone || QuestType.story => null,
    };
    return instance.period != null && def.expiresIn == standard
        ? null
        : def.expiresIn;
  }

  DateTime? _expirationAt(QuestInstance instance, QuestDefinition def) {
    final periodEnd = instance.period?.endUtc;
    final expiry = _customExpiry(instance, def);
    final cap = expiry == null
        ? null
        : instance.assignedAtUtc
              .add(expiry)
              .add(const Duration(milliseconds: 1));
    if (periodEnd == null) return cap;
    return cap != null && cap.isBefore(periodEnd) ? cap : periodEnd;
  }

  bool _isExpired(QuestInstance instance, QuestDefinition def, DateTime now) {
    final at = _expirationAt(instance, def);
    return at != null && !now.isBefore(at);
  }

  Future<DateTime?> _validateSources(
    QuestInstance instance,
    QuestDefinition def,
    DateTime now,
    Map<String, String> pins,
  ) async {
    DateTime? latest;
    for (final progress in instance.progress) {
      final objective = def.objectives.singleWhere(
        (value) => value.objectiveId == progress.objectiveId,
      );
      for (final id in progress.sourceEventIds) {
        final source = await _loadAnswer(id, instance.ownerId);
        final event = _answerEvent(source.$1, source.$2);
        _requireWindow(
          instance,
          def,
          event.occurredAtUtc,
          now,
          historical: true,
        );
        if (!objective.criteria.matches(event)) _deny();
        final pin = _answerPin(source);
        if (pins[id] != null && pins[id] != pin) _deny();
        pins[id] = pin;
        if (latest == null || event.occurredAtUtc.isAfter(latest)) {
          latest = event.occurredAtUtc;
        }
      }
    }
    if (instance.state == QuestInstanceState.completed &&
        instance.period != null &&
        (latest == null || latest != instance.completedAtUtc)) {
      _deny();
    }
    return latest;
  }

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
      write: () => _applyOwnedEvent(
        ownerId: ownerId,
        suppliedEvent: suppliedEvent,
        suppliedCatalog: suppliedCatalog,
      ),
    );
  }

  Future<List<QuestCompletedEvent>> _applyOwnedEvent({
    required String ownerId,
    required EventEnvelopeV2 suppliedEvent,
    required List<QuestDefinition> suppliedCatalog,
    bool historical = false,
    String? onlyInstanceId,
  }) async {
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
              (row) => row.ownerId.equals(ownerId) & row.state.equals('active'),
            ))
            .get();
    final completions = <QuestCompletedEvent>[];
    final expected = <String, String>{};
    final definitionPins = <String, String>{};
    final windows = <QuestInstance, QuestDefinition>{};

    for (final row in instanceRows) {
      if (onlyInstanceId != null && row.instanceId != onlyInstanceId) continue;
      final pinned = _pinnedDefinition(row);
      final matches = suppliedCatalog.where(
        (def) => def.questId == row.questId,
      );
      if (pinned == null && matches.isEmpty) continue;
      if (matches.length != 1) {
        _deny();
      }
      final supplied = matches.single;
      final currentDefinition = await getDefinition(row.questId);
      if (pinned == null && currentDefinition == null) continue;
      if (currentDefinition == null ||
          _definitionPin(currentDefinition) != _definitionPin(supplied)) {
        _deny();
      }
      if (pinned == null &&
          currentDefinition.catalogVersion != row.catalogVersion) {
        continue;
      }
      final stored = pinned ?? currentDefinition;
      if (stored.catalogVersion != row.catalogVersion) _deny();
      definitionPins[row.questId] = _definitionPin(currentDefinition);
      final instance = await _validatedInstance(row, stored);
      _requireWindow(
        instance,
        stored,
        canonical.occurredAtUtc,
        now,
        historical: historical,
      );
      windows[instance] = stored;

      for (final progress in instance.progress) {
        final objective = stored.objectives.singleWhere(
          (objective) => objective.objectiveId == progress.objectiveId,
        );
        for (final id in progress.sourceEventIds) {
          final prior = await _loadAnswer(id, ownerId);
          final priorEvent = _answerEvent(prior.$1, prior.$2);
          _requireWindow(
            instance,
            stored,
            priorEvent.occurredAtUtc,
            now,
            historical: historical,
          );
          if (!objective.criteria.matches(priorEvent)) {
            _deny();
          }
          sourcePins[id] = _answerPin(prior);
        }
      }

      final updated = instance.advanceIfMatches(canonical, stored.objectives);
      if (!identical(instance, updated)) {
        for (final progress in updated.progress) {
          final count =
              await (_database.update(_database.questObjectiveProgress)..where(
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
      if (!identical(instance, updated) && updated.isAllObjectivesComplete) {
        final completedAt = await _validateSources(
          updated,
          stored,
          now,
          sourcePins,
        );
        if (completedAt == null) _deny();
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
                    completedAtUtcMs: Value(completedAt.millisecondsSinceEpoch),
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
          period: updated.period,
          definition: updated.definition,
          definitionSha256: updated.definitionSha256,
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
        _pinnedDefinition(row) ??
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
            historical: historical,
          );
        }
      },
    );
    return List<QuestCompletedEvent>.unmodifiable(completions);
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
    if (await _isResearchControlledSession(session.id)) _deny();
    return (answer, session);
  }

  Future<bool> _isResearchControlledSession(String sessionId) async =>
      await _database
          .customSelect(
            'SELECT 1 AS controlled FROM assessment_runs WHERE learning_session_id=? '
            'UNION ALL SELECT 1 AS controlled FROM measurement_opportunities '
            'WHERE learning_session_id=? LIMIT 1',
            variables: [
              Variable<String>(sessionId),
              Variable<String>(sessionId),
            ],
          )
          .getSingleOrNull() !=
      null;

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
    DateTime now, {
    bool historical = false,
  }) {
    if (occurred.isBefore(instance.assignedAtUtc) || occurred.isAfter(now)) {
      _deny();
    }
    final expiry = _customExpiry(instance, def);
    final period = instance.period;
    if (period != null &&
        (!period.contains(occurred) ||
            (!historical && !period.contains(now)))) {
      _deny();
    }
    if (expiry != null) {
      final deadline = instance.assignedAtUtc.add(expiry);
      if (occurred.isAfter(deadline) ||
          (!historical && now.isAfter(deadline))) {
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
    final period = instance.period;
    if (period != null &&
        (!period.contains(instance.assignedAtUtc) ||
            period.kind !=
                switch (def.type) {
                  QuestType.daily => 'daily',
                  QuestType.weekly => 'weekly',
                  QuestType.milestone || QuestType.story => 'once',
                } ||
            instance.definition == null ||
            _definitionPin(instance.definition!) != _definitionPin(def) ||
            sha256.convert(utf8.encode(_definitionSnapshot(def))).toString() !=
                instance.definitionSha256)) {
      _deny();
    }
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
        def.reward.xpAmount < 0 ||
        def.reward.xpAmount > 1000000 ||
        def.title.length > 200 ||
        def.description.length > 2000 ||
        def.tags.length > 20 ||
        def.tags.any((tag) => tag.length > 80) ||
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

  QuestPeriod? _rowPeriod(db.QuestInstance row) {
    final source = row.periodJson;
    if (source == null) {
      if (!row.periodKey.startsWith('legacy') ||
          row.definitionSnapshotJson != null ||
          row.definitionSha256 != null) {
        _deny();
      }
      return null;
    }
    if (row.definitionSnapshotJson == null || row.definitionSha256 == null) {
      _deny();
    }
    final period = QuestPeriod.parse(source);
    if (period.key != row.periodKey) _deny();
    return period;
  }

  String _definitionSnapshot(QuestDefinition def) {
    final source = _jsonPin({
      'schemaVersion': 1,
      ...jsonDecode(_definitionPin(def)) as Map<String, dynamic>,
    });
    if (utf8.encode(source).length > 16384) _deny();
    return source;
  }

  QuestDefinition? _pinnedDefinition(db.QuestInstance row) {
    if (_rowPeriod(row) == null) return null;
    final source = row.definitionSnapshotJson!;
    if (utf8.encode(source).length > 16384 ||
        sha256.convert(utf8.encode(source)).toString() != row.definitionSha256) {
      _deny();
    }
    final value = jsonDecode(source);
    const keys = {
      'schemaVersion',
      'questId',
      'catalogVersion',
      'title',
      'description',
      'type',
      'objectives',
      'reward',
      'expiresInMs',
      'tags',
    };
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['schemaVersion'] != 1) {
      _deny();
    }
    final objectives = <QuestObjective>[];
    for (final raw in value['objectives'] as List) {
      final object = raw as Map<String, dynamic>;
      if (object.length != 5 ||
          !object.keys.toSet().containsAll({
            'objectiveId',
            'description',
            'targetCount',
            'eventType',
            'filters',
          })) {
        _deny();
      }
      objectives.add(
        QuestObjective(
          objectiveId: object['objectiveId'] as String,
          description: object['description'] as String,
          targetCount: object['targetCount'] as int,
          criteria: ObjectiveCriteria(
            eventType: object['eventType'] as String,
            filters: (object['filters'] as Map?)?.cast<String, dynamic>(),
          ),
        ),
      );
    }
    final reward = value['reward'] as Map<String, dynamic>;
    if (reward.length != 2 ||
        !reward.keys.toSet().containsAll({'xpAmount', 'rewardItemId'})) {
      _deny();
    }
    final expiry = value['expiresInMs'] as int?;
    final def = _snapshotDefinition(
      QuestDefinition(
        questId: value['questId'] as String,
        catalogVersion: value['catalogVersion'] as int,
        title: value['title'] as String,
        description: value['description'] as String,
        type: QuestType.values.byName(value['type'] as String),
        objectives: objectives,
        reward: RewardSpec(
          xpAmount: reward['xpAmount'] as int,
          rewardItemId: reward['rewardItemId'] as String?,
        ),
        expiresIn: expiry == null ? null : Duration(milliseconds: expiry),
        tags: (value['tags'] as List).cast<String>(),
      ),
    );
    if (def.questId != row.questId ||
        def.catalogVersion != row.catalogVersion ||
        _definitionSnapshot(def) != source) {
      _deny();
    }
    return def;
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
    period: instance.period,
    definition: instance.definition == null
        ? null
        : _snapshotDefinition(instance.definition!),
    definitionSha256: instance.definitionSha256,
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
    'period': instance.period?.json,
    'definition': instance.definition == null
        ? null
        : _definitionSnapshot(instance.definition!),
    'definitionSha256': instance.definitionSha256,
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
      period: _rowPeriod(row),
      definition: _pinnedDefinition(row),
      definitionSha256: row.definitionSha256,
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
