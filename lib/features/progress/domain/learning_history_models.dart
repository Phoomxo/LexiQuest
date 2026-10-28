final class LearningHistoryOwnerChanged extends StateError {
  LearningHistoryOwnerChanged() : super('history owner changed');
}

final class LearningHistoryCursor {
  const LearningHistoryCursor({
    required this.ownerId,
    required this.startedAtUtc,
    required this.sessionId,
  });

  final String ownerId;
  final DateTime startedAtUtc;
  final String sessionId;
}

final class LearningHistoryEntry {
  const LearningHistoryEntry({
    required this.sessionId,
    required this.activityType,
    required this.state,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.answerCount,
    required this.correctCount,
  });

  final String sessionId;
  final String activityType;
  final String state;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final int answerCount;
  final int correctCount;
}

final class LearningHistoryDay {
  const LearningHistoryDay({required this.day, required this.answerCount});

  final DateTime day;
  final int answerCount;
}

final class LearningHistorySnapshot {
  LearningHistorySnapshot({
    required this.ownerId,
    required List<LearningHistoryEntry> entries,
    required List<LearningHistoryDay> days,
    this.nextCursor,
  }) : entries = List.unmodifiable(entries),
       days = List.unmodifiable(days);

  final String ownerId;
  final List<LearningHistoryEntry> entries;
  final List<LearningHistoryDay> days;
  final LearningHistoryCursor? nextCursor;

  bool get hasMore => nextCursor != null;
}
