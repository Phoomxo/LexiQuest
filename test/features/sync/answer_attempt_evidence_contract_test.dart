import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  test('v1 recovers only the frozen legacy sentinel', () {
    final context = AnswerAttemptSyncPayloadContract.requireEvidenceContext(
      payloadVersion: 1,
      payload: answerPayload(),
    );
    expect(context.toJson(), legacyAnswerEvidence().toJson());
    expect(
      context.classificationSource,
      EvidenceClassificationSource.legacyInferred,
    );
    expect(context.rolloutMode, EvidencePolicyRolloutMode.legacy);
    expect(context.assignmentId, isNull);
    expect(context.instrumentId, isNull);
  });

  test('attempt v2 preserves declared ordinary metadata', () {
    final evidence = ordinaryAnswerEvidence();
    final payload = answerPayload(evidence: evidence);
    final context = AnswerAttemptSyncPayloadContract.requireEvidenceContext(
      payloadVersion: 2,
      payload: payload,
    );
    final mutation = PushMutation(
      operationId: 'operation-a',
      firebaseUid: 'uid-a',
      collection: SyncCollection.attempts,
      entityId: 'attempt-a',
      operationKind: SyncOperationKind.upsert,
      payloadVersion: 2,
      baseRevision: 0,
      localRevision: 1,
      clientUpdatedAtUtc: DateTime.utc(2026, 10, 28),
      payload: payload,
    );
    expect(context.toJson(), evidence.toJson());
    expect(mutation.payload['evidenceContext'], isA<Map>());
    expect(currentSyncPayloadVersion, 1);
  });

  test('v2 remains unavailable for every other collection', () {
    for (final collection in SyncCollection.values.where(
      (c) => c != SyncCollection.attempts,
    )) {
      expect(
        () => PushMutation(
          operationId: 'operation-a',
          firebaseUid: 'uid-a',
          collection: collection,
          entityId: 'entity-a',
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 2,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: DateTime.utc(2026, 10, 28),
          payload: const {},
        ),
        throwsA(isA<UnsupportedSyncSchemaFailure>()),
      );
    }
  });

  test(
    'wire metadata cannot be omitted, widened or disagree with its class',
    () {
      final valid = answerPayload(evidence: ordinaryAnswerEvidence());
      for (final malformed in <Map<String, Object?>>[
        answerPayload(),
        {...valid, 'evidenceClass': 'independentRecall'},
        {...valid, 'evidenceContext': '{}'},
        {...valid, 'unrelated': 'PRIVATE_SYNTHETIC_CANARY'},
        {
          ...valid,
          'evidenceContext': {
            ...ordinaryAnswerEvidence().toJson(),
            'schemaVersion': 2,
          },
        },
      ]) {
        expect(
          () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
            payloadVersion: 2,
            payload: malformed,
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
      }
      expect(
        () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
          payloadVersion: 1,
          payload: valid,
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    },
  );

  test('each research pin is refused even when rollout is declared legacy', () {
    for (final pin in <String, Object>{
      'protocolId': 'synthetic-protocol',
      'protocolVersion': '1',
      'experimentId': 'synthetic-experiment',
      'experimentVersion': 1,
      'assignmentId': 'synthetic-assignment',
      'cohort': 'synthetic-cohort',
      'researchConsentVersion': 1,
      'instrumentId': 'synthetic-instrument',
      'instrumentVersion': '1',
      'formId': 'synthetic-form',
      'formVersion': '1',
      'assessmentItemId': 'synthetic-item',
      'assessmentResponseCode': 'correct',
      'scoringRuleVersion': '1',
    }.entries) {
      final payload = answerPayload(evidence: ordinaryAnswerEvidence());
      payload['evidenceContext'] = {
        ...ordinaryAnswerEvidence().toJson(),
        pin.key: pin.value,
      };
      expect(
        () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
          payloadVersion: 2,
          payload: payload,
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
        reason: pin.key,
      );
    }
  });

  test(
    'legacy-inferred metadata cannot be relabelled as v2 declared evidence',
    () {
      expect(
        () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
          payloadVersion: 2,
          payload: answerPayload(evidence: legacyAnswerEvidence()),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    },
  );

  test('fully pinned research contexts remain refused without authority', () {
    final research = {
      ...ordinaryAnswerEvidence().toJson(),
      'protocolId': 'synthetic-protocol',
      'protocolVersion': '1',
      'experimentId': 'synthetic-experiment',
      'experimentVersion': 1,
      'assignmentId': 'synthetic-assignment',
      'cohort': 'synthetic-cohort',
      'researchConsentVersion': 1,
      'instrumentId': 'synthetic-instrument',
      'instrumentVersion': '1',
      'formId': 'synthetic-form',
      'formVersion': '1',
      'assessmentItemId': 'synthetic-item',
      'assessmentResponseCode': 'correct',
      'scoringRuleVersion': '1',
    };
    for (final mode in ['legacy', 'shadow', 'enforced']) {
      final evidence = EvidenceContext.fromJson({
        ...research,
        'rolloutMode': mode,
      });
      expect(
        () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
          payloadVersion: 2,
          payload: answerPayload(evidence: evidence),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
        reason: mode,
      );
    }
    final assessment = EvidenceContext.fromJson({
      ...research,
      'evidenceClass': 'assessment',
    });
    expect(
      () => AnswerAttemptSyncPayloadContract.requireEvidenceContext(
        payloadVersion: 2,
        payload: answerPayload(evidence: assessment),
      ),
      throwsA(isA<InvalidSyncPayloadFailure>()),
    );
  });
}
