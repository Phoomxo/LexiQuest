import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../motivation/domain/timezone_policy.dart';

final class OriginalAnswerMetadata {
  OriginalAnswerMetadata({required this.calendar, this.quest}) {
    final c = calendar;
    final q = quest;
    if (q == null) return;
    if (c.originOwnerId != q.originOwnerId ||
        c.occurredAtUtcMs != q.occurredAtUtcMs) {
      throw const FormatException('Answer metadata owner or time mismatch');
    }
    if (q is PinnedQuestIntent) {
      final rule = switch (c) {
        CapturedCalendarEvidence() => c.rule,
        UnavailableCalendarEvidence() => c.rule,
      };
      if (rule == null || _ruleIdentity(rule) != _ruleIdentity(q.rule)) {
        throw const FormatException('Quest and calendar rules differ');
      }
      if (q is CapturedQuestIntent &&
          (c is! CapturedCalendarEvidence ||
              c.civilDay != q.civilDay ||
              c.weekMonday != q.weekMonday)) {
        throw const FormatException('Quest calendar period mismatch');
      }
      if (q is PendingQuestIntent && c is! UnavailableCalendarEvidence) {
        throw const FormatException(
          'Pending intent requires unavailable calendar',
        );
      }
    }
  }

  final AnswerCalendarEvidence calendar;
  final QuestAnswerIntent? quest;
}

sealed class AnswerCalendarEvidence {
  const AnswerCalendarEvidence({
    required this.originOwnerId,
    required this.occurredAtUtcMs,
  });

  final String originOwnerId;
  final int occurredAtUtcMs;
}

final class CapturedCalendarEvidence extends AnswerCalendarEvidence {
  CapturedCalendarEvidence({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
    required this.rule,
    required this.civilDay,
    required this.weekMonday,
    required this.offsetSeconds,
    required List<(int, int)> daySegments,
    required List<(int, int)> weekSegments,
  }) : daySegments = List.unmodifiable(daySegments),
       weekSegments = List.unmodifiable(weekSegments);

  final OwnerCalendarRule rule;
  final String civilDay;
  final String weekMonday;
  final int offsetSeconds;
  final List<(int, int)> daySegments;
  final List<(int, int)> weekSegments;
}

final class UnavailableCalendarEvidence extends AnswerCalendarEvidence {
  const UnavailableCalendarEvidence({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
    this.rule,
  });

  final OwnerCalendarRule? rule;
}

final class QuestRevisionPin {
  const QuestRevisionPin({
    required this.questId,
    required this.catalogVersion,
    required this.definitionDigest,
  });

  final String questId;
  final int catalogVersion;
  final String definitionDigest;
}

sealed class QuestAnswerIntent {
  const QuestAnswerIntent({
    required this.originOwnerId,
    required this.occurredAtUtcMs,
  });

  final String originOwnerId;
  final int occurredAtUtcMs;
}

sealed class PinnedQuestIntent extends QuestAnswerIntent {
  const PinnedQuestIntent({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
    required this.rule,
    required this.daily,
    required this.weekly,
  });

  final OwnerCalendarRule rule;
  final QuestRevisionPin daily;
  final QuestRevisionPin weekly;
}

final class CapturedQuestIntent extends PinnedQuestIntent {
  const CapturedQuestIntent({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
    required super.rule,
    required super.daily,
    required super.weekly,
    required this.civilDay,
    required this.weekMonday,
  });

  final String civilDay;
  final String weekMonday;

  String get dailyPeriodId => _periodId('daily', civilDay, daily.questId);
  String get weeklyPeriodId => _periodId('weekly', weekMonday, weekly.questId);

  String _periodId(String cadence, String label, String questId) => sha256
      .convert(
        utf8.encode(
          canonicalJson([originOwnerId, rule.ruleId, cadence, label, questId]),
        ),
      )
      .toString();
}

final class PendingQuestIntent extends PinnedQuestIntent {
  const PendingQuestIntent({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
    required super.rule,
    required super.daily,
    required super.weekly,
  });
}

final class UnavailableQuestIntent extends QuestAnswerIntent {
  const UnavailableQuestIntent({
    required super.originOwnerId,
    required super.occurredAtUtcMs,
  });
}

