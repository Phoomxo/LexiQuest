/// Provider-neutral value types and failure taxonomy for the hybrid voice
/// pipeline.
enum VoiceEngine { nativeTts, omniVoice }

enum VoiceMode { practice, researchEvaluation }

/// Privacy-safe failure categories used for telemetry and user feedback.
enum VoiceFailureCategory {
  validation,
  authentication,
  network,
  timeout,
  rateLimited,
  modelUnavailable,
  synthesis,
  playback,
  cancelled,
  configuration,
  unknown,
}

/// Carries only a typed [category] and a safe message.
class VoiceFailure implements Exception {
  const VoiceFailure({required this.category, required this.message});

  final VoiceFailureCategory category;
  final String message;

  @override
  String toString() => 'VoiceFailure(${category.name}: $message)';
}

/// An immutable, normalized request to synthesize and play speech.
class VoiceRequest {
  const VoiceRequest._({
    required this.text,
    required this.language,
    required this.voiceId,
    required this.speed,
    required this.contentId,
    required this.contentType,
    required this.mode,
    required this.assignedEngine,
  });

  final String text;
  final String language;
  final String voiceId;
  final double speed;
  final String contentId;
  final String contentType;
  final VoiceMode mode;
  final VoiceEngine? assignedEngine;

  factory VoiceRequest.create({
    required String text,
    required String language,
    required String voiceId,
    required double speed,
    required String contentId,
    required String contentType,
    required VoiceMode mode,
    VoiceEngine? assignedEngine,
  }) {
    final normalizedText = _normalizeText(text);
    if (normalizedText.isEmpty || normalizedText.length > 500) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'Voice request text is missing or too long.',
      );
    }

    final normalizedLanguage = language.trim().toLowerCase();
    if (normalizedLanguage != 'en' && normalizedLanguage != 'th') {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'Voice request language is not supported.',
      );
    }

    if (speed.isNaN || speed.isInfinite || speed < 0.5 || speed > 1.5) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'Voice request speed is out of range.',
      );
    }

    final normalizedVoiceId = voiceId.trim();
    final normalizedContentId = contentId.trim();
    final normalizedContentType = contentType.trim();
    if (normalizedVoiceId.isEmpty ||
        normalizedContentId.isEmpty ||
        normalizedContentType.isEmpty) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'Voice request identifiers are missing.',
      );
    }

    if (mode == VoiceMode.researchEvaluation && assignedEngine == null) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'Research evaluation requires an assigned voice engine.',
      );
    }

    return VoiceRequest._(
      text: normalizedText,
      language: normalizedLanguage,
      voiceId: normalizedVoiceId,
      speed: speed,
      contentId: normalizedContentId,
      contentType: normalizedContentType,
      mode: mode,
      assignedEngine: assignedEngine,
    );
  }

  static String _normalizeText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Outcome of synthesizing a [VoiceRequest].
class VoicePlaybackResult {
  const VoicePlaybackResult({
    required this.requestedEngine,
    required this.actualEngine,
    required this.usedFallback,
    required this.cacheHit,
    this.requestId,
    this.modelVersion,
  });

  final VoiceEngine requestedEngine;
  final VoiceEngine actualEngine;
  final bool usedFallback;
  final bool cacheHit;
  final String? requestId;
  final String? modelVersion;
}
