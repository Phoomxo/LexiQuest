import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

typedef _CaptureNativeSubmission =
    CapturedNativeModeSubmission Function(
      CurrentActivityEvidenceAdapter evidence,
      String ownerId,
    );

void main() {
  final assessment = TranscriptPronunciationAssessment(
    target: 'durable',
    transcript: 'durable',
    similarityPercent: 100,
    isExactMatch: true,
    method: 'exact',
    engine: 'test',
    locale: 'en-US',
    occurredAtUtc: DateTime.utc(2026, 8, 28, 11),
  );
  final cases = <({String name, _CaptureNativeSubmission capture})>[
    (
      name: 'dictation',
      capture: (evidence, ownerId) => const DictationModeAdapter().capture(
        evidence: evidence,
        ownerId: ownerId,
        sessionId: 'session:dictation',
        wordId: 'word:dictation',
        target: 'durable',
        response: 'durable',
        supportUsed: false,
        responseTimeMs: 100,
        attemptNumber: 1,
      ),
    ),
    (
      name: 'speaking',
      capture: (evidence, ownerId) => const SpeakingModeAdapter().capture(
        evidence: evidence,
        ownerId: ownerId,
        sessionId: 'session:speaking',
        wordId: 'word:speaking',
        assessment: assessment,
        responseTimeMs: 100,
        attemptNumber: 1,
      ),
    ),
    (
      name: 'shadowing',
      capture: (evidence, ownerId) => const ShadowingModeAdapter().capture(
        evidence: evidence,
        ownerId: ownerId,
        sessionId: 'session:shadowing',
        wordId: 'word:shadowing',
        assessment: assessment,
        responseTimeMs: 100,
        attemptNumber: 1,
      ),
    ),
    (
      name: 'CEFR reading',
      capture: (evidence, ownerId) => const CefrReadingModeAdapter().capture(
        evidence: evidence,
        ownerId: ownerId,
        sessionId: 'session:cefr-reading',
        wordId: 'word:cefr-reading',
        responseTimeMs: 100,
        attemptNumber: 1,
      ),
    ),
    (
      name: 'sentence scramble',
      capture: (evidence, ownerId) =>
          const SentenceScrambleModeAdapter().capture(
            evidence: evidence,
            ownerId: ownerId,
            sessionId: 'session:sentence-scramble',
            wordId: 'word:sentence-scramble',
            target: 'a durable sentence',
            response: 'a durable sentence',
            responseTimeMs: 100,
            attemptNumber: 1,
          ),
    ),
    (
      name: 'word scramble',
      capture: (evidence, ownerId) => const WordScrambleModeAdapter().capture(
        evidence: evidence,
        ownerId: ownerId,
        sessionId: 'session:word-scramble',
        wordId: 'word:word-scramble',
        target: 'durable',
        response: 'durable',
        responseTimeMs: 100,
        attemptNumber: 1,
      ),
    ),
  ];

  for (final testCase in cases) {
    test(
      '${testCase.name} evidence retry remains bound to its session owner',
      () async {
        final owners = _MutableOwnerRepository();
        final repository = _RetryEvidenceRepository();
        var nextId = 0;
        final learning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'native-owner-${++nextId}',
          nowUtc: () => DateTime.utc(2026, 8, 28, 11, 0, nextId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final pending = testCase
            .capture(
              CurrentActivityEvidenceAdapter(learning: learning),
              'owner-a',
            )
            .pending;
        owners.activeOwnerId = 'owner-b';

        await expectLater(pending.record(), throwsStateError);
        await pending.retry();

        expect(repository.commands, hasLength(2));
        expect(
          repository.commands.map((command) => command.ownerId),
          everyElement('owner-a'),
        );
      },
    );
  }
}

final class _MutableOwnerRepository implements LocalOwnerRepository {
  String activeOwnerId = 'owner-a';

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: activeOwnerId, createdAtUtc: DateTime.utc(2026, 8, 28));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryEvidenceRepository implements LearningRepository {
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _failed = false;

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (!_failed) {
      _failed = true;
      throw StateError('simulated evidence failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
