import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';
import '../../support/srs_review_harness.dart' show SrsReviewHarness;

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository repository;
  late LearningUseCases learning;
  var nextId = 0;

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
    learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'synthetic-time-admission-${++nextId}',
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

  Future<ConfiguredQuizState> quiz() async => learning.startConfiguredQuiz(
    await learning.prepareConfiguredQuiz(
      expectedOwnerId: configuredOwnerId,
      configuration: QuizConfiguration.category(
        categoryId: configuredCategoryId,
        limit: 1,
      ),
    ),
  );

  Future<CanonicalLearningTimeAdmission> admit(
    ConfiguredQuizState state, {
    LearningTimeCallerContext callerContext =
        LearningTimeCallerContext.ordinary,
  }) => learning.admitCanonicalLearningTime(
    ConfiguredQuizTimeAdmission(state, callerContext: callerContext),
    expectedOwnerId: configuredOwnerId,
    stillCurrent: () => true,
  );

  Future<void> require(CanonicalLearningTimeAdmission proof) =>
      repository.requireCanonicalLearningTimeAdmission(
        proof,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );

  test(
    'admission and closed validation read only and serialize no prompt',
    () async {
      final state = await quiz();
      final before = await h.snapshot();
      final proof = await admit(state);
      await require(proof);
      expect(await h.snapshot(), before);
      expect(proof.sessionId, state.sessionId);
      expect(proof.sourceKind, CanonicalLearningTimeSourceKind.configuredQuiz);
      final source =
          jsonDecode(proof.sourceBindingJson) as Map<String, dynamic>;
      expect(source.keys.toSet(), {
        'schemaVersion',
        'kind',
        'sessionId',
        'activityType',
        'acceptedPlanId',
      });
      for (final serialized in [
        proof.sourceBindingJson,
        proof.contextBindingJson,
      ]) {
        expect(
          serialized,
          isNot(contains(state.plan.questions.single.word.spelling)),
        );
        expect(
          serialized,
          isNot(contains(state.plan.questions.single.word.meaning)),
        );
      }
    },
  );

  test(
    'copied public proof and another issuer sharing DB are rejected',
    () async {
      final proof = await admit(await quiz());
      await expectLater(require(_CopiedProof(proof)), throwsStateError);
      final otherIssuer = DriftLearningRepository(
        h.database,
        ownerWrites: h.ownerWrites,
      );
      await expectLater(
        otherIssuer.requireCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: configuredOwnerId,
          ownerStillCurrent: () => true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'uncommitted configured start cannot mint live time admission',
    () async {
      await h.database.transaction(() async {
        final uncommitted = await quiz();
        await expectLater(admit(uncommitted), throwsStateError);
      });
    },
  );

  test(
    'checkpoint advance retires live context but preserves closed proof',
    () async {
      final state = await quiz();
      final proof = await admit(state);
      h.now = h.now.add(const Duration(seconds: 1));
      final next = await learning.setQuizHint(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
        visible: true,
      );
      await expectLater(admit(state), throwsStateError);
      await require(proof);
      final assisted = await admit(next);
      expect(assisted.evidenceContext.hintLevel, 1);
      expect(proof.evidenceContext.hintLevel, 0);
    },
  );

  test('canonical completion preserves closed proof', () async {
    final state = await quiz();
    final proof = await admit(state);
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
    await require(proof);
  });

  test(
    'Research/unavailable callers fail closed with no observer row',
    () async {
      final state = await quiz();
      final before = await h.snapshot();
      for (final caller in [
        LearningTimeCallerContext.researchControlled,
        LearningTimeCallerContext.unavailable,
      ]) {
        await expectLater(
          admit(state, callerContext: caller),
          throwsStateError,
        );
      }
      expect(await h.snapshot(), before);
    },
  );

  test(
    'foreign owner, generation retirement and deletion fence reject',
    () async {
      final proof = await admit(await quiz());
      await h.switchOwner(configuredOtherOwnerId);
      await expectLater(require(proof), throwsStateError);
      await h.switchOwner(configuredOwnerId);
      await expectLater(
        repository.requireCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: configuredOwnerId,
          ownerStillCurrent: () => false,
        ),
        throwsStateError,
      );
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-time-fence-operation',
      );
      final fenced = await h.snapshot();
      await expectLater(require(proof), throwsStateError);
      expect(await h.snapshot(), fenced);
    },
  );

  test(
    'native requires original started handle and excludes recreation',
    () async {
      final prepared = (await learning.prepareDictation(
        stillCurrent: () => true,
      ))!;
      final request = NativeLearningTimeAdmission(
        prepared,
        hintLevel: 0,
        callerContext: LearningTimeCallerContext.ordinary,
      );
      await expectLater(
        learning.admitCanonicalLearningTime(
          request,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      final started = await learning.startNativeExercise(
        prepared,
        stillCurrent: () => true,
      );
      final proof = await learning.admitCanonicalLearningTime(
        request,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final forged = DictationSession(
        session: started.session,
        word: started.word,
      );
      await expectLater(
        learning.admitCanonicalLearningTime(
          NativeLearningTimeAdmission(
            forged,
            hintLevel: 0,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      await require(proof);
      final scramble = (await learning.prepareWordScramble(
        stillCurrent: () => true,
      ))!;
      await learning.startNativeExercise(scramble, stillCurrent: () => true);
      await expectLater(
        learning.admitCanonicalLearningTime(
          NativeLearningTimeAdmission(
            scramble,
            hintLevel: 0,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'SRS closed proof survives old route; forged deck cannot enter',
    () async {
      final srs = await SrsReviewHarness.open();
      addTearDown(srs.close);
      final review = await srs.ready();
      final proof = await srs.learning.admitCanonicalLearningTime(
        OwnedSrsTimeAdmission(
          review,
          cardIndex: 0,
          phase: SrsTimePhase.front,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => srs.current,
      );
      final revealed = await srs.learning.admitCanonicalLearningTime(
        OwnedSrsTimeAdmission(
          review,
          cardIndex: 0,
          phase: SrsTimePhase.revealed,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => srs.current,
      );
      expect(jsonDecode(proof.contextBindingJson)['phase'], 'front');
      expect(jsonDecode(revealed.contextBindingJson)['phase'], 'revealed');
      expect(revealed.sourceBindingJson, proof.sourceBindingJson);
      srs.current = false;
      final before = await srs.storage.snapshot();
      await srs.repository.requireCanonicalLearningTimeAdmission(
        proof,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      expect(await srs.storage.snapshot(), before);
      final forged = SrsReviewSession(
        session: review.session,
        words: review.words,
        selection: review.selection,
      );
      await expectLater(
        srs.learning.admitCanonicalLearningTime(
          OwnedSrsTimeAdmission(
            forged,
            cardIndex: 0,
            phase: SrsTimePhase.front,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
    },
  );
}

final class _CopiedProof implements CanonicalLearningTimeAdmission {
  const _CopiedProof(this.original);
  final CanonicalLearningTimeAdmission original;
  @override
  String get ownerId => original.ownerId;
  @override
  String get sessionId => original.sessionId;
  @override
  String get activityType => original.activityType;
  @override
  CanonicalLearningTimeSourceKind get sourceKind => original.sourceKind;
  @override
  String get sourceBindingJson => original.sourceBindingJson;
  @override
  String get contextBindingJson => original.contextBindingJson;
  @override
  EvidenceContext get evidenceContext => original.evidenceContext;
}
