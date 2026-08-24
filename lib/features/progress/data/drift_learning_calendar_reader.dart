import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/evidence_context.dart';
import '../../motivation/domain/timezone_policy.dart';
import '../domain/learning_calendar.dart';

/// Local-only projection of canonical evidence for one learner-local week.
///
/// This reader has no mutation methods. f24's persisted active durations are
/// summed as effort; answer evidence supplies all other axes.
final class DriftLearningCalendarReader {
  const DriftLearningCalendarReader(this.database);

  final AppDatabase database;

  Future<LearningCalendarSnapshot> loadWeek({
    required String ownerId,
    required DateTime referenceUtc,
    required String timezoneId,
  }) async {
    if (!referenceUtc.isUtc) {
      throw ArgumentError.value(referenceUtc, 'referenceUtc', 'must be UTC');
    }
    if (ownerId.isEmpty || ownerId != ownerId.trim()) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must be canonical text');
    }

    final weekStart = _weekStart(
      TimezonePolicy.getLearningDay(referenceUtc, timezoneId),
    );
    final weekEndExclusive = _addDays(weekStart, 7);
    final days = <DateTime, _DayAccumulator>{
      for (var offset = 0; offset < 7; offset++)
        _addDays(weekStart, offset): _DayAccumulator(),
    };

