import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../consent/application/research_consent_use_cases.dart'
    show ConsentUtcNow;
import '../domain/experiment_assignment.dart';
import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_measurement_repository.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_operation_authorizer.dart';
import 'drift_research_participation_repository.dart';

final class DriftMotivationMeasurementRepository
    implements MotivationMeasurementRepository {
  DriftMotivationMeasurementRepository(
    this.database, {
    required this.participation,
    required this.timing,
    required this.consentNowUtc,
  }) {
    if (!identical(participation.database, database)) {
      throw ArgumentError('Measurement and participation databases must match');
    }
  }

  final AppDatabase database;
  final DriftResearchParticipationRepository participation;
  final MotivationMeasurementTimingReader timing;
  final ConsentUtcNow consentNowUtc;
  MotivationStudyProtocol get _study => participation.assignments.binding.study;

  @override
  Future<MotivationMeasurementRun> start(MotivationMeasurementStart command) {
    _codes([command.ownerId, command.permitId]);
    return _owner(command.ownerId, () async {
      final authority = await _participant(command.ownerId, command.permitId);
      final id = motivationMeasurementRunId(
        ownerId: command.ownerId,
        permitId: command.permitId,
        protocolId: _study.protocolId,
        protocolVersion: _study.protocolVersion,
        instrumentChecksumSha256: _study.instrument.checksumSha256,
      );
      final existing = await _read(command.ownerId, id);
      if (existing != null) {
        _context(existing, authority, await _now());
        return _finish(existing, needTiming: false);
      }
      final conflict = await database
          .customSelect(
            'SELECT id FROM motivation_measurement_runs WHERE owner_id = ? AND '
            'assignment_id = ? AND protocol_id = ? AND protocol_version = ?',
            variables: [
              Variable<String>(command.ownerId),
              Variable<String>(authority.snapshot.assignment.id),
              Variable<String>(_study.protocolId),
              Variable<String>(_study.protocolVersion),
            ],
          )
          .getSingleOrNull();
      if (conflict != null) _deny(ResearchCaptureReason.versionConflict);
      final now = await _now();
      _authorityAt(authority, command.ownerId, now);
      final snapshot = authority.snapshot;
      final binding = participation.assignments.binding;
      await _insert('motivation_measurement_runs', {
        'id': id,
        'owner_id': command.ownerId,
        'local_revision': 1,
        'permit_id': command.permitId,
        'permit_payload_sha256': snapshot.permit.payloadSha256,
        'assignment_id': snapshot.assignment.id,
        'assignment_revision': binding.assignmentRevision,
        'consent_version': _study.consentVersion,
        'consent_decided_at_utc_ms':
            snapshot.consent.decidedAtUtc!.millisecondsSinceEpoch,
        'protocol_id': _study.protocolId,
        'protocol_version': _study.protocolVersion,
        'protocol_revision': binding.protocolRevision,
        'treatment': snapshot.assignment.cohort,
        'instrument_id': _study.instrument.instrumentId,
        'instrument_version': _study.instrument.instrumentVersion,
        'instrument_revision': binding.instrumentRevision,
        'instrument_checksum_sha256': _study.instrument.checksumSha256,
        'form_id': _study.instrument.formId,
        'form_version': _study.instrument.formVersion,
        'item_catalog_version': _study.instrument.itemCatalogVersion,
        'scoring_rule_version': motivationScoringRuleVersion,
        'app_version': _study.appVersion,
        'build_id': _study.buildId,
        'database_schema_version': database.schemaVersion,
        'content_revision': _study.contentRevision,
        'evidence_policy_version': _study.evidencePolicyVersion,
        'catalog_version': _study.catalogVersion,
        'state': 'started',
        'started_at_utc_ms': now.millisecondsSinceEpoch,
        'closed_at_utc_ms': null,
      });
      final inserted = await _read(command.ownerId, id);
      if (inserted == null) _deny(ResearchCaptureReason.identityConflict);
      return _finish(inserted, needTiming: false);
    });
  }

  @override
  Future<MotivationMeasurementRun> record(MotivationResponse command) {
    _codes([
      command.ownerId,
      command.runId,
      command.itemId,
      command.responseCode,
    ]);
    return _owner(command.ownerId, () async {
      final run = await _requiredRun(command.ownerId, command.runId);
      if (run.state == MotivationMeasurementRunState.withdrawn) {
        _deny(ResearchCaptureReason.withdrawn);
      }
      final authority = await _participant(run.ownerId, run.permitId);
      _context(run, authority, await _now());
      late final MotivationItem item;
      late final MotivationResponseOption option;
      try {
        item = _study.instrument.item(command.itemId);
        option = _study.instrument.response(
          command.itemId,
          command.responseCode,
        );
      } on FormatException {
        _deny(ResearchCaptureReason.invalidInput);
      }
      final prior = run.responses.where((r) => r.itemId == item.id).firstOrNull;
      if (prior != null) {
        if (prior.responseCode != command.responseCode) {
          _deny(ResearchCaptureReason.identityConflict);
        }
        return _finish(
          run,
          needTiming: true,
          validate: (result, facts, now) {
            _historicalResponse(result, prior, facts, now);
          },
        );
      }
      if (run.state != MotivationMeasurementRunState.started) {
        _deny(ResearchCaptureReason.noActiveRun);
      }
      final beforeTiming = await _timing(run);
      final now = await _now();
      _context(run, authority, now);
      _newResponseWindow(run, item.timepoint, beforeTiming, now);
      final answeredAt = _milliseconds(now);
      await _insert('motivation_responses', {
        'id': motivationResponseId(runId: run.id, itemId: item.id),
        'owner_id': run.ownerId,
        'local_revision': 1,
        'run_id': run.id,
        'item_id': item.id,
        'item_catalog_version': _study.instrument.itemCatalogVersion,
        'response_code': option.code,
        'ordinal_value': option.ordinalValue,
        'answered_at_utc_ms': answeredAt.millisecondsSinceEpoch,
      });
      final updated = await _requiredRun(run.ownerId, run.id);
      final complete =
          updated.score(MotivationTimepoint.baseline) != null &&
          updated.score(MotivationTimepoint.post) != null;
      if (complete) _completeTiming(updated, beforeTiming, now);
      await _transition(
        run,
        complete
            ? MotivationMeasurementRunState.completed
            : MotivationMeasurementRunState.started,
        complete ? answeredAt : null,
      );
      final expected = await _requiredRun(run.ownerId, run.id);
      return _finish(
        expected,
        needTiming: true,
        validate: (result, facts, lastNow) {
          _newResponseWindow(result, item.timepoint, facts, lastNow);
          if (!_sameTiming(beforeTiming, facts)) {
            _deny(ResearchCaptureReason.outsideWindow);
          }
          final response = result.responses
              .where((r) => r.itemId == item.id)
              .single;
          if (response.responseCode != option.code ||
              response.answeredAtUtc != answeredAt) {
            _deny(ResearchCaptureReason.identityConflict);
          }
          if (complete) _completeTiming(result, facts, lastNow);
        },
      );
    });
  }

  @override
  Future<MotivationMeasurementRun> close(MotivationMeasurementClose command) {
    _codes([command.ownerId, command.runId]);
    if (command.state == MotivationMeasurementRunState.started) {
      _deny(ResearchCaptureReason.invalidInput);
    }
    if (command.state == MotivationMeasurementRunState.withdrawn) {
      return _withdraw(command);
    }
    return _owner(command.ownerId, () async {
      final run = await _requiredRun(command.ownerId, command.runId);
      if (run.state == MotivationMeasurementRunState.withdrawn) {
        _deny(ResearchCaptureReason.withdrawn);
      }
      final authority = await _participant(run.ownerId, run.permitId);
      _context(run, authority, await _now());
      if (run.state == command.state) {
        return _finish(
          run,
          needTiming: run.state == MotivationMeasurementRunState.completed,
          validate: run.state == MotivationMeasurementRunState.completed
              ? _completeTiming
              : null,
        );
      }
      if (run.state != MotivationMeasurementRunState.started ||
          command.state == MotivationMeasurementRunState.completed) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      final now = await _now();
      _context(run, authority, now);
      await _transition(run, command.state, _milliseconds(now));
      return _finish(
        await _requiredRun(run.ownerId, run.id),
        needTiming: false,
      );
    });
  }

  Future<MotivationMeasurementRun> _withdraw(
    MotivationMeasurementClose command,
  ) async {
    final consent = participation.assignments.consent;
    final existing = await consent.load(
      ownerId: command.ownerId,
      version: _study.consentVersion,
    );
    if (existing.accepted) {
      final deniedAt = consentNowUtc();
      _validTime(deniedAt);
      await consent.decide(
        ownerId: command.ownerId,
        version: _study.consentVersion,
        accepted: false,
        decidedAtUtc: _milliseconds(deniedAt),
      );
    }
    final denied = await consent.load(
      ownerId: command.ownerId,
      version: _study.consentVersion,
    );
    if (denied.accepted) _deny(ResearchCaptureReason.ownerConflict);
    return _owner(command.ownerId, () async {
      final run = await _requiredRun(command.ownerId, command.runId);
      if (run.state == MotivationMeasurementRunState.withdrawn) return run;
      final now = await _now();
      _factTimes(run, now);
      await _transition(
        run,
        MotivationMeasurementRunState.withdrawn,
        run.closedAtUtc ?? _milliseconds(now),
      );
      return _requiredRun(run.ownerId, run.id);
    });
  }

  @override
  Future<MotivationMeasurementRun?> load(String ownerId, String runId) {
    _codes([ownerId, runId]);
    return _owner(ownerId, () async {
      final run = await _read(ownerId, runId);
      if (run == null) return null;
      MotivationTimingFacts? facts;
      try {
        facts = await _timing(run);
        final now = await _now();
        _factTimes(run, now);
        _factTiming(run, facts, now);
      } on Object {
        facts = null;
      }
      return _withTiming(run, facts);
    });
  }

  Future<MotivationMeasurementRun> _finish(
    MotivationMeasurementRun expected, {
    required bool needTiming,
    void Function(MotivationMeasurementRun, MotivationTimingFacts, DateTime)?
    validate,
  }) async {
    final authority = await _participant(expected.ownerId, expected.permitId);
    final facts = needTiming ? await _timing(expected) : null;
    return _owner(expected.ownerId, () async {
      final run = await _requiredRun(
        expected.ownerId,
        expected.id,
        timingFacts: facts,
      );
      final consent = await participation.assignments.consent.load(
        ownerId: run.ownerId,
        version: run.consentVersion,
      );
      final now = await _now();
      _context(run, authority, now);
      if (!consent.accepted ||
          consent.withdrawnAtUtc != null ||
          consent.decidedAtUtc != run.consentDecidedAtUtc) {
        _deny(ResearchCaptureReason.withdrawn);
      }
      if (run.localRevision != expected.localRevision ||
          run.state != expected.state ||
          run.closedAtUtc != expected.closedAtUtc) {
        _deny(ResearchCaptureReason.identityConflict);
      }
      if (facts != null) {
        _factTiming(run, facts, now);
        if (run.state == MotivationMeasurementRunState.completed) {
          _completeTiming(run, facts, now);
        }
        validate?.call(run, facts, now);
      }
      return run;
    });
  }

  Future<AuthorizedResearchParticipant> _participant(
    String ownerId,
    String permitId,
  ) async {
    final result = await participation.requireParticipantWithReceipt(
      ownerId: ownerId,
      permitId: permitId,
    );
    if (result == null) _deny(ResearchCaptureReason.invalidPermit);
    return result;
  }

  void _authorityAt(
    AuthorizedResearchParticipant authority,
    String ownerId,
    DateTime now,
  ) {
    final snapshot = authority.snapshot;
    final permit = snapshot.permit;
    final operation = authority.operation.permit;
    final binding = participation.assignments.binding;
    if (permit.ownerId != ownerId ||
        operation.ownerId != ownerId ||
        operation.assignmentId != snapshot.assignment.id ||
        operation.operation != ResearchOperation.collect ||
        operation.assignmentRevision != binding.assignmentRevision ||
        operation.protocolId != _study.protocolId ||
        operation.protocolRevision != binding.protocolRevision ||
        operation.instrumentId != _study.instrument.instrumentId ||
        operation.instrumentRevision != binding.instrumentRevision ||
        authority.operation.verifiedAtUtc.isAfter(now)) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    if (now.isBefore(operation.issuedAtUtc) ||
        !now.isBefore(operation.expiresAtUtc) ||
        now.isBefore(permit.issuedAtUtc) ||
        !now.isBefore(permit.expiresAtUtc)) {
      _deny(ResearchCaptureReason.expiredPermit);
    }
    if (permit.isDeleted ||
        (permit.revokedAtUtc != null && !now.isBefore(permit.revokedAtUtc!))) {
      _deny(ResearchCaptureReason.revokedPermit);
    }
    final decision = snapshot.consent.decidedAtUtc;
    if (!snapshot.consent.accepted ||
        snapshot.consent.withdrawnAtUtc != null ||
        decision == null ||
        snapshot.consent.version != _study.consentVersion ||
        snapshot.assignment.assignedAtUtc.isBefore(decision) ||
        snapshot.assignment.assignedAtUtc.isAfter(now)) {
      _deny(ResearchCaptureReason.withdrawn);
    }
  }

  void _context(
    MotivationMeasurementRun run,
    AuthorizedResearchParticipant authority,
    DateTime now,
  ) {
    _authorityAt(authority, run.ownerId, now);
    _factTimes(run, now);
    final snapshot = authority.snapshot;
    if (run.permitId != snapshot.permit.id ||
        run.permitPayloadSha256 != snapshot.permit.payloadSha256 ||
        run.assignmentId != snapshot.assignment.id ||
        run.treatment != snapshot.assignment.cohort ||
        run.treatment != snapshot.permit.assignedTreatment.wireName ||
        run.consentVersion != snapshot.consent.version ||
        run.consentDecidedAtUtc != snapshot.consent.decidedAtUtc ||
        run.startedAtUtc.isBefore(snapshot.assignment.assignedAtUtc) ||
        run.startedAtUtc.isBefore(snapshot.permit.issuedAtUtc)) {
      _deny(ResearchCaptureReason.versionConflict);
    }
  }

  static void _factTimes(MotivationMeasurementRun run, DateTime now) {
    if (run.startedAtUtc.isAfter(now) ||
        run.closedAtUtc?.isAfter(now) == true ||
        run.responses.any((response) => response.answeredAtUtc.isAfter(now))) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
  }

  Future<MotivationTimingFacts> _timing(MotivationMeasurementRun run) async {
    final facts = await timing.read(
      ownerId: run.ownerId,
      runId: run.id,
      permitId: run.permitId,
      assignmentId: run.assignmentId,
    );
    if (facts == null) _deny(ResearchCaptureReason.timingUnavailable);
    if (facts.ownerId != run.ownerId ||
        facts.runId != run.id ||
        facts.permitId != run.permitId ||
        facts.assignmentId != run.assignmentId) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    return facts;
  }

  void _factTiming(
    MotivationMeasurementRun run,
    MotivationTimingFacts facts,
    DateTime now,
  ) {
    if (facts is MotivationBeforeExposure) return;
    final exposed = facts as MotivationAfterExposure;
    _codes([exposed.firstExposureEventId]);
    _validTime(exposed.firstExposureAtUtc);
    if (exposed.firstExposureAtUtc.isBefore(run.startedAtUtc) ||
        exposed.firstExposureAtUtc.isAfter(now)) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
    final index = exposed.indexSession;
    if (index == null) return;
    _codes([index.id]);
    _validTime(index.startedAtUtc);
    if (index.startedAtUtc.isBefore(exposed.firstExposureAtUtc) ||
        index.startedAtUtc.isAfter(now)) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
    if (index.state == MotivationIndexSessionState.completed) {
      final end = index.completedAtUtc;
      if (end == null) _deny(ResearchCaptureReason.sessionUnavailable);
      _validTime(end);
      if (end.isBefore(index.startedAtUtc) || end.isAfter(now)) {
        _deny(ResearchCaptureReason.outsideWindow);
      }
    } else if (index.completedAtUtc != null) {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
  }

  void _newResponseWindow(
    MotivationMeasurementRun run,
    MotivationTimepoint point,
    MotivationTimingFacts facts,
    DateTime now,
  ) {
    _factTiming(run, facts, now);
    if (point == MotivationTimepoint.baseline) {
      if (facts is! MotivationBeforeExposure) {
        _deny(ResearchCaptureReason.outsideWindow);
      }
      return;
    }
    if (facts is! MotivationAfterExposure ||
        facts.indexSession?.state != MotivationIndexSessionState.completed) {
      _deny(ResearchCaptureReason.sessionUnavailable);
    }
    final completion = facts.indexSession!.completedAtUtc!;
    if (now.isBefore(completion) ||
        now.isAfter(completion.add(const Duration(minutes: 30)))) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
  }

  void _historicalResponse(
    MotivationMeasurementRun run,
    RecordedMotivationResponse response,
    MotivationTimingFacts facts,
    DateTime now,
  ) {
    _factTiming(run, facts, now);
    if (response.answeredAtUtc.isBefore(run.startedAtUtc) ||
        response.answeredAtUtc.isAfter(now)) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
    if (_study.instrument.item(response.itemId).timepoint ==
        MotivationTimepoint.baseline) {
      if (facts is MotivationAfterExposure &&
          response.answeredAtUtc.isAfter(facts.firstExposureAtUtc)) {
        _deny(ResearchCaptureReason.outsideWindow);
      }
    } else {
      if (facts is! MotivationAfterExposure ||
          facts.indexSession?.state != MotivationIndexSessionState.completed) {
        _deny(ResearchCaptureReason.sessionUnavailable);
      }
      final end = facts.indexSession!.completedAtUtc!;
      if (response.answeredAtUtc.isBefore(end) ||
          response.answeredAtUtc.isAfter(
            end.add(const Duration(minutes: 30)),
          )) {
        _deny(ResearchCaptureReason.outsideWindow);
      }
    }
  }

  void _completeTiming(
    MotivationMeasurementRun run,
    MotivationTimingFacts facts,
    DateTime now,
  ) {
    if (run.score(MotivationTimepoint.baseline) == null ||
        run.score(MotivationTimepoint.post) == null ||
        facts is! MotivationAfterExposure ||
        facts.indexSession?.state != MotivationIndexSessionState.completed) {
      _deny(ResearchCaptureReason.incomplete);
    }
    for (final response in run.responses) {
      _historicalResponse(run, response, facts, now);
    }
  }

  static bool _sameTiming(MotivationTimingFacts a, MotivationTimingFacts b) {
    if (a is MotivationBeforeExposure) return b is MotivationBeforeExposure;
    if (b is! MotivationAfterExposure) return false;
    final first = a as MotivationAfterExposure;
    return first.firstExposureEventId == b.firstExposureEventId &&
        first.firstExposureAtUtc == b.firstExposureAtUtc &&
        first.indexSession?.id == b.indexSession?.id &&
        first.indexSession?.startedAtUtc == b.indexSession?.startedAtUtc &&
        first.indexSession?.state == b.indexSession?.state &&
        first.indexSession?.completedAtUtc == b.indexSession?.completedAtUtc;
  }

  Future<MotivationMeasurementRun> _requiredRun(
    String ownerId,
    String runId, {
    MotivationTimingFacts? timingFacts,
  }) async {
    final run = await _read(ownerId, runId, timingFacts: timingFacts);
    if (run == null) _deny(ResearchCaptureReason.noActiveRun);
    return run;
  }

  Future<MotivationMeasurementRun?> _read(
    String ownerId,
    String runId, {
    MotivationTimingFacts? timingFacts,
  }) async {
    final row = await database
        .customSelect(
          'SELECT * FROM motivation_measurement_runs WHERE id = ? AND owner_id = ?',
          variables: [Variable<String>(runId), Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final r = row.data;
    final binding = participation.assignments.binding;
    final expected = <String, Object?>{
      'owner_id': ownerId,
      'assignment_id': experimentAssignmentId(
        ownerId: ownerId,
        experimentId: _study.experimentId,
        experimentVersion: _study.experimentVersion,
      ),
      'assignment_revision': binding.assignmentRevision,
      'consent_version': _study.consentVersion,
      'protocol_id': _study.protocolId,
      'protocol_version': _study.protocolVersion,
      'protocol_revision': binding.protocolRevision,
      'instrument_id': _study.instrument.instrumentId,
      'instrument_version': _study.instrument.instrumentVersion,
      'instrument_revision': binding.instrumentRevision,
      'instrument_checksum_sha256': _study.instrument.checksumSha256,
      'form_id': _study.instrument.formId,
      'form_version': _study.instrument.formVersion,
      'item_catalog_version': _study.instrument.itemCatalogVersion,
      'scoring_rule_version': motivationScoringRuleVersion,
      'app_version': _study.appVersion,
      'build_id': _study.buildId,
      'database_schema_version': database.schemaVersion,
      'content_revision': _study.contentRevision,
      'evidence_policy_version': _study.evidencePolicyVersion,
      'catalog_version': _study.catalogVersion,
    };
    if (expected.entries.any((entry) => r[entry.key] != entry.value)) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    final permitId = _text(r['permit_id']);
    _codes([permitId]);
    final hash = _text(r['permit_payload_sha256']);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        runId !=
            motivationMeasurementRunId(
              ownerId: ownerId,
              permitId: permitId,
              protocolId: _study.protocolId,
              protocolVersion: _study.protocolVersion,
              instrumentChecksumSha256: _study.instrument.checksumSha256,
            )) {
      _deny(ResearchCaptureReason.identityConflict);
    }
    final started = _date(r['started_at_utc_ms']);
    final decision = _date(r['consent_decided_at_utc_ms']);
    final closed = r['closed_at_utc_ms'] == null
        ? null
        : _date(r['closed_at_utc_ms']);
    final state = MotivationMeasurementRunState.values
        .where((s) => s.name == r['state'])
        .firstOrNull;
    final revision = _integer(r['local_revision']);
    if (state == null ||
        revision < 1 ||
        started.isBefore(decision) ||
        (state == MotivationMeasurementRunState.started
            ? closed != null
            : closed == null || closed.isBefore(started))) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    final rows = await database
        .customSelect(
          'SELECT * FROM motivation_responses WHERE owner_id = ? AND run_id = ? ORDER BY item_id',
          variables: [Variable<String>(ownerId), Variable<String>(runId)],
        )
        .get();
    final responses = <RecordedMotivationResponse>[];
    final seen = <String>{};
    for (final answer in rows) {
      final value = answer.data;
      final itemId = _text(value['item_id']);
      final code = _text(value['response_code']);
      late final MotivationResponseOption option;
      try {
        option = _study.instrument.response(itemId, code);
      } on FormatException {
        _deny(ResearchCaptureReason.versionConflict);
      }
      final answered = _date(value['answered_at_utc_ms']);
      if (!seen.add(itemId) ||
          value['id'] != motivationResponseId(runId: runId, itemId: itemId) ||
          value['item_catalog_version'] !=
              _study.instrument.itemCatalogVersion ||
          value['ordinal_value'] != option.ordinalValue ||
          value['local_revision'] != 1 ||
          answered.isBefore(started) ||
          (closed != null && answered.isAfter(closed))) {
        _deny(ResearchCaptureReason.versionConflict);
      }
      responses.add(
        RecordedMotivationResponse(
          id: _text(value['id']),
          itemId: itemId,
          responseCode: code,
          ordinalValue: option.ordinalValue,
          answeredAtUtc: answered,
          localRevision: 1,
        ),
      );
    }
    final run = MotivationMeasurementRun(
      id: runId,
      ownerId: ownerId,
      permitId: permitId,
      permitPayloadSha256: hash,
      assignmentId: _text(r['assignment_id']),
      assignmentRevision: binding.assignmentRevision,
      protocolRevision: binding.protocolRevision,
      instrumentRevision: binding.instrumentRevision,
      consentVersion: _study.consentVersion,
      consentDecidedAtUtc: decision,
      treatment: _text(r['treatment']),
      study: _study,
      databaseSchemaVersion: database.schemaVersion,
      state: state,
      startedAtUtc: started,
      closedAtUtc: closed,
      localRevision: revision,
      responses: responses,
      timing: timingFacts,
    );
    if (state == MotivationMeasurementRunState.completed &&
        (run.score(MotivationTimepoint.baseline) == null ||
            run.score(MotivationTimepoint.post) == null)) {
      _deny(ResearchCaptureReason.incomplete);
    }
    return run;
  }

  Future<void> _transition(
    MotivationMeasurementRun run,
    MotivationMeasurementRunState state,
    DateTime? closed,
  ) async {
    await database.customStatement(
      'UPDATE motivation_measurement_runs SET state = ?, closed_at_utc_ms = ?, local_revision = ? '
      'WHERE id = ? AND owner_id = ? AND local_revision = ?',
      [
        state.name,
        closed?.millisecondsSinceEpoch,
        run.localRevision + 1,
        run.id,
        run.ownerId,
        run.localRevision,
      ],
    );
    final changed = await database
        .customSelect('SELECT changes() AS changed')
        .getSingle();
    if (changed.read<int>('changed') != 1) {
      _deny(ResearchCaptureReason.identityConflict);
    }
  }

  Future<void> _insert(
    String table,
    Map<String, Object?> values,
  ) => database.customStatement(
    'INSERT INTO $table (${values.keys.join(', ')}) VALUES (${List.filled(values.length, '?').join(', ')})',
    values.values.toList(),
  );

  Future<T> _owner<T>(String ownerId, Future<T> Function() work) async {
    try {
      return await participation.assignments.ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: work,
      );
    } on AccountDeletionException {
      _deny(ResearchCaptureReason.ownerConflict);
    }
  }

  Future<DateTime> _now() async {
    final reading = await participation.assignments.trustedTime.read();
    if (reading == null || !reading.isFresh) {
      _deny(ResearchCaptureReason.invalidPermit);
    }
    final now = reading.effectiveNowUtc;
    _validTime(now);
    return now;
  }

  static MotivationMeasurementRun _withTiming(
    MotivationMeasurementRun run,
    MotivationTimingFacts? facts,
  ) => MotivationMeasurementRun(
    id: run.id,
    ownerId: run.ownerId,
    permitId: run.permitId,
    permitPayloadSha256: run.permitPayloadSha256,
    assignmentId: run.assignmentId,
    assignmentRevision: run.assignmentRevision,
    protocolRevision: run.protocolRevision,
    instrumentRevision: run.instrumentRevision,
    consentVersion: run.consentVersion,
    consentDecidedAtUtc: run.consentDecidedAtUtc,
    treatment: run.treatment,
    study: run.study,
    databaseSchemaVersion: run.databaseSchemaVersion,
    state: run.state,
    startedAtUtc: run.startedAtUtc,
    closedAtUtc: run.closedAtUtc,
    localRevision: run.localRevision,
    responses: run.responses,
    timing: facts,
  );

  static void _codes(List<String> values) {
    try {
      for (final value in values) {
        requireResearchCode(value);
      }
    } on FormatException {
      _deny(ResearchCaptureReason.invalidInput);
    }
  }

  static void _validTime(DateTime value) {
    if (!value.isUtc || value.microsecondsSinceEpoch < 0) {
      _deny(ResearchCaptureReason.outsideWindow);
    }
  }

  static int _integer(Object? value) {
    if (value is! int) _deny(ResearchCaptureReason.versionConflict);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String || value.isEmpty) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    return value;
  }

  static DateTime _date(Object? value) {
    final epoch = _integer(value);
    if (epoch < 0 || epoch > 8640000000000000) {
      _deny(ResearchCaptureReason.versionConflict);
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
  }

  static DateTime _milliseconds(DateTime now) =>
      DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      );
  static Never _deny(ResearchCaptureReason reason) =>
      throw ResearchCaptureDenied(reason);
}
