class SrsItem {
  final String word;
  final int boxLevel;
  final int intervalDays;
  final DateTime lastReviewedAt;
  final DateTime nextReviewAt;
  final double easeFactor;

  const SrsItem({
    required this.word,
    required this.boxLevel,
    required this.intervalDays,
    required this.lastReviewedAt,
    required this.nextReviewAt,
    this.easeFactor = 2.5,
  });

  /// Creates a new SRS item at Box 1 due immediately.
  factory SrsItem.initial(String word, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return SrsItem(
      word: word,
      boxLevel: 1,
      intervalDays: 1,
      lastReviewedAt: current,
      nextReviewAt: current,
      easeFactor: 2.5,
    );
  }

  /// Evaluates review outcome using standard Leitner/HLR interval calculation.
  /// Correct answers increase box level (1 -> 2 -> 3 -> 4 -> 5) and scale interval.
  /// Incorrect answers reset box level to 1 and interval to 1 day.
  SrsItem processReview({required bool isCorrect, DateTime? now}) {
    final current = now ?? DateTime.now();
    if (!isCorrect) {
      return SrsItem(
        word: word,
        boxLevel: 1,
        intervalDays: 1,
        lastReviewedAt: current,
        nextReviewAt: current.add(const Duration(days: 1)),
        easeFactor: (easeFactor - 0.2).clamp(1.3, 2.5),
      );
    }

    final newBox = (boxLevel + 1).clamp(1, 5);
    int newInterval;
    switch (newBox) {
      case 2:
        newInterval = 2;
        break;
      case 3:
        newInterval = 5;
        break;
      case 4:
        newInterval = 10;
        break;
      case 5:
        newInterval = 30;
        break;
      default:
        newInterval = 1;
    }

    return SrsItem(
      word: word,
      boxLevel: newBox,
      intervalDays: newInterval,
      lastReviewedAt: current,
      nextReviewAt: current.add(Duration(days: newInterval)),
      easeFactor: (easeFactor + 0.1).clamp(1.3, 2.5),
    );
  }

  bool isDue({DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.isAfter(nextReviewAt) ||
        current.isAtSameMomentAs(nextReviewAt);
  }

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'boxLevel': boxLevel,
      'intervalDays': intervalDays,
      'lastReviewedAt': lastReviewedAt.toIso8601String(),
      'nextReviewAt': nextReviewAt.toIso8601String(),
      'easeFactor': easeFactor,
    };
  }

  factory SrsItem.fromJson(Map<String, dynamic> json) {
    return SrsItem(
      word: json['word'] as String,
      boxLevel: json['boxLevel'] as int? ?? 1,
      intervalDays: json['intervalDays'] as int? ?? 1,
      lastReviewedAt: DateTime.parse(json['lastReviewedAt'] as String),
      nextReviewAt: DateTime.parse(json['nextReviewAt'] as String),
      easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
    );
  }
}
