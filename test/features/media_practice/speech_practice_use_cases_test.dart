import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test(
    'starts only after microphone permission and preserves provenance',
    () async {
      final gateway = _FakeSpeechGateway();
      final useCases = SpeechPracticeUseCases(gateway);
      SpeechRecognitionEvent? received;

      await useCases.start(
        locale: 'en-US',
        onEvent: (event) => received = event,
        onFailure: (_) {},
        onStatus: (_) {},
      );

      expect(gateway.permissionRequests, 1);
      expect(gateway.initializeCalls, 1);
      expect(received!.transcript, 'apple');
      final assessment = useCases.assess(target: 'Apple', event: received!);
      expect(assessment.similarityPercent, 100);
      expect(assessment.isExactMatch, isTrue);
      expect(assessment.method, 'transcript-edit-distance-v1');
      expect(assessment.engine, 'fake-device-stt');
      expect(assessment.hasAcousticPitchMeasurement, isFalse);
      expect(assessment.hasPhonemeAlignment, isFalse);
    },
  );

  test('permission denial prevents recognizer initialization', () async {
    final gateway = _FakeSpeechGateway()
      ..permission = MediaPermissionState.denied;
    final useCases = SpeechPracticeUseCases(gateway);

    await expectLater(
      useCases.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      ),
      throwsA(
        isA<SpeechPracticeException>().having(
          (error) => error.code,
          'code',
          SpeechFailureCode.permissionDenied,
        ),
      ),
    );

    expect(gateway.initializeCalls, 0);
  });

  test('empty or unmatched transcript never invents an acoustic score', () {
    final useCases = SpeechPracticeUseCases(_FakeSpeechGateway());
    final assessment = useCases.assess(
      target: 'practice',
      event: SpeechRecognitionEvent(
        transcript: '',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'fake-device-stt',
        locale: 'en-US',
      ),
    );

    expect(assessment.similarityPercent, 0);
    expect(assessment.hasAcousticPitchMeasurement, isFalse);
    expect(assessment.hasPhonemeAlignment, isFalse);
  });
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  MediaPermissionState permission = MediaPermissionState.granted;
  int permissionRequests = 0;
  int initializeCalls = 0;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    initializeCalls += 1;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'apple',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'fake-device-stt',
        locale: locale,
        recognitionConfidence: 0.8,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}
