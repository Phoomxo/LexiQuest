import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../adventure/domain/adventure_entry.dart';
import '../../learning/data/learning_session_lifecycle_observer.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_measurement.dart';
import '../domain/research_event_identity.dart';

final class DriftMotivationMeasurementTimingReader
    implements MotivationMeasurementTimingReader {
  const DriftMotivationMeasurementTimingReader(this.database);
  final AppDatabase database;

  @override
  Future<MotivationTimingFacts?> read({
    required String ownerId,
    required String runId,
    required String permitId,
    required String assignmentId,
  }) => _read(ownerId, runId, permitId, assignmentId);

  Future<MotivationTimingFacts?> readForAcceptedSession({
    required String ownerId,
    required String runId,
    required String permitId,
    required String assignmentId,
    required LearningSessionLifecycleFact session,
  }) => _read(ownerId, runId, permitId, assignmentId, accepted: session);

  Future<MeasurementOpportunity?> loadOpportunity(
    String ownerId,
    String id,
  ) async {
    final row = await database
        .customSelect(
          'SELECT * FROM measurement_opportunities WHERE id = ? AND owner_id = ?',
          variables: [Variable<String>(id), Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    return row == null ? null : _opportunity(row.data);
  }

  /// Integrity only. A pending receipt never becomes collection timing facts.
  Future<bool> validatePresentationHistory(
    MeasurementOpportunity opportunity, {
    DateTime? notAfter,
  }) async {
    try {
      final run = await _one(
        'SELECT * FROM motivation_measurement_runs WHERE id = ? AND owner_id = ?',
        [opportunity.measurementRunId, opportunity.ownerId],
      );
      if (run == null || opportunity.presentation == null) {
        return false;
      }
      final assignment = await _one(
        'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
        [_string(run['assignment_id']), opportunity.ownerId],
      );
      final permit = await _one(
        'SELECT * FROM research_participation_permits WHERE id = ? AND owner_id = ?',
        [opportunity.permitId, opportunity.ownerId],
      );
      final presented = await _one(
        'SELECT * FROM events_v2 WHERE event_id = ? AND owner_id = ?',
        [opportunity.presentation!.eventId, opportunity.ownerId],
      );
      final changed = await database
          .customSelect(
            'SELECT * FROM events_v2 WHERE event_type = ? AND (correlation_id = ? OR aggregate_id = ?)',
            variables: [
              const Variable<String>(measurementPresentationChangedEventType),
              Variable<String>(opportunity.id),
              Variable<String>(opportunity.id),
            ],
          )
          .get();
      return assignment != null &&
          permit != null &&
          presented != null &&
          _eventMatches(opportunity, presented, run, assignment, permit) &&
          _changedMatches(
            opportunity,
            changed.map((row) => row.data).toList(),
            run,
            assignment,
            permit,
            notAfter: notAfter,
          );
    } on Object {
      return false;
    }
  }

  Future<MotivationTimingFacts?> _read(
    String ownerId,
    String runId,
    String permitId,
    String assignmentId, {
    LearningSessionLifecycleFact? accepted,
  }) async {
    try {
      return await database.transaction(() async {
        final run = await _one(
          'SELECT * FROM motivation_measurement_runs WHERE id = ? AND owner_id = ?',
          [runId, ownerId],
        );
        if (run == null ||
            run['permit_id'] != permitId ||
            run['assignment_id'] != assignmentId) {
          return null;
        }
        final assignment = await _one(
          'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          [assignmentId, ownerId],
        );
        if (assignment == null ||
            assignment['cohort'] != run['treatment'] ||
            assignment['protocol_version'] != run['protocol_version']) {
          return null;
        }
        final permit = await _one(
          'SELECT * FROM research_participation_permits WHERE id = ? AND owner_id = ?',
          [permitId, ownerId],
        );
        if (permit == null ||
            permit['assignment_id'] != assignmentId ||
            permit['payload_sha256'] != run['permit_payload_sha256']) {
          return null;
        }

        final rows = await database
            .customSelect(
              'SELECT * FROM measurement_opportunities WHERE owner_id = ?',
              variables: [Variable<String>(ownerId)],
            )
            .get();
        final all = {
          for (final row in rows)
            _string(row.data['id']): _opportunity(row.data),
        };
        final opportunities = all.values
            .where((o) => o.measurementRunId == runId)
            .toList();
        for (final o in opportunities) {
          if (o.pendingPresentationChange != null ||
              o.permitId != permitId ||
              o.assignedTreatment.wireName != run['treatment'] ||
              o.openedAtUtc.millisecondsSinceEpoch <
                  _integer(run['started_at_utc_ms'])) {
            return null;
          }
        }
        final eventRows = await database
            .customSelect(
              'SELECT * FROM events_v2 WHERE owner_id = ? AND event_type = ?',
              variables: [
                Variable<String>(ownerId),
                const Variable<String>(measurementPresentedEventType),
              ],
            )
            .get();
        final events = {
          for (final row in eventRows) _string(row.data['event_id']): row.data,
        };
        for (final event in events.values) {
          final opportunity = all[event['correlation_id']];
          if (opportunity == null ||
              opportunity.presentation?.eventId != event['event_id'] ||
              event['aggregate_id'] != opportunity.id ||
              event['aggregate_type'] != 'MeasurementOpportunity') {
            return null;
          }
        }
        for (final o in opportunities) {
          final presentation = o.presentation;
          if (presentation == null) {
            continue;
          }
          final event = events[presentation.eventId];
          if (event == null ||
              !_eventMatches(o, event, run, assignment, permit)) {
            return null;
          }
        }
        final changedRows = await database
            .customSelect(
              'SELECT * FROM events_v2 WHERE owner_id = ? AND event_type = ?',
              variables: [
                Variable<String>(ownerId),
                const Variable<String>(measurementPresentationChangedEventType),
              ],
            )
            .get();
        for (final row in changedRows) {
          final linked = all[row.data['correlation_id']];
          if (linked == null || row.data['aggregate_id'] != linked.id) {
            return null;
          }
        }
        for (final o in opportunities) {
          if (!_changedMatches(
            o,
            changedRows
                .where((row) => row.data['correlation_id'] == o.id)
                .map((row) => row.data)
                .toList(),
            run,
            assignment,
            permit,
          )) {
            return null;
          }
        }
        final exposed =
            opportunities.where((o) => o.presentation != null).toList()
              ..sort((a, b) {
                final time = a.presentation!.occurredAtUtc.compareTo(
                  b.presentation!.occurredAtUtc,
                );
                return time == 0 ? a.id.compareTo(b.id) : time;
              });
        if (exposed.isEmpty) {
          return MotivationBeforeExposure(
            ownerId: ownerId,
            runId: runId,
            permitId: permitId,
            assignmentId: assignmentId,
          );
        }
        final first = exposed.first;
        final exposure = first.presentation!;
        final links = opportunities.where((o) => o.indexLink != null).toList();
        if (links.length > 1 ||
            (links.isNotEmpty && links.single.id != first.id)) {
          return null;
        }
        Map<String, Object?>? acceptedRow;
        if (accepted != null) {
          if (accepted.ownerId != ownerId) {
            return null;
          }
          acceptedRow = await _one(
            'SELECT * FROM learning_sessions WHERE id = ? AND owner_id = ?',
            [accepted.id, ownerId],
          );
          if (acceptedRow == null ||
              !_sameSession(acceptedRow, accepted) ||
              accepted.state != 'active' ||
              accepted.activityType == 'syncedEvidence') {
            return null;
          }
        }
        MotivationIndexSession? index;
        if (links.isNotEmpty) {
          final linked = links.single;
          final link = linked.indexLink!;
          final session = await _one(
            'SELECT * FROM learning_sessions WHERE id = ? AND owner_id = ?',
            [link.sessionId, ownerId],
          );
          if (session == null ||
              session['activity_type'] == 'syncedEvidence' ||
              session['state'] == 'syncedEvidence' ||
              session['app_version'] != run['app_version'] ||
              session['build_id'] != run['build_id'] ||
              session['started_at_utc_ms'] !=
                  link.startedAtUtc.millisecondsSinceEpoch ||
              link.startedAtUtc.isBefore(exposure.occurredAtUtc)) {
            return null;
          }
          final state = switch (session['state']) {
            'active' => MotivationIndexSessionState.active,
            'completed' => MotivationIndexSessionState.completed,
            'abandoned' => MotivationIndexSessionState.abandoned,
            _ => null,
          };
          if (state == null) {
            return null;
          }
          DateTime? end;
          if (state == MotivationIndexSessionState.completed) {
            end = _date(session['ended_at_utc_ms']);
            if (end.isBefore(link.startedAtUtc)) {
              return null;
            }
          } else if (state == MotivationIndexSessionState.active &&
              session['ended_at_utc_ms'] != null) {
            return null;
          }
          if (linked.closedAtUtc != null && linked.closedAtUtc != end) {
            return null;
          }
          index = MotivationIndexSession(
            id: link.sessionId,
            startedAtUtc: link.startedAtUtc,
            state: state,
            completedAtUtc: end,
          );
        }
        final candidates = await database
            .customSelect(
              'SELECT * FROM learning_sessions WHERE owner_id = ? AND started_at_utc_ms >= ? '
              "AND NOT (activity_type = 'syncedEvidence' AND state = 'syncedEvidence')",
              variables: [
                Variable<String>(ownerId),
                Variable<int>(exposure.occurredAtUtc.millisecondsSinceEpoch),
              ],
            )
            .get();
        final cutoff =
            index?.startedAtUtc.millisecondsSinceEpoch ??
            accepted?.startedAtUtcMs;
        for (final row in candidates) {
          final candidate = row.data;
          if (candidate['id'] == index?.id || candidate['id'] == accepted?.id) {
            continue;
          }
          if (cutoff == null ||
              _integer(candidate['started_at_utc_ms']) <= cutoff) {
            return null;
          }
        }
        if (acceptedRow != null &&
            (_integer(acceptedRow['started_at_utc_ms']) <
                    exposure.occurredAtUtc.millisecondsSinceEpoch ||
                acceptedRow['app_version'] != run['app_version'] ||
                acceptedRow['build_id'] != run['build_id'])) {
          return null;
        }
        return MotivationAfterExposure(
          ownerId: ownerId,
          runId: runId,
          permitId: permitId,
          assignmentId: assignmentId,
          firstExposureEventId: exposure.eventId,
          firstExposureAtUtc: exposure.occurredAtUtc,
          indexSession: index,
        );
      });
    } on Object {
      return null;
    }
  }

  static bool _eventMatches(
    MeasurementOpportunity o,
    Map<String, Object?> event,
    Map<String, Object?> run,
    Map<String, Object?> assignment,
    Map<String, Object?> permit, {
    DateTime? occurrence,
    String? eventIdentity,
    String? type,
    Map<String, Object?>? eventPayload,
  }) {
    final at = occurrence ?? o.presentation!.occurredAtUtc;
    final identity = eventIdentity ?? measurementPresentedIdentity(o.id);
    final payload =
        eventPayload ??
        <String, Object?>{
          'assignedTreatment': o.assignedTreatment.wireName,
          'effectivePresentation': o.effectivePresentation.wireName,
          'entryAttemptId': o.entryAttemptId,
          'catalogVersion': run['catalog_version'],
        };
    if (eventPayload == null) {
      validateMeasurementPresentedPayload(payload);
    }
    return event.length == 22 &&
        event['event_id'] == researchEventId(identity, at) &&
        event['event_type'] == (type ?? measurementPresentedEventType) &&
        event['event_version'] == measurementPresentedEventVersion &&
        event['owner_id'] == o.ownerId &&
        event['actor_identity'] == o.ownerId &&
        event['aggregate_type'] == 'MeasurementOpportunity' &&
        event['aggregate_id'] == o.id &&
        event['correlation_id'] == o.id &&
        event['idempotency_key'] == identity &&
        event['tenant_context_json'] == null &&
        event['causation_id'] == null &&
        event['provider_provenance_json'] == null &&
        event['occurred_at_utc'] == at.millisecondsSinceEpoch ~/ 1000 &&
        event['recorded_at_utc'] == at.millisecondsSinceEpoch ~/ 1000 &&
        event['content_revision'] == run['content_revision'] &&
        event['policy_version'] == run['evidence_policy_version'] &&
        event['app_version'] == run['app_version'] &&
        event['build_id'] == run['build_id'] &&
        event['privacy_classification'] == 'ownerOnly' &&
        _jsonMatches(event['payload_json'], payload) &&
        _jsonMatches(event['consent_context_json'], {
          'researchConsentVersion': run['consent_version'],
          'aiConsentGranted': false,
          'voiceConsentGranted': false,
          'socialConsentGranted': false,
        }) &&
        _jsonMatches(event['experiment_context_json'], {
          'experimentId': assignment['experiment_id'],
          'variantId': assignment['cohort'],
          'assignedAtUtc': _date(
            assignment['assigned_at_utc_ms'],
          ).toIso8601String(),
        }) &&
        _integer(run['consent_decided_at_utc_ms']) <=
            _integer(assignment['assigned_at_utc_ms']) &&
        _integer(assignment['assigned_at_utc_ms']) <=
            at.millisecondsSinceEpoch &&
        _integer(permit['issued_at_utc_ms']) <= at.millisecondsSinceEpoch;
  }

  static bool _changedMatches(
    MeasurementOpportunity o,
    List<Map<String, Object?>> events,
    Map<String, Object?> run,
    Map<String, Object?> assignment,
    Map<String, Object?> permit, {
    DateTime? notAfter,
  }) {
    if (events.length != o.lastSwitchOrdinal ||
        (o.presentation == null && o.totalSwitches != 0)) {
      return false;
    }
    if (o.presentation == null) {
      return true;
    }
    final byOrdinal = <int, Map<String, Object?>>{};
    for (final row in events) {
      final payload =
          jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
      validateMeasurementPresentationChangedPayload(payload);
      final ordinal = payload['switchOrdinal']! as int;
      if (byOrdinal.containsKey(ordinal)) {
        return false;
      }
      byOrdinal[ordinal] = row;
    }
    var previous = o.presentation!.occurredAtUtc;
    for (var ordinal = 1; ordinal <= o.lastSwitchOrdinal; ordinal++) {
      final row = byOrdinal[ordinal];
      if (row == null) {
        return false;
      }
      final at = researchEventOccurrence(
        _string(row['event_id']),
        DateTime.fromMillisecondsSinceEpoch(
          _integer(row['occurred_at_utc']) * 1000,
          isUtc: true,
        ),
      );
      final from = ordinal.isOdd
          ? o.effectivePresentation
          : oppositePresentation(o.effectivePresentation);
      final payload = <String, Object?>{
        'assignedTreatment': o.assignedTreatment.wireName,
        'effectivePresentation': oppositePresentation(from).wireName,
        'fromPresentation': from.wireName,
        'switchOrdinal': ordinal,
      };
      if (at.isBefore(previous) ||
          (notAfter != null && at.isAfter(notAfter)) ||
          (o.closedAtUtc != null && at.isAfter(o.closedAtUtc!)) ||
          !_eventMatches(
            o,
            row,
            run,
            assignment,
            permit,
            occurrence: at,
            eventIdentity: measurementPresentationChangedIdentity(
              o.id,
              ordinal,
            ),
            type: measurementPresentationChangedEventType,
            eventPayload: payload,
          )) {
        return false;
      }
      previous = at;
    }
    return true;
  }

  static MeasurementOpportunity _opportunity(Map<String, Object?> row) {
    final id = _string(row['id']);
    final owner = _string(row['owner_id']);
    final run = _string(row['measurement_run_id']);
    final permit = _string(row['permit_id']);
    final entry = _string(row['entry_attempt_id']);
    requireMeasurementEntryId(entry);
    if (id !=
        measurementOpportunityId(
          ownerId: owner,
          measurementRunId: run,
          permitId: permit,
          entryAttemptId: entry,
        )) {
      throw const FormatException('Opportunity identity mismatch');
    }
    final opened = _date(row['opened_at_utc_ms']);
    final revision = _integer(row['local_revision']);
    if (revision < 1) {
      throw const FormatException('Invalid opportunity revision');
    }
    MeasurementPresentationFact? presentation;
    if (row['presented_event_id'] != null ||
        row['presented_at_utc_ms'] != null) {
      final at = _date(row['presented_at_utc_ms']);
      if (at.isBefore(opened)) {
        throw const FormatException('Presentation precedes opportunity');
      }
      presentation = MeasurementPresentationFact(
        eventId: _string(row['presented_event_id']),
        occurredAtUtc: at,
      );
    }
    MeasurementIndexLink? index;
    if (row['learning_session_id'] != null ||
        row['learning_session_started_at_utc_ms'] != null ||
        row['is_index_session'] != 0) {
      final start = _date(row['learning_session_started_at_utc_ms']);
      if (row['is_index_session'] != 1 ||
          presentation == null ||
          start.isBefore(presentation.occurredAtUtc)) {
        throw const FormatException('Invalid index linkage');
      }
      index = MeasurementIndexLink(
        sessionId: _string(row['learning_session_id']),
        startedAtUtc: start,
      );
    }
    final closed = row['closed_at_utc_ms'] == null
        ? null
        : _date(row['closed_at_utc_ms']);
    if (closed != null &&
        (index == null || closed.isBefore(index.startedAtUtc))) {
      throw const FormatException('Invalid opportunity closure');
    }
    final ordinal = _integer(row['last_switch_ordinal']);
    final suppressed = _integer(row['suppressed_switch_count']);
    validatePresentationCounters(ordinal, suppressed);
    final startedPresentation = row['started_effective_presentation'] == null
        ? null
        : TodayExperiencePresentationCodec.decode(
            row['started_effective_presentation'],
          );
    if ((index == null) != (startedPresentation == null)) {
      throw const FormatException('Invalid Started presentation snapshot');
    }
    final pending = row['pending_presentation_change_json'] == null
        ? null
        : PendingPresentationChange.fromJson(
            _string(row['pending_presentation_change_json']),
          );
    final firstPresentation = TodayExperiencePresentationCodec.decode(
      row['effective_presentation'],
    );
    final currentPresentation = (ordinal + suppressed).isEven
        ? firstPresentation
        : oppositePresentation(firstPresentation);
    if (pending != null &&
        (pending.ownerId != owner ||
            pending.opportunityId != id ||
            pending.entryAttemptId != entry ||
            pending.baseRevision + 1 != revision ||
            pending.baseOrdinal != ordinal ||
            pending.baseSuppressed != suppressed ||
            pending.from != currentPresentation ||
            presentation == null ||
            pending.preparedAtUtc.isBefore(presentation.occurredAtUtc) ||
            closed != null)) {
      throw const FormatException('Invalid pending presentation binding');
    }
    return MeasurementOpportunity(
      id: id,
      ownerId: owner,
      measurementRunId: run,
      permitId: permit,
      entryAttemptId: entry,
      assignedTreatment: TodayExperiencePresentationCodec.decode(
        row['assigned_treatment'],
      ),
      effectivePresentation: TodayExperiencePresentationCodec.decode(
        row['effective_presentation'],
      ),
      openedAtUtc: opened,
      localRevision: revision,
      presentation: presentation,
      indexLink: index,
      closedAtUtc: closed,
      lastSwitchOrdinal: ordinal,
      suppressedSwitchCount: suppressed,
      startedEffectivePresentation: startedPresentation,
      pendingPresentationChange: pending,
    );
  }

  Future<Map<String, Object?>?> _one(String sql, List<String> values) async =>
      (await database
              .customSelect(
                sql,
                variables: values.map(Variable<String>.new).toList(),
              )
              .getSingleOrNull())
          ?.data;

  static bool _sameSession(
    Map<String, Object?> row,
    LearningSessionLifecycleFact fact,
  ) =>
      row['id'] == fact.id &&
      row['owner_id'] == fact.ownerId &&
      row['activity_type'] == fact.activityType &&
      row['state'] == fact.state &&
      row['started_at_utc_ms'] == fact.startedAtUtcMs &&
      row['ended_at_utc_ms'] == fact.endedAtUtcMs &&
      row['app_version'] == fact.appVersion &&
      row['build_id'] == fact.buildId;

  static bool _jsonMatches(Object? value, Map<String, Object?> expected) {
    if (value is! String) {
      return false;
    }
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> &&
        decoded.length == expected.length &&
        expected.entries.every((entry) => decoded[entry.key] == entry.value);
  }

  static int _integer(Object? value) {
    if (value is! int) {
      throw const FormatException('Expected integer');
    }
    return value;
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('Expected identifier');
    }
    return value;
  }

  static DateTime _date(Object? value) {
    final ms = _integer(value);
    if (ms < 0 || ms > 8640000000000000) {
      throw const FormatException('Invalid epoch');
    }
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
