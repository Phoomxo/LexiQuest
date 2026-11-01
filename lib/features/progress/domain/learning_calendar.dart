import '../../learning_time/application/learning_time_use_cases.dart';

final class LearningCalendarPeriod {
  LearningCalendarPeriod({required DateTime firstDay, required this.dayCount})
    : firstDay = DateTime(firstDay.year, firstDay.month, firstDay.day) {
    if (firstDay.year < 1970 ||
        firstDay.year > 9998 ||
        dayCount < 1 ||
        dayCount > 31) {
      throw ArgumentError(
        'Calendar requires 1 to 31 civil dates in a supported year',
      );
    }
  }

  factory LearningCalendarPeriod.month(int year, int month) {
    if (year < 1970 || year > 9998 || month < 1 || month > 12) {
      throw ArgumentError('Invalid calendar month');
    }
    return LearningCalendarPeriod(
      firstDay: DateTime(year, month),
      dayCount: DateTime(year, month + 1, 0).day,
    );
  }

  factory LearningCalendarPeriod.weekEnding(DateTime day) =>
      LearningCalendarPeriod(
        firstDay: DateTime(day.year, day.month, day.day - 6),
        dayCount: 7,
      );

  final DateTime firstDay;
  final int dayCount;
  DateTime dayAt(int index) =>
      DateTime(firstDay.year, firstDay.month, firstDay.day + index);
  DateTime get endExclusive => dayAt(dayCount);
}

final class LearningCalendarDay {
  const LearningCalendarDay({
    required this.date,
    required this.answerCount,
    required this.correctCount,
    required this.completedSessionCount,
    this.recordedTime = const RecordedTimeRead.unavailable(),
  });

  final DateTime date;
  final int answerCount;
  final int correctCount;
  final int completedSessionCount;
  final RecordedTimeRead recordedTime;

  LearningCalendarDay withTime(RecordedTimeRead time) => LearningCalendarDay(
    date: date,
    answerCount: answerCount,
    correctCount: correctCount,
    completedSessionCount: completedSessionCount,
    recordedTime: time,
  );
}

final class LearningCalendarSnapshot {
  LearningCalendarSnapshot({
    required this.ownerId,
    required this.period,
    required List<LearningCalendarDay> days,
  }) : days = List.unmodifiable(days);
  final String ownerId;
  final LearningCalendarPeriod period;
  final List<LearningCalendarDay> days;
  int get answerCount => days.fold(0, (sum, day) => sum + day.answerCount);
  int get correctCount => days.fold(0, (sum, day) => sum + day.correctCount);
  int get completedSessionCount =>
      days.fold(0, (sum, day) => sum + day.completedSessionCount);
  RecordedTimeRead get recordedTime {
    if (days.any(
      (day) =>
          day.recordedTime.status == RecordedTimeStatus.unavailable ||
          day.recordedTime.status == RecordedTimeStatus.unsupported,
    )) {
      return const RecordedTimeRead.unavailable();
    }
    final duration = days.fold<int>(
      0,
      (sum, day) => sum + day.recordedTime.activeDurationUs!,
    );
    final segments = days.fold<int>(
      0,
      (sum, day) => sum + day.recordedTime.segmentCount!,
    );
    if (duration > 9007199254740991 || segments > 9007199254740991) {
      return const RecordedTimeRead.unavailable();
    }
    return segments == 0
        ? const RecordedTimeRead.noneRecorded()
        : RecordedTimeRead.recorded(
            activeDurationUs: duration,
            segmentCount: segments,
          );
  }
}
