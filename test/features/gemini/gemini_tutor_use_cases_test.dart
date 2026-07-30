import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/application/gemini_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  test('validates replacement before overwriting existing key', () async {
    final store = _MemorySettingsStore()..key = 'existing-private-key';
    final gateway = _FakeGateway()
      ..validationFailure = const GeminiException(GeminiFailureCode.invalidKey);
    final tutor = _tutor(store, gateway);

    await expectLater(
      tutor.configure(
        key: 'invalid-replacement-key-that-is-long',
        providerConsent: true,
        shareLearningSummary: false,
      ),
      throwsA(isA<GeminiException>()),
    );

    expect(store.key, 'existing-private-key');
    expect(gateway.generatedKeys, isEmpty);
  });

  test('removing key prevents all future provider calls', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(store, gateway);

    await tutor.removeKey();

    await expectLater(
      tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'A coffee please'),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.consentRequired,
        ),
      ),
    );
    expect(gateway.generateCalls, 0);
  });

  test('sends bounded aggregate progress only after summary consent', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true
      ..summaryConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(store, gateway, loadProgress: () async => _progress());

    final reply = await tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );

    expect(reply.text, 'Live provider reply');
    expect(reply.model, 'gemini-test');
    expect(gateway.lastSummary, contains('answers=10'));
    expect(gateway.lastSummary, contains('apple:50%(n=4)'));
    expect(gateway.lastSummary, isNot(contains('owner')));
  });

  test('does not read or send progress without summary consent', () async {
    var progressCalls = 0;
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(
      store,
      gateway,
      loadProgress: () async {
        progressCalls += 1;
        return _progress();
      },
    );

    await tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );

    expect(progressCalls, 0);
    expect(gateway.lastSummary, isNull);
  });

  test('removing key cancels and awaits active provider work', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _PendingGateway();
    final tutor = GeminiTutorUseCases(
      store: store,
      gateway: gateway,
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    final reply = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );
    final replyExpectation = expectLater(
      reply,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
    await gateway.started.future;

    await tutor.removeKey();
    await replyExpectation;

    expect(store.key, isNull);
    expect(gateway.cancelled, isTrue);
  });

  test('removal is ordered before a reply started during revocation', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _PendingGateway();
    final tutor = GeminiTutorUseCases(
      store: store,
      gateway: gateway,
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    final first = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'First message',
    );
    final firstExpectation = expectLater(
      first,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
    await gateway.started.future;

    final removal = tutor.removeKey();
    final second = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'Second message',
    );
    final secondExpectation = expectLater(
      second,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.consentRequired,
        ),
      ),
    );

    await Future.wait([removal, firstExpectation, secondExpectation]);
    expect(gateway.generateCalls, 1);
  });
}

GeminiTutorUseCases _tutor(
  _MemorySettingsStore store,
  _FakeGateway gateway, {
  LoadProgressSnapshot? loadProgress,
}) {
  return GeminiTutorUseCases(
    store: store,
    gateway: gateway,
    loadProgress: loadProgress,
    nowUtc: () => DateTime.utc(2026, 7, 30),
  );
}

ProgressSnapshot _progress() => ProgressSnapshot(
  sampleSize: 10,
  correctCount: 7,
  wrongCount: 3,
  accuracy: 0.7,
  points: 70,
  completedSessions: 2,
  streakDays: 1,
  dueReviewCount: 3,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 1,
  skills: const [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'apple',
      meaning: 'ผลไม้',
      sampleSize: 4,
      incorrectCount: 2,
      errorRate: 0.5,
      dueAtUtc: DateTime.utc(2026, 7, 31),
    ),
  ],
  recommendations: const [],
);

final class _MemorySettingsStore implements GeminiSettingsStore {
  String? key;
  bool providerConsent = false;
  bool summaryConsent = false;

  @override
  Future<void> deleteKey() async => key = null;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<bool> readLearningSummaryConsent() async => summaryConsent;

  @override
  Future<bool> readProviderConsent() async => providerConsent;

  @override
  Future<void> writeKey(String key) async => this.key = key;

  @override
  Future<void> writeLearningSummaryConsent(bool value) async {
    summaryConsent = value;
  }

  @override
  Future<void> writeProviderConsent(bool value) async {
    providerConsent = value;
  }
}

final class _FakeGateway implements GeminiGateway {
  GeminiException? validationFailure;
  final List<String> generatedKeys = [];
  int generateCalls = 0;
  String? lastSummary;

  @override
  String get model => 'gemini-test';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    generatedKeys.add(key);
    lastSummary = learningSummary;
    return 'Live provider reply';
  }

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {
    final failure = validationFailure;
    if (failure != null) throw failure;
  }
}

final class _PendingGateway implements GeminiGateway {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;
  int generateCalls = 0;

  @override
  String get model => 'gemini-test';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    started.complete();
    await cancellation!.whenCancelled;
    cancelled = true;
    throw const GeminiException(GeminiFailureCode.cancelled);
  }

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}
}
