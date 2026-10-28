import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import '../../motivation/domain/timezone_policy.dart';

/// Organization only. One item is a one-minute planning estimate, never a
/// promise of completion or permission to mutate canonical learning evidence.
final class StudyPlanRevision {
  StudyPlanRevision._(this._payload);
  final Map<String, Object?> _payload;

  factory StudyPlanRevision.propose({
    required String operationId,
    required int expectedPriorRevision,
    required DateTime createdAtUtc,
    required String timezoneId,
    required int availableMinutes,
    required String authorityHash,
    required String? goalId,
    required DateTime? deadlineAtUtc,
    required List<String> dueItemIds,
    required List<String> newItemIds,
    DateTime? priorCreatedAtUtc,
  }) {
    if (operationId.trim().isEmpty ||
        operationId.trim() != operationId ||
        authorityHash.isEmpty ||
        (goalId != null && (goalId.isEmpty || goalId.trim() != goalId)) ||
        expectedPriorRevision < 0 ||
        availableMinutes < 0 ||
        availableMinutes > 1440 ||
        !createdAtUtc.isUtc ||
        createdAtUtc.millisecondsSinceEpoch < 0 ||
        (deadlineAtUtc != null &&
            (!deadlineAtUtc.isUtc ||
                deadlineAtUtc.millisecondsSinceEpoch < 0)) ||
        (priorCreatedAtUtc != null &&
            (!priorCreatedAtUtc.isUtc ||
                priorCreatedAtUtc.isAfter(createdAtUtc)))) {
      throw ArgumentError('Invalid study plan inputs');
    }
    final all = [...dueItemIds, ...newItemIds];
    if (all.any((id) => id.isEmpty || id.trim() != id) ||
        all.toSet().length != all.length) {
      throw ArgumentError('Plan items must be unique canonical identities');
    }
    DateTime ordinal(DateTime instant) {
      final d = TimezonePolicy.getLearningDay(instant, timezoneId);
      return DateTime.utc(d.year, d.month, d.day);
    }

    final day = ordinal(createdAtUtc);
    final due = dueItemIds.take(availableMinutes).toList();
    final fresh = newItemIds.take(availableMinutes - due.length).toList();
    return StudyPlanRevision._(
      Map.unmodifiable({
        'schemaVersion': 1,
        'policy': 'due-first-minute-estimate-v1',
        'operationId': operationId,
        'expectedPriorRevision': expectedPriorRevision,
        'revision': expectedPriorRevision + 1,
        'createdAtUtcMs': createdAtUtc.millisecondsSinceEpoch,
        'timezoneId': timezoneId,
        'learningDay': day.toIso8601String().substring(0, 10),
        'availableMinutes': availableMinutes,
        'authorityHash': authorityHash,
        'goalId': goalId,
        'deadlineAtUtcMs': deadlineAtUtc?.millisecondsSinceEpoch,
        'deadlinePassed':
            deadlineAtUtc != null && ordinal(deadlineAtUtc).isBefore(day),
        'missedDays': priorCreatedAtUtc == null
            ? 0
            : math.max(
                0,
                day.difference(ordinal(priorCreatedAtUtc)).inDays - 1,
              ),
        'dueItems': List<String>.unmodifiable(due),
        'newItems': List<String>.unmodifiable(fresh),
        'carryOver': List<String>.unmodifiable(dueItemIds.skip(due.length)),
        'rationale':
            'Due work first; one minute per item is an estimate. '
            'Unallocated due work stays in the canonical review queue.',
      }),
    );
  }

