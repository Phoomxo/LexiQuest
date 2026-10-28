import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/drift_ai_usage_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  late AppDatabase database;
  late DriftAiUsageRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftAiUsageRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 8, 1),
    );
  });

  tearDown(() => database.close());

  test('records metadata-only usage and returns aggregate totals', () async {
    await repository.record(
      AiUsageEvent(
        eventId: 'event-1',
        occurredAtUtc: DateTime.utc(2026, 8, 1),
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        requestType: 'tutorReply',
        outcome: 'success',
        latencyMs: 420,
        inputTokens: 10,
        outputTokens: 4,
        totalTokens: 14,
      ),
    );

    final summaries = await repository.summarize();

    expect(summaries, hasLength(1));
    expect(summaries.single.providerId, AiProviderId.openrouter);
    expect(summaries.single.requestCount, 1);
    expect(summaries.single.totalTokens, 14);
  });

  test('purges raw events older than 90 days after every insert', () async {
    await repository.record(
      AiUsageEvent(
        eventId: 'old',
        occurredAtUtc: DateTime.utc(2026, 4, 1),
        providerId: AiProviderId.gemini,
        model: 'model-a',
        requestType: 'tutorReply',
        outcome: 'success',
        latencyMs: 10,
      ),
    );
    await repository.record(
      AiUsageEvent(
        eventId: 'recent',
        occurredAtUtc: DateTime.utc(2026, 7, 31),
        providerId: AiProviderId.gemini,
        model: 'model-a',
        requestType: 'tutorReply',
        outcome: 'success',
        latencyMs: 10,
      ),
    );

    expect((await repository.summarize()).single.requestCount, 1);
  });

  test('reports provider cost as unknown when provider omits it', () async {
    await repository.record(
      AiUsageEvent(
        eventId: 'no-cost',
        occurredAtUtc: DateTime.utc(2026, 8, 1),
        providerId: AiProviderId.claude,
        model: 'model-a',
        requestType: 'tutorReply',
        outcome: 'success',
        latencyMs: 20,
      ),
    );

    expect(
      (await repository.summarize()).single.providerReportedCostMicrosUsd,
      isNull,
    );
  });

  test(
    'aggregate research export contains no content or identifiers',
    () async {
      await repository.record(
        AiUsageEvent(
          eventId: 'private-event-id',
          occurredAtUtc: DateTime.utc(2026, 8, 1),
          providerId: AiProviderId.openai,
          model: 'model-a',
          requestType: 'tutorReply',
          outcome: 'success',
          latencyMs: 20,
        ),
      );

      final encoded = await repository.exportAggregateJson(
        researchConsent: true,
      );
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(decoded['schemaVersion'], 1);
      expect(encoded, isNot(contains('private-event-id')));
      expect(encoded, isNot(contains('prompt')));
      expect(encoded, isNot(contains('response')));
      expect(encoded, isNot(contains('apiKey')));
    },
  );

  test('aggregate export requires explicit research consent', () async {
    await expectLater(
      repository.exportAggregateJson(researchConsent: false),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.consentRequired,
        ),
      ),
    );
  });
}
