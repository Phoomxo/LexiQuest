/// Provider-neutral value types and failure taxonomy for the LexiQuest AI
/// content pipeline.
///
/// Mirrors the structure of `lib/voice/voice_models.dart` so the AI client
/// composes identically to the (proven) voice client: a single typed
/// failure taxonomy drives both error mapping and telemetry, and an
/// immutable request/response pair keeps the wire contract explicit.
library;

/// Kinds of teaching content the LexiQuest-LM (or any compatible provider)
/// can generate. Matches the `ContentKind` literal on the backend so the
/// wire contract cannot drift.
enum ContentKind {
  sentence,
  story,
  explanation;

  /// Wire string sent to the backend. Kept here (not in the provider) so the
  /// enum is the single source of truth.
  String get wire => name;

  /// Parse the wire string back to the enum; returns `null` on unknown
  /// values so the provider can map an unexpected response to a typed
  /// failure rather than crash.
  static ContentKind? fromWire(String? value) {
    if (value == null) return null;
    for (final kind in ContentKind.values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// CEFR levels supported across the app and backend. `unknown` allows a
/// request that is not level-bound (e.g. a free-form tutor question) without
/// forcing a bogus level.
enum CefrLevel {
  a1,
  a2,
  b1,
  b2,
  c1,
  c2,
  unknown;

  String get wire => name;

  static CefrLevel fromWire(String? value) {
    if (value == null) return CefrLevel.unknown;
    final lower = value.trim().toLowerCase();
    for (final level in CefrLevel.values) {
      if (level.wire == lower) return level;
    }
    return CefrLevel.unknown;
  }
}

/// Privacy-safe failure categories used for telemetry and user feedback.
/// Mirrors `VoiceFailureCategory` so failures are reported uniformly.
enum AiFailureCategory {
  validation,
  authentication,
  network,
  timeout,
  rateLimited,
  providerUnavailable,
  generation,
  cancelled,
  configuration,
  unknown,
}

/// Carries only a typed [category] and a safe message. Never includes the
/// request text, bearer token, or provider internals.
class AiFailure implements Exception {
  const AiFailure({required this.category, required this.message});

  final AiFailureCategory category;
  final String message;

  @override
  String toString() => 'AiFailure(${category.name}: $message)';
}

/// An immutable, normalized request to generate teaching content.
class ContentRequest {
  const ContentRequest._({
    required this.text,
    required this.kind,
    required this.cefr,
    required this.language,
  });

  final String text;
  final ContentKind kind;
  final CefrLevel cefr;
  final String language; // 'en' or 'th'

  /// Validates inputs against the same rules as the backend schema, so a
  /// caller-side error throws before we even cross the network.
  factory ContentRequest.create({
    required String text,
    required ContentKind kind,
    CefrLevel cefr = CefrLevel.unknown,
    String language = 'en',
  }) {
    final normalizedText = _normalizeText(text);
    if (normalizedText.isEmpty || normalizedText.length > 500) {
      throw const AiFailure(
        category: AiFailureCategory.validation,
        message: 'Content request text is missing or too long.',
      );
    }

    final normalizedLanguage = language.trim().toLowerCase();
    if (normalizedLanguage != 'en' && normalizedLanguage != 'th') {
      throw const AiFailure(
        category: AiFailureCategory.validation,
        message: 'Content request language must be en or th.',
      );
    }

    return ContentRequest._(
      text: normalizedText,
      kind: kind,
      cefr: cefr,
      language: normalizedLanguage,
    );
  }

  static String _normalizeText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Outcome of generating content for a [ContentRequest].
class ContentResponse {
  const ContentResponse({
    required this.text,
    required this.kind,
    required this.cefr,
    required this.language,
    required this.modelVersion,
    required this.cached,
  });

  final String text;
  final ContentKind kind;
  final CefrLevel cefr;
  final String language;
  final String modelVersion;
  final bool cached;
}
