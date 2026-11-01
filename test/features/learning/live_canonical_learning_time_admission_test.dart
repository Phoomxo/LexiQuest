import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository repository;
  late LearningUseCases learning;
  var sequence = 0;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
    learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'synthetic-live-time-${++sequence}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-v1',
        buildId: 'synthetic-v1',
      ),
      eventAdapter: const EventV1ToV2Adapter(
        appVersion: 'synthetic-v1',
        buildId: 'synthetic-v1',
      ),
    );
  });
  tearDown(() => h.close());

  Future<ConfiguredQuizState> start() async => learning.startConfiguredQuiz(
    await learning.prepareConfiguredQuiz(
      expectedOwnerId: configuredOwnerId,
      configuration: QuizConfiguration.category(
        categoryId: configuredCategoryId,
        limit: 1,
      ),
    ),
  );

  Future<CanonicalLearningTimeAdmission> proof(ConfiguredQuizState state) =>
      learning.admitCanonicalLearningTime(
        ConfiguredQuizTimeAdmission(
          state,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );

  Future<void> live(CanonicalLearningTimeAdmission value) =>
      learning.requireLiveCanonicalLearningTimeAdmission(
        value,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );

  Future<void> closed(CanonicalLearningTimeAdmission value) =>
      learning.requireCanonicalLearningTimeAdmission(
        value,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );

  test(
    'current proof re-arms read-only but a newer checkpoint cannot reuse it',
    () async {
      final state = await start();
      final original = await proof(state);
      final before = await h.snapshot();
      await live(original);
      expect(await h.snapshot(), before);
      h.now = h.now.add(const Duration(seconds: 1));
      final assisted = await learning.setQuizHint(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
        visible: true,
      );
      await expectLater(live(original), throwsStateError);
      await closed(original);
      await live(await proof(assisted));
    },
  );

  test(
    'completed source cannot re-arm while its closed segment proof survives',
    () async {
      final state = await start();
      final original = await proof(state);
      final question = state.plan.questions.single;
      final pending = await learning.prepareQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
        selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
        responseTimeMs: 10,
      );
      final answered = (await learning.commitQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      )).state;
      final closing = await learning.prepareQuizFinish(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: answered.checkpointRevision,
      );
      await learning.finishConfiguredQuiz(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: closing.checkpointRevision,
      );
      final before = await h.snapshot();
      await expectLater(live(original), throwsStateError);
      await closed(original);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'LIVE rejects inherited transaction; CLOSED is allowed in time commit',
    () async {
      final original = await proof(await start());
      final before = await h.snapshot();
      await h.database.transaction(() async {
        await expectLater(live(original), throwsStateError);
        await closed(original);
      });
      expect(await h.snapshot(), before);
    },
  );
}
