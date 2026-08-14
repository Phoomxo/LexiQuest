import 'dart:convert';

import 'evidence_context.dart';

abstract final class LearningEvidenceContract {
  static const int maxIdentifierLength = 256;
  static const int maxSourceEvidenceIdLength = 197;
  static const int maxLearningProjectionNameLength = 20;
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

  static bool validSourceEvidenceId(String value) =>
      value.trim() == value &&
      validText(value, maxLength: maxSourceEvidenceIdLength);

  static DateTime canonicalEventUtcSecond(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'value', 'must be UTC');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (value.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond) *
          Duration.millisecondsPerSecond,
      isUtc: true,
    );
  }

  static bool isCanonicalEventUtcSecond(DateTime value) =>
      value.isUtc && value == canonicalEventUtcSecond(value);

  static String learningEventId(String sourceEvidenceId) => _derivedId(
    'learning-event:${_sourceEvidenceId(sourceEvidenceId)}',
    'learningEventId',
  );

  static String learningAttemptIdempotencyKey(String sourceEvidenceId) =>
      _derivedId(
        'learning-attempt:${_sourceEvidenceId(sourceEvidenceId)}:v2',
        'learningAttemptIdempotencyKey',
      );

  static String answerAttemptOutboxOperationId(String sourceEvidenceId) =>
      _derivedId(
        'attempt:${_sourceEvidenceId(sourceEvidenceId)}:1',
        'answerAttemptOutboxOperationId',
      );

  static String learningProjectionReceiptId({
    required String projection,
    required String sourceEventId,
    required int appliedVersion,
  }) {
    if (projection.trim() != projection ||
        !validText(projection, maxLength: maxLearningProjectionNameLength)) {
      throw ArgumentError.value(projection, 'projection', 'invalid name');
    }
    if (!validIdentifier(sourceEventId)) {
      throw ArgumentError.value(
        sourceEventId,
        'sourceEventId',
        'invalid identifier',
      );
    }
    if (appliedVersion < 1) {
      throw ArgumentError.value(
        appliedVersion,
        'appliedVersion',
        'must be positive',
      );
    }
    return _derivedId(
      'learning-projection:$projection:$sourceEventId:v$appliedVersion',
      'learningProjectionReceiptId',
    );
  }

  static EvidenceContext frozenV13LegacyEvidenceContext() =>
      _frozenV13LegacyEvidenceContext;

  static bool isExactFrozenV13LegacyEvidence(EvidenceContext context) =>
      jsonEncode(context.toJson()) == _frozenV13LegacyEvidenceJson;

  static final EvidenceContext _frozenV13LegacyEvidenceContext =
      EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'legacy-unspecified',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );

  static final String _frozenV13LegacyEvidenceJson = jsonEncode(
    _frozenV13LegacyEvidenceContext.toJson(),
  );

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
    required String evidenceClass,
    required String evidenceContextJson,
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
            (providerProvenance.runes.length <= maxProviderProvenanceLength)) &&
        validEvidenceMetadata(
          evidenceClass: evidenceClass,
          evidenceContextJson: evidenceContextJson,
        );
  }

  static bool validEvidenceMetadata({
    required String evidenceClass,
    required String evidenceContextJson,
  }) {
    try {
      final decoded = jsonDecode(evidenceContextJson);
      if (decoded is! Map) return false;
      final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
      return evidenceClass == context.evidenceClass.name &&
          evidenceContextJson == jsonEncode(context.toJson());
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  static bool sameEvidenceMetadata({
    required String evidenceClass,
    required String evidenceContextJson,
    required EvidenceContext expectedContext,
  }) {
    return validEvidenceMetadata(
          evidenceClass: evidenceClass,
          evidenceContextJson: evidenceContextJson,
        ) &&
        evidenceClass == expectedContext.evidenceClass.name &&
        evidenceContextJson == jsonEncode(expectedContext.toJson());
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

  static String _sourceEvidenceId(String value) {
    if (!validSourceEvidenceId(value)) {
      throw ArgumentError.value(
        value,
        'sourceEvidenceId',
        'invalid stable identifier',
      );
    }
    return value;
  }

  static String _derivedId(String value, String name) {
    if (!validIdentifier(value)) {
      throw StateError('$name exceeds the canonical identifier budget');
    }
    return value;
  }
}
