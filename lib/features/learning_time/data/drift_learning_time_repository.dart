import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/learning_time_admission.dart';
import '../application/learning_time_use_cases.dart';

final class DriftLearningTimeRepository implements LearningTimeRepository {
  DriftLearningTimeRepository({
    required this.database,
    required DriftOwnerWriteCoordinator ownerWrites,
    required DriftLearningRepository learning,
  }) : _ownerWrites = ownerWrites,
       _learning = learning {
    if (!identical(database, ownerWrites.database) ||
        !identical(database, learning.database)) {
      throw ArgumentError(
        'Learning time requires the real same-database writers',
      );
    }
  }

  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator _ownerWrites;
  final DriftLearningRepository _learning;
  final _issuedSources = Expando<bool>();
  final _issuedLinks = Expando<bool>();

  @override
  Stream<LearningTimePreference?> watchPreference(String ownerId) {
    _id(ownerId);
    return database
        .customSelect(
          'SELECT p.* FROM local_owners o '
          'LEFT JOIN learning_time_preferences p ON p.owner_id = o.id '
          'WHERE o.id = ? AND o.is_active = 1',
          variables: [Variable<String>(ownerId)],
          readsFrom: {
            database.localOwners,
            database.learningTimePreferences,
            database.runtimeFlags,
          },
        )
        .watch()
        .asyncMap((_) async {
          try {
            return await readPreference(
              expectedOwnerId: ownerId,
              isCurrent: () => true,
            );
          } on Object {
            return null;
          }
        });
  }

  @override
  Future<LearningTimePreference> readPreference({
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    await _requireOwner(expectedOwnerId, isCurrent);
    final result = await _readPreference(expectedOwnerId);
    await _requireOwner(expectedOwnerId, isCurrent);
    return result;
  }

  @override
  Future<LearningTimePreference> commitPreference(
    LearningTimePreferenceIntent intent,
  ) async {
    if (!intent.belongsTo(this)) _unavailable();
    _integer(intent.expectedRevision, min: 0, max: 9007199254740990);
    _utc(intent.updatedAtUtcMs);
    return _write(
      intent.ownerId,
      () => intent.isCurrent,
      write: () async {
        final current = await _readPreference(intent.ownerId);
        if (current.revision == intent.expectedRevision + 1 &&
            current.enabled == intent.enabled &&
            current.updatedAtUtcMs == intent.updatedAtUtcMs) {
          return current;
        }
        if (current.revision != intent.expectedRevision) _conflict();
        if (current.enabled == intent.enabled) return current;
        await database.customStatement(
          'INSERT INTO learning_time_preferences (owner_id,enabled,revision,updated_at_utc_ms) '
          'VALUES (?,?,?,?) ON CONFLICT(owner_id) DO UPDATE SET '
          'enabled=excluded.enabled,revision=excluded.revision,updated_at_utc_ms=excluded.updated_at_utc_ms',
          [
            intent.ownerId,
            intent.enabled ? 1 : 0,
            current.revision + 1,
            intent.updatedAtUtcMs,
          ],
        );
        return LearningTimePreference(
          ownerId: intent.ownerId,
          enabled: intent.enabled,
          revision: current.revision + 1,
          updatedAtUtcMs: intent.updatedAtUtcMs,
        );
      },
      verify: (result) async {
        if (!(await _readPreference(intent.ownerId)).sameAs(result)) {
          _unavailable();
        }
      },
      updates: {database.learningTimePreferences},
    );
  }

  @override
  Future<TimeSourceAdmission> admitSource({
    required TimeSource source,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) _unavailable();
    await _requireOwner(expectedOwnerId, isCurrent);
    if (source.callerContext != LearningTimeCallerContext.ordinary) {
      _unavailable();
    }
    late final TimeSourceKind kind;
    late final String sourceJson;
    late final String contextJson;
    CanonicalLearningTimeAdmission? canonical;
    switch (source) {
      case CanonicalTimeSource(:final proof):
        await _learning.requireLiveCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: isCurrent,
        );
        if (proof.ownerId != expectedOwnerId) _unavailable();
        kind = TimeSourceKind.values.byName(proof.sourceKind.name);
        sourceJson = proof.sourceBindingJson;
        contextJson = proof.contextBindingJson;
        canonical = proof;
      case ReadingTimeSource():
        kind = TimeSourceKind.reading;
        sourceJson = source.sourceBindingJson;
        contextJson = source.contextBindingJson;
      case TutorTimeSource():
        kind = TimeSourceKind.tutor;
        sourceJson = source.sourceBindingJson;
        contextJson = source.contextBindingJson;
    }
    _binding(sourceJson, kind, false);
    _binding(contextJson, kind, true);
    await _requireOwner(expectedOwnerId, isCurrent);
    final proof = canonical;
    final admission = TimeSourceAdmission(
      ownerId: expectedOwnerId,
      sourceKind: kind,
      sourceBindingJson: sourceJson,
      contextBindingJson: contextJson,
      linkedSessionId: proof?.sessionId,
      sessionLinkBindingJson: proof == null
          ? null
          : _linkJson(proof.sessionId, sourceJson, proof.sourceBindingJson),
      verifyClosed: (ownerStillCurrent) async {
        await _requireOwner(expectedOwnerId, ownerStillCurrent);
        if (proof != null) {
          await _learning.requireCanonicalLearningTimeAdmission(
            proof,
            expectedOwnerId: expectedOwnerId,
            ownerStillCurrent: ownerStillCurrent,
          );
        }
      },
    );
    _issuedSources[admission] = true;
    return admission;
  }

