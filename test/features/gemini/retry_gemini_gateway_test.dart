import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/retry_gemini_gateway.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test('opens after transient retry budgets and later probes', () async {
    var now = DateTime.utc(2026, 8, 9, 12);
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.providerUnavailable),
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

    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    expect(gateway.circuitState, CircuitState.open);
    await expectLater(
      _generate(gateway),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.providerUnavailable,
        ),
      ),
    );
    expect(inner.calls, 2);

    now = now.add(const Duration(minutes: 1));
    inner.error = null;
    await expectLater(_generate(gateway), completion('reply'));
    expect(gateway.circuitState, CircuitState.closed);
  });

  test('invalid credentials do not trip the provider breaker', () async {
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.invalidKey),
    );
    final gateway = RetryGeminiGateway(
      inner,
      maxAttempts: 1,
      breaker: CircuitBreaker(
        threshold: 1,
        shouldCountFailure: (error) =>
            error is GeminiException &&
            error.code == GeminiFailureCode.providerUnavailable,
      ),
    );

    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    expect(gateway.circuitState, CircuitState.closed);
    expect(inner.calls, 2);
  });
}

Future<String> _generate(RetryGeminiGateway gateway) {
  return gateway.generateTutorReply(
    key: 'key',
    scenario: 'practice',
    learnerMessage: 'hello',
  );
}

final class _FakeGateway implements GeminiGateway {
  _FakeGateway({this.error});

  GeminiException? error;
  int calls = 0;

  @override
  String get model => 'fake';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    calls++;
    if (error case final failure?) throw failure;
    return 'reply';
  }

  @override
  Future<List<String>> listModels(
    String key, {
    GeminiCancellation? cancellation,
  }) async => const ['fake'];

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}
}
