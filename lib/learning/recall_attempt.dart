enum RecallMode { unaided, cued, cloze, multipleChoice, transfer }

enum CueLevel { none, highlight, associationHint, fullDefinition }

class RecallAttempt {
  final String attemptId;
  final String sessionId;
  final String wordKey;
  final RecallMode recallMode;
  final CueLevel cueLevel;
  final bool correctness;
  final int responseTimeMs;
  final int confidence; // 1 to 5
  final String? contextId;
  final String algorithmVersion;
  final DateTime occurredAt;

  RecallAttempt({
    required this.attemptId,
    required this.sessionId,
    required this.wordKey,
    required this.recallMode,
    required this.cueLevel,
    required this.correctness,
    required this.responseTimeMs,
    required this.confidence,
    this.contextId,
    this.algorithmVersion = 'v1.0.0',
    required this.occurredAt,
  }) {
    if (confidence < 1 || confidence > 5) {
      throw ArgumentError('confidence must be between 1 and 5');
    }
    if (responseTimeMs < 0) {
      throw ArgumentError('responseTimeMs must be non-negative');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'attemptId': attemptId,
      'sessionId': sessionId,
      'wordKey': wordKey,
      'recallMode': recallMode.name,
      'cueLevel': cueLevel.name,
      'correctness': correctness,
      'responseTimeMs': responseTimeMs,
      'confidence': confidence,
      'contextId': contextId,
      'algorithmVersion': algorithmVersion,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }

  factory RecallAttempt.fromJson(Map<String, dynamic> json) {
    return RecallAttempt(
      attemptId: json['attemptId'] as String,
      sessionId: json['sessionId'] as String,
      wordKey: json['wordKey'] as String,
      recallMode: RecallMode.values.byName(json['recallMode'] as String),
      cueLevel: CueLevel.values.byName(json['cueLevel'] as String),
      correctness: json['correctness'] as bool,
      responseTimeMs: json['responseTimeMs'] as int,
      confidence: json['confidence'] as int,
      contextId: json['contextId'] as String?,
      algorithmVersion: json['algorithmVersion'] as String? ?? 'v1.0.0',
      occurredAt: DateTime.parse(json['occurredAt'] as String),
    );
  }
}
