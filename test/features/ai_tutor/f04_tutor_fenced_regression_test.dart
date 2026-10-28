import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_credential_version_index.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/drift_ai_usage_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_compatible_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  for (final remove in [true, false]) {
    for (final paid in [true, false]) {
      test(
        'F04 fenced revoke remove=$remove paid=$paid drains one attempt',
        () async {
          final gateway = _DrainingGateway(paid: paid);
          final fixture = await _Fixture.create(gateway);
          addTearDown(fixture.close);
          final first = fixture.tutor.reply(
            scenario: 'Cafe',
            learnerMessage: 'first',
          );
          final firstResult = paid
              ? expectLater(first, completion(isA<AiTutorReply>()))
              : expectLater(first, throwsA(_failure(AiFailureCode.cancelled)));
          await gateway.started.future;
          final revoke = remove
              ? fixture.tutor.removeKey()
              : fixture.tutor.updateConsents(
                  providerConsent: false,
                  shareLearningSummary: false,
                );
          final second = expectLater(
            fixture.tutor.reply(scenario: 'Cafe', learnerMessage: 'second'),
            throwsA(
              _failure(
                remove
                    ? AiFailureCode.missingKey
                    : AiFailureCode.consentRequired,
              ),
            ),
          );
          await gateway.cancelled.future;
          gateway.drain.complete();
          await Future.wait([firstResult, revoke, second]);
          expect(gateway.calls, 1);
          final events = await fixture.database
              .select(fixture.database.aiUsageEvents)
              .get();
          expect(events, hasLength(1));
          expect(events.single.ownerId, 'owner-a');
          expect(events.single.outcome, paid ? 'success' : 'failure');
          expect(events.single.errorCategory, paid ? isNull : 'cancelled');
          final stored = await fixture.store.readCredentialForOwner('owner-a');
          expect(stored?.providerConsent, remove ? isNull : isFalse);
        },
      );
    }
  }

  test(
    'F04 raw overflow cost completes one paid Drift attempt with unknown cost',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          '{"choices":[{"message":{"content":"paid reply"}}],'
          '"usage":{"total_tokens":5,"cost":1e308}}',
          200,
        );
      });
      addTearDown(client.close);
      final fixture = await _Fixture.create(
        OpenAiCompatibleGateway(
          client: client,
          baseUri: Uri.parse('https://synthetic.example'),
          model: 'synthetic',
        ),
      );
      addTearDown(fixture.close);
      final reply = await fixture.tutor.reply(
        scenario: 'Cafe',
        learnerMessage: 'hello',
      );
      expect(reply.text, 'paid reply');
      expect(requests, 1);
      final event = await fixture.database
          .select(fixture.database.aiUsageEvents)
          .getSingle();
      expect(event.outcome, 'success');
      expect(event.totalTokens, 5);
      expect(event.providerReportedCostMicrosUsd, isNull);
    },
  );
}

Matcher _failure(AiFailureCode code) =>
    isA<AiTutorException>().having((e) => e.code, 'code', code);

class _Fixture {
  _Fixture(this.database, this.store, this.tutor);
  final AppDatabase database;
  final SecureAiTutorSettingsStore store;
  final AiTutorUseCases tutor;

  static Future<_Fixture> create(AiTutorGateway gateway) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1));
    final store = SecureAiTutorSettingsStore(
      _MemorySecrets(),
      activeOwnerId: () async => 'owner-a',
      versionIndex: DriftAiCredentialVersionIndex(database),
    );
    await store.writeCredential(
      const AiTutorCredential(
        key: 'synthetic-key-long-enough',
        providerId: AiProviderId.openai,
        model: 'synthetic',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final now = DateTime.utc(2026, 9, 20);
    var token = 0;
    var event = 0;
    final tutor = AiTutorUseCases(
      store: store,
      gatewayResolver: ({required providerId, required model, customBaseUrl}) =>
          gateway,
      nowUtc: () => now,
      usageEventId: () => 'event-${event++}',
      usageRepository: DriftAiUsageRepository(
        database,
        activeOwnerId: () async => 'owner-a',
        activeOwnerLeaseToken: () =>
            OwnerOperationCoordinator.currentLeaseToken,
        nowUtc: () => now,
      ),
      ownerCoordinator: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(database),
        activeOwnerId: () async => 'owner-a',
        nowUtc: () => now,
        generateToken: () => 'lease-${token++}',
      ),
    );
    return _Fixture(database, store, tutor);
  }

  Future<void> close() async {
    await tutor.dispose();
    await database.close();
  }
}

class _MemorySecrets implements SecureValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _DrainingGateway implements AiTutorGateway {
  _DrainingGateway({required this.paid});
  final bool paid;
  final started = Completer<void>();
  final cancelled = Completer<void>();
  final drain = Completer<void>();
  int calls = 0;
  @override
  AiProviderId get providerId => AiProviderId.openai;
  @override
  String get model => 'synthetic';
  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    TutorRequestContext? context,
    AiCancellation? cancellation,
  }) async {
    calls++;
    started.complete();
    await cancellation!.whenCancelled;
    cancelled.complete();
    await drain.future;
    if (!paid) throw const AiTutorException(AiFailureCode.cancelled);
    return const AiGatewayReply(text: 'paid reply');
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async => [];
  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {}
}
