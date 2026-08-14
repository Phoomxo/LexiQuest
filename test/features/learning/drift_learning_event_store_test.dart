import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';

void main() {
  late AppDatabase database;
  late DriftLearningEventStore store;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftLearningEventStore(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'session-1',
            ownerId: 'owner-1',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: '1.0.0',
            buildId: 'test',
          ),
        );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Test',
            normalizedName: 'test',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: 'owner-1',
            categoryId: 'category-1',
            spelling: 'test',
            normalizedSpelling: 'test',
            meaning: 'test',
            normalizedMeaning: 'test',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  });

  tearDown(() => database.close());

  test('source lookup round-trips a whole-second learning event', () async {
    final exactOccurredAtUtc = DateTime.utc(2026, 8, 14, 9, 0, 0, 123);
    final event = _event(
      sourceEvidenceId: 'evidence-1',
      occurredAtUtc: exactOccurredAtUtc,
    );

    expect(event.occurredAtUtc, DateTime.utc(2026, 8, 14, 9));
    expect(event.recordedAtUtc, DateTime.utc(2026, 8, 14, 9));
    await store.append(event);

    final stored = await store.readBySourceEvidenceId('evidence-1');
    expect(stored?.toJson(), event.toJson());
  });

  test(
    'append rejects a learning event with subsecond envelope time',
    () async {
      final exactOccurredAtUtc = DateTime.utc(2026, 8, 14, 9, 0, 0, 123);
      final json =
          _event(
              sourceEvidenceId: 'evidence-subsecond',
              occurredAtUtc: exactOccurredAtUtc,
            ).toJson()
            ..['occurredAtUtc'] = exactOccurredAtUtc.toIso8601String()
            ..['recordedAtUtc'] = exactOccurredAtUtc.toIso8601String();

      await expectLater(
        store.append(EventEnvelopeV2.fromJson(json)),
        throwsArgumentError,
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  test('source lookup rejects corrupt deterministic identity', () async {
    await store.append(
      _event(
        sourceEvidenceId: 'evidence-corrupt',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 9),
      ),
    );
    await database.customUpdate(
      'UPDATE events_v2 SET idempotency_key = ? WHERE event_id = ?',
      variables: const [
        Variable<String>('learning-attempt:different:v2'),
        Variable<String>('learning-event:evidence-corrupt'),
      ],
      updates: {database.eventsV2},
    );

    await expectLater(
      store.readBySourceEvidenceId('evidence-corrupt'),
      throwsStateError,
    );
  });

  test('decision set replay rejects a same-ID decision mutation', () async {
    final at = DateTime.utc(2026, 8, 14, 9);
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'evidence-decisions',
            ownerId: 'owner-1',
            sessionId: 'session-1',
            wordId: 'word-1',
            promptMode: 'meaningChoice',
            isCorrect: true,
            attemptNumber: 1,
            occurredAtUtcMs: at.millisecondsSinceEpoch,
          ),
        );
    final attempt = await (database.select(
      database.answerAttempts,
    )..where((row) => row.id.equals('evidence-decisions'))).getSingle();
    final source = EventEnvelopeV2(
      eventId: 'learning-event:evidence-decisions',
      eventType: 'QuizCompleted',
      eventVersion: 1,
      occurredAtUtc: at,
      recordedAtUtc: at,
      actorIdentity: 'owner-1',
      ownerIdentity: 'owner-1',
      aggregateType: 'LearningSession',
      aggregateId: 'session-1',
      idempotencyKey: 'learning-attempt:evidence-decisions:v1',
      consentContext: const ConsentContext.none(),
      appVersion: '1.0.0',
      buildId: 'test',
      privacyClassification: PrivacyClassification.anonymized,
      payload: const <String, dynamic>{'attemptId': 'evidence-decisions'},
    );

    final decisionSet = await store.ensureDecisionSetForAttempt(
      attempt: attempt,
      sourceEvent: source,
    );
    expect(decisionSet.decisions, hasLength(11));
    final row =
        await (database.select(database.eventsV2)..where(
              (candidate) => candidate.eventId.equals(
                'learning-evidence-decisions:evidence-decisions:v1',
              ),
            ))
            .getSingle();
    final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    final decisions = (payload['decisions'] as List)
        .cast<Map<String, dynamic>>();
    decisions.first['effectiveDecision'] = 'deny';
    await database.customUpdate(
      'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(jsonEncode(payload)),
        const Variable<String>(
          'learning-evidence-decisions:evidence-decisions:v1',
        ),
      ],
      updates: {database.eventsV2},
    );

    await expectLater(
      store.ensureDecisionSetForAttempt(attempt: attempt, sourceEvent: source),
      throwsStateError,
    );
  });

  test(
    'declared v2 correlation rejects every non-canonical envelope shape',
    () async {
      final occurredAtUtc = DateTime.utc(2026, 8, 14, 11, 0, 0, 123);
      final context = _declaredEvidence();
      await _insertAttempt(
        database,
        id: 'declared-exact',
        occurredAtUtc: occurredAtUtc,
        evidenceContext: context,
      );
      final exact = _event(
        sourceEvidenceId: 'declared-exact',
        occurredAtUtc: occurredAtUtc,
        evidenceContext: context,
      );
      expect((await store.resolveEvidenceForSource(exact)).isResolved, isTrue);

      final corruptions = <(String, void Function(Map<String, dynamic>))>[
        ('event type', (json) => json['eventType'] = 'QuizAttempted'),
        ('event version', (json) => json['eventVersion'] = 1),
        (
          'recorded time',
          (json) => json['recordedAtUtc'] = DateTime.utc(
            2026,
            8,
            14,
            11,
            0,
            1,
          ).toIso8601String(),
        ),
        ('aggregate', (json) => json['aggregateId'] = 'other-session'),
        (
          'tenant',
          (json) => json['tenantContext'] = <String, dynamic>{
            'tenantId': 'tenant-1',
            'role': 'student',
          },
        ),
        ('correlation', (json) => json['correlationId'] = 'correlation-1'),
        ('causation', (json) => json['causationId'] = 'causation-1'),
        (
          'provider provenance',
          (json) => json['providerProvenance'] = <String, dynamic>{
            'providerId': 'provider-1',
            'modelVersion': 'model-1',
          },
        ),
        ('privacy', (json) => json['privacyClassification'] = 'ownerOnly'),
        ('content revision', (json) => json['contentRevision'] = 'other'),
        ('policy version', (json) => json['policyVersion'] = 'other'),
        (
          'extra payload key',
          (json) => (json['payload'] as Map<String, dynamic>)['extra'] = true,
        ),
        (
          'payload correctness',
          (json) =>
              (json['payload'] as Map<String, dynamic>)['correct'] = false,
        ),
      ];
      for (final (label, corrupt) in corruptions) {
        final candidate = _mutateEvent(exact, corrupt);
        expect(
          (await store.resolveEvidenceForSource(candidate)).isResolved,
          isFalse,
          reason: label,
        );
      }
    },
  );

  test(
    'contextless legacy accepts only the exact frozen v1 envelope',
    () async {
      final at = DateTime.utc(2026, 8, 14, 12);
      await _insertAttempt(database, id: 'frozen-v13', occurredAtUtc: at);
      final exact = _legacyEvent(sourceEvidenceId: 'frozen-v13', at: at);
      expect((await store.resolveEvidenceForSource(exact)).isResolved, isTrue);

      final corruptions = <(String, void Function(Map<String, dynamic>))>[
        ('event version', (json) => json['eventVersion'] = 2),
        (
          'idempotency',
          (json) => json['idempotencyKey'] = 'learning-attempt:frozen-v13:v2',
        ),
        ('privacy', (json) => json['privacyClassification'] = 'ownerOnly'),
        (
          'content metadata',
          (json) => json['contentRevision'] = 'legacy-unknown',
        ),
        (
          'research metadata',
          (json) => json['consentContext'] = <String, dynamic>{
            'researchConsentVersion': 1,
            'aiConsentGranted': false,
            'voiceConsentGranted': false,
            'socialConsentGranted': false,
          },
        ),
        (
          'extra payload key',
          (json) =>
              (json['payload'] as Map<String, dynamic>)['wordId'] = 'word-1',
        ),
      ];
      for (final (label, corrupt) in corruptions) {
        expect(
          (await store.resolveEvidenceForSource(
            _mutateEvent(exact, corrupt),
          )).isResolved,
          isFalse,
          reason: label,
        );
      }
    },
  );

  test(
    'source actor must be current or an authorized immutable predecessor',
    () async {
      final at = DateTime.utc(2026, 8, 14, 13);
      final context = _declaredEvidence();
      await _insertAttempt(
        database,
        id: 'historical-actor',
        occurredAtUtc: at,
        evidenceContext: context,
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'merged-guest',
              accountState: const Value('mergedInto:owner-1'),
              createdAtUtcMs: 0,
              isActive: const Value(false),
            ),
          );
      final exact = _event(
        sourceEvidenceId: 'historical-actor',
        occurredAtUtc: at,
        evidenceContext: context,
      );
      final authorized = _mutateEvent(
        exact,
        (json) => json['actorIdentity'] = 'merged-guest',
      );
      expect(
        (await store.resolveEvidenceForSource(authorized)).isResolved,
        isTrue,
      );
      final unauthorized = _mutateEvent(
        exact,
        (json) => json['actorIdentity'] = 'unknown-actor',
      );
      expect(
        (await store.resolveEvidenceForSource(unauthorized)).isResolved,
        isFalse,
      );
    },
  );
}

