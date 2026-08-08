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
    return switch (cefrLevel.toUpperCase()) {
      'A1' || 'A2' => 'The cat sits on the mat. It is a sunny day. '
          'The cat is happy.',
      'B1' || 'B2' => 'Learning a new language opens doors to different '
          'cultures and perspectives. Regular practice helps you improve '
          'your skills over time.',
      'C1' || 'C2' => 'The nuances of linguistic proficiency extend far '
          'beyond mere vocabulary acquisition; they encompass the subtle '
          'interplay of pragmatics, sociolinguistics, and cognitive load.',
      _ => 'Read the passage carefully and answer the questions that follow.',
    };
  }
}
