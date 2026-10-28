import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/retry_gemini_gateway.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test('opens after complete transient retry budgets are exhausted', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    final inner = _FakeGeminiGateway(
      generateError: const GeminiException(
        GeminiFailureCode.providerUnavailable,
      ),
    );
    final breaker = CircuitBreaker(
      threshold: 2,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
      shouldCountFailure: (error) =>
          error is GeminiException &&
          error.code == GeminiFailureCode.providerUnavailable,
    );
    final gateway = RetryGeminiGateway(
      inner,
      maxAttempts: 1,
      baseDelay: Duration.zero,
      breaker: breaker,
    );

    await expectLater(
      gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
      ),
      throwsA(isA<GeminiException>()),
    );
    await expectLater(
      gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
      ),
      throwsA(isA<GeminiException>()),
    );

    expect(gateway.circuitState, CircuitState.open);
    await expectLater(
      gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
      ),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.providerUnavailable,
        ),
      ),
    );
    expect(inner.generateCalls, 2);

    now = now.add(const Duration(minutes: 1));
    inner.generateError = null;
    await expectLater(
      gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
      ),
      completion('generated reply'),
    );
    expect(gateway.circuitState, CircuitState.closed);
  });

  test('does not trip the provider breaker for invalid credentials', () async {
    final inner = _FakeGeminiGateway(
      generateError: const GeminiException(GeminiFailureCode.invalidKey),
    );
    final breaker = CircuitBreaker(
      threshold: 1,
      shouldCountFailure: (error) =>
          error is GeminiException &&
          error.code == GeminiFailureCode.providerUnavailable,
    );
    final gateway = RetryGeminiGateway(inner, maxAttempts: 1, breaker: breaker);

    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        gateway.generateTutorReply(
          key: 'bad-key',
          scenario: 'practice',
          learnerMessage: 'hello',
        ),
        throwsA(
          isA<GeminiException>().having(
            (error) => error.code,
            'code',
            GeminiFailureCode.invalidKey,
          ),
        ),
      );
    }

    expect(gateway.circuitState, CircuitState.closed);
    expect(inner.generateCalls, 2);
  });
}

final class _FakeGeminiGateway implements GeminiGateway {
  _FakeGeminiGateway({this.generateError});

  GeminiException? generateError;
  int generateCalls = 0;

  @override
  String get model => 'fake-model';

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generateCalls++;
    final error = generateError;
    if (error != null) throw error;
    return 'generated reply';
  }

  @override
  Future<List<String>> listModels(
    String key, {
    GeminiCancellation? cancellation,
  }) async => <String>['fake-model'];
}
