import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  final speech = SpeechPracticeUseCases(_UnusedGateway());
  for (final entry in [
    ('  Rail   STATION ', 'rail station', 100),
    ('abcde', 'abcdx', 80),
    ('abcde', 'abcxx', 60),
    ('😊a', '😊b', 50),
    ('cat', 'dog', 0),
  ]) {
    test('text comparison ${entry.$1}/${entry.$2} retains v1 meaning', () {
      final value = speech.assess(
        target: entry.$1,
        event: SpeechRecognitionEvent(
          transcript: entry.$2,
          isFinal: true,
          recognizedAtUtc: DateTime.utc(2026, 9, 14),
          engine: 'fixture',
          locale: 'en-US',
          recognitionConfidence: null,
        ),
      )!;
      expect(value.similarityPercent, entry.$3);
      expect(value.method, 'transcript-edit-distance-v1');
      expect(value.hasAcousticPitchMeasurement, isFalse);
      expect(value.hasPhonemeAlignment, isFalse);
      expect(
        const SpeakingModeAdapter().evaluate(assessment: value).isCorrect,
        entry.$3 == 100,
      );
      expect(
        const ShadowingModeAdapter().evaluate(assessment: value).isCorrect,
        entry.$3 >= 80,
      );
    });
  }
}

class _UnusedGateway implements SpeechRecognitionGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
