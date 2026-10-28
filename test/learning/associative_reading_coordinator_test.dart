import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/adaptive_associative_scheduler.dart';
import 'package:vocab_learning_app/learning/associative_reading_coordinator.dart';
import 'package:vocab_learning_app/learning/learning_commit.dart';
import 'package:vocab_learning_app/learning/learning_repository.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database.dart';
import 'package:vocab_learning_app/learning/vocabulary_mixer.dart';

void main() {
  late LearningDatabase database;
  late DriftLearningRepository store;
  late _ControllableRepository repository;
  late AssociativeReadingCoordinator coordinator;

  setUp(() {
    database = LearningDatabase(NativeDatabase.memory());
    store = DriftLearningRepository(database);
    repository = _ControllableRepository(store);
    coordinator = _coordinator(repository: repository, reader: store);
  });

  tearDown(() => database.close());

  test(
    'start commits a supported-reading session before exposing it',
    () async {
      final state = await coordinator.start(_startRequest);

      expect(state.session.currentStage, ReadingSessionStage.supportedReading);
      expect(
        (await store.readSession(
          ownerId: 'owner-a',
          sessionId: state.session.sessionId,
        ))?.currentStage,
        ReadingSessionStage.supportedReading,
      );
      expect(state.content.provenance, ReadingContentProvenance.curated);
    },
  );

  test('enforces the six-stage order and persists answer evidence', () async {
    await coordinator.start(_startRequest);
    await coordinator.advance();
    await coordinator.advance();

    expect(coordinator.state?.session.currentStage, ReadingSessionStage.recall);
    await expectLater(
      coordinator.advance(),
      throwsA(
        isA<ReadingCoordinatorException>().having(
          (error) => error.code,
          'code',
          ReadingCoordinatorErrorCode.illegalTransition,
        ),
      ),
    );

    await coordinator.submit(
      const ReadingAnswerSubmission(
        wordKey: 'resilient',
        correct: true,
        responseTimeMs: 800,
        confidence: 4,
        cueLevel: RecallCueLevel.none,
      ),
    );
    await coordinator.advance();
    await coordinator.submit(
      const ReadingAnswerSubmission(
        wordKey: 'resilient',
        correct: true,
        responseTimeMs: 1100,
        confidence: 4,
        cueLevel: RecallCueLevel.none,
      ),
    );

    expect(
      coordinator.state?.session.currentStage,
      ReadingSessionStage.scheduling,
    );
    expect(await database.select(database.recallAttempts).get(), hasLength(2));
  });

  test('does not navigate when the evidence transaction fails', () async {
    await coordinator.start(_startRequest);
    repository.failNext = true;

    await expectLater(
      coordinator.advance(),
      throwsA(isA<LearningRepositoryException>()),
    );

    expect(
      coordinator.state?.session.currentStage,
      ReadingSessionStage.supportedReading,
    );
  });

  test('resumes after restart and isolates owners', () async {
    final started = await coordinator.start(_startRequest);
    await coordinator.advance();
    final restarted = _coordinator(repository: repository, reader: store);

    final resumed = await restarted.resume(
      ownerId: 'owner-a',
      sessionId: started.session.sessionId,
    );

    expect(resumed.session.currentStage, ReadingSessionStage.cueFading);
    await expectLater(
      restarted.resume(
        ownerId: 'owner-b',
        sessionId: started.session.sessionId,
      ),
      throwsA(
        isA<ReadingCoordinatorException>().having(
          (error) => error.code,
          'code',
          ReadingCoordinatorErrorCode.sessionNotFound,
        ),
      ),
    );
    expect(restarted.state, isNull);
  });

  test('finalize and abandon are idempotent terminal operations', () async {
    await coordinator.start(_startRequest);
    await coordinator.advance();
    await coordinator.advance();
    await coordinator.submit(_answer);
    await coordinator.advance();
    await coordinator.submit(_answer);
    final completed = await coordinator.finalize();
    final repeated = await coordinator.finalize();

    expect(completed.session.currentStage, ReadingSessionStage.completed);
    expect(identical(completed, repeated), isTrue);
    final memory = await store.readMemoryState(
      ownerId: 'owner-a',
      wordKey: 'resilient',
    );
    expect(memory?.algorithmVersion, 'associative-v1');
    expect(memory!.nextDueAtUtc.isAfter(memory.lastReviewedAtUtc!), isTrue);
    final events = await database.select(database.learningEvents).get();
    expect(events, hasLength(1));
    expect(events.single.activity, 'associative_reading');
    expect(events.single.skill, 'context_recall');

    final another = _coordinator(repository: repository, reader: store);
    await another.start(_startRequest);
    final abandoned = await another.abandon();
    final repeatedAbandon = await another.abandon();

    expect(abandoned.session.currentStage, ReadingSessionStage.abandoned);
    expect(identical(abandoned, repeatedAbandon), isTrue);
  });

  test('failed scheduling commit leaves the session ready to retry', () async {
    await coordinator.start(_startRequest);
    await coordinator.advance();
    await coordinator.advance();
    await coordinator.submit(_answer);
    await coordinator.advance();
    await coordinator.submit(_answer);
    repository.failNext = true;

    await expectLater(
      coordinator.finalize(),
      throwsA(isA<LearningRepositoryException>()),
    );

    expect(
      coordinator.state?.session.currentStage,
      ReadingSessionStage.scheduling,
    );
    expect(
      await store.readMemoryState(ownerId: 'owner-a', wordKey: 'resilient'),
      isNull,
    );
  });

  test('restart at scheduling rebuilds from durable attempts', () async {
    final started = await coordinator.start(_startRequest);
    await coordinator.advance();
    await coordinator.advance();
    await coordinator.submit(_answer);
    await coordinator.advance();
    await coordinator.submit(_answer);
    final restarted = _coordinator(repository: repository, reader: store);
    await restarted.resume(
      ownerId: 'owner-a',
      sessionId: started.session.sessionId,
    );

    final completed = await restarted.finalize();

    expect(completed.session.currentStage, ReadingSessionStage.completed);
    expect(
      await store.readMemoryState(ownerId: 'owner-a', wordKey: 'resilient'),
      isNotNull,
    );
    expect(await database.select(database.learningEvents).get(), hasLength(1));
  });
}