EventEnvelopeV2 _event({
  required String sourceEvidenceId,
  required DateTime occurredAtUtc,
  EvidenceContext? evidenceContext,
}) {
  final evidence = evidenceContext ?? _declaredEvidence();
  return const EventV1ToV2Adapter(
    appVersion: '1.0.0',
    buildId: 'test',
  ).adaptFromCommand(
    sourceEvidenceId: sourceEvidenceId,
    ownerId: 'owner-1',
    sessionId: 'session-1',
    wordId: 'word-1',
    promptMode: 'meaningChoice',
    isCorrect: true,
    attemptNumber: 1,
    occurredAtUtc: occurredAtUtc,
    evidenceContext: evidence,
    learningEventContext: LearningEventContext.noResearch(evidence),
  );
}

EvidenceContext _declaredEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy-current-activity',
  hintLevel: 0,
  contentRevision: 'legacy-unknown',
  engagementAllowed: true,
);

Future<void> _insertAttempt(
  AppDatabase database, {
  required String id,
  required DateTime occurredAtUtc,
  EvidenceContext? evidenceContext,
}) async {
  final context = evidenceContext;
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: context == null
              ? const Value.absent()
              : Value(context.evidenceClass.name),
          evidenceContextJson: context == null
              ? const Value.absent()
              : Value(jsonEncode(context.toJson())),
        ),
      );
}

EventEnvelopeV2 _legacyEvent({
  required String sourceEvidenceId,
  required DateTime at,
}) => EventEnvelopeV2(
  eventId: 'learning-event:$sourceEvidenceId',
  eventType: 'QuizCompleted',
  eventVersion: 1,
  occurredAtUtc: at,
  recordedAtUtc: at,
  actorIdentity: 'owner-1',
  ownerIdentity: 'owner-1',
  aggregateType: 'LearningSession',
  aggregateId: 'session-1',
  idempotencyKey: 'learning-attempt:$sourceEvidenceId:v1',
  consentContext: const ConsentContext.none(),
  appVersion: '1.0.0',
  buildId: 'test',
  privacyClassification: PrivacyClassification.anonymized,
  payload: <String, dynamic>{'attemptId': sourceEvidenceId},
);

EventEnvelopeV2 _mutateEvent(
  EventEnvelopeV2 source,
  void Function(Map<String, dynamic>) mutate,
) {
  final json = (jsonDecode(jsonEncode(source.toJson())) as Map)
      .cast<String, dynamic>();
  mutate(json);
  return EventEnvelopeV2.fromJson(json);
}
