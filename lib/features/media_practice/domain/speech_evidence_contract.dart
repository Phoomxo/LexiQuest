import 'media_practice_contracts.dart';

/// Maximum length of a persisted speech-evidence provenance string. Keeps
/// every screen and the Drift column within a single bounded contract.
const int speechEvidenceProvenanceMaxLength = 120;

/// Versioned, centralized provenance for a speech-evidence record. Every
/// screen builds its provenance through this type so the engine, locale, and
/// similarity method are recorded consistently.
final class SpeechEvidenceProvenance {
  const SpeechEvidenceProvenance({
    required this.engine,
    required this.locale,
    required this.method,
  });

  /// The supported transcript-similarity algorithm version.
  static const String supportedMethod = 'transcript-edit-distance-v1';

  static const int maxProvenanceLength = speechEvidenceProvenanceMaxLength;

  final String engine;
  final String locale;
  final String method;

  /// Single colon-joined provenance string, e.g.
  /// `platform-speech-recognizer:en-US:transcript-edit-distance-v1`.
  String toProvenanceString() => '$engine:$locale:$method';
}

/// Typed reason a pronunciation measurement is unavailable. Silence,
/// permission denial, cancellation, an unsupported locale, and provider
/// failure never produce a zero or random score (spec §9).
enum SpeechEvidenceUnavailable {
  silence,
  permissionDenied,
  cancelled,
  unsupportedLocale,
  providerFailure,
}

/// A pronunciation assessment result: either a real measurement is available,
/// or a typed unavailable reason explains why no score exists.
sealed class SpeechAssessmentResult {
  const SpeechAssessmentResult();

  /// Whether a real similarity measurement is present.
  bool get isAvailable;

  /// Builds an available result carrying the assessment and provenance.
  factory SpeechAssessmentResult.available({
    required TranscriptPronunciationAssessment assessment,
    required SpeechRecognitionEvent event,
  }) = SpeechAssessmentAvailable;

  /// Builds an unavailable result carrying a typed reason.
  factory SpeechAssessmentResult.unavailable({
    required SpeechEvidenceUnavailable reason,
    required SpeechRecognitionEvent event,
  }) = SpeechAssessmentUnavailable;
}

/// A real, non-fabricated pronunciation measurement with provenance.
final class SpeechAssessmentAvailable extends SpeechAssessmentResult {
  SpeechAssessmentAvailable({
    required this.assessment,
    required SpeechRecognitionEvent event,
  }) : provenance = SpeechEvidenceProvenance(
         engine: event.engine,
         locale: event.locale,
         method: assessment.method,
       ),
       recognitionConfidence = event.recognitionConfidence;

  final TranscriptPronunciationAssessment assessment;
  final SpeechEvidenceProvenance provenance;
  final double? recognitionConfidence;

  @override
  bool get isAvailable => true;
}

/// No measurement could be produced. Never carries a score.
final class SpeechAssessmentUnavailable extends SpeechAssessmentResult {
  SpeechAssessmentUnavailable({
    required this.reason,
    required SpeechRecognitionEvent event,
  }) : engine = event.engine,
       locale = event.locale,
       occurredAtUtc = event.recognizedAtUtc;

  final SpeechEvidenceUnavailable reason;
  final String engine;
  final String locale;
  final DateTime occurredAtUtc;

  @override
  bool get isAvailable => false;
}
