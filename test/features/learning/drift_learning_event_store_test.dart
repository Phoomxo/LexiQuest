import 'package:drift/drift.dart' show Variable;
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
}

EventEnvelopeV2 _event({
  required String sourceEvidenceId,
  required DateTime occurredAtUtc,
}) {
  final evidence = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'legacy-current-activity',
    hintLevel: 0,
    contentRevision: 'legacy-unknown',
    engagementAllowed: true,
  );
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