const _startRequest = ReadingStartRequest(
  ownerId: 'owner-a',
  cefrLevel: 'A2',
  mixRequest: VocabularyMixRequest(
    dueWords: ['resilient'],
    weakWords: [],
    newWords: [],
    targetCount: 1,
    maxNewWords: 1,
    seed: 7,
  ),
);

const _answer = ReadingAnswerSubmission(
  wordKey: 'resilient',
  correct: true,
  responseTimeMs: 900,
  confidence: 4,
  cueLevel: RecallCueLevel.none,
);

AssociativeReadingCoordinator _coordinator({
  required LearningRepository repository,
  required LearningReader reader,
}) {
  return AssociativeReadingCoordinator(
    repository: repository,
    reader: reader,
    contentSource: CuratedReadingContentSource(const [
      ReadingContent(
        contentId: 'a2-resilient',
        contentVersion: 'curated-v1',
        cefrLevel: 'A2',
        passage: 'Nok stays resilient when plans change.',
        targetWords: ['resilient'],
        provenance: ReadingContentProvenance.curated,
      ),
    ]),
    mixer: const VersionedVocabularyMixer(),
    scheduler: const AdaptiveAssociativeScheduler(),
    idGenerator: _CounterIdGenerator(),
    clock: _Clock().now,
    appVersion: '1.0.0+1',
    buildId: 'test-build',
  );
}

final class _ControllableRepository implements LearningRepository {
  _ControllableRepository(this.delegate);

  final LearningRepository delegate;
  bool failNext = false;

  @override
  Future<CommitResult> commit(LearningCommit commit) {
    if (failNext) {
      failNext = false;
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.unavailable,
        'test failure',
      );
    }
    return delegate.commit(commit);
  }
}

final class _CounterIdGenerator implements SecureIdGenerator {
  static var value = 0;

  @override
  String nextId() => 'reading-${++value}';
}

final class _Clock {
  var value = DateTime.utc(2026, 7, 29, 15);

  DateTime now() {
    final current = value;
    value = value.add(const Duration(seconds: 1));
    return current;
  }
}