  @override
  Future<void> commitSegment(ClosedTimeSegmentIntent intent) async {
    if (!intent.belongsTo(this) || _issuedSources[intent.admission] != true) {
      _unavailable();
    }
    final scope = intent.scope;
    _validateScope(scope);
    _id(intent.id, prefix: 'time-segment:');
    _integer(intent.ordinal, min: 0, max: 9007199254740991);
    _integer(
      intent.activeDurationUs,
      min: 1,
      max: learningTimeMaximumSegmentUs,
    );
    _utc(intent.startedAtUtcMs);
    _utc(intent.endedAtUtcMs);
    if (intent.capturePolicyRevision != learningTimeCapturePolicyRevision ||
        scope.ownerId != intent.admission.ownerId ||
        scope.sourceKind != intent.admission.sourceKind ||
        scope.sourceBindingJson != intent.admission.sourceBindingJson ||
        intent.eligibilityContextJson != intent.admission.contextBindingJson) {
      _unavailable();
    }
    _binding(intent.eligibilityContextJson, scope.sourceKind, true);
    final expected = <String, Object?>{
      'id': intent.id,
      'scope_id': scope.id,
      'ordinal': intent.ordinal,
      'eligibility_context_json': intent.eligibilityContextJson,
      'started_at_utc_ms': intent.startedAtUtcMs,
      'ended_at_utc_ms': intent.endedAtUtcMs,
      'active_duration_us': intent.activeDurationUs,
      'capture_policy_revision': intent.capturePolicyRevision,
    };
    Future<void> requirePermission() async {
      await _requireCapture(
        scope.ownerId,
        intent.preferenceRevision,
        () => intent.isCurrent,
      );
      await intent.admission.verifyClosed(
        ownerStillCurrent: () => intent.isCurrent,
      );
      final link = intent.sessionLinkAdmission;
      if (link != null) {
        _requireIssuedLink(link, scope);
        await link.verifyClosed(ownerStillCurrent: () => intent.isCurrent);
      }
      if (scope.linkedSessionId != null &&
          (scope.linkedSessionId != intent.admission.linkedSessionId ||
              scope.sessionLinkBindingJson !=
                  intent.admission.sessionLinkBindingJson) &&
          link == null) {
        _unavailable();
      }
    }

    await _write<void>(
      scope.ownerId,
      () => intent.isCurrent,
      write: () async {
        await requirePermission();
        var existingScope = await _scopeRow(scope.id);
        if (existingScope == null) {
          if (intent.ordinal != 0) _conflict();
          await database.customStatement(
            'INSERT INTO learning_time_scopes '
            '(id,owner_id,source_kind,source_binding_json,created_at_utc_ms,linked_session_id,session_link_binding_json) '
            'VALUES (?,?,?,?,?,?,?)',
            [
              scope.id,
              scope.ownerId,
              scope.sourceKind.name,
              scope.sourceBindingJson,
              scope.createdAtUtcMs,
              scope.linkedSessionId,
              scope.sessionLinkBindingJson,
            ],
          );
          existingScope = await _scopeRow(scope.id);
        }
        _requireSameScope(existingScope, scope);
        final existing = await _segmentRow(intent.id);
        if (existing != null) {
          if (!_sameRow(existing, expected)) _conflict();
          return;
        }
        final previous = await database
            .customSelect(
              'SELECT COUNT(*) AS count,MAX(ordinal) AS last FROM learning_time_segments WHERE scope_id = ?',
              variables: [Variable<String>(scope.id)],
            )
            .getSingle();
        if (previous.read<int>('count') != intent.ordinal ||
            (previous.readNullable<int>('last') ?? -1) != intent.ordinal - 1) {
          _conflict();
        }
        await database.customStatement(
          'INSERT INTO learning_time_segments '
          '(id,scope_id,ordinal,eligibility_context_json,started_at_utc_ms,ended_at_utc_ms,active_duration_us,capture_policy_revision) '
          'VALUES (?,?,?,?,?,?,?,?)',
          expected.values.toList(),
        );
      },
      verify: (_) async {
        await requirePermission();
        _requireSameScope(await _scopeRow(scope.id), scope);
        final row = await _segmentRow(intent.id);
        if (row == null || !_sameRow(row, expected)) _unavailable();
      },
      updates: {database.learningTimeScopes, database.learningTimeSegments},
    );
  }

