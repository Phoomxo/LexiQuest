enum LearningActivity {
  multipleChoiceQuiz('multiple_choice_quiz');

  const LearningActivity(this.wireName);

  final String wireName;

  static LearningActivity fromWireName(String wireName) {
    return values.firstWhere(
      (value) => value.wireName == wireName,
      orElse: () => throw ArgumentError.value(
        wireName,
        'wireName',
        'Unknown LearningActivity wire name',
      ),
    );
  }
}

enum LearningSkill {
  meaningRecall('meaning_recall');

  const LearningSkill(this.wireName);

  final String wireName;

  static LearningSkill fromWireName(String wireName) {
    return values.firstWhere(
      (value) => value.wireName == wireName,
      orElse: () => throw ArgumentError.value(
        wireName,
        'wireName',
        'Unknown LearningSkill wire name',
      ),
    );
  }
}

final class LearningEvent {
  LearningEvent({
    required this.eventId,
    required this.schemaVersion,
    required this.pseudonymousUserId,
    required DateTime occurredAtUtc,
    required this.activity,
    required this.contentId,
    required this.categoryId,
    required this.cefrLevel,
    required this.skill,
    required this.correct,
    required this.score,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.appVersion,
    required this.buildId,
  }) : occurredAtUtc = occurredAtUtc.toUtc() {
    if (schemaVersion != 1) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion', 'must be 1');
    }
    if (score < 0 || score > 100) {
      throw ArgumentError.value(score, 'score', 'must be between 0 and 100');
    }
    if (attemptNumber < 1) {
      throw ArgumentError.value(attemptNumber, 'attemptNumber', 'must be >= 1');
    }
    final measuredResponseTimeMs = responseTimeMs;
    if (measuredResponseTimeMs != null && measuredResponseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be >= 0',
      );
    }
    _requireRequiredString(eventId, 'eventId');
    _requireRequiredString(pseudonymousUserId, 'pseudonymousUserId');
    _requireRequiredString(contentId, 'contentId');
    _requireRequiredString(appVersion, 'appVersion');
    _requireRequiredString(buildId, 'buildId');
  }

  final String eventId;
  final int schemaVersion;
  final String pseudonymousUserId;
  final DateTime occurredAtUtc;
  final LearningActivity activity;
  final String contentId;
  final String? categoryId;
  final String? cefrLevel;
  final LearningSkill skill;
  final bool correct;
  final int score;
  final int? responseTimeMs;
  final int attemptNumber;
  final String appVersion;
  final String buildId;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'eventId': eventId,
      'schemaVersion': schemaVersion,
      'pseudonymousUserId': pseudonymousUserId,
      'occurredAtUtc': occurredAtUtc.toIso8601String(),
      'activity': activity.wireName,
      'contentId': contentId,
      'categoryId': categoryId,
      'cefrLevel': cefrLevel,
      'skill': skill.wireName,
      'correct': correct,
      'score': score,
      'responseTimeMs': responseTimeMs,
      'attemptNumber': attemptNumber,
      'appVersion': appVersion,
      'buildId': buildId,
    };
  }

  factory LearningEvent.fromMap(Map<String, dynamic> map) {
    return LearningEvent(
      eventId: map['eventId'] as String,
      schemaVersion: map['schemaVersion'] as int,
      pseudonymousUserId: map['pseudonymousUserId'] as String,
      occurredAtUtc: DateTime.parse(map['occurredAtUtc'] as String),
      activity: LearningActivity.fromWireName(map['activity'] as String),
      contentId: map['contentId'] as String,
      categoryId: map['categoryId'] as String?,
      cefrLevel: map['cefrLevel'] as String?,
      skill: LearningSkill.fromWireName(map['skill'] as String),
      correct: map['correct'] as bool,
      score: map['score'] as int,
      responseTimeMs: map['responseTimeMs'] as int?,
      attemptNumber: map['attemptNumber'] as int,
      appVersion: map['appVersion'] as String,
      buildId: map['buildId'] as String,
    );
  }

  @override
  String toString() => 'LearningEvent';
}

void _requireRequiredString(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must be non-empty after trimming');
  }
  if (value.length > 200) {
    throw ArgumentError.value(value, name, 'must be at most 200 characters');
  }
}
