import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  test('repair AI timeout cancels and returns authored fallback', () async {
    final cancellation = AiCancellation();
    final result = await AiTutorUseCases.guidedRepairHelp(
      request: (_) => Completer<String>().future,
      cancellation: cancellation,
      fallback: 'Read the context again.',
      timeout: const Duration(milliseconds: 1),
    );
    expect(result.generated, isFalse);
    expect(result.text, 'Read the context again.');
    expect(cancellation.isCancelled, isTrue);
  });
  test(
    'provider errors and malformed help do not become authoritative',
    () async {
      for (final request in <Future<String> Function(AiCancellation)>[
        (_) async => throw const AiTutorException(AiFailureCode.quota),
        (_) async => '',
      ]) {
        final result = await AiTutorUseCases.guidedRepairHelp(
          request: request,
          cancellation: AiCancellation(),
          fallback: 'Authored hint',
        );
        expect(result.generated, isFalse);
      }
    },
  );
  test('cancelled help never publishes a late provider result', () async {
    final cancellation = AiCancellation();
    final pending = Completer<String>();
    final result = AiTutorUseCases.guidedRepairHelp(
      request: (_) => pending.future,
      cancellation: cancellation,
      fallback: 'Authored hint',
    );
    cancellation.cancel();
    pending.complete('Late help');
    expect((await result).generated, isFalse);
  });
}
