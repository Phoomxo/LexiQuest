import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/rewards/application/shadow_reward_orchestrator.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

const _adapter = EventV1ToV2Adapter(
  appVersion: '2.0.0',
  buildId: 'synthetic-build',
);
final _occurred = DateTime.utc(2026, 10, 30, 12, 0, 0, 123);

void main() {
  test('the persisted attempt replays identically across fresh adapters', () {
    final first = _adapt(_adapter, 'attempt:synthetic-persisted');
    final fresh = EventV1ToV2Adapter(
      appVersion: '2.0.0',
      buildId: 'synthetic-build',
    );
    final replay = _adapt(fresh, 'attempt:synthetic-persisted');

    expect(first.eventId, 'attempt:synthetic-persisted');
    expect(first.idempotencyKey, 'answer-attempt:attempt:synthetic-persisted');
    expect(replay.toJson(), first.toJson());
  });

  test(
    'two persisted answers in one session and millisecond remain distinct',
    () {
      final first = _adapt(_adapter, 'attempt:synthetic-one');
      final second = _adapt(_adapter, 'attempt:synthetic-two');

      expect(first.aggregateId, second.aggregateId);
      expect(first.occurredAtUtc, second.occurredAtUtc);
      expect(first.payload, second.payload);
      expect(first.eventId, 'attempt:synthetic-one');
      expect(second.eventId, 'attempt:synthetic-two');
      expect(first.idempotencyKey, isNot(second.idempotencyKey));
    },
  );

  test('attempt identity does not derive from clock or build metadata', () {
    final first = _adapt(_adapter, 'attempt:synthetic-stable');
    final changedMetadata = _adapt(
      _adapter,
      'attempt:synthetic-stable',
      at: _occurred.add(const Duration(days: 1)),
      appVersion: '3.0.0',
      buildId: 'synthetic-new-build',
    );

    expect(changedMetadata.eventId, first.eventId);
    expect(changedMetadata.idempotencyKey, first.idempotencyKey);
    expect(changedMetadata.occurredAtUtc, isNot(first.occurredAtUtc));
    expect(changedMetadata.appVersion, '3.0.0');
    expect(changedMetadata.buildId, 'synthetic-new-build');
  });

  for (final blank in ['', ' ', '\t\n']) {
    test('blank canonical attempt identity ${blank.codeUnits} is rejected', () {
      expect(() => _adapt(_adapter, blank), throwsArgumentError);
    });
  }

  test('a nonblank persisted identity is preserved without normalization', () {
    const id = ' attempt:synthetic-exact ';
    final event = _adapt(_adapter, id);
    expect(event.eventId, id);
    expect(event.idempotencyKey, 'answer-attempt:$id');
  });

  for (final correct in [true, false]) {
    test(
      'canonical $correct answer preserves the frozen envelope and payload',
      () {
        final event = _adapt(
          _adapter,
          'attempt:synthetic-shape',
          correct: correct,
          responseTimeMs: 125,
          provider: 'synthetic-provider',
        );

        expect(EventEnvelopeV2.schemaVersion, 2);
        expect(event.eventType, correct ? 'QuizCompleted' : 'QuizAttempted');
        expect(event.eventVersion, 1);
        expect(event.occurredAtUtc, _occurred);
        expect(event.recordedAtUtc, _occurred);
        expect(event.actorIdentity, 'synthetic-owner');
        expect(event.ownerIdentity, 'synthetic-owner');
        expect(event.aggregateType, 'LearningSession');
        expect(event.aggregateId, 'synthetic-session');
        expect(event.consentContext.researchConsentVersion, 0);
        expect(event.consentContext.aiConsentGranted, isFalse);
        expect(event.consentContext.voiceConsentGranted, isFalse);
        expect(event.consentContext.socialConsentGranted, isFalse);
        expect(event.tenantContext, isNull);
        expect(event.correlationId, isNull);
        expect(event.causationId, isNull);
        expect(event.experimentContext, isNull);
        expect(event.contentRevision, isNull);
        expect(event.policyVersion, isNull);
        expect(event.providerProvenance, isNull);
        expect(event.privacyClassification, PrivacyClassification.anonymized);
        expect(event.payload, {
          'wordId': 'synthetic-word',
          'promptMode': 'meaningChoice',
          'correct': correct,
          'score': correct ? 100 : 0,
          'responseTimeMs': 125,
          'attemptNumber': 1,
          'providerProvenance': 'synthetic-provider',
        });
        expect(
          EventEnvelopeV2.fromJson(event.toJson()).toJson(),
          event.toJson(),
        );
      },
    );
  }

  test(
    'optional payload fields stay absent and supplied local time normalizes to UTC',
    () {
      final local = DateTime(2026, 10, 30, 12);
      final event = _adapt(_adapter, 'attempt:synthetic-utc', at: local);
      expect(event.occurredAtUtc, local.toUtc());
      expect(event.recordedAtUtc, local.toUtc());
      expect(event.payload.keys.toSet(), {
        'wordId',
        'promptMode',
        'correct',
        'score',
        'attemptNumber',
      });
    },
  );

  test(
    'one committed configured answer feeds both optional sinks with its actual row ID and replay dispatches neither',
    () async {
      final harness = await ConfiguredQuizHarness.open();
      addTearDown(harness.close);
      final logger = InMemoryShadowLogger();
      final shadowKeys = <String>[];
      final questEvents = <EventEnvelopeV2>[];
      var sequence = 0;
      final useCases = _learning(
        harness,
        shadow: ShadowRewardOrchestrator(
          logger: logger,
          canGrant: (owner, key) async {
            shadowKeys.add(key);
            return true;
          },
          generateId: () => 'synthetic-shadow-${++sequence}',
          nowUtc: () => harness.now,
        ),
        questSink: (event) async {
          questEvents.add(event);
        },
      );
      final pending = await _pendingCorrect(useCases);
      final committed = await useCases.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      final attempt =
          (await harness.database.select(harness.database.answerAttempts).get())
              .single;

      expect(committed.record.inserted, isTrue);
      expect(logger.errors, isEmpty);
      expect(logger.entries, hasLength(1));
      expect(questEvents, hasLength(1));
      expect(logger.entries.single.eventId, attempt.id);
      expect(logger.entries.single.request!.sourceEventId, attempt.id);
      expect(shadowKeys, ['answer-attempt:${attempt.id}']);
      expect(questEvents.single.eventId, attempt.id);
      expect(questEvents.single.idempotencyKey, shadowKeys.single);
      expect(questEvents.single.aggregateId, attempt.sessionId);
      expect(questEvents.single.payload['wordId'], attempt.wordId);
      final after = await harness.snapshot();
      final replay = await useCases.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      expect(replay.record.inserted, isFalse);
      expect(logger.entries, hasLength(1));
      expect(shadowKeys, hasLength(1));
      expect(questEvents, hasLength(1));
      expect(await harness.snapshot(), after);
      expect(
        (await harness.researchCounts()).values.every((value) => value == 0),
        isTrue,
      );
      expect(await harness.count('assessment_runs'), 0);
    },
  );

  test(
    'a throwing Quest callback sees the committed answer and cannot undo its ordinary effects',
    () async {
      final harness = await ConfiguredQuizHarness.open();
      addTearDown(harness.close);
      Map<String, List<String>>? committedInsideSink;
      String? receivedId;
      var calls = 0;
      final useCases = _learning(
        harness,
        questSink: (event) async {
          calls++;
          receivedId = event.eventId;
          committedInsideSink = await harness.snapshot();
          throw StateError('synthetic optional Quest failure');
        },
      );
      final pending = await _pendingCorrect(useCases);
      final result = await useCases.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      final attempt =
          (await harness.database.select(harness.database.answerAttempts).get())
              .single;
      expect(result.record.inserted, isTrue);
      expect(receivedId, attempt.id);
      expect(calls, 1);
      expect(committedInsideSink, isNotNull);
      expect(await harness.snapshot(), committedInsideSink);
      expect(await harness.count('outbox_operations'), greaterThan(0));
      expect(
        (await harness.researchCounts()).values.every((value) => value == 0),
        isTrue,
      );
      expect(await harness.count('assessment_runs'), 0);
    },
  );
}

