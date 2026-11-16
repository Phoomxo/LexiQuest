abstract final class LearningEvidenceContract {
  static const int maxIdentifierLength = 256;
  static const int maxPromptModeLength = 60;
  static const int maxProviderProvenanceLength = 120;
  static const int maxResponseTimeMs = 2147483647;
  static const int maxAttemptNumber = 1000000;

  static bool validText(String value, {required int maxLength}) {
    final length = value.runes.length;
    return value.trim().isNotEmpty && length <= maxLength;
  }

  static bool validIdentifier(String value) =>
      validText(value, maxLength: maxIdentifierLength);

  static bool validAttempt({
    required String id,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required int? responseTimeMs,
    required int attemptNumber,
    required int occurredAtUtcMs,
    required String? providerProvenance,
  }) {
    return validIdentifier(id) &&
        validIdentifier(ownerId) &&
        validIdentifier(sessionId) &&
        validIdentifier(wordId) &&
        validText(promptMode, maxLength: maxPromptModeLength) &&
        (responseTimeMs == null ||
            (responseTimeMs >= 0 && responseTimeMs <= maxResponseTimeMs)) &&
        attemptNumber > 0 &&
        attemptNumber <= maxAttemptNumber &&
        occurredAtUtcMs >= 0 &&
        (providerProvenance == null ||
            (providerProvenance.runes.length <= maxProviderProvenanceLength));
  }

  static bool validReading({
    required String eventId,
    required String ownerId,
    required String documentId,
    required int documentRevision,
    required String eventType,
    required int? position,
    required int occurredAtUtcMs,
  }) {
    return validIdentifier(eventId) &&
        validIdentifier(ownerId) &&
        validIdentifier(documentId) &&
        documentRevision > 0 &&
        (eventType == 'checkpoint' || eventType == 'completed') &&
        (position == null || position >= 0) &&
        occurredAtUtcMs >= 0;
  }
}
