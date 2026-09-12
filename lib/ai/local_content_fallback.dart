import '../services/local_reading_catalog.dart';

/// Local deterministic content fallback used when all AI providers are
/// unavailable (offline, quota exhausted, key missing).
///
/// These responses are simple, deterministic, and never claim to be
/// AI-generated. They provide a baseline learning experience so the app
/// remains useful without connectivity.
final class LocalContentFallback {
  const LocalContentFallback._();

  /// Returns a deterministic practice sentence for [word].
  /// Used as a last-resort when AI generation is unavailable.
  static String practiceSentence(String word) {
    return 'Can you use "$word" in a sentence?';
  }

  /// Returns a simple encouraging reply for the learner.
  /// Used as last-resort tutor reply.
  static String tutorReply(String learnerMessage) {
    return 'Keep practicing! Your message has been noted. '
        'Connect to the internet for AI-powered feedback.';
  }

  /// Returns a fixed reading passage for CEFR level practice.
  /// Used when generated reading content is unavailable.
  static String readingPassage(String cefrLevel) {
    return LocalReadingCatalog.forLevel(cefrLevel).text;
  }
}