EventEnvelopeV2 _adapt(
  EventV1ToV2Adapter adapter,
  String id, {
  DateTime? at,
  bool correct = true,
  int? responseTimeMs,
  String? provider,
  String appVersion = '2.0.0',
  String buildId = 'synthetic-build',
}) => adapter.adaptFromCommand(
  attemptId: id,
  ownerId: 'synthetic-owner',
  sessionId: 'synthetic-session',
  wordId: 'synthetic-word',
  promptMode: 'meaningChoice',
  isCorrect: correct,
  responseTimeMs: responseTimeMs,
  attemptNumber: 1,
  occurredAtUtc: at ?? _occurred,
  appVersion: appVersion,
  buildId: buildId,
  providerProvenance: provider,
);

LearningUseCases _learning(
  ConfiguredQuizHarness harness, {
  ShadowRewardOrchestrator? shadow,
  QuestEventSink? questSink,
}) {
  var sequence = 0;
  return LearningUseCases(
    owners: harness.owners,
    repository: DriftLearningRepository(
      harness.database,
      ownerWrites: harness.ownerWrites,
    ),
    generateId: () => 'synthetic-canonical-event-${++sequence}',
    nowUtc: () => harness.now,
    buildInfo: const AppBuildInfo(
      version: 'synthetic-v1',
      buildId: 'synthetic-build-1',
    ),
    eventAdapter: const EventV1ToV2Adapter(
      appVersion: 'synthetic-v1',
      buildId: 'synthetic-build-1',
    ),
    shadowOrchestrator: shadow,
    questEventSink: questSink,
  );
}

Future<ConfiguredQuizState> _pendingCorrect(LearningUseCases useCases) async {
  final launch = await useCases.prepareConfiguredQuiz(
    expectedOwnerId: configuredOwnerId,
    configuration: QuizConfiguration.category(
      categoryId: configuredCategoryId,
      limit: 1,
    ),
  );
  final state = await useCases.startConfiguredQuiz(launch);
  final question = state.plan.questions.single;
  return useCases.prepareQuizAnswer(
    sessionId: state.sessionId,
    expectedOwnerId: configuredOwnerId,
    expectedRevision: state.checkpointRevision,
    selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
    responseTimeMs: 100,
  );
}
