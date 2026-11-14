import 'quest_models.dart';

enum QuestProgressState {
  active,
  completedUnclaimed,
  claimed,
  expired,
  unavailable,
  conflict,
  legacy,
}

final class QuestProgressCard {
  QuestProgressCard({
    required this.instanceId,
    required this.cadence,
    required this.civilLabel,
    required this.title,
    required this.targetCount,
    required this.xpAmount,
    required this.correctCount,
    required this.completedAtUtc,
    required this.lastEndUtc,
    required this.state,
    List<String> receiptIds = const [],
  }) : receiptIds = List.unmodifiable(receiptIds);

  final String instanceId;
  final QuestType? cadence;
  final String? civilLabel;
  final String title;
  final int? targetCount;
  final int? xpAmount;
  final int? correctCount;
  final DateTime? completedAtUtc;
  final DateTime? lastEndUtc;
  final QuestProgressState state;
  final List<String> receiptIds;
}

enum QuestProgressIssue {
  unavailableCatalog,
  unavailableCalendar,
  pendingCalendar,
  unavailableEvidence,
}

final class QuestSummary {
  QuestSummary({
    required List<QuestProgressCard> current,
    required List<QuestProgressCard> history,
    required List<QuestProgressIssue> issues,
  }) : current = List.unmodifiable(current),
       history = List.unmodifiable(history),
       issues = List.unmodifiable(issues);

  final List<QuestProgressCard> current;
  final List<QuestProgressCard> history;
  final List<QuestProgressIssue> issues;
}