  @override
  Future<TimeSessionLinkAdmission> prepareSessionLink({
    required LearningTimeScope scope,
    required CanonicalLearningTimeSessionLinkReceipt proof,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) _unavailable();
    _validateScope(scope);
    await _requireOwner(expectedOwnerId, isCurrent);
    if (scope.ownerId != expectedOwnerId ||
        proof.ownerId != expectedOwnerId ||
        scope.sourceKind.name != proof.sourceKind.name ||
        scope.sourceBindingJson != proof.sourceBindingJson) {
      _unavailable();
    }
    await _learning.requireCanonicalLearningTimeSessionLinkReceipt(
      proof,
      expectedOwnerId: expectedOwnerId,
      ownerStillCurrent: isCurrent,
    );
    final result = TimeSessionLinkAdmission(
      ownerId: expectedOwnerId,
      scopeId: scope.id,
      linkedSessionId: proof.sessionId,
      sessionLinkBindingJson: _linkJson(
        proof.sessionId,
        scope.sourceBindingJson,
        proof.sourceBindingJson,
      ),
      verifyClosed: (ownerStillCurrent) =>
          _learning.requireCanonicalLearningTimeSessionLinkReceipt(
            proof,
            expectedOwnerId: expectedOwnerId,
            ownerStillCurrent: ownerStillCurrent,
          ),
    );
    await _requireOwner(expectedOwnerId, isCurrent);
    _issuedLinks[result] = true;
    return result;
  }

