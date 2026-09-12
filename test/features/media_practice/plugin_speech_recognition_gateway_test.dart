import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vocab_learning_app/features/media_practice/data/plugin_speech_recognition_gateway.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  for (final error in ['error_speech_timeout', 'error_no_match']) {
    test('$error reaches the no-speech recovery policy', () async {
      final speech = _SpeechFixture();
      final gateway = PluginSpeechRecognitionGateway(speech: speech);
      final failures = <SpeechFailureCode>[];
      await gateway.initialize(onFailure: failures.add, onStatus: (_) {});
      speech.onError!(SpeechRecognitionError(error, true));
      expect(failures, [SpeechFailureCode.noMatch]);
    });
  }

  test('unavailable native recognizer fails before any listening', () async {
    final gateway = PluginSpeechRecognitionGateway(
      speech: _SpeechFixture(available: false),
    );
    await expectLater(
      gateway.initialize(onFailure: (_) {}, onStatus: (_) {}),
      throwsA(
        isA<SpeechPracticeException>().having(
          (error) => error.code,
          'code',
          SpeechFailureCode.unavailable,
        ),
      ),
    );
  });
}

final class _SpeechFixture implements SpeechToText {
  _SpeechFixture({this.available = true});
  final bool available;
  SpeechErrorListener? onError;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    this.onError = onError;
    return available;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