String canonicalJson(Object? value) {
  Object? ordered(Object? node) {
    if (node == null || node is bool || node is String || node is int) {
      return node;
    }
    if (node is List) return node.map(ordered).toList();
    if (node is Map && node.keys.every((key) => key is String)) {
      final keys = node.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(node[key])};
    }
    throw const FormatException(
      'Canonical JSON requires string keys and integer numbers',
    );
  }

  return jsonEncode(ordered(value));
}

typedef _Json = Map<String, Object?>;

const _baseKeys = [
  'v',
  'policyVersion',
  'kind',
  'originOwnerId',
  'occurredAtUtcMs',
];
const _maxColumnBytes = 64 * 1024;
const _maxUtcUs = 8640000000000000000;

String _bounded(String column) {
  if (column.length > _maxColumnBytes ||
      utf8.encode(column).length > _maxColumnBytes) {
    throw const FormatException('Answer metadata exceeds 64 KiB');
  }
  return column;
}

// The two wire schemas contain at most the root object, a segment array and a pair.
void _checkNesting(String column) {
  var depth = 0, quoted = false, escaped = false;
  for (final c in column.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5c) {
        escaped = true;
      } else if (c == 0x22) {
        quoted = false;
      }
    } else if (c == 0x22) {
      quoted = true;
    } else if (c == 0x5b || c == 0x7b) {
      if (++depth > 3) throw const FormatException('Excess metadata nesting');
    } else if (c == 0x5d || c == 0x7d) {
      depth--;
    }
  }
}

_Json _column(String column) {
  _bounded(column);
  _checkNesting(column);
  final value = jsonDecode(column);
  if (value is! _Json) throw const FormatException('Expected metadata object');
  if (value['v'] is! int ||
      value['v'] != 1 ||
      value['policyVersion'] is! int ||
      value['policyVersion'] != TimezonePolicy.version) {
    throw const FormatException('Unknown answer metadata version');
  }
  return value;
}

void _keys(_Json value, List<String> expected) {
  if (expected.length != value.length || !expected.every(value.containsKey)) {
    throw const FormatException('Unexpected metadata keys');
  }
}

T _field<T>(_Json map, String key) {
  final value = map[key];
  if (value is! T) throw FormatException('Invalid $key');
  return value;
}

String _id(String value, {int max = 256}) {
  if (value.isEmpty ||
      value.trim() != value ||
      value.runes.length > max ||
      value.codeUnits.any((unit) => unit < 32 || unit == 127) ||
      utf8.decode(utf8.encode(value)) != value) {
    throw const FormatException('Invalid authority identifier');
  }
  return value;
}

int _instant(int ms) {
  if (ms < 0 || ms > _maxUtcUs ~/ 1000) {
    throw const FormatException('Invalid answer UTC milliseconds');
  }
  return ms;
}

_Json _base(String kind, String origin, int ms) => {
  'v': 1,
  'policyVersion': TimezonePolicy.version,
  'kind': kind,
  'originOwnerId': _id(origin),
  'occurredAtUtcMs': _instant(ms),
};

(String, String, String, String, int, int?) _ruleIdentity(
  OwnerCalendarRule r,
) => (
  r.ruleId,
  r.originOwnerId,
  r.ianaId,
  r.tzdbRevision,
  r.effectiveUtcUs,
  r.expiresUtcUs,
);

_Json _ruleMap(OwnerCalendarRule r, String origin, int ms) {
  final us = _instant(ms) * 1000;
  final end = r.expiresUtcUs;
  if (origin != r.originOwnerId ||
      r.effectiveUtcUs < -_maxUtcUs ||
      r.effectiveUtcUs > us ||
      (end != null && (end <= us || end > _maxUtcUs))) {
    throw const FormatException(
      'Rule does not cover original owner and instant',
    );
  }
  return {
    'ruleId': _id(r.ruleId, max: 512),
    'originOwnerId': _id(origin),
    'ianaId': _id(r.ianaId),
    'tzdbRevision': _id(r.tzdbRevision),
    'effectiveUtcUs': r.effectiveUtcUs,
    'expiresUtcUs': end,
  };
}

