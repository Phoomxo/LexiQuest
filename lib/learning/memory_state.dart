class MemoryState {
  final String ownerId;
  final String wordKey;
  final double strength;
  final double cueDependency;
  final double stability;
  final double difficulty;
  final int lapseCount;
  final DateTime? lastReviewedAt;
  final DateTime nextDueAt;
  final String? lastErrorType;
  final String algorithmVersion;

  MemoryState({
    required this.ownerId,
    required this.wordKey,
    this.strength = 1.0,
    this.cueDependency = 0.0,
    this.stability = 1.0,
    this.difficulty = 5.0,
    this.lapseCount = 0,
    this.lastReviewedAt,
    required this.nextDueAt,
    this.lastErrorType,
    this.algorithmVersion = 'v1.0.0',
  });

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'wordKey': wordKey,
      'strength': strength,
      'cueDependency': cueDependency,
      'stability': stability,
      'difficulty': difficulty,
      'lapseCount': lapseCount,
      'lastReviewedAt': lastReviewedAt?.toUtc().toIso8601String(),
      'nextDueAt': nextDueAt.toUtc().toIso8601String(),
      'lastErrorType': lastErrorType,
      'algorithmVersion': algorithmVersion,
    };
  }

  factory MemoryState.fromJson(Map<String, dynamic> json) {
    return MemoryState(
      ownerId: json['ownerId'] as String,
      wordKey: json['wordKey'] as String,
      strength: (json['strength'] as num).toDouble(),
      cueDependency: (json['cueDependency'] as num).toDouble(),
      stability: (json['stability'] as num).toDouble(),
      difficulty: (json['difficulty'] as num).toDouble(),
      lapseCount: json['lapseCount'] as int,
      lastReviewedAt: json['lastReviewedAt'] != null
          ? DateTime.parse(json['lastReviewedAt'] as String)
          : null,
      nextDueAt: DateTime.parse(json['nextDueAt'] as String),
      lastErrorType: json['lastErrorType'] as String?,
      algorithmVersion: json['algorithmVersion'] as String? ?? 'v1.0.0',
    );
  }
}
