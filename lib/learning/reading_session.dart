class ReadingSession {
  final String sessionId;
  final String ownerId;
  final String cefrLevel;
  final List<String> targetWordKeys;
  final String mixPolicyVersion;
  final String contentId;
  final String contentVersion;
  final List<int> completedStages;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int schemaVersion;

  ReadingSession({
    required this.sessionId,
    required this.ownerId,
    required this.cefrLevel,
    required this.targetWordKeys,
    this.mixPolicyVersion = 'v1.0.0',
    required this.contentId,
    this.contentVersion = 'v1.0.0',
    this.completedStages = const [],
    required this.startedAt,
    this.completedAt,
    this.schemaVersion = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'ownerId': ownerId,
      'cefrLevel': cefrLevel,
      'targetWordKeys': targetWordKeys,
      'mixPolicyVersion': mixPolicyVersion,
      'contentId': contentId,
      'contentVersion': contentVersion,
      'completedStages': completedStages,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'completedAt': completedAt?.toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
    };
  }

  factory ReadingSession.fromJson(Map<String, dynamic> json) {
    return ReadingSession(
      sessionId: json['sessionId'] as String,
      ownerId: json['ownerId'] as String,
      cefrLevel: json['cefrLevel'] as String,
      targetWordKeys: List<String>.from(json['targetWordKeys'] as List),
      mixPolicyVersion: json['mixPolicyVersion'] as String? ?? 'v1.0.0',
      contentId: json['contentId'] as String,
      contentVersion: json['contentVersion'] as String? ?? 'v1.0.0',
      completedStages: List<int>.from(json['completedStages'] as List? ?? []),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
    );
  }
}