OwnerCalendarRule _rule(_Json m) {
  _keys(m, [
    'ruleId',
    'originOwnerId',
    'ianaId',
    'tzdbRevision',
    'effectiveUtcUs',
    'expiresUtcUs',
  ]);
  return OwnerCalendarRule(
    ruleId: _field(m, 'ruleId'),
    originOwnerId: _field(m, 'originOwnerId'),
    ianaId: _field(m, 'ianaId'),
    tzdbRevision: _field(m, 'tzdbRevision'),
    effectiveUtcUs: _field(m, 'effectiveUtcUs'),
    expiresUtcUs: _field(m, 'expiresUtcUs'),
  );
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
DateTime _labels(String day, String monday) {
  DateTime parse(String label) {
    if (!_datePattern.hasMatch(label)) {
      throw const FormatException('Invalid civil label');
    }
    final year = int.parse(label.substring(0, 4));
    final month = int.parse(label.substring(5, 7));
    final date = int.parse(label.substring(8));
    final utc = DateTime.utc(year, month, date);
    if (utc.year != year || utc.month != month || utc.day != date) {
      throw const FormatException('Invalid civil date');
    }
    return utc;
  }

  final date = parse(day);
  if (parse(monday) !=
      date.subtract(Duration(days: date.weekday - DateTime.monday))) {
    throw const FormatException('Wrong Monday for civil day');
  }
  return date;
}

List<List<int>> _segments(
  List<(int, int)> segments,
  OwnerCalendarRule rule,
  int ms,
) {
  final us = ms * 1000;
  final end = rule.expiresUtcUs ?? _maxUtcUs;
  int? previousEnd;
  var contains = false;
  final wire = <List<int>>[];
  for (final (start, stop) in segments) {
    if (start < rule.effectiveUtcUs ||
        stop > end ||
        start >= stop ||
        (previousEnd != null && start <= previousEnd)) {
      throw const FormatException(
        'Expected normalized UTC segments within epoch',
      );
    }
    contains = contains || (start <= us && us < stop);
    previousEnd = stop;
    wire.add([start, stop]);
  }
  if (!contains) {
    throw const FormatException('UTC segments exclude original instant');
  }
  return wire;
}

_Json _calendarMap(AnswerCalendarEvidence c) {
  final origin = c.originOwnerId, ms = c.occurredAtUtcMs;
  switch (c) {
    case UnavailableCalendarEvidence():
      final rule = c.rule;
      return {
        ..._base('unavailable', origin, ms),
        'rule': rule == null ? null : _ruleMap(rule, origin, ms),
      };
    case CapturedCalendarEvidence():
      final base = _base('captured', origin, ms),
          rule = _ruleMap(c.rule, origin, ms);
      final day = _labels(c.civilDay, c.weekMonday);
      final offset = c.offsetSeconds;
      if (offset <= -86400 || offset >= 86400) {
        throw const FormatException('Invalid UTC offset');
      }
      final msOfDay = ms - day.millisecondsSinceEpoch + offset * 1000;
      if (msOfDay < 0 || msOfDay >= Duration.millisecondsPerDay) {
        throw const FormatException('Civil day and UTC offset disagree');
      }
      final days = _segments(c.daySegments, c.rule, ms);
      final weeks = _segments(c.weekSegments, c.rule, ms);
      var i = 0;
      for (final (start, stop) in c.daySegments) {
        while (i < weeks.length && weeks[i][1] <= start) {
          i++;
        }
        if (i == weeks.length || start < weeks[i][0] || stop > weeks[i][1]) {
          throw const FormatException('Day outside its week');
        }
      }
      return {
        ...base,
        'rule': rule,
        'civilDay': c.civilDay,
        'weekMonday': c.weekMonday,
        'offsetSeconds': offset,
        'daySegments': days,
        'weekSegments': weeks,
      };
  }
}

String encodeCalendarEvidence(AnswerCalendarEvidence evidence) =>
    _bounded(canonicalJson(_calendarMap(evidence)));

List<(int, int)> _readSegments(List<Object?> segments) => [
  for (final part in segments)
    if (part case [final int start, final int end])
      (start, end)
    else
      throw const FormatException('Expected pair of UTC microseconds'),
];

AnswerCalendarEvidence decodeCalendarEvidence(String column) {
  final m = _column(column);
  final String origin = _field(m, 'originOwnerId');
  final int ms = _field(m, 'occurredAtUtcMs');
  final AnswerCalendarEvidence result;
  switch (m['kind']) {
    case 'captured':
      _keys(m, [
        ..._baseKeys,
        'rule',
        'civilDay',
        'weekMonday',
        'offsetSeconds',
        'daySegments',
        'weekSegments',
      ]);
      result = CapturedCalendarEvidence(
        originOwnerId: origin,
        occurredAtUtcMs: ms,
        rule: _rule(_field(m, 'rule')),
        civilDay: _field(m, 'civilDay'),
        weekMonday: _field(m, 'weekMonday'),
        offsetSeconds: _field(m, 'offsetSeconds'),
        daySegments: _readSegments(_field(m, 'daySegments')),
        weekSegments: _readSegments(_field(m, 'weekSegments')),
      );
    case 'unavailable':
      _keys(m, [..._baseKeys, 'rule']);
      result = UnavailableCalendarEvidence(
        originOwnerId: origin,
        occurredAtUtcMs: ms,
        rule: m['rule'] == null ? null : _rule(_field(m, 'rule')),
      );
    default:
      throw const FormatException('Unknown calendar evidence');
  }
  if (encodeCalendarEvidence(result) != column.trim()) {
    throw const FormatException('Noncanonical calendar evidence');
  }
  return result;
}

final _digest = RegExp(r'^[0-9a-f]{64}$');
_Json _pinMap(QuestRevisionPin pin) {
  if (pin.catalogVersion < 1 || !_digest.hasMatch(pin.definitionDigest)) {
    throw const FormatException('Invalid Quest revision pin');
  }
  return {
    'questId': _id(pin.questId),
    'catalogVersion': pin.catalogVersion,
    'definitionDigest': pin.definitionDigest,
  };
}

QuestRevisionPin _pin(_Json m) {
  _keys(m, ['questId', 'catalogVersion', 'definitionDigest']);
  return QuestRevisionPin(
    questId: _field(m, 'questId'),
    catalogVersion: _field(m, 'catalogVersion'),
    definitionDigest: _field(m, 'definitionDigest'),
  );
}

String encodeQuestIntent(QuestAnswerIntent q) {
  final origin = q.originOwnerId, ms = q.occurredAtUtcMs;
  if (q is UnavailableQuestIntent) {
    return _bounded(canonicalJson(_base('unavailable', origin, ms)));
  }
  final p = q as PinnedQuestIntent;
  if (p.daily.questId == p.weekly.questId) {
    throw const FormatException('Duplicate Quest family');
  }
  final m = {
    ..._base(p is CapturedQuestIntent ? 'captured' : 'pending', origin, ms),
    'rule': _ruleMap(p.rule, origin, ms),
    'daily': _pinMap(p.daily),
    'weekly': _pinMap(p.weekly),
  };
  if (p is CapturedQuestIntent) {
    _labels(p.civilDay, p.weekMonday);
    m.addAll({
      'civilDay': p.civilDay,
      'weekMonday': p.weekMonday,
      'dailyPeriodId': p.dailyPeriodId,
      'weeklyPeriodId': p.weeklyPeriodId,
    });
  }
  return _bounded(canonicalJson(m));
}

QuestAnswerIntent decodeQuestIntent(String column) {
  final m = _column(column);
  final String origin = _field(m, 'originOwnerId');
  final int ms = _field(m, 'occurredAtUtcMs');
  final QuestAnswerIntent q;
  switch (m['kind']) {
    case 'unavailable':
      _keys(m, _baseKeys);
      q = UnavailableQuestIntent(originOwnerId: origin, occurredAtUtcMs: ms);
    case 'pending':
      _keys(m, [..._baseKeys, 'rule', 'daily', 'weekly']);
      q = PendingQuestIntent(
        originOwnerId: origin,
        occurredAtUtcMs: ms,
        rule: _rule(_field(m, 'rule')),
        daily: _pin(_field(m, 'daily')),
        weekly: _pin(_field(m, 'weekly')),
      );
    case 'captured':
      _keys(m, [
        ..._baseKeys,
        'rule',
        'daily',
        'weekly',
        'civilDay',
        'weekMonday',
        'dailyPeriodId',
        'weeklyPeriodId',
      ]);
      q = CapturedQuestIntent(
        originOwnerId: origin,
        occurredAtUtcMs: ms,
        rule: _rule(_field(m, 'rule')),
        daily: _pin(_field(m, 'daily')),
        weekly: _pin(_field(m, 'weekly')),
        civilDay: _field(m, 'civilDay'),
        weekMonday: _field(m, 'weekMonday'),
      );
    default:
      throw const FormatException('Unknown Quest intent');
  }
  if (encodeQuestIntent(q) != column.trim()) {
    throw const FormatException('Invalid or noncanonical Quest intent');
  }
  return q;
}
