import '../../learning_profile/domain/learning_profile.dart';
import 'streak_policy.dart';

enum MotivationFailureCode {
  ownerChanged,
  unavailable,
  invalid,
  conflict,
  noFreeze,
}

final class MotivationException implements Exception {
  const MotivationException(this.code);
  final MotivationFailureCode code;
  @override
  String toString() => 'MotivationException(${code.name})';
}

final class LearningDayFact {
  const LearningDayFact({
    required this.learningDay,
    required this.timezoneId,
    required this.sourceAttemptId,
    required this.occurredAtUtc,
    required this.pinned,
  });
  final String learningDay;
  final String timezoneId;
  final String sourceAttemptId;
  final DateTime occurredAtUtc;
  final bool pinned;
}

final class MotivationSnapshot {
  MotivationSnapshot({
    required this.ownerId,
    required this.state,
    required this.timezoneId,
    required this.usedUtcFallback,
    required List<LearningDayFact> learningDays,
    required Set<String> protectedDays,
    required this.questXp,
  }) : learningDays = List.unmodifiable(learningDays),
       protectedDays = Set.unmodifiable(protectedDays);
  final String ownerId;
  final StreakState state;
  final String timezoneId;
  final bool usedUtcFallback;
  final List<LearningDayFact> learningDays;
  final Set<String> protectedDays;
  final int questXp;
}

final class FreezeProtectionIntent {
  const FreezeProtectionIntent({
    required this.id,
    required this.ownerId,
    required this.protectedDay,
    required this.timezoneId,
    required this.sourceAttemptId,
    required this.occurredAtUtc,
    required this.stillCurrent,
  });
  final String id;
  final String ownerId;
  final String protectedDay;
  final String timezoneId;
  final String sourceAttemptId;
  final DateTime occurredAtUtc;
  final bool Function() stillCurrent;
}

DateTime motivationCivilDay(String label) {
  final date = LearningCivilDate.parse(label);
  return DateTime.utc(date.year, date.month, date.day);
}

String motivationDayLabel(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

StreakState projectCanonicalStreak({
  required String ownerId,
  required Iterable<LearningDayFact> learningDays,
  required Set<String> protectedDays,
  required String today,
  required int freezeCount,
}) {
  final facts = learningDays.toList();
  final learned = facts.map((fact) => fact.learningDay).toSet();
  final labels = {...learned, ...protectedDays}.toList()..sort();
  var run = 0;
  var longest = 0;
  DateTime? previous;
  for (final label in labels) {
    final day = motivationCivilDay(label);
    if (previous == null || day.difference(previous).inDays != 1) run = 0;
    if (learned.contains(label)) run++;
    if (run > longest) longest = run;
    previous = day;
  }
  final latest = facts.isEmpty
      ? null
      : facts
            .map((fact) => fact.occurredAtUtc.millisecondsSinceEpoch)
            .reduce((a, b) => a > b ? a : b);
  return StreakState(
    ownerId: ownerId,
    currentStreakDays:
        previous != null &&
            motivationCivilDay(today).difference(previous).inDays <= 1
        ? run
        : 0,
    longestStreakDays: longest,
    freezeCount: freezeCount,
    lastLearnedAtUtcMs: latest,
    updatedAtUtcMs: latest ?? 0,
  );
}
