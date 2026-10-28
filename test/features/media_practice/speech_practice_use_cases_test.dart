import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/domain/speech_evidence_contract.dart';

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

  test('assessEvidence returns a typed available result with provenance', () {
    final useCases = SpeechPracticeUseCases(_FakeSpeechGateway());
    final result = useCases.assessEvidence(
      target: 'Apple',
      event: SpeechRecognitionEvent(
        transcript: 'apple',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 31),
        engine: 'platform-speech-recognizer',
        locale: 'en-US',
        recognitionConfidence: 0.9,
      ),
    );

    expect(result.isAvailable, isTrue);
    final available = result as SpeechAssessmentAvailable;
    expect(available.assessment.similarityPercent, 100);
    expect(available.assessment.isExactMatch, isTrue);
    expect(
      available.assessment.method,
      SpeechEvidenceProvenance.supportedMethod,
    );
    expect(
      available.provenance.toProvenanceString(),
      'platform-speech-recognizer:en-US:transcript-edit-distance-v1',
    );
    expect(available.recognitionConfidence, 0.9);
  });

  test(
    'assessEvidence treats silence as a typed unavailable state, not zero',
    () {
      final useCases = SpeechPracticeUseCases(_FakeSpeechGateway());
      final result = useCases.assessEvidence(
        target: 'practice',
        event: SpeechRecognitionEvent(
          transcript: '   ',
          isFinal: true,
          recognizedAtUtc: DateTime.utc(2026, 7, 31),
          engine: 'platform-speech-recognizer',
          locale: 'en-US',
        ),
      );

      expect(result.isAvailable, isFalse);
      final unavailable = result as SpeechAssessmentUnavailable;
      expect(unavailable.reason, SpeechEvidenceUnavailable.silence);
      expect(unavailable.engine, 'platform-speech-recognizer');
      expect(unavailable.locale, 'en-US');
    },
  );
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
