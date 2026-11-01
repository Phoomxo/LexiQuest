import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
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
      generateId: () => 'synthetic-bound-start-${++sequence}',
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

  Future<PreparedSourceBoundVocabularyStart> reading({
    LearningTimeCallerContext caller = LearningTimeCallerContext.ordinary,
  }) async {
    final words = await repository.listQuizWords(
      ownerId: configuredOwnerId,
      wordIds: [configuredWordIds.first],
      limit: 1,
    );
    final source = ReadingLearningTimeSourcePin(
      documentId: 'synthetic-reading-doc',
      documentRevision: 1,
      snapshotSha256: sha256
          .convert(
            utf8.encode(
              'synthetic actual displayed passage and immutable target snapshot',
            ),
          )
          .toString(),
      targetPinsSha256: learningTimeTargetPinsSha256(words),
    );
    return (await learning.prepareSourceBoundReadingStart(
      expectedOwnerId: configuredOwnerId,
      wordIds: words.map((word) => word.id),
      source: source,
      callerContext: caller,
      stillCurrent: () => true,
    ))!;
  }

  Future<CanonicalLearningTimeAdmission> admit(
    PreparedSourceBoundVocabularyStart intent,
  ) => learning.admitCanonicalLearningTime(
    SourceBoundVocabularyTimeAdmission(
      intent,
      wordIndex: 0,
      callerContext: LearningTimeCallerContext.ordinary,
    ),
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
    'prepare is read-only; time cannot link a merely prepared recall start',
    () async {
      final before = await h.snapshot();
      final intent = await reading();
      expect(await h.snapshot(), before);
      await expectLater(admit(intent), throwsStateError);
      expect(await h.snapshot(), before);
      expect(intent.source.sourceKind, CanonicalLearningTimeSourceKind.reading);
      expect(
        jsonDecode(intent.source.sourceBindingJson),
        isNot(contains('sessionId')),
      );
    },
  );

  test(
    'lost caller ACK retries original real start without a second session',
    () async {
      final intent = await reading();
      Future<void> loseCallerAck() async {
        await learning.startSourceBoundVocabularySession(
          intent,
          operationStillCurrent: () => true,
        );
        throw StateError('synthetic lost ACK after actual canonical commit');
      }

      await expectLater(loseCallerAck(), throwsStateError);
      expect(await h.count('learning_sessions'), 1);
      final retried = await learning.startSourceBoundVocabularySession(
        intent,
        operationStillCurrent: () => true,
      );
      expect(retried.id, intent.sessionId);
      expect(await h.count('learning_sessions'), 1);
      final before = await h.snapshot();
      final receipt = await learning.readSourceBoundVocabularyStartReceipt(
        intent,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      await repository.requireCanonicalLearningTimeSessionLinkReceipt(
        receipt,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      expect(receipt.sourceBindingJson, intent.source.sourceBindingJson);
      await expectLater(admit(intent), throwsStateError);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'copied intent and same-DB foreign issuer cannot start or prove receipt',
    () async {
      final intent = await reading();
      final copy = _CopiedStart(intent);
      await expectLater(
        learning.startSourceBoundVocabularySession(
          copy,
          operationStillCurrent: () => true,
        ),
        throwsStateError,
      );
      final otherIssuer = DriftLearningRepository(
        h.database,
        ownerWrites: h.ownerWrites,
      );
      await expectLater(
        otherIssuer.startSourceBoundVocabularySession(
          intent,
          operationStillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.count('learning_sessions'), 0);
    },
  );

  test(
    'source-bound start inside inherited transaction cannot claim ACK',
    () async {
      final intent = await reading();
      await h.database.transaction(() async {
        await expectLater(
          learning.startSourceBoundVocabularySession(
            intent,
            operationStillCurrent: () => true,
          ),
          throwsStateError,
        );
      });
      expect(await h.count('learning_sessions'), 0);
    },
  );

  test(
    'completed canonical start retains closed proof despite current content edit',
    () async {
      final intent = await reading();
      await learning.startSourceBoundVocabularySession(
        intent,
        operationStillCurrent: () => true,
      );
      final receipt = await learning.readSourceBoundVocabularyStartReceipt(
        intent,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      await learning.finishSession(intent.sessionId);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
        [configuredWordIds.first],
      );
      final before = await h.snapshot();
      await repository.requireCanonicalLearningTimeSessionLinkReceipt(
        receipt,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      expect(await h.snapshot(), before);
      await expectLater(admit(intent), throwsStateError);
    },
  );

  test(
    'Research caller continues canonical learning but never ordinary time proof',
    () async {
      final intent = await reading(
        caller: LearningTimeCallerContext.researchControlled,
      );
      final result = await learning.startSourceBoundVocabularySession(
        intent,
        operationStillCurrent: () => true,
      );
      expect(result.id, intent.sessionId);
      expect(await h.count('learning_sessions'), 1);
      final before = await h.snapshot();
      await expectLater(admit(intent), throwsStateError);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'link-only ACK receipt survives retired route/completion and cannot collect',
    () async {
      final intent = await reading();
      await expectLater(
        learning.readSourceBoundVocabularyStartReceipt(
          intent,
          expectedOwnerId: configuredOwnerId,
          ownerStillCurrent: () => true,
        ),
        throwsStateError,
      );
      await learning.startSourceBoundVocabularySession(
        intent,
        operationStillCurrent: () => true,
      );
      await learning.finishSession(intent.sessionId);
      final before = await h.snapshot();
      final receipt = await learning.readSourceBoundVocabularyStartReceipt(
        intent,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      expect(receipt, isNot(isA<CanonicalLearningTimeAdmission>()));
      expect(receipt.sourceBindingJson, intent.source.sourceBindingJson);
      await h.database.transaction(() async {
        await repository.requireCanonicalLearningTimeSessionLinkReceipt(
          receipt,
          expectedOwnerId: configuredOwnerId,
          ownerStillCurrent: () => true,
        );
      });
      expect(await h.snapshot(), before);
      await expectLater(
        repository.requireCanonicalLearningTimeSessionLinkReceipt(
          _CopiedLinkReceipt(receipt),
          expectedOwnerId: configuredOwnerId,
          ownerStillCurrent: () => true,
        ),
        throwsStateError,
      );
    },
  );

  for (final kind in VoiceLearningTimePracticeKind.values) {
    test(
      'original voice prompt receipt pins reference without transcript for ${kind.name}',
      () async {
        final intent = (await learning.prepareSourceBoundVoicePracticeStart(
          expectedOwnerId: configuredOwnerId,
          practiceKind: kind,
          wordIds: [configuredWordIds.first],
          callerContext: LearningTimeCallerContext.ordinary,
          stillCurrent: () => true,
        ))!;
        await learning.startSourceBoundVocabularySession(
          intent,
          operationStillCurrent: () => true,
        );
        final proof = await admit(intent);
        final source =
            jsonDecode(proof.sourceBindingJson) as Map<String, dynamic>;
        expect(source.keys.toList(), [
          'schemaVersion',
          'kind',
          'sessionId',
          'episodeId',
          'targetPinsSha256',
        ]);
        expect(source['episodeId'], startsWith('voice-prompt:'));
        expect(proof.sourceKind, CanonicalLearningTimeSourceKind.voicePractice);
        expect(
          proof.sourceBindingJson,
          isNot(contains(intent.presentation.questions.single.word.spelling)),
        );
        expect(proof.contextBindingJson, isNot(contains('transcriptValue')));
        await require(proof);
      },
    );
  }
}

final class _CopiedStart implements PreparedSourceBoundVocabularyStart {
  const _CopiedStart(this.original);
  final PreparedSourceBoundVocabularyStart original;
  @override
  String get ownerId => original.ownerId;
  @override
  String get sessionId => original.sessionId;
  @override
  QuizSession get presentation => original.presentation;
  @override
  VocabularyLearningTimeSourcePin get source => original.source;
  @override
  LearningTimeCallerContext get callerContext => original.callerContext;
}

final class _CopiedLinkReceipt
    implements CanonicalLearningTimeSessionLinkReceipt {
  const _CopiedLinkReceipt(this.original);
  final CanonicalLearningTimeSessionLinkReceipt original;
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
}
