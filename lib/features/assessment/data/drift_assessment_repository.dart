import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' show AppDatabase;
import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../../runtime/app_build_info.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../research/domain/research_authority_snapshot.dart';
import '../../research/domain/research_participation_permit.dart';
import '../domain/assessment_authority.dart';
import '../domain/assessment_instrument_catalog.dart';
import '../domain/assessment_models.dart';
import '../domain/assessment_repository.dart';
import 'drift_assessment_authority.dart';
import 'drift_assessment_cycle_reader.dart';
import 'assessment_run_codec.dart';

/// Owns a durable outer transaction. No ordinary learning or reward writer runs.
final class DriftAssessmentRepository implements AssessmentRepository {
  DriftAssessmentRepository(
    this.database, {
    required this.authority,
    required this.cycleReader,
    required this.catalog,
    required this.contentAuthority,
    required this.buildInfo,
    required this.participationPermitId,
  }) {
    if (!identical(database, authority.cache.ownerWrites.database) ||
        !identical(database, cycleReader.database)) {
      throw ArgumentError(
        'Assessment and authority must share the actual database.',
      );
    }
    AssessmentRun.validateCanonicalText(
      participationPermitId,
      'participationPermitId',
    );
  }
  final AppDatabase database;
  final DriftAssessmentAuthority authority;
  final DriftAssessmentCycleReader cycleReader;
  final AssessmentInstrumentCatalog catalog;
  final AssessmentFormContentAuthority contentAuthority;
  final AppBuildInfo buildInfo;
  final String participationPermitId;

