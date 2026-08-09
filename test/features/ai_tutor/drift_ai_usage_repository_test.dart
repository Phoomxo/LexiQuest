import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/drift_ai_usage_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  late AppDatabase database;
  late String activeOwner;
  late DriftAiUsageRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    activeOwner = 'owner-a';
    for (final owner in ['owner-a', 'owner-b']) {
      await database
          .into(database.localOwners)
          .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
    }
    repository = DriftAiUsageRepository(
      database,
      activeOwnerId: () async => activeOwner,
      nowUtc: () => DateTime.utc(2026, 5, 1),
    );
  });

  tearDown(() => database.close());

  test(
    'records idempotently and isolates summaries and clearing by owner',
    () async {
      final event = _event(id: 'same-id', outcome: 'success');
      await repository.record(event);
      await repository.record(event);
      expect((await repository.summarize()).single.requestCount, 1);

      activeOwner = 'owner-b';
      expect(await repository.summarize(), isEmpty);
      await repository.record(event);
      expect((await repository.summarize()).single.requestCount, 1);
      await repository.clear();
      expect(await repository.summarize(), isEmpty);

      activeOwner = 'owner-a';
      expect((await repository.summarize()).single.requestCount, 1);
    },
  );

  test('retention only purges the active owner', () async {
    final expiredAt = DateTime.utc(2026, 5, 1);
    await repository.record(
      _event(id: 'expired-a', outcome: 'success', at: expiredAt),
    );
    activeOwner = 'owner-b';
    await repository.record(
      _event(id: 'expired-b', outcome: 'success', at: expiredAt),
    );

    expect(await repository.purgeExpired(DateTime.utc(2026, 8, 2)), 1);
    expect(await repository.summarize(), isEmpty);
    activeOwner = 'owner-a';
    expect((await repository.summarize()).single.requestCount, 1);
  });

  test('aggregate export is metadata-only and consent-gated', () async {
    await repository.record(
      _event(id: 'private-event-id', outcome: 'success', tokens: 11),
    );

    await expectLater(
      repository.exportAggregateJson(researchConsent: false),
      throwsA(isA<AiTutorException>()),
    );
    final exported = await repository.exportAggregateJson(
      researchConsent: true,
    );
    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    expect(decoded['kind'], 'ai_usage_aggregate');
    expect(exported, isNot(contains('private-event-id')));
    expect(exported, isNot(contains('secret-key-sentinel')));
    expect(exported, isNot(contains('learner-message-sentinel')));
  });
}

AiUsageEvent _event({
  required String id,
  required String outcome,
  DateTime? at,
  int? tokens,
}) => AiUsageEvent(
  eventId: id,
  occurredAtUtc: at ?? DateTime.utc(2026, 8, 1),
  providerId: AiProviderId.openai,
  model: 'model-a',
  requestType: 'tutorReply',
  outcome: outcome,
  latencyMs: 10,
  totalTokens: tokens,
);