  @override
  Future<void> commitSessionLink(TimeSessionLinkIntent intent) async {
    if (!intent.belongsTo(this)) _unavailable();
    _validateScope(intent.scope);
    _requireIssuedLink(intent.admission, intent.scope);
    Future<void> requirePermission() async {
      await _requireCapture(
        intent.scope.ownerId,
        intent.preferenceRevision,
        () => intent.isCurrent,
      );
      await intent.admission.verifyClosed(
        ownerStillCurrent: () => intent.isCurrent,
      );
    }

    await _write<void>(
      intent.scope.ownerId,
      () => intent.isCurrent,
      write: () async {
        await requirePermission();
        final row = await _scopeRow(intent.scope.id);
        _requireSameScope(row, intent.scope);
        final existing = row!.readNullable<String>('linked_session_id');
        if (existing != null) {
          if (existing != intent.linkedSessionId ||
              row.readNullable<String>('session_link_binding_json') !=
                  intent.sessionLinkBindingJson) {
            _conflict();
          }
          return;
        }
        await database.customStatement(
          'UPDATE learning_time_scopes SET linked_session_id=?,session_link_binding_json=? WHERE id=? AND linked_session_id IS NULL',
          [
            intent.linkedSessionId,
            intent.sessionLinkBindingJson,
            intent.scope.id,
          ],
        );
      },
      verify: (_) async {
        await requirePermission();
        final row = await _scopeRow(intent.scope.id);
        _requireSameScope(row, intent.scope);
        if (row!.readNullable<String>('linked_session_id') !=
                intent.linkedSessionId ||
            row.readNullable<String>('session_link_binding_json') !=
                intent.sessionLinkBindingJson) {
          _unavailable();
        }
      },
      updates: {database.learningTimeScopes},
    );
  }

