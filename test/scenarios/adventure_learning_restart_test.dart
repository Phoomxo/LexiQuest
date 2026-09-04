import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

void main() {
  test(
    'lost acknowledgement and process restart keep one evidence record',
    () async {
      final durable = _DurableGateway()..loseFirstAcknowledgement = true;
      final first = AdventureRecoveryUseCases(
        gateway: durable,
        canStartNewMission: () => true,
      );
      await first.startOrResume(
        plan: _plan(),
        activeOwnerId: _owner,
        sessionId: _session,
      );
      final exact = AdventureExactRetry(
        evidenceId: 'evidence:one',
        sessionId: _session,
        ownerId: _owner,
        payloadFingerprint: 'sha256:answer-one',
        payload: const <String, Object?>{'answer': 'station', 'attempt': 1},
      );
      await expectLater(first.record(exact), throwsStateError);
      expect(durable.durableEvidenceIds, {'evidence:one'});

      final restarted = AdventureRecoveryUseCases(
        gateway: durable,
        canStartNewMission: () => true,
      );
      await restarted.startOrResume(
        plan: _plan(),
        activeOwnerId: _owner,
        sessionId: _session,
      );
      await restarted.record(exact);

      expect(durable.durableEvidenceIds, hasLength(1));
      expect(durable.duplicateEvidenceWrites, 0);
      expect(durable.rewardCount, 1);
    },
  );
}

final class _DurableGateway implements AdventureRecoveryGateway {
  bool loseFirstAcknowledgement = false;
  final Set<String> durableEvidenceIds = <String>{};
  int duplicateEvidenceWrites = 0;
  int rewardCount = 0;

  @override
  Future<void> start(AdventureRecoverySession session) async {}
  @override
  Future<void> resume(AdventureRecoverySession session) async {}
  @override
  Future<void> close(AdventureRecoverySession session) async {}

  @override
  Future<void> record(AdventureExactRetry retry) async {
    if (durableEvidenceIds.add(retry.evidenceId)) {
      rewardCount += 1;
      if (loseFirstAcknowledgement) {
        loseFirstAcknowledgement = false;
        throw StateError('acknowledgement lost after commit');
      }
      return;
    }
    // Canonical Learning treats exact replay as a successful no-op.
  }
}

const _owner = 'owner:one';
const _session = 'session:one';
final _now = DateTime.utc(2026, 9, 4, 9);
const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:one',
  revision: 1,
);

AdventureSessionPlanV1 _plan() {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: _owner,
    mode: LessonMode.typedRecall,
    itemCount: 1,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 1,
    timing: const SessionTiming.timed(Duration(minutes: 5)),
    packIdentity: null,
    protocolId: 'protocol:local',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:one',
  );
  const planId = 'adventure-plan:restart';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: _owner,
    createdAtUtc: _now,
    sourceEvaluatedAtUtc: _now,
    content: const <ContentIdentity>[_identity],
    contentChecksumsSha256: <String, String>{'word:one': 'a' * 64},
    mode: LessonMode.typedRecall,
    configuration: configuration,
    recommendationPolicyVersion: 'recommendation-v1',
    sourceReasonCode: 'due',
    learnerOverrideApplied: false,
    origin: const AdventureOriginContextV1(
      planId: planId,
      nodeId: 'today-mission',
      catalogId: 'catalog:one',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      presentation: TodayExperiencePresentation.adventure,
    ),
  );
}
