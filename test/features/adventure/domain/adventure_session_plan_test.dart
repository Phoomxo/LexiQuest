import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

void main() {
  test('Adventure session plan keeps immutable content and exact pins', () {
    final configuration = _configuration();
    final plan = AdventureSessionPlanV1(
      planId: 'adventure-plan:001',
      ownerId: 'owner-001',
      createdAtUtc: _now,
      sourceEvaluatedAtUtc: _now,
      content: const <ContentIdentity>[
        ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word-001',
          revision: 4,
        ),
      ],
      contentChecksumsSha256: const <String, String>{
        'word-001':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
      mode: LessonMode.typedRecall,
      configuration: configuration,
      recommendationPolicyVersion: 'f14-v1',
      sourceReasonCode: 'due_review',
      learnerOverrideApplied: false,
      origin: const AdventureOriginContextV1(
        planId: 'adventure-plan:001',
        nodeId: 'resume-review',
        catalogId: 'lexiquest.adventure.world-v1',
        catalogVersion: '1.0.0',
        catalogSchemaVersion: 1,
        presentation: TodayExperiencePresentation.adventure,
      ),
      assignmentId: null,
      treatment: 'adventure',
    );

    expect(() => plan.content.clear(), throwsUnsupportedError);
    expect(() => plan.contentChecksumsSha256.clear(), throwsUnsupportedError);
    expect(plan.configuration, same(configuration));
    expect(plan.origin.planId, plan.planId);
    expect(plan.toJson()['recommendationPolicyVersion'], 'f14-v1');
  });
}

SessionConfiguration _configuration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'owner-001',
  mode: LessonMode.typedRecall,
  itemCount: 1,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 1,
  timing: const SessionTiming.timed(Duration(minutes: 5)),
  packIdentity: null,
  protocolId: 'protocol-local',
  protocolVersion: '1.0.0',
  protocolLimitsIdentity: 'limits-001',
);

final _now = DateTime.utc(2026, 9, 4, 10);