    final segments =
        await (database.select(database.learningTimeSegments)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.startedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    for (final segment in segments) {
      for (final allocation in _allocateActiveDuration(
        startedAtUtcMs: segment.startedAtUtcMs,
        activeDurationMs: segment.activeDurationMs,
        timezoneId: timezoneId,
      )) {
        final bucket = days[allocation.day];
        if (bucket == null ||
            !_isInWeek(allocation.day, weekStart, weekEndExclusive)) {
          continue;
        }
        bucket.activeDurationMs += allocation.durationMs;
      }
    }

    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    for (final attempt in attempts) {
      final day = TimezonePolicy.getLearningDay(
        DateTime.fromMillisecondsSinceEpoch(
          attempt.occurredAtUtcMs,
          isUtc: true,
        ),
        timezoneId,
      );
      final bucket = days[day];
      if (bucket == null || !_isInWeek(day, weekStart, weekEndExclusive)) {
        continue;
      }
      final context = _canonicalEvidence(attempt);
      // Assessment outcomes are intentionally separate from learning accuracy,
      // skill distribution, and their trend. Their captured active time above
      // remains legitimate effort.
      if (context.evidenceClass == EvidenceClass.assessment ||
          context.evidenceClass == EvidenceClass.recreational) {
        continue;
      }
      bucket.recordPracticeAttempt(
        skillId: context.skillId,
        isCorrect: attempt.isCorrect,
      );
    }

    final dailyBuckets = List<LearningCalendarDay>.unmodifiable(
      days.entries
          .map((entry) => entry.value.toDay(day: entry.key))
          .toList(growable: false),
    );
    final weeklyAccumulator = _DayAccumulator();
    for (final bucket in days.values) {
      weeklyAccumulator.merge(bucket);
    }
    return LearningCalendarSnapshot(
      timezoneId: timezoneId,
      weekStart: weekStart,
      days: dailyBuckets,
      weekly: WeeklyLearningAnalytics(
        effort: LearningEffortAxis(
          activeDuration: Duration(
            milliseconds: weeklyAccumulator.activeDurationMs,
          ),
        ),
        accuracy: weeklyAccumulator.accuracy,
        skillDistribution: weeklyAccumulator.skillDistribution,
        accuracyTrend: dailyBuckets
            .map(
              (bucket) => LearningAccuracyTrendPoint(
                day: bucket.day,
                accuracy: bucket.accuracy,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  EvidenceContext _canonicalEvidence(AnswerAttempt attempt) {
    final decoded = jsonDecode(attempt.evidenceContextJson);
    if (decoded is! Map) {
      throw const FormatException('attempt evidence context must be an object');
    }
    final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
    if (attempt.evidenceClass != context.evidenceClass.name ||
        attempt.evidenceContextJson != jsonEncode(context.toJson())) {
      throw const FormatException('attempt evidence metadata mismatch');
    }
    return context;
  }
}

final class _DayAccumulator {
  var activeDurationMs = 0;
  var sampleSize = 0;
  var correctCount = 0;
  final Map<String, _SkillAccumulator> skills = <String, _SkillAccumulator>{};

  LearningAccuracyAxis get accuracy =>
      LearningAccuracyAxis(sampleSize: sampleSize, correctCount: correctCount);

  List<LearningSkillDistribution> get skillDistribution {
    final entries = skills.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return List<LearningSkillDistribution>.unmodifiable(
      entries
          .map(
            (entry) => LearningSkillDistribution(
              skillId: entry.key,
              sampleSize: entry.value.sampleSize,
              correctCount: entry.value.correctCount,
            ),
          )
          .toList(growable: false),
    );
  }

  void recordPracticeAttempt({
    required String skillId,
    required bool isCorrect,
  }) {
    sampleSize += 1;
    if (isCorrect) correctCount += 1;
    final skill = skills.putIfAbsent(skillId, _SkillAccumulator.new);
    skill.sampleSize += 1;
    if (isCorrect) skill.correctCount += 1;
  }

  void merge(_DayAccumulator other) {
    activeDurationMs += other.activeDurationMs;
    sampleSize += other.sampleSize;
    correctCount += other.correctCount;
    for (final entry in other.skills.entries) {
      final skill = skills.putIfAbsent(entry.key, _SkillAccumulator.new);
      skill.sampleSize += entry.value.sampleSize;
      skill.correctCount += entry.value.correctCount;
    }
  }

  LearningCalendarDay toDay({required DateTime day}) => LearningCalendarDay(
    day: day,
    effort: LearningEffortAxis(
      activeDuration: Duration(milliseconds: activeDurationMs),
    ),
    accuracy: accuracy,
    skillDistribution: skillDistribution,
  );
}

final class _SkillAccumulator {
  var sampleSize = 0;
  var correctCount = 0;
}

DateTime _weekStart(DateTime day) => _addDays(day, 1 - day.weekday);

DateTime _addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

bool _isInWeek(DateTime day, DateTime start, DateTime endExclusive) =>
    !day.isBefore(start) && day.isBefore(endExclusive);

/// Splits f24's canonical active duration at learner-local day boundaries.
///
/// The UTC occurrence timestamp anchors the first active millisecond. From
/// there the exact stored active duration advances in UTC; it is never derived
/// from `endedAtUtcMs`. Each loop consumes a positive integer number of
/// milliseconds, so the final trailing remainder is assigned whole to its
/// final local day and the allocations sum exactly to `activeDurationMs`.
Iterable<_ActiveDurationAllocation> _allocateActiveDuration({
  required int startedAtUtcMs,
  required int activeDurationMs,
  required String timezoneId,
}) sync* {
  var cursorUtc = DateTime.fromMillisecondsSinceEpoch(
    startedAtUtcMs,
    isUtc: true,
  );
  var remainingMs = activeDurationMs;
  while (remainingMs > 0) {
    final day = TimezonePolicy.getLearningDay(cursorUtc, timezoneId);
    final nextBoundaryUtc = TimezonePolicy.getNextDayBoundary(
      cursorUtc,
      timezoneId,
    );
    final millisecondsUntilBoundary = nextBoundaryUtc
        .difference(cursorUtc)
        .inMilliseconds;
    if (millisecondsUntilBoundary <= 0) {
      throw StateError('timezone day boundary must follow the active cursor');
    }
    final durationMs = remainingMs < millisecondsUntilBoundary
        ? remainingMs
        : millisecondsUntilBoundary;
    yield _ActiveDurationAllocation(day: day, durationMs: durationMs);
    remainingMs -= durationMs;
    cursorUtc = cursorUtc.add(Duration(milliseconds: durationMs));
  }
}

final class _ActiveDurationAllocation {
  const _ActiveDurationAllocation({
    required this.day,
    required this.durationMs,
  });

  final DateTime day;
  final int durationMs;
}