  @override
  Future<AssessmentRun> start(
    AssessmentStartCommand command, {
    required String ownerId,
    required bool Function() stillVisible,
  }) async {
    await _outside(stillVisible);
    _ids(ownerId, command.runId);
    AssessmentRun.validateCanonicalText(
      command.learningSessionId,
      'learningSessionId',
    );
    AssessmentRun.validateCanonicalText(command.studyCycleId, 'studyCycleId');
    final scope = authority.cache.currentScope();
    final generation = authority.cache.readGeneration;
    final definition = catalog.lookup(
      instrumentId: command.instrumentId,
      instrumentVersion: command.instrumentVersion,
      formId: command.formId,
      formVersion: command.formVersion,
    );
    await _content(definition, stillVisible);
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final previous = await _find(command.runId);
        if (previous != null) {
          if (previous.ownerId != ownerId ||
              previous.learningSessionId != command.learningSessionId ||
              previous.studyCycleId != command.studyCycleId ||
              previous.phase != command.phase ||
              previous.instrumentId != command.instrumentId ||
              previous.instrumentVersion != command.instrumentVersion ||
              previous.formId != command.formId ||
              previous.formVersion != command.formVersion) {
            _conflict(
              command.runId,
              'Start identity already has different intent.',
            );
          }
          _definition(previous);
          await _container(previous);
          _visible(stillVisible);
          return previous;
        }
        final existing = await database
            .customSelect(
              'SELECT id FROM assessment_runs WHERE owner_id = ? AND study_cycle_id = ? AND phase = ?',
              variables: [
                Variable<String>(ownerId),
                Variable<String>(command.studyCycleId),
                Variable<String>(command.phase.name),
              ],
            )
            .getSingleOrNull();
        if (existing != null) {
          _conflict(command.runId, 'Cycle phase already has its original run.');
        }
        _captured(scope, generation, ownerId);
        final receipt = await authority.requireCurrent(
          expectedScope: scope!,
          definition: definition,
          expectedParticipationPermitId: participationPermitId,
        );
        final run = AssessmentRun(
          id: command.runId,
          ownerId: ownerId,
          learningSessionId: command.learningSessionId,
          studyCycleId: command.studyCycleId,
          phase: command.phase,
          state: AssessmentRunState.active,
          protocolId: receipt.mapping.protocolId,
          protocolVersion: receipt.mapping.protocolVersion,
          protocolRevision: receipt.mapping.protocolRevision,
          experimentId: receipt.assignment.experimentId,
          experimentVersion: receipt.assignment.experimentVersion,
          assignmentId: receipt.assignment.id,
          assignmentRevision: scope.requirements.assignmentRevision,
          cohort: receipt.assignment.cohort,
          consentVersion: scope.consentVersion,
          consentDecidedAtUtc: receipt.consentDecidedAtUtc,
          instrumentId: definition.instrumentId,
          instrumentVersion: definition.instrumentVersion,
          instrumentRevision: receipt.mapping.instrumentRevision,
          formId: definition.formId,
          formVersion: definition.formVersion,
          formContentRevision: definition.formContentRevision,
          participationPermitId: receipt.participationPermitId,
          participationPermitRevision: receipt.participationPermitRevision,
          participationPermitPayloadSha256:
              receipt.participationPermitPayloadSha256,
          instrumentChecksumSha256: definition.instrumentChecksumSha256,
          formChecksumSha256: definition.formChecksumSha256,
          appVersion: buildInfo.version,
          buildId: buildInfo.buildId,
          databaseSchemaVersion: database.schemaVersion,
          contentRevision: definition.contentRevision,
          evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
          featureContractRevision: currentFeatureContractIdentity.revision,
          featureContractHash: currentFeatureContractIdentity.semanticHash,
          startedAtUtc: receipt.verifiedAtUtc,
          completedAtUtc: null,
          abandonedAtUtc: null,
        );
        final cycle = await cycleReader.requirePhase(run: run);
        await _pairedPre(run, cycle);
        await _words(definition, ownerId);
        await _clock(receipt, scope, generation, stillVisible);
        await database.customStatement(
          'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
          "VALUES (?, ?, 'assessment', 'active', ?, ?, ?)",
          [
            run.learningSessionId,
            ownerId,
            run.startedAtUtc.millisecondsSinceEpoch,
            run.appVersion,
            run.buildId,
          ],
        );
        await _insert('assessment_runs', _encode(run));
        await _finish(run, definition, scope, generation, stillVisible);
        return run;
      },
    );
  }

  @override
  Future<AssessmentRun> getRun({
    required String ownerId,
    required String runId,
  }) {
    _ids(ownerId, runId);
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final run = await _required(ownerId, runId);
        await _container(run);
        return run;
      },
    );
  }

  @override
  Future<AssessmentPresentationRead> requireActivePresentation({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) async {
    await _outside(stillVisible);
    final scope = authority.cache.currentScope();
    final generation = authority.cache.readGeneration;
    final run = await getRun(ownerId: ownerId, runId: runId);
    final definition = _definition(run);
    await _content(definition, stillVisible);
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        _active(await _required(ownerId, runId));
        final receipt = await _finish(
          run,
          definition,
          scope,
          generation,
          stillVisible,
        );
        return (
          run: run,
          verifiedAtUtc: receipt.verifiedAtUtc,
          validUntilUtc: receipt.validUntilUtc,
        );
      },
    );
  }

  @override
  Future<AssessmentResponseResult> recordResponse({
    required String ownerId,
    required String runId,
    required String itemId,
    required String option,
    required int responseTimeMs,
    required bool Function() stillVisible,
  }) async {
    await _outside(stillVisible);
    _ids(ownerId, runId);
    AssessmentRun.validateCanonicalText(itemId, 'itemId');
    AssessmentRun.validateCanonicalText(option, 'option');
    if (responseTimeMs < 0 ||
        responseTimeMs > LearningEvidenceContract.maxResponseTimeMs) {
      throw ArgumentError.value(responseTimeMs, 'responseTimeMs');
    }
    final scope = authority.cache.currentScope();
    final generation = authority.cache.readGeneration;
    final original = await getRun(ownerId: ownerId, runId: runId);
    final definition = _definition(original);
    final item = definition.item(itemId);
    final controlled = item.responses[option];
    if (controlled == null) {
      throw ArgumentError.value(
        option,
        'option',
        'must be a controlled option',
      );
    }
    await _content(definition, stillVisible);
    final identity = assessmentResponseIdentity(runId, itemId);
    final context = _context(original, item, controlled.responseCode);
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final run = await _required(ownerId, runId);
        if (!_sameOriginalPins(run, original)) {
          _conflict(runId, 'Run changed during content verification.');
        }
        await _container(run);
        final previous = await database
            .customSelect(
              'SELECT * FROM answer_attempts WHERE id = ?',
              variables: [Variable<String>(identity)],
            )
            .getSingleOrNull();
        if (previous != null) {
          final evidence = _evidence(run, definition, previous.data);
          if (evidence.wordId != item.wordId ||
              evidence.promptMode != item.promptMode ||
              evidence.isCorrect != controlled.isCorrect ||
              evidence.responseTimeMs != responseTimeMs ||
              jsonEncode(evidence.evidenceContext.toJson()) !=
                  jsonEncode(context.toJson())) {
            _conflict(
              runId,
              'Response identity already has different canonical facts.',
            );
          }
          _visible(stillVisible);
          return AssessmentResponseResult(
            sourceEvidenceId: identity,
            responseCode: controlled.responseCode,
            isCorrect: controlled.isCorrect,
            inserted: false,
          );
        }
        _active(run);
        _captured(scope, generation, ownerId);
        final receipt = await authority.requireCurrent(
          expectedScope: scope!,
          definition: definition,
          expectedParticipationPermitId: participationPermitId,
          pinnedRun: run,
        );
        final cycle = await cycleReader.requirePhase(run: run);
        await _pairedPre(run, cycle);
        await _words(definition, ownerId);
        final now = await _clock(receipt, scope, generation, stillVisible);
        await _insert('answer_attempts', {
          'id': identity,
          'owner_id': ownerId,
          'session_id': run.learningSessionId,
          'word_id': item.wordId,
          'prompt_mode': item.promptMode,
          'is_correct': controlled.isCorrect ? 1 : 0,
          'response_time_ms': responseTimeMs,
          'attempt_number': 1,
          'occurred_at_utc_ms': now.millisecondsSinceEpoch,
          'provider_provenance': null,
          'evidence_class': 'assessment',
          'evidence_context_json': jsonEncode(context.toJson()),
        });
        await _finish(run, definition, scope, generation, stillVisible);
        return AssessmentResponseResult(
          sourceEvidenceId: identity,
          responseCode: controlled.responseCode,
          isCorrect: controlled.isCorrect,
          inserted: true,
        );
      },
    );
  }

  @override
  Future<AssessmentRun> complete({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) => _close(ownerId, runId, AssessmentRunState.completed, stillVisible);
  @override
  Future<AssessmentRun> abandon({
    required String ownerId,
    required String runId,
    required bool Function() stillVisible,
  }) => _close(ownerId, runId, AssessmentRunState.abandoned, stillVisible);

  Future<AssessmentRun> _close(
    String ownerId,
    String runId,
    AssessmentRunState target,
    bool Function() stillVisible,
  ) async {
    await _outside(stillVisible);
    final scope = authority.cache.currentScope();
    final generation = authority.cache.readGeneration;
    final original = await getRun(ownerId: ownerId, runId: runId);
    final definition = _definition(original);
    await _content(definition, stillVisible);
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final run = await _required(ownerId, runId);
        if (!_sameOriginalPins(run, original)) {
          _conflict(runId, 'Run changed during content verification.');
        }
        await _container(run);
        final evidence = await _outcomes(run, definition);
        if (target == AssessmentRunState.completed &&
            evidence.length != definition.items.length) {
          _conflict(
            runId,
            'Every pinned item requires one canonical response.',
          );
        }
        if (run.state == target) {
          _visible(stillVisible);
          return run;
        }
        _active(run);
        _captured(scope, generation, ownerId);
        final receipt = await authority.requireCurrent(
          expectedScope: scope!,
          definition: definition,
          expectedParticipationPermitId: participationPermitId,
          pinnedRun: run,
        );
        final cycle = await cycleReader.requirePhase(run: run);
        await _pairedPre(run, cycle);
        final now = await _clock(receipt, scope, generation, stillVisible);
        if (evidence.any((fact) => fact.occurredAtUtc.isAfter(now))) {
          _conflict(runId, 'Future response facts.');
        }
        final closed = run.withTerminalState(state: target, terminalAtUtc: now);
        await database.customStatement(
          'UPDATE assessment_runs SET state = ?, completed_at_utc_ms = ?, abandoned_at_utc_ms = ? WHERE id = ? AND owner_id = ?',
          [
            target.name,
            closed.completedAtUtc?.millisecondsSinceEpoch,
            closed.abandonedAtUtc?.millisecondsSinceEpoch,
            runId,
            ownerId,
          ],
        );
        await database.customStatement(
          'UPDATE learning_sessions SET state = ?, ended_at_utc_ms = ? WHERE id = ? AND owner_id = ?',
          [
            target.name,
            now.millisecondsSinceEpoch,
            run.learningSessionId,
            ownerId,
          ],
        );
        await _finish(closed, definition, scope, generation, stillVisible);
        return closed;
      },
    );
  }

  @override
  Future<List<AssessmentRun>> listRunsForStudyCycle({
    required String ownerId,
    required String studyCycleId,
  }) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(studyCycleId, 'studyCycleId');
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final rows = await database
            .customSelect(
              'SELECT * FROM assessment_runs WHERE owner_id = ? AND study_cycle_id = ? ORDER BY started_at_utc_ms, id',
              variables: [
                Variable<String>(ownerId),
                Variable<String>(studyCycleId),
              ],
            )
            .get();
        final runs = rows
            .map((row) => decodeAssessmentRunRow(row.data))
            .toList(growable: false);
        for (final run in runs) {
          await _container(run);
        }
        return List.unmodifiable(runs);
      },
    );
  }

  @override
  Future<List<AssessmentOutcomeEvidence>> listOutcomeEvidence({
    required String ownerId,
    required String learningSessionId,
  }) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateCanonicalText(learningSessionId, 'learningSessionId');
    return authority.cache.ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final rows = await database
            .customSelect(
              'SELECT * FROM assessment_runs WHERE owner_id = ? AND learning_session_id = ?',
              variables: [
                Variable<String>(ownerId),
                Variable<String>(learningSessionId),
              ],
            )
            .get();
        if (rows.length != 1) {
          throw StateError('Session lacks its exact Assessment run.');
        }
        final run = decodeAssessmentRunRow(rows.single.data);
        await _container(run);
        return _outcomes(run, _historicalDefinition(run));
      },
    );
  }

  Future<AssessmentAuthorityReceipt> _finish(
    AssessmentRun expected,
    AssessmentInstrumentDefinition definition,
    ResearchAuthorityScope? scope,
    int generation,
    bool Function() stillVisible,
  ) async {
    _captured(scope, generation, expected.ownerId);
    final receipt = await authority.requireCurrent(
      expectedScope: scope!,
      definition: definition,
      expectedParticipationPermitId: participationPermitId,
      pinnedRun: expected,
    );
    final cycle = await cycleReader.requirePhase(run: expected);
    await _pairedPre(expected, cycle);
    final participant = await authority.cache.loadCurrent(
      ownerId: expected.ownerId,
      permitId: expected.participationPermitId,
    );
    _captured(scope, generation, expected.ownerId);
    if (participant == null ||
        participant.localRevision != receipt.participationPermitRevision ||
        participant.payloadSha256 != receipt.participationPermitPayloadSha256) {
      throw StateError('Original participation snapshot is unavailable.');
    }
    // No authority waits follow this final canonical SQL inspection.
    final current = await _required(expected.ownerId, expected.id);
    if (current != expected) {
      _conflict(expected.id, 'Stored run changed before commit.');
    }
    await _container(current);
    final evidence = await _outcomes(current, definition);
    await _words(definition, current.ownerId);
    await _localOwner(current, scope, receipt, participant);
    final now = await _clock(receipt, scope, generation, stillVisible);
    final terminal = current.completedAtUtc ?? current.abandonedAtUtc;
    if (current.startedAtUtc.isAfter(now) ||
        (terminal != null && terminal.isAfter(now)) ||
        evidence.any((fact) => fact.occurredAtUtc.isAfter(now))) {
      _conflict(current.id, 'Future Assessment facts.');
    }
    return receipt;
  }

  Future<void> _localOwner(
    AssessmentRun run,
    ResearchAuthorityScope scope,
    AssessmentAuthorityReceipt receipt,
    ResearchParticipationPermit participant,
  ) async {
    if (await authority.cache.ownerWrites.inspect() != null) {
      throw StateError('Owner writes are fenced.');
    }
    final rows = await database
        .customSelect(
          'SELECT o.id, o.firebase_uid, o.account_state, c.consent_state, c.decided_at_utc_ms, c.withdrawn_at_utc_ms '
          'FROM local_owners o LEFT JOIN research_consents c ON c.owner_id = o.id AND c.consent_version = ? '
          'WHERE o.is_active = 1',
          variables: [Variable<int>(run.consentVersion)],
        )
        .get();
    if (rows.length != 1 ||
        rows.single.data['id'] != run.ownerId ||
        rows.single.data['firebase_uid'] != scope.binding.authSubjectId ||
        rows.single.data['account_state'] != 'firebaseBound' ||
        rows.single.data['consent_state'] != 'accepted' ||
        rows.single.data['decided_at_utc_ms'] !=
            run.consentDecidedAtUtc.millisecondsSinceEpoch ||
        rows.single.data['withdrawn_at_utc_ms'] != null) {
      throw StateError('Owner or consent changed before commit.');
    }
    final assignment = receipt.assignment;
    final assignmentRow = await database
        .customSelect(
          'SELECT * FROM experiment_assignments WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(assignment.id),
            Variable<String>(run.ownerId),
          ],
        )
        .getSingleOrNull();
    final expectedAssignment = <String, Object?>{
      'id': assignment.id,
      'owner_id': assignment.ownerId,
      'experiment_id': assignment.experimentId,
      'experiment_version': assignment.experimentVersion,
      'cohort': assignment.cohort,
      'protocol_version': assignment.protocolVersion,
      'assigned_at_utc_ms': assignment.assignedAtUtc.millisecondsSinceEpoch,
    };
    if (assignmentRow == null ||
        expectedAssignment.entries.any(
          (entry) => assignmentRow.data[entry.key] != entry.value,
        )) {
      throw StateError('Original assignment changed before commit.');
    }
    final permitRow = await database
        .customSelect(
          'SELECT * FROM research_participation_permits WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>(participant.id),
            Variable<String>(run.ownerId),
          ],
        )
        .getSingleOrNull();
    final expectedPermit = <String, Object?>{
      'id': participant.id,
      'owner_id': participant.ownerId,
      'local_revision': participant.localRevision,
      'cloud_revision': participant.cloudRevision,
      'is_deleted': participant.isDeleted ? 1 : 0,
      'participant_class': participant.participantClass.name,
      'age_band_code': participant.ageBandCode,
      'assignment_id': participant.assignmentId,
      'assigned_treatment': participant.assignedTreatment.name,
      'consent_receipt_id': participant.consentReceiptId,
      'guardian_permission_receipt_ref':
          participant.guardianPermissionReceiptRef,
      'learner_assent_receipt_ref': participant.learnerAssentReceiptRef,
      'protocol_id': participant.protocolId,
      'protocol_version': participant.protocolVersion,
      'issued_at_utc_ms': participant.issuedAtUtc.millisecondsSinceEpoch,
      'expires_at_utc_ms': participant.expiresAtUtc.millisecondsSinceEpoch,
      'revoked_at_utc_ms': participant.revokedAtUtc?.millisecondsSinceEpoch,
      'issuer_key_id': participant.issuerKeyId,
      'payload_sha256': participant.payloadSha256,
      'signature': participant.signature,
    };
    if (permitRow == null ||
        expectedPermit.entries.any(
          (entry) => permitRow.data[entry.key] != entry.value,
        )) {
      throw StateError(
        'Original participation document changed before commit.',
      );
    }
  }

  Future<DateTime> _clock(
    AssessmentAuthorityReceipt receipt,
    ResearchAuthorityScope scope,
    int generation,
    bool Function() stillVisible,
  ) async {
    // The concrete cache read only uses memory and its local monotonic clock.
    final reading = await authority.cache.read();
    _captured(scope, generation, scope.binding.ownerId);
    _visible(stillVisible);
    if (reading == null ||
        !reading.isFresh ||
        reading.effectiveNowUtc.isBefore(receipt.verifiedAtUtc) ||
        !reading.effectiveNowUtc.isBefore(receipt.validUntilUtc)) {
      throw StateError('Assessment authority lease expired before commit.');
    }
    return reading.effectiveNowUtc;
  }

  Future<void> _outside(bool Function() stillVisible) async {
    if (await authority.cache.ownerWrites.hasAmbientTransaction()) {
      throw StateError(
        'Assessment mutations require their own committed boundary.',
      );
    }
    _visible(stillVisible);
  }

  Future<void> _content(
    AssessmentInstrumentDefinition definition,
    bool Function() stillVisible,
  ) async {
    await requireVerifiedAssessmentForm(
      definition: definition,
      contentAuthority: contentAuthority,
    );
    _visible(stillVisible);
  }

  void _captured(
    ResearchAuthorityScope? scope,
    int generation,
    String ownerId,
  ) {
    if (scope == null ||
        scope.binding.ownerId != ownerId ||
        authority.cache.currentScope() != scope ||
        authority.cache.readGeneration != generation) {
      throw StateError(
        'Assessment authority scope changed during the operation.',
      );
    }
  }

  AssessmentInstrumentDefinition _definition(AssessmentRun run) {
    final definition = _historicalDefinition(run);
    if (run.appVersion != buildInfo.version ||
        run.buildId != buildInfo.buildId ||
        run.databaseSchemaVersion != database.schemaVersion) {
      _conflict(
        run.id,
        'Current capture requires the original app and schema pins.',
      );
    }
    return definition;
  }

  AssessmentInstrumentDefinition _historicalDefinition(AssessmentRun run) {
    final definition = catalog.lookup(
      instrumentId: run.instrumentId,
      instrumentVersion: run.instrumentVersion,
      formId: run.formId,
      formVersion: run.formVersion,
    );
    final mapping = authority.mapping;
    if (definition.protocolId != run.protocolId ||
        definition.experimentId != run.experimentId ||
        definition.experimentVersion != run.experimentVersion ||
        definition.contentRevision != run.contentRevision ||
        definition.formContentRevision != run.formContentRevision ||
        definition.instrumentChecksumSha256 != run.instrumentChecksumSha256 ||
        definition.formChecksumSha256 != run.formChecksumSha256 ||
        mapping.protocolVersion != run.protocolVersion ||
        mapping.protocolRevision != run.protocolRevision ||
        mapping.instrumentRevision != run.instrumentRevision ||
        run.evidencePolicyVersion != EvidenceContext.currentPolicyVersion ||
        run.featureContractRevision !=
            currentFeatureContractIdentity.revision ||
        run.featureContractHash !=
            currentFeatureContractIdentity.semanticHash) {
      _conflict(
        run.id,
        'Stored pins cannot be reinterpreted by current configuration.',
      );
    }
    return definition;
  }

  Future<void> _words(
    AssessmentInstrumentDefinition definition,
    String ownerId,
  ) async {
    for (final word in definition.items.map((item) => item.wordId).toSet()) {
      final row = await database
          .customSelect(
            'SELECT id FROM vocabulary_words WHERE id = ? AND owner_id = ? AND is_deleted = 0',
            variables: [Variable<String>(word), Variable<String>(ownerId)],
          )
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Assessment word is unavailable to its owner.');
      }
    }
  }

  Future<void> _container(AssessmentRun run) async {
    final row = await database
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ?',
          variables: [Variable<String>(run.learningSessionId)],
        )
        .getSingleOrNull();
    if (row == null ||
        row.data['owner_id'] != run.ownerId ||
        row.data['activity_type'] != 'assessment' ||
        row.data['state'] != run.state.name ||
        row.data['started_at_utc_ms'] !=
            run.startedAtUtc.millisecondsSinceEpoch ||
        row.data['ended_at_utc_ms'] !=
            (run.completedAtUtc ?? run.abandonedAtUtc)
                ?.millisecondsSinceEpoch ||
        row.data['correct_count'] != 0 ||
        row.data['wrong_count'] != 0 ||
        row.data['score'] != null ||
        row.data['accepted_plan_id'] != null ||
        row.data['accepted_plan_json'] != null ||
        row.data['checkpoint_json'] != null ||
        row.data['checkpoint_revision'] != 0 ||
        row.data['app_version'] != run.appVersion ||
        row.data['build_id'] != run.buildId) {
      _conflict(run.id, 'Assessment session container is inconsistent.');
    }
  }

  Future<void> _pairedPre(
    AssessmentRun run,
    AssessmentCycleReceipt cycle,
  ) async {
    if (run.phase != AssessmentPhase.post) return;
    final row = await database
        .customSelect(
          "SELECT * FROM assessment_runs WHERE owner_id = ? AND study_cycle_id = ? AND phase = 'pre'",
          variables: [
            Variable<String>(run.ownerId),
            Variable<String>(run.studyCycleId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      _conflict(run.id, 'Post requires the original completed pre phase.');
    }
    final pre = decodeAssessmentRunRow(row.data);
    await _container(pre);
    final prePins = _encode(pre)
      ..removeWhere((key, _) => _phaseSpecific.contains(key));
    final postPins = _encode(run)
      ..removeWhere((key, _) => _phaseSpecific.contains(key));
    if (pre.state != AssessmentRunState.completed ||
        pre.completedAtUtc == null ||
        jsonEncode(prePins) != jsonEncode(postPins) ||
        cycle.firstExposureAtUtc == null ||
        cycle.interventionStartedAtUtc == null ||
        pre.completedAtUtc!.isAfter(cycle.firstExposureAtUtc!) ||
        pre.completedAtUtc!.isAfter(cycle.interventionStartedAtUtc!)) {
      _conflict(
        run.id,
        'Paired pre phase or intervention timing is inconsistent.',
      );
    }
    final definition = _definition(pre);
    if ((await _outcomes(pre, definition)).length != definition.items.length) {
      _conflict(run.id, 'Paired pre phase lacks its responses.');
    }
  }

  static bool _sameOriginalPins(AssessmentRun left, AssessmentRun right) {
    const terminalFields = {
      'state',
      'completed_at_utc_ms',
      'abandoned_at_utc_ms',
    };
    final leftPins = _encode(left)
      ..removeWhere((key, _) => terminalFields.contains(key));
    final rightPins = _encode(right)
      ..removeWhere((key, _) => terminalFields.contains(key));
    return jsonEncode(leftPins) == jsonEncode(rightPins);
  }

  static const _phaseSpecific = {
    'id',
    'learning_session_id',
    'phase',
    'state',
    'started_at_utc_ms',
    'completed_at_utc_ms',
    'abandoned_at_utc_ms',
  };

  Future<List<AssessmentOutcomeEvidence>> _outcomes(
    AssessmentRun run,
    AssessmentInstrumentDefinition definition,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT * FROM answer_attempts WHERE session_id = ? ORDER BY occurred_at_utc_ms, id',
          variables: [Variable<String>(run.learningSessionId)],
        )
        .get();
    final items = <String>{};
    final result = <AssessmentOutcomeEvidence>[];
    for (final row in rows) {
      final fact = _evidence(run, definition, row.data);
      if (!items.add(fact.evidenceContext.assessmentItemId!)) {
        _conflict(run.id, 'Duplicate Assessment item facts.');
      }
      result.add(fact);
    }
    return List.unmodifiable(result);
  }

  AssessmentOutcomeEvidence _evidence(
    AssessmentRun run,
    AssessmentInstrumentDefinition definition,
    Map<String, Object?> row,
  ) {
    final context = EvidenceContext.fromJson(
      Map<String, Object?>.from(
        jsonDecode(row['evidence_context_json']! as String) as Map,
      ),
    );
    final item = definition.item(context.assessmentItemId ?? '');
    final matching = item.responses.values
        .where(
          (response) =>
              response.responseCode == context.assessmentResponseCode &&
              response.isCorrect == _bool(row['is_correct']),
        )
        .toList();
    if (matching.isEmpty ||
        row['id'] != assessmentResponseIdentity(run.id, item.itemId) ||
        row['owner_id'] != run.ownerId ||
        row['session_id'] != run.learningSessionId ||
        row['word_id'] != item.wordId ||
        row['prompt_mode'] != item.promptMode ||
        row['attempt_number'] != 1 ||
        row['provider_provenance'] != null ||
        jsonEncode(context.toJson()) !=
            jsonEncode(
              _context(run, item, matching.first.responseCode).toJson(),
            )) {
      _conflict(
        run.id,
        'Stored response differs from the pinned controlled item.',
      );
    }
    final occurred = _utc(row['occurred_at_utc_ms']);
    final end = run.completedAtUtc ?? run.abandonedAtUtc;
    if (occurred.isBefore(run.startedAtUtc) ||
        (end != null && occurred.isAfter(end))) {
      _conflict(run.id, 'Response lies outside the original run.');
    }
    return AssessmentOutcomeEvidence(
      sourceEvidenceId: row['id']! as String,
      ownerId: run.ownerId,
      learningSessionId: run.learningSessionId,
      wordId: item.wordId,
      promptMode: item.promptMode,
      isCorrect: _bool(row['is_correct']),
      responseTimeMs: row['response_time_ms']! as int,
      occurredAtUtc: occurred,
      persistedEvidenceClass: row['evidence_class']! as String,
      evidenceContext: context,
    );
  }

  static EvidenceContext _context(
    AssessmentRun run,
    AssessmentItemDefinition item,
    String responseCode,
  ) => EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: item.wordId,
    hintLevel: 0,
    contentRevision: run.contentRevision,
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: run.protocolId,
    protocolVersion: run.protocolVersion,
    experimentId: run.experimentId,
    experimentVersion: run.experimentVersion,
    assignmentId: run.assignmentId,
    cohort: run.cohort,
    researchConsentVersion: run.consentVersion,
    instrumentId: run.instrumentId,
    instrumentVersion: run.instrumentVersion,
    formId: run.formId,
    formVersion: run.formVersion,
    assessmentItemId: item.itemId,
    assessmentResponseCode: responseCode,
    scoringRuleVersion: item.scoringRuleVersion,
  );

  Future<AssessmentRun?> _find(String runId) async {
    final row = await database
        .customSelect(
          'SELECT * FROM assessment_runs WHERE id = ?',
          variables: [Variable<String>(runId)],
        )
        .getSingleOrNull();
    return row == null ? null : decodeAssessmentRunRow(row.data);
  }

  Future<AssessmentRun> _required(String ownerId, String runId) async {
    final run = await _find(runId);
    if (run == null || run.ownerId != ownerId) {
      _conflict(runId, 'Run is unavailable to this owner.');
    }
    return run;
  }

  Future<void> _insert(
    String table,
    Map<String, Object?> row,
  ) => database.customStatement(
    'INSERT INTO $table (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
    row.values.toList(),
  );
  static void _ids(String ownerId, String runId) {
    AssessmentRun.validateCanonicalText(ownerId, 'ownerId');
    AssessmentRun.validateRunId(runId);
  }

  static void _active(AssessmentRun run) {
    if (run.state != AssessmentRunState.active) {
      _conflict(run.id, 'Original run is terminal.');
    }
  }

  static void _visible(bool Function() stillVisible) {
    if (!stillVisible()) {
      throw StateError('Assessment surface is no longer visible.');
    }
  }

  static DateTime _utc(Object? value) {
    if (value is! int || value < 0 || value > 8640000000000000) {
      throw const FormatException('Invalid Assessment timestamp.');
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static bool _bool(Object? value) => switch (value) {
    true || 1 => true,
    false || 0 => false,
    _ => throw const FormatException('Invalid Assessment correctness.'),
  };
  static Never _conflict(String runId, String reason) =>
      throw AssessmentRunConflict(runId: runId, reason: reason);

  static Map<String, Object?> _encode(AssessmentRun run) => {
    'id': run.id,
    'owner_id': run.ownerId,
    'learning_session_id': run.learningSessionId,
    'study_cycle_id': run.studyCycleId,
    'phase': run.phase.name,
    'state': run.state.name,
    'protocol_id': run.protocolId,
    'protocol_version': run.protocolVersion,
    'protocol_revision': run.protocolRevision,
    'experiment_id': run.experimentId,
    'experiment_version': run.experimentVersion,
    'assignment_id': run.assignmentId,
    'assignment_revision': run.assignmentRevision,
    'cohort': run.cohort,
    'consent_version': run.consentVersion,
    'consent_decided_at_utc_ms': run.consentDecidedAtUtc.millisecondsSinceEpoch,
    'instrument_id': run.instrumentId,
    'instrument_version': run.instrumentVersion,
    'instrument_revision': run.instrumentRevision,
    'form_id': run.formId,
    'form_version': run.formVersion,
    'form_content_revision': run.formContentRevision,
    'participation_permit_id': run.participationPermitId,
    'participation_permit_revision': run.participationPermitRevision,
    'participation_permit_payload_sha256': run.participationPermitPayloadSha256,
    'instrument_checksum_sha256': run.instrumentChecksumSha256,
    'form_checksum_sha256': run.formChecksumSha256,
    'app_version': run.appVersion,
    'build_id': run.buildId,
    'database_schema_version': run.databaseSchemaVersion,
    'content_revision': run.contentRevision,
    'evidence_policy_version': run.evidencePolicyVersion,
    'feature_contract_revision': run.featureContractRevision,
    'feature_contract_hash': run.featureContractHash,
    'started_at_utc_ms': run.startedAtUtc.millisecondsSinceEpoch,
    'completed_at_utc_ms': run.completedAtUtc?.millisecondsSinceEpoch,
    'abandoned_at_utc_ms': run.abandonedAtUtc?.millisecondsSinceEpoch,
  };
}
