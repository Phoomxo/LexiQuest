import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
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

  test(
    'coins receipt rejects an outcome without its exact result shape',
    () async {
      final source = _event(
        sourceEvidenceId: 'coins-invalid-result',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 9),
      );
      await store.append(source);

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'coins',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
        ),
        throwsStateError,
      );

      final rows =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.isIn(const <String>[
                  'learning-projection:coins:'
                      'learning-event:coins-invalid-result:v2',
                  'learning-projection-cursor:owner-1:coins:v2',
                ]),
              ))
              .get();
      expect(
        rows,
        isEmpty,
        reason: 'receipt and cursor must roll back together',
      );
    },
  );

  test(
    'coins receipts accept only stable terminal statuses and reasons',
    () async {
      final appliedSource = _event(
        sourceEvidenceId: 'coins-valid-applied',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 9),
      );
      final skippedSource = _event(
        sourceEvidenceId: 'coins-valid-skipped',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 10),
      );
      await store.append(appliedSource);
      await store.append(skippedSource);

      await store.markProjectionOutcome(
        source: appliedSource,
        projection: 'coins',
        appliedVersion: 2,
        outcome: LearningProjectionOutcome.applied,
        result: const <String, dynamic>{'status': 'replayed'},
      );
      await store.markProjectionOutcome(
        source: skippedSource,
        projection: 'coins',
        appliedVersion: 2,
        outcome: LearningProjectionOutcome.notApplicable,
        result: const <String, dynamic>{
          'reasonCode': 'capturedByLegacyBackfill',
        },
      );

      expect(
        (await store.readProjectionReceipt(
          source: appliedSource,
          projection: 'coins',
          appliedVersion: 2,
        ))?.result,
        const <String, dynamic>{'status': 'replayed'},
      );
      expect(
        (await store.readProjectionReceipt(
          source: skippedSource,
          projection: 'coins',
          appliedVersion: 2,
        ))?.result,
        const <String, dynamic>{'reasonCode': 'capturedByLegacyBackfill'},
      );
    },
  );

  test(
    'version-two Quest grants require stable source and occurrence fields',
    () async {
      final source = _event(
        sourceEvidenceId: 'quest-v2-stable-award',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 11),
      );
      await store.append(source);

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[
              <String, dynamic>{
                'ownerId': 'owner-1',
                'idempotencyKey': 'quest-v2-stable-award',
                'xpAmount': 50,
              },
            ],
          },
        ),
        throwsStateError,
      );

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[
              <String, dynamic>{
                'ownerId': 'owner-1',
                'idempotencyKey': 'quest-v2-stable-award',
                'xpAmount': 50,
                'sourceEventId': 'different-source',
                'occurredAtUtcMs': 1786676400000,
              },
            ],
          },
        ),
        throwsStateError,
      );

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[
              <String, dynamic>{
                'ownerId': 'owner-1',
                'idempotencyKey': 'quest-v2-stable-award',
                'xpAmount': 50,
                'sourceEventId': 'quest-v2-stable-award',
                'occurredAtUtcMs': 8640000000000001,
              },
            ],
          },
        ),
        throwsStateError,
      );
    },
  );

  test(
    'version-two Quest receipt bridged from v1 accepts legacy grant shape',
    () async {
      final source = _event(
        sourceEvidenceId: 'quest-v1-bridged-award',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 12),
      );
      await store.append(source);

      const legacyResult = <String, dynamic>{
        'eligible': true,
        'rewardGrants': <Object>[
          <String, dynamic>{
            'ownerId': 'owner-1',
            'idempotencyKey': 'quest-v1-bridged-award',
            'xpAmount': 50,
          },
        ],
      };
      await store.markProjectionOutcome(
        source: source,
        projection: 'quest',
        appliedVersion: 1,
        outcome: LearningProjectionOutcome.applied,
        result: legacyResult,
      );
      await store.markProjectionOutcome(
        source: source,
        projection: 'quest',
        appliedVersion: 2,
        outcome: LearningProjectionOutcome.applied,
        bridgedFromVersion: 1,
        result: legacyResult,
      );

      final receipt = await store.readProjectionReceipt(
        source: source,
        projection: 'quest',
        appliedVersion: 2,
      );
      expect(receipt?.bridgedFromVersion, 1);
      expect(receipt?.result['rewardGrants'], const <Object>[
        <String, dynamic>{
          'ownerId': 'owner-1',
          'idempotencyKey': 'quest-v1-bridged-award',
          'xpAmount': 50,
        },
      ]);
    },
  );

  test(
    'version-two Quest bridge without v1 receipt rolls back receipt and cursor',
    () async {
      final source = _event(
        sourceEvidenceId: 'quest-v1-missing-provenance',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 13),
      );
      await store.append(source);

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          bridgedFromVersion: 1,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[
              <String, dynamic>{
                'ownerId': 'owner-1',
                'idempotencyKey': 'quest-v1-missing-provenance',
                'xpAmount': 50,
              },
            ],
          },
        ),
        throwsStateError,
      );

      const receiptId =
          'learning-projection:quest:learning-event:quest-v1-missing-provenance:v2';
      const cursorId = 'learning-projection-cursor:owner-1:quest:v2';
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(cursorId))).getSingleOrNull(),
        isNull,
      );
    },
  );

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
    'Ghost recreational evidence stays game-history-only in Legacy and Shadow stores',
    () async {
      final contexts = <EvidenceContext>[
        _recreationalEvidence(EvidencePolicyRolloutMode.legacy),
        _recreationalEvidence(EvidencePolicyRolloutMode.shadow),
      ];

      for (final context in contexts) {
        final id = 'ghost-${context.rolloutMode.name}';
        final occurredAtUtc = DateTime.utc(
          2026,
          8,
          14,
          context.rolloutMode == EvidencePolicyRolloutMode.legacy ? 9 : 10,
        );
        await _insertAttempt(
          database,
          id: id,
          occurredAtUtc: occurredAtUtc,
          evidenceContext: context,
        );
        final attempt = await (database.select(
          database.answerAttempts,
        )..where((row) => row.id.equals(id))).getSingle();
        final source = context.rolloutMode == EvidencePolicyRolloutMode.legacy
            ? _event(
                sourceEvidenceId: id,
                occurredAtUtc: occurredAtUtc,
                evidenceContext: context,
              )
            : _enforcedEvent(
                sourceEvidenceId: id,
                occurredAtUtc: occurredAtUtc,
                evidenceContext: context,
              );
        final modeStore = DriftLearningEventStore(
          database,
          rolloutModeProvider:
              context.rolloutMode == EvidencePolicyRolloutMode.legacy
              ? const FixedEvidencePolicyRolloutModeProvider.legacy()
              : const ContextEvidencePolicyRolloutModeProvider(),
        );

        final decisions = await modeStore.ensureDecisionSetForAttempt(
          attempt: attempt,
          sourceEvent: source,
        );

        for (final projection in LearningProjection.values) {
          final expected =
              evidenceEligibilityV1[EvidenceClass.recreational]![projection]!;
          expect(
            decisions.decisionFor(projection).effectiveDecision,
            expected,
            reason: '${context.rolloutMode.name} $projection',
          );
          expect(
            decisions.allows(projection),
            expected == ProjectionDisposition.allow,
            reason: '${context.rolloutMode.name} $projection',
          );
        }
      }
    },
  );

  test(
    'decision set replay validates the full immutable expected envelope',
    () async {
      final at = DateTime.utc(2026, 8, 14, 10);
      final context = _enforcedEvidence();
      final enforcedStore = DriftLearningEventStore(
        database,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      );
      await _insertAttempt(
        database,
        id: 'decision-envelope',
        occurredAtUtc: at,
        evidenceContext: context,
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'other-owner',
              createdAtUtcMs: 2,
              isActive: const Value(false),
            ),
          );
      final attempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals('decision-envelope'))).getSingle();
      final source = _enforcedEvent(
        sourceEvidenceId: 'decision-envelope',
        occurredAtUtc: at,
        evidenceContext: context,
      );
      await enforcedStore.ensureDecisionSetForAttempt(
        attempt: attempt,
        sourceEvent: source,
      );
      const decisionId = 'learning-evidence-decisions:decision-envelope:v1';
      final canonical = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(decisionId))).getSingle();
      final canonicalPayload =
          jsonDecode(canonical.payloadJson) as Map<String, dynamic>;
      expect(
        canonicalPayload['evidenceContext'],
        isA<Map>(),
        reason: 'protocol and assignment identity must be immutable evidence',
      );
      String mutatePayload(void Function(Map<String, dynamic>) mutate) {
        final payload =
            jsonDecode(canonical.payloadJson) as Map<String, dynamic>;
        mutate(payload);
        return jsonEncode(payload);
      }

      final changedExperiment =
          jsonDecode(canonical.experimentContextJson!) as Map<String, dynamic>
            ..['variantId'] = 'forged';
      final corruptions = <(String, EventsV2Data Function(EventsV2Data))>[
        (
          'occurred time',
          (row) => row.copyWith(
            occurredAtUtc: row.occurredAtUtc.add(const Duration(seconds: 1)),
          ),
        ),
        (
          'recorded time',
          (row) => row.copyWith(
            recordedAtUtc: row.recordedAtUtc.add(const Duration(seconds: 1)),
          ),
        ),
        ('actor lineage', (row) => row.copyWith(actorIdentity: 'other-owner')),
        ('owner', (row) => row.copyWith(ownerId: 'other-owner')),
        (
          'tenant null rule',
          (row) => row.copyWith(
            tenantContextJson: const Value(
              '{"tenantId":"tenant-1","role":"student"}',
            ),
          ),
        ),
        (
          'aggregate type',
          (row) => row.copyWith(aggregateType: 'OtherAggregate'),
        ),
        ('aggregate id', (row) => row.copyWith(aggregateId: 'other-attempt')),
        (
          'correlation null rule',
          (row) =>
              row.copyWith(correlationId: const Value('forged-correlation')),
        ),
        (
          'causation',
          (row) => row.copyWith(
            causationId: const Value('learning-event:other-attempt'),
          ),
        ),
        (
          'idempotency',
          (row) => row.copyWith(idempotencyKey: 'forged-idempotency'),
        ),
        (
          'consent',
          (row) => row.copyWith(
            consentContextJson: jsonEncode(
              const ConsentContext.none().toJson(),
            ),
          ),
        ),
        (
          'experiment',
          (row) => row.copyWith(
            experimentContextJson: Value(jsonEncode(changedExperiment)),
          ),
        ),
        (
          'content revision',
          (row) => row.copyWith(contentRevision: const Value('forged-content')),
        ),
        (
          'policy version',
          (row) => row.copyWith(policyVersion: const Value('forged-policy')),
        ),
        ('app version', (row) => row.copyWith(appVersion: 'forged-app')),
        ('build id', (row) => row.copyWith(buildId: 'forged-build')),
        (
          'provider null rule',
          (row) => row.copyWith(
            providerProvenanceJson: const Value(
              '{"providerId":"provider-1","modelVersion":"model-1"}',
            ),
          ),
        ),
        ('privacy', (row) => row.copyWith(privacyClassification: 'ownerOnly')),
        ('event version', (row) => row.copyWith(eventVersion: 2)),
        ('event type', (row) => row.copyWith(eventType: 'ForgedDecision')),
        (
          'protocol',
          (row) => row.copyWith(
            payloadJson: mutatePayload(
              (payload) => (payload['evidenceContext'] as Map)['protocolId'] =
                  'forged-protocol',
            ),
          ),
        ),
        (
          'assignment',
          (row) => row.copyWith(
            payloadJson: mutatePayload(
              (payload) => (payload['evidenceContext'] as Map)['assignmentId'] =
                  'forged-assignment',
            ),
          ),
        ),
        (
          'decision payload',
          (row) => row.copyWith(
            payloadJson: mutatePayload(
              (payload) =>
                  ((payload['decisions'] as List).first
                          as Map<String, dynamic>)['effectiveDecision'] =
                      'deny',
            ),
          ),
        ),
      ];
      for (final (label, mutate) in corruptions) {
        await (database.delete(
          database.eventsV2,
        )..where((row) => row.eventId.equals(decisionId))).go();
        await database.into(database.eventsV2).insert(mutate(canonical));
        await expectLater(
          enforcedStore.ensureDecisionSetForAttempt(
            attempt: attempt,
            sourceEvent: source,
          ),
          throwsStateError,
          reason: label,
        );
      }
    },
  );

  test(
    'upgraded owner replays a decision set authored by its merged guest',
    () async {
      final at = DateTime.utc(2026, 8, 14, 10, 30);
      final context = _declaredEvidence();
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
      await _insertAttempt(
        database,
        id: 'upgraded-decision',
        occurredAtUtc: at,
        evidenceContext: context,
      );
      final attempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals('upgraded-decision'))).getSingle();
      final source = _mutateEvent(
        _event(
          sourceEvidenceId: 'upgraded-decision',
          occurredAtUtc: at,
          evidenceContext: context,
        ),
        (json) => json['actorIdentity'] = 'merged-guest',
      );

      await store.ensureDecisionSetForAttempt(
        attempt: attempt,
        sourceEvent: source,
      );
      final replayed = await store.ensureDecisionSetForAttempt(
        attempt: attempt,
        sourceEvent: source,
      );

      expect(replayed.sourceEvidenceId, 'upgraded-decision');
      final stored =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-evidence-decisions:upgraded-decision:v1',
                ),
              ))
              .getSingle();
      expect(stored.actorIdentity, 'merged-guest');
      expect(stored.ownerId, 'owner-1');
    },
  );

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

  test('default rollout cannot activate embedded Enforced evidence', () async {
    final at = DateTime.utc(2026, 8, 14, 14);
    final context = _enforcedEvidence();
    await _insertAttempt(
      database,
      id: 'default-enforced',
      occurredAtUtc: at,
      evidenceContext: context,
    );

    final resolution = await store.resolveEvidenceForSource(
      _enforcedEvent(
        sourceEvidenceId: 'default-enforced',
        occurredAtUtc: at,
        evidenceContext: context,
      ),
    );

    expect(
      store.rolloutModeProvider,
      isA<FixedEvidencePolicyRolloutModeProvider>(),
    );
    expect(resolution.isResolved, isFalse);
    expect(resolution.reasonCode, 'decisionSetConflict');
    expect(
      await (database.select(database.eventsV2)..where(
            (row) => row.eventId.equals(
              'learning-evidence-decisions:default-enforced:v1',
            ),
          ))
          .getSingleOrNull(),
      isNull,
    );
  });

  test(
    'alternate receipt identity collision cannot advance its cursor',
    () async {
      final source = _event(
        sourceEvidenceId: 'receipt-collision',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 15),
      );
      const receiptId =
          'learning-projection:quest:learning-event:receipt-collision:v2';
      const cursorId = 'learning-projection-cursor:owner-1:quest:v2';
      final collision = EventEnvelopeV2(
        eventId: 'alternate-receipt-row',
        eventType: 'CollisionFixture',
        eventVersion: 1,
        occurredAtUtc: source.occurredAtUtc,
        recordedAtUtc: source.recordedAtUtc,
        actorIdentity: source.actorIdentity,
        ownerIdentity: source.ownerIdentity,
        aggregateType: 'CollisionFixture',
        aggregateId: source.eventId,
        idempotencyKey: receiptId,
        consentContext: source.consentContext,
        appVersion: source.appVersion,
        buildId: source.buildId,
        privacyClassification: source.privacyClassification,
        payload: const <String, dynamic>{'fixture': true},
      );
      await _insertRawEvent(database, collision);

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[],
          },
        ),
        throwsStateError,
      );

      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(cursorId))).getSingleOrNull(),
        isNull,
      );
      expect(
        (await (database.select(database.eventsV2)
                  ..where((row) => row.eventId.equals('alternate-receipt-row')))
                .getSingle())
            .idempotencyKey,
        receiptId,
      );
    },
  );

  test(
    'conflicting cursor rolls back a new receipt without mutation',
    () async {
      final source = _event(
        sourceEvidenceId: 'cursor-collision',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 16),
      );
      const receiptId =
          'learning-projection:quest:learning-event:cursor-collision:v2';
      const cursorId = 'learning-projection-cursor:owner-1:quest:v2';
      final collision = EventEnvelopeV2(
        eventId: cursorId,
        eventType: 'LearningProjectionCursor',
        eventVersion: 1,
        occurredAtUtc: DateTime.utc(2020),
        recordedAtUtc: DateTime.utc(2020),
        actorIdentity: source.actorIdentity,
        ownerIdentity: source.ownerIdentity,
        aggregateType: 'LearningProjectionCursor',
        aggregateId: 'conflicting-source',
        causationId: 'conflicting-source',
        idempotencyKey: 'conflicting-cursor-key',
        consentContext: source.consentContext,
        appVersion: source.appVersion,
        buildId: source.buildId,
        privacyClassification: source.privacyClassification,
        payload: const <String, dynamic>{
          'sourceEventId': 'conflicting-source',
          'projection': 'quest',
          'appliedVersion': 2,
        },
      );
      await _insertRawEvent(database, collision);
      final cursorBefore = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(cursorId))).getSingle();

      await expectLater(
        store.markProjectionOutcome(
          source: source,
          projection: 'quest',
          appliedVersion: 2,
          outcome: LearningProjectionOutcome.applied,
          result: const <String, dynamic>{
            'eligible': true,
            'rewardGrants': <Object>[],
          },
        ),
        throwsStateError,
      );

      expect(
        await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
        isNull,
      );
      expect(
        (await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(cursorId))).getSingle()).toJson(),
        cursorBefore.toJson(),
      );
      expect(
        (await (database.select(
              database.eventsV2,
            )..where((row) => row.eventId.equals(cursorId))).getSingle())
            .idempotencyKey,
        'conflicting-cursor-key',
      );
    },
  );

  test(
    'cursor discovery rejects dangling future and receiptless provenance',
    () async {
      final first = _event(
        sourceEvidenceId: 'cursor-source-1',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 19),
      );
      final second = _event(
        sourceEvidenceId: 'cursor-source-2',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 20),
      );
      await store.append(first);
      await store.append(second);

      await store.markProjectionOutcome(
        source: first,
        projection: 'quest',
        appliedVersion: 2,
        outcome: LearningProjectionOutcome.applied,
        result: const <String, dynamic>{
          'eligible': true,
          'rewardGrants': <Object>[],
        },
      );
      const questCursorId = 'learning-projection-cursor:owner-1:quest:v2';
      final forgedAt = first.occurredAtUtc.add(const Duration(days: 30));
      await database.customUpdate(
        '''UPDATE events_v2
           SET occurred_at_utc = ?, recorded_at_utc = ?
           WHERE event_id = ?''',
        variables: <Variable<Object>>[
          Variable<DateTime>(forgedAt),
          Variable<DateTime>(forgedAt),
          const Variable<String>(questCursorId),
        ],
        updates: {database.eventsV2},
      );
      await expectLater(
        store.listPendingProjectionEvents(
          ownerId: 'owner-1',
          projection: 'quest',
          appliedVersion: 2,
          limit: 50,
        ),
        throwsStateError,
        reason: 'a forged future cursor must not skip valid pending evidence',
      );
      await (database.delete(
        database.eventsV2,
      )..where((row) => row.eventId.equals(questCursorId))).go();

      final receiptless = _projectionCursor(
        sourceEventId: second.eventId,
        projection: 'streak',
        occurredAtUtc: second.occurredAtUtc,
      );
      await _insertRawEvent(database, receiptless);
      await expectLater(
        store.listPendingProjectionEvents(
          ownerId: 'owner-1',
          projection: 'streak',
          appliedVersion: 2,
          limit: 50,
        ),
        throwsStateError,
        reason: 'a cursor without its matching terminal receipt is invalid',
      );
      await (database.delete(
        database.eventsV2,
      )..where((row) => row.eventId.equals(receiptless.eventId))).go();

      final dangling = _projectionCursor(
        sourceEventId: 'learning-event:missing-source',
        projection: 'reward',
        occurredAtUtc: DateTime.utc(2030),
      );
      await _insertRawEvent(database, dangling);
      await expectLater(
        store.listPendingProjectionEvents(
          ownerId: 'owner-1',
          projection: 'reward',
          appliedVersion: 2,
          limit: 50,
        ),
        throwsStateError,
        reason: 'a dangling cursor source cannot establish ordering',
      );
    },
  );

  test(
    'present optional receipt and Quest grant fields cannot be null',
    () async {
      final source = _event(
        sourceEvidenceId: 'null-receipt-fields',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 17),
      );
      await store.append(source);
      await store.markProjectionOutcome(
        source: source,
        projection: 'streak',
        appliedVersion: 1,
        outcome: LearningProjectionOutcome.applied,
      );
      const receiptId =
          'learning-projection:streak:learning-event:null-receipt-fields:v1';
      final row = await (database.select(
        database.eventsV2,
      )..where((candidate) => candidate.eventId.equals(receiptId))).getSingle();
      final canonicalPayload =
          jsonDecode(row.payloadJson) as Map<String, dynamic>;
      for (final field in const <String>[
        'reasonCode',
        'bridgedFromVersion',
        'decision',
      ]) {
        final corrupt = Map<String, dynamic>.from(canonicalPayload)
          ..[field] = null;
        await database.customUpdate(
          'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(corrupt)),
            const Variable<String>(receiptId),
          ],
          updates: {database.eventsV2},
        );
        await expectLater(
          store.readProjectionReceipt(
            source: source,
            projection: 'streak',
            appliedVersion: 1,
          ),
          throwsStateError,
          reason: field,
        );
        await database.customUpdate(
          'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(jsonEncode(canonicalPayload)),
            const Variable<String>(receiptId),
          ],
          updates: {database.eventsV2},
        );
      }

      final questSource = _event(
        sourceEvidenceId: 'null-reward-item',
        occurredAtUtc: DateTime.utc(2026, 8, 14, 18),
      );
      await store.append(questSource);
      await store.markProjectionOutcome(
        source: questSource,
        projection: 'quest',
        appliedVersion: 1,
        outcome: LearningProjectionOutcome.applied,
        result: const <String, dynamic>{
          'eligible': true,
          'rewardGrants': <Object>[
            <String, dynamic>{
              'ownerId': 'owner-1',
              'idempotencyKey': 'null-reward-item',
              'xpAmount': 1,
            },
          ],
        },
      );
      const questReceiptId =
          'learning-projection:quest:learning-event:null-reward-item:v1';
      final questReceipt = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(questReceiptId))).getSingle();
      final questPayload =
          jsonDecode(questReceipt.payloadJson) as Map<String, dynamic>;
      (((questPayload['result'] as Map<String, dynamic>)['rewardGrants']
                      as List)
                  .single
              as Map<String, dynamic>)['rewardItemId'] =
          null;
      await database.customUpdate(
        'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(jsonEncode(questPayload)),
          const Variable<String>(questReceiptId),
        ],
        updates: {database.eventsV2},
      );
      await expectLater(
        store.readProjectionReceipt(
          source: questSource,
          projection: 'quest',
          appliedVersion: 1,
        ),
        throwsStateError,
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

EvidenceContext _enforcedEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'enforced-recall',
  hintLevel: 0,
  contentRevision: 'content-v1',
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: 'protocol-a',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-a',
  experimentVersion: 1,
  assignmentId: 'assignment-a',
  cohort: 'enforced',
  researchConsentVersion: 1,
  engagementAllowed: true,
);