  @override
  Future<RecordedTimeRead> read({
    required TimeReadTarget target,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    try {
      await _requireOwner(expectedOwnerId, isCurrent);
      final variables = <Variable>[Variable<String>(expectedOwnerId)];
      var predicate = '';
      switch (target) {
        case OwnerTimeRead(:final sourceKind):
          if (sourceKind != null) {
            predicate = ' AND s.source_kind = ?';
            variables.add(Variable<String>(sourceKind.name));
          }
        case ScopeTimeRead(:final scopeId):
          _id(scopeId, prefix: 'time-scope:');
          predicate = ' AND s.id = ?';
          variables.add(Variable<String>(scopeId));
        case SessionTimeRead(:final sessionId):
          _id(sessionId);
          if (!await _supportsSession(expectedOwnerId, sessionId)) {
            await _requireOwner(expectedOwnerId, isCurrent);
            return const RecordedTimeRead.unsupported();
          }
          predicate = ' AND s.linked_session_id = ?';
          variables.add(Variable<String>(sessionId));
      }
      final rows = await database
          .customSelect(
            'SELECT s.*,g.id AS segment_id,g.ordinal,g.eligibility_context_json,'
            'g.started_at_utc_ms,g.ended_at_utc_ms,g.active_duration_us,g.capture_policy_revision '
            'FROM learning_time_scopes s JOIN learning_time_segments g ON g.scope_id=s.id '
            'WHERE s.owner_id = ?$predicate ORDER BY s.id,g.ordinal',
            variables: variables,
          )
          .get();
      var total = 0;
      final scopes = <String>{};
      for (final row in rows) {
        final scope = _decodeScope(row);
        if (scope.ownerId != expectedOwnerId) _unavailable();
        if (scopes.add(scope.id) && scope.linkedSessionId != null) {
          if (!await _supportsSession(
            expectedOwnerId,
            scope.linkedSessionId!,
          )) {
            _unavailable();
          }
        }
        _id(row.read<String>('segment_id'), prefix: 'time-segment:');
        _integer(row.read<int>('ordinal'), min: 0, max: 9007199254740991);
        _binding(
          row.read<String>('eligibility_context_json'),
          scope.sourceKind,
          true,
        );
        _utc(row.read<int>('started_at_utc_ms'));
        _utc(row.read<int>('ended_at_utc_ms'));
        final duration = row.read<int>('active_duration_us');
        _integer(duration, min: 1, max: learningTimeMaximumSegmentUs);
        if (row.read<String>('capture_policy_revision') !=
            learningTimeCapturePolicyRevision) {
          _unavailable();
        }
        total += duration;
        _integer(total, min: 1, max: 9007199254740991);
      }
      await _requireOwner(expectedOwnerId, isCurrent);
      return rows.isEmpty
          ? const RecordedTimeRead.noneRecorded()
          : RecordedTimeRead.recorded(
              activeDurationUs: total,
              segmentCount: rows.length,
            );
    } on Object {
      return const RecordedTimeRead.unavailable();
    }
  }

  Future<T> _write<T>(
    String ownerId,
    bool Function() isCurrent, {
    required Future<T> Function() write,
    required Future<void> Function(T) verify,
    required Set<TableInfo> updates,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) _unavailable();
    _check(isCurrent);
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        _check(isCurrent);
        final result = await write();
        return _ownerWrites.writeForActiveOwner(
          expectedOwnerId: ownerId,
          write: () async {
            await verify(result);
            _check(isCurrent);
            database.markTablesUpdated(updates);
            return result;
          },
        );
      },
    );
  }

  Future<void> _requireCapture(
    String ownerId,
    int revision,
    bool Function() isCurrent,
  ) async {
    await _requireOwner(ownerId, isCurrent);
    final preference = await _readPreference(ownerId);
    if (!preference.enabled || preference.revision != revision) _unavailable();
    _check(isCurrent);
  }

  Future<LearningTimePreference> _readPreference(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM learning_time_preferences WHERE owner_id=?',
          variables: [Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    return row == null
        ? LearningTimePreference.absent(ownerId)
        : _preference(row, ownerId);
  }

  LearningTimePreference _preference(QueryRow row, String ownerId) {
    final enabled = row.read<int>('enabled');
    final revision = row.read<int>('revision');
    final updated = row.read<int>('updated_at_utc_ms');
    if (row.read<String>('owner_id') != ownerId ||
        (enabled != 0 && enabled != 1)) {
      _unavailable();
    }
    _integer(revision, min: 1, max: 9007199254740991);
    _utc(updated);
    return LearningTimePreference(
      ownerId: ownerId,
      enabled: enabled == 1,
      revision: revision,
      updatedAtUtcMs: updated,
    );
  }

  Future<QueryRow?> _scopeRow(String id) => database
      .customSelect(
        'SELECT * FROM learning_time_scopes WHERE id=?',
        variables: [Variable<String>(id)],
      )
      .getSingleOrNull();
  Future<QueryRow?> _segmentRow(String id) => database
      .customSelect(
        'SELECT * FROM learning_time_segments WHERE id=?',
        variables: [Variable<String>(id)],
      )
      .getSingleOrNull();

  LearningTimeScope _decodeScope(QueryRow row) {
    final result = LearningTimeScope(
      id: row.read<String>('id'),
      ownerId: row.read<String>('owner_id'),
      sourceKind: TimeSourceKind.values.byName(row.read<String>('source_kind')),
      sourceBindingJson: row.read<String>('source_binding_json'),
      createdAtUtcMs: row.read<int>('created_at_utc_ms'),
      linkedSessionId: row.readNullable<String>('linked_session_id'),
      sessionLinkBindingJson: row.readNullable<String>(
        'session_link_binding_json',
      ),
    );
    _validateScope(result);
    return result;
  }

  void _requireSameScope(QueryRow? row, LearningTimeScope expected) {
    if (row == null) _unavailable();
    final current = _decodeScope(row);
    if (current.id != expected.id ||
        current.ownerId != expected.ownerId ||
        current.sourceKind != expected.sourceKind ||
        current.sourceBindingJson != expected.sourceBindingJson ||
        current.createdAtUtcMs != expected.createdAtUtcMs) {
      _conflict();
    }
    if (expected.linkedSessionId != null &&
        (current.linkedSessionId != expected.linkedSessionId ||
            current.sessionLinkBindingJson !=
                expected.sessionLinkBindingJson)) {
      _conflict();
    }
  }

  void _validateScope(LearningTimeScope scope) {
    _id(scope.id, prefix: 'time-scope:');
    _id(scope.ownerId);
    _utc(scope.createdAtUtcMs);
    _binding(scope.sourceBindingJson, scope.sourceKind, false);
    if ((scope.linkedSessionId == null) !=
        (scope.sessionLinkBindingJson == null)) {
      _unavailable();
    }
    if (scope.linkedSessionId != null) {
      _id(scope.linkedSessionId!);
      final link = parseTimeSessionLinkBindingJson(
        scope.sessionLinkBindingJson!,
      );
      if (link['sessionId'] != scope.linkedSessionId ||
          link['sourceBindingSha256'] != _digest(scope.sourceBindingJson) ||
          link['canonicalSourceBindingSha256'] !=
              _digest(scope.sourceBindingJson)) {
        _unavailable();
      }
    }
  }

  void _requireIssuedLink(
    TimeSessionLinkAdmission link,
    LearningTimeScope scope,
  ) {
    if (_issuedLinks[link] != true ||
        link.ownerId != scope.ownerId ||
        link.scopeId != scope.id) {
      _unavailable();
    }
    if (scope.linkedSessionId != null &&
        (scope.linkedSessionId != link.linkedSessionId ||
            scope.sessionLinkBindingJson != link.sessionLinkBindingJson)) {
      _conflict();
    }
  }

  String _linkJson(String sessionId, String source, String canonical) =>
      jsonEncode({
        'schemaVersion': 1,
        'sessionId': sessionId,
        'sourceBindingSha256': _digest(source),
        'canonicalSourceBindingSha256': _digest(canonical),
      });
  String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
  void _binding(String value, TimeSourceKind kind, bool context) {
    final decoded = parseTimeBindingJson(
      value,
      sourceKind: kind,
      isContext: context,
    );
    if (jsonEncode(decoded) != value) _unavailable();
  }

  bool _sameRow(QueryRow row, Map<String, Object?> expected) =>
      row.data.length == expected.length &&
      expected.entries.every((e) => row.data[e.key] == e.value);

  Future<bool> _supportsSession(String ownerId, String sessionId) async {
    final row = await database
        .customSelect(
          'SELECT activity_type FROM learning_sessions WHERE id=? AND owner_id=?',
          variables: [Variable<String>(sessionId), Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    if (row == null ||
        !const {
          'quiz',
          'sourcePractice',
          'weaknessPractice',
          'srsReview',
          'dictation',
          'cloze',
          'associativeReading',
          'shadowing',
          'pronunciation',
        }.contains(row.read<String>('activity_type'))) {
      return false;
    }
    final controlled = await database
        .customSelect(
          'SELECT 1 FROM assessment_runs WHERE learning_session_id=? '
          'UNION ALL SELECT 1 FROM measurement_opportunities WHERE learning_session_id=? LIMIT 1',
          variables: [Variable<String>(sessionId), Variable<String>(sessionId)],
        )
        .getSingleOrNull();
    return controlled == null;
  }

  Future<void> _requireOwner(String ownerId, bool Function() isCurrent) async {
    _id(ownerId);
    _check(isCurrent);
    final owners =
        await (database.select(database.localOwners)
              ..where((owner) => owner.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1 || owners.single.id != ownerId) _unavailable();
    final fence = await _ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(ownerId) ||
            (fence.cloudReceipt != null &&
                ownerId ==
                    accountDeletionReplacementGuestOwnerId(
                      fence.cloudReceipt!,
                    )))) {
      _unavailable();
    }
    _check(isCurrent);
  }

  void _id(String value, {String prefix = ''}) {
    if (value.trim() != value ||
        value.trim().isEmpty ||
        utf8.encode(value).length > 256 ||
        (prefix.isNotEmpty &&
            (!value.startsWith(prefix) ||
                value.substring(prefix.length).trim().isEmpty))) {
      _unavailable();
    }
  }

  void _integer(int value, {required int min, required int max}) {
    if (value < min || value > max) _unavailable();
  }

  void _utc(int value) => _integer(value, min: 0, max: 8640000000000000);
  void _check(bool Function() isCurrent) {
    if (!isCurrent()) _unavailable();
  }

  Never _unavailable() => throw StateError('Learning-time storage unavailable');
  Never _conflict() => throw StateError('Learning-time identity conflict');
}
