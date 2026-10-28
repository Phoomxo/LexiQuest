import '../../time_tracking/domain/learning_time_segment.dart';

enum LearningGoalKind { languageTest, course, personal }

abstract final class LearningGoalKindCodec {
  static LearningGoalKind parse(String value) => switch (value) {
    'languageTest' => LearningGoalKind.languageTest,
    'course' => LearningGoalKind.course,
    'personal' => LearningGoalKind.personal,
    _ => throw ArgumentError.value(value, 'kind', 'unsupported goal kind'),
  };
}

enum LearningGoalStatus { active, completed, cancelled }

abstract final class LearningGoalStatusCodec {
  static LearningGoalStatus parse(String value) => switch (value) {
    'active' => LearningGoalStatus.active,
    'completed' => LearningGoalStatus.completed,
    'cancelled' => LearningGoalStatus.cancelled,
    _ => throw ArgumentError.value(value, 'status', 'unsupported goal status'),
  };
}

final class LearningGoalTimezoneContext {
  const LearningGoalTimezoneContext({
    required this.timezoneId,
    required this.utcOffsetMinutes,
  });

  final String timezoneId;
  final int utcOffsetMinutes;
}

final class LearningGoal {
  factory LearningGoal({
    required String id,
    required LearningGoalKind kind,
    required String title,
    required DateTime deadlineAtUtc,
    required LearningGoalTimezoneContext timezone,
    required LearningGoalStatus status,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
  }) {
    final canonicalId = _canonicalText(id, 'id', maximumLength: 256);
    final canonicalTitle = _canonicalText(title, 'title', maximumLength: 120);
    final deadline = _utc(deadlineAtUtc, 'deadlineAtUtc');
    final created = _utc(createdAtUtc, 'createdAtUtc');
    final updated = _utc(updatedAtUtc, 'updatedAtUtc');
    if (updated.isBefore(created)) {
      throw ArgumentError.value(
        updatedAtUtc,
        'updatedAtUtc',
        'must not precede createdAtUtc',
      );
    }
    LearningTimeSegment.requireCanonicalTimezoneContext(
      timezoneId: timezone.timezoneId,
      utcOffsetMinutes: timezone.utcOffsetMinutes,
      occurredAtUtcMs: deadline.millisecondsSinceEpoch,
    );
    return LearningGoal._(
      id: canonicalId,
      kind: kind,
      title: canonicalTitle,
      deadlineAtUtc: deadline,
      timezone: LearningGoalTimezoneContext(
        timezoneId: timezone.timezoneId,
        utcOffsetMinutes: timezone.utcOffsetMinutes,
      ),
      status: status,
      createdAtUtc: created,
      updatedAtUtc: updated,
    );
  }

  const LearningGoal._({
    required this.id,
    required this.kind,
    required this.title,
    required this.deadlineAtUtc,
    required this.timezone,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final LearningGoalKind kind;
  final String title;
  final DateTime deadlineAtUtc;
  final LearningGoalTimezoneContext timezone;
  final LearningGoalStatus status;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  LearningGoal copyWith({
    LearningGoalKind? kind,
    String? title,
    DateTime? deadlineAtUtc,
    LearningGoalTimezoneContext? timezone,
    LearningGoalStatus? status,
    DateTime? updatedAtUtc,
  }) => LearningGoal(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    deadlineAtUtc: deadlineAtUtc ?? this.deadlineAtUtc,
    timezone: timezone ?? this.timezone,
    status: status ?? this.status,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
}

String _canonicalText(
  String value,
  String field, {
  required int maximumLength,
}) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > maximumLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
    throw ArgumentError.value(value, field, 'must be canonical text');
  }
  return value;
}

DateTime _utc(DateTime value, String field) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, field, 'must be nonnegative UTC');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  );
}