EvidenceContext _recreationalEvidence(EvidencePolicyRolloutMode rolloutMode) {
  if (rolloutMode == EvidencePolicyRolloutMode.legacy) {
    return EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'ghost-duel',
      hintLevel: 0,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    );
  }
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.recreational,
    skillId: 'ghost-duel',
    hintLevel: 0,
    contentRevision: 'built-in-v1',
    rolloutMode: rolloutMode,
    protocolId: 'protocol-a',
    protocolVersion: 'protocol-v1',
    experimentId: 'experiment-a',
    experimentVersion: 1,
    assignmentId: 'assignment-a',
    cohort: 'enforced',
    researchConsentVersion: 1,
    engagementAllowed: true,
  );
}

EventEnvelopeV2 _enforcedEvent({
  required String sourceEvidenceId,
  required DateTime occurredAtUtc,
  required EvidenceContext evidenceContext,
}) => EventEnvelopeV2(
  eventId: 'learning-event:$sourceEvidenceId',
  eventType: 'QuizCompleted',
  eventVersion: 2,
  occurredAtUtc: occurredAtUtc,
  recordedAtUtc: occurredAtUtc,
  actorIdentity: 'owner-1',
  ownerIdentity: 'owner-1',
  aggregateType: 'LearningSession',
  aggregateId: 'session-1',
  idempotencyKey: 'learning-attempt:$sourceEvidenceId:v2',
  consentContext: const ConsentContext(
    researchConsentVersion: 1,
    aiConsentGranted: false,
    voiceConsentGranted: false,
    socialConsentGranted: false,
  ),
  experimentContext: ExperimentContext(
    experimentId: 'experiment-a',
    variantId: 'enforced',
    assignedAtUtc: DateTime.utc(2026, 8, 1),
  ),
  contentRevision: evidenceContext.contentRevision,
  policyVersion: evidenceContext.policyVersion,
  appVersion: '1.0.0',
  buildId: 'test',
  privacyClassification: PrivacyClassification.anonymized,
  payload: <String, dynamic>{
    'attemptId': sourceEvidenceId,
    'wordId': 'word-1',
    'promptMode': 'meaningChoice',
    'correct': true,
    'score': 100,
    'attemptNumber': 1,
    'evidenceContext': evidenceContext.toJson(),
  },
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

EventEnvelopeV2 _projectionCursor({
  required String sourceEventId,
  required String projection,
  required DateTime occurredAtUtc,
}) {
  final key = 'learning-projection-cursor:owner-1:$projection:v2';
  return EventEnvelopeV2(
    eventId: key,
    eventType: 'LearningProjectionCursor',
    eventVersion: 1,
    occurredAtUtc: occurredAtUtc,
    recordedAtUtc: occurredAtUtc,
    actorIdentity: 'owner-1',
    ownerIdentity: 'owner-1',
    aggregateType: 'LearningProjectionCursor',
    aggregateId: sourceEventId,
    causationId: sourceEventId,
    idempotencyKey: key,
    consentContext: const ConsentContext.none(),
    appVersion: 'learning-projection-cursor-v1',
    buildId: 'learning-projection-cursor-v1',
    privacyClassification: PrivacyClassification.anonymized,
    payload: <String, dynamic>{
      'sourceEventId': sourceEventId,
      'projection': projection,
      'appliedVersion': 2,
    },
  );
}

Future<void> _insertRawEvent(AppDatabase database, EventEnvelopeV2 event) =>
    database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: event.eventId,
            eventType: event.eventType,
            eventVersion: event.eventVersion,
            occurredAtUtc: event.occurredAtUtc,
            recordedAtUtc: event.recordedAtUtc,
            actorIdentity: event.actorIdentity,
            ownerId: event.ownerIdentity,
            tenantContextJson: Value(
              event.tenantContext == null
                  ? null
                  : jsonEncode(event.tenantContext!.toJson()),
            ),
            aggregateType: event.aggregateType,
            aggregateId: event.aggregateId,
            correlationId: Value(event.correlationId),
            causationId: Value(event.causationId),
            idempotencyKey: event.idempotencyKey,
            consentContextJson: jsonEncode(event.consentContext.toJson()),
            experimentContextJson: Value(
              event.experimentContext == null
                  ? null
                  : jsonEncode(event.experimentContext!.toJson()),
            ),
            contentRevision: Value(event.contentRevision),
            policyVersion: Value(event.policyVersion),
            appVersion: event.appVersion,
            buildId: event.buildId,
            providerProvenanceJson: Value(
              event.providerProvenance == null
                  ? null
                  : jsonEncode(event.providerProvenance!.toJson()),
            ),
            privacyClassification: event.privacyClassification.name,
            payloadJson: jsonEncode(event.payload),
          ),
        );
