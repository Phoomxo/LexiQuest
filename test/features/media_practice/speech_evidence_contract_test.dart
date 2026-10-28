import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/domain/speech_evidence_contract.dart';

void main() {
  group('SpeechEvidenceProvenance', () {
    test('builds a single colon-joined provenance string', () {
      const provenance = SpeechEvidenceProvenance(
        engine: 'platform-speech-recognizer',
        locale: 'en-US',
        method: 'transcript-edit-distance-v1',
      );

      expect(
        provenance.toProvenanceString(),
        'platform-speech-recognizer:en-US:transcript-edit-distance-v1',
      );
    });

    test('respects the maximum provenance length contract', () {
      expect(
        SpeechEvidenceProvenance.maxProvenanceLength,
        lessThanOrEqualTo(120),
      );
    });

    test('exposes the supported similarity method version', () {
      expect(
        SpeechEvidenceProvenance.supportedMethod,
        'transcript-edit-distance-v1',
      );
    });
  });

  group('SpeechAssessmentResult', () {
    final event = SpeechRecognitionEvent(
      transcript: 'apple',
      isFinal: true,
      recognizedAtUtc: DateTime.utc(2026, 7, 31),
      engine: 'platform-speech-recognizer',
      locale: 'en-US',
      recognitionConfidence: 0.8,
    );

    test('available carries the assessment and provenance', () {
      final assessment = TranscriptPronunciationAssessment(
        target: 'Apple',
        transcript: 'apple',
        similarityPercent: 100,
        isExactMatch: true,
        method: 'transcript-edit-distance-v1',
        engine: 'platform-speech-recognizer',
        locale: 'en-US',
        occurredAtUtc: event.recognizedAtUtc,
      );

      final result = SpeechAssessmentResult.available(
        assessment: assessment,
        event: event,
      );

      expect(result.isAvailable, isTrue);
      result as SpeechAssessmentAvailable;
      expect(result.assessment.similarityPercent, 100);
      expect(
        result.provenance.toProvenanceString(),
        'platform-speech-recognizer:en-US:transcript-edit-distance-v1',
      );
      expect(result.recognitionConfidence, 0.8);
    });

    test('unavailable carries a typed reason and never a score', () {
      final result = SpeechAssessmentResult.unavailable(
        reason: SpeechEvidenceUnavailable.silence,
        event: event,
      );

      expect(result.isAvailable, isFalse);
      result as SpeechAssessmentUnavailable;
      expect(result.reason, SpeechEvidenceUnavailable.silence);
      expect(result.engine, 'platform-speech-recognizer');
      expect(result.locale, 'en-US');
    });
  });
}
