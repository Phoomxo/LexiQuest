import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_learning_bridge.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

void main() {
  test(
    'Adventure and Standard prepare byte/value-equivalent start commands',
    () {
      final plan = createAdventureTestPlan();
      final launch = const AdventureLearningBridge().prepare(
        plan: plan,
        activeOwnerId: _owner,
        sessionId: 'session:one',
        startedAtUtc: _now,
      );

      final standard = <String, Object?>{
        'mode': LessonMode.typedRecall.name,
        'sessionId': 'session:one',
        'startedAtUtc': _now.toIso8601String(),
        'itemCount': 1,
        'ownerId': _owner,
        'configuration': plan.configuration.stableSerialization,
      };
      final adventure = <String, Object?>{
        'mode': launch.command.mode.name,
        'sessionId': launch.command.sessionId,
        'startedAtUtc': launch.command.startedAtUtc.toIso8601String(),
        'itemCount': launch.command.itemCount,
        'ownerId': launch.command.ownerId,
        'configuration': launch.command.configuration!.stableSerialization,
      };
      expect(adventure, standard);
      expect(identical(launch.content.single, plan.content.single), isTrue);
      expect(launch.transientOrigin.toJson().keys, isNot(contains('evidence')));
    },
  );

  test('mixed owner and unresolved pin fail before controller invocation', () {
    final bridge = const AdventureLearningBridge();
    expect(
      () => bridge.prepare(
        plan: createAdventureTestPlan(),
        activeOwnerId: 'owner:other',
        sessionId: 'session:one',
        startedAtUtc: _now,
      ),
      throwsA(
        isA<AdventureSessionPlanException>().having(
          (error) => error.reason,
          'reason',
          AdventureSessionPlanFailure.ownerMismatch,
        ),
      ),
    );

    final malformed = createAdventureTestPlan(checksum: '${'A' * 63}!');
    expect(
      () => bridge.prepare(
        plan: malformed,
        activeOwnerId: _owner,
        sessionId: 'session:one',
        startedAtUtc: _now,
      ),
      throwsA(
        isA<AdventureSessionPlanException>().having(
          (error) => error.reason,
          'reason',
          AdventureSessionPlanFailure.unresolvedContent,
        ),
      ),
    );
  });
}

const _owner = 'owner:one';
final _now = DateTime.utc(2026, 9, 4, 9);
const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:one',
  revision: 1,
);

AdventureSessionPlanV1 createAdventureTestPlan({String? checksum}) {
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
  const planId = 'adventure-plan:one';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: _owner,
    createdAtUtc: _now,
    sourceEvaluatedAtUtc: _now,
    content: const <ContentIdentity>[_identity],
    contentChecksumsSha256: <String, String>{'word:one': checksum ?? 'a' * 64},
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