  factory StudyPlanRevision.fromJson(Map<String, Object?> json) {
    try {
      final payload = Map<String, Object?>.from(json)..remove('payloadHash');
      if (payload['schemaVersion'] != 1 ||
          payload['policy'] != 'due-first-minute-estimate-v1' ||
          json['payloadHash'] != studyPlanHash(payload)) {
        throw const FormatException('Study plan integrity mismatch');
      }
      for (final key in ['dueItems', 'newItems', 'carryOver']) {
        payload[key] = List<String>.unmodifiable(
          (payload[key] as List).cast<String>(),
        );
      }
      final p = StudyPlanRevision._(Map.unmodifiable(payload));
      const fields = {
        'schemaVersion',
        'policy',
        'operationId',
        'expectedPriorRevision',
        'revision',
        'createdAtUtcMs',
        'timezoneId',
        'learningDay',
        'availableMinutes',
        'authorityHash',
        'goalId',
        'deadlineAtUtcMs',
        'deadlinePassed',
        'missedDays',
        'dueItems',
        'newItems',
        'carryOver',
        'rationale',
      };
      bool text(Object? value) =>
          value is String && value.isNotEmpty && value.trim() == value;
      final day = TimezonePolicy.getLearningDay(p.createdAtUtc, p.timezoneId);
      final dayKey = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).toIso8601String().substring(0, 10);
      final deadline = p.deadlineAtUtc;
      final deadlineDay = deadline == null
          ? null
          : TimezonePolicy.getLearningDay(deadline, p.timezoneId);
      final expectedPassed =
          deadlineDay != null &&
          DateTime.utc(
            deadlineDay.year,
            deadlineDay.month,
            deadlineDay.day,
          ).isBefore(DateTime.utc(day.year, day.month, day.day));
      if (payload.length != fields.length ||
          !payload.keys.toSet().containsAll(fields) ||
          !text(p.operationId) ||
          !text(p.authorityHash) ||
          (p.goalId != null && !text(p.goalId)) ||
          p.missedDays < 0 ||
          p.createdAtUtc.millisecondsSinceEpoch < 0 ||
          p.learningDay != dayKey ||
          payload['deadlinePassed'] is! bool ||
          payload['rationale'] is! String ||
          p.deadlinePassed != expectedPassed ||
          (deadline != null && deadline.millisecondsSinceEpoch < 0) ||
          [
            ...p.dueItems,
            ...p.newItems,
            ...p.carryOver,
          ].any((id) => !text(id)) ||
          (p.carryOver.isNotEmpty && p.dueItems.length != p.availableMinutes)) {
        throw const FormatException('Invalid study plan metadata');
      }
      if (p.availableMinutes < 0 ||
          p.availableMinutes > 1440 ||
          p.revision != p.expectedPriorRevision + 1 ||
          p.expectedPriorRevision < 0 ||
          p.dueItems.length + p.newItems.length > p.availableMinutes ||
          (p.carryOver.isNotEmpty && p.newItems.isNotEmpty) ||
          {...p.dueItems, ...p.newItems, ...p.carryOver}.length !=
              p.dueItems.length + p.newItems.length + p.carryOver.length) {
        throw const FormatException('Invalid study plan allocation');
      }
      return p;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Invalid study plan payload');
    }
  }
  String get operationId => _payload['operationId'] as String;
  int get revision => _payload['revision'] as int;
  int get expectedPriorRevision => _payload['expectedPriorRevision'] as int;
  int get availableMinutes => _payload['availableMinutes'] as int;
  DateTime get createdAtUtc => DateTime.fromMillisecondsSinceEpoch(
    _payload['createdAtUtcMs'] as int,
    isUtc: true,
  );
  String get timezoneId => _payload['timezoneId'] as String;
  String get learningDay => _payload['learningDay'] as String;
  String get authorityHash => _payload['authorityHash'] as String;
  String? get goalId => _payload['goalId'] as String?;
  DateTime? get deadlineAtUtc => _payload['deadlineAtUtcMs'] == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          _payload['deadlineAtUtcMs'] as int,
          isUtc: true,
        );
  bool get deadlinePassed => _payload['deadlinePassed'] as bool;
  int get missedDays => _payload['missedDays'] as int;
  List<String> get dueItems => _payload['dueItems'] as List<String>;
  List<String> get newItems => _payload['newItems'] as List<String>;
  List<String> get carryOver => _payload['carryOver'] as List<String>;
  String get payloadHash => studyPlanHash(_payload);
  Map<String, Object?> toJson() => {..._payload, 'payloadHash': payloadHash};
}

String studyPlanHash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
