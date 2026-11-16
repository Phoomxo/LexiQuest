import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';

const _rule = OwnerCalendarRule(
  originOwnerId: 'A',
  ruleId: 'rule-A',
  ianaId: 'UTC',
  tzdbRevision: 'test-revision',
  effectiveUtcUs: 0,
  expiresUtcUs: 40000,
);
const _digest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _daily = QuestRevisionPin(
  questId: 'd',
  catalogVersion: 2,
  definitionDigest: _digest,
);
const _weekly = QuestRevisionPin(
  questId: 'w',
  catalogVersion: 1,
  definitionDigest: _digest,
);
const _captured = CapturedQuestIntent(
  originOwnerId: 'A',
  occurredAtUtcMs: 20,
  rule: _rule,
  daily: _daily,
  weekly: _weekly,
  civilDay: '1970-01-01',
  weekMonday: '1969-12-29',
);

CapturedCalendarEvidence _calendar({
  List<(int, int)> day = const [(0, 8000), (18000, 27000)],
  List<(int, int)> week = const [(0, 10000), (15000, 40000)],
}) => CapturedCalendarEvidence(
  originOwnerId: 'A',
  occurredAtUtcMs: 20,
  rule: _rule,
  civilDay: '1970-01-01',
  weekMonday: '1969-12-29',
  offsetSeconds: 0,
  daySegments: day,
  weekSegments: week,
);

Map<String, dynamic> _object(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  test('canonical JSON sorts nested objects and preserves authored arrays', () {
    expect(
      canonicalJson({
        'z': [true, null, 4, 'é'],
        'a': [
          {'b': 1, 'a': 2},
        ],
      }),
      '{"a":[{"a":2,"b":1}],"z":[true,null,4,"é"]}',
    );
    for (final value in <Object>[
      1.0,
      {1: 'number key'},
      Object(),
    ]) {
      expect(() => canonicalJson(value), throwsFormatException);
    }
  });

  test('calendar retains occurrence, original authority and exact unions', () {
    final day = [(0, 8000), (18000, 27000)];
    final input = _calendar(day: day);
    day.clear();
    final encoded = encodeCalendarEvidence(input);
    final decoded = decodeCalendarEvidence(encoded) as CapturedCalendarEvidence;
    expect(decoded.originOwnerId, 'A');
    expect(decoded.occurredAtUtcMs, 20);
    expect(decoded.rule.ruleId, 'rule-A');
    expect(decoded.rule.originOwnerId, 'A');
    expect(decoded.rule.ianaId, 'UTC');
    expect(decoded.rule.tzdbRevision, 'test-revision');
    expect(decoded.rule.effectiveUtcUs, 0);
    expect(decoded.rule.expiresUtcUs, 40000);
    expect(decoded.civilDay, '1970-01-01');
    expect(decoded.weekMonday, '1969-12-29');
    expect(decoded.offsetSeconds, 0);
    expect(decoded.daySegments, [(0, 8000), (18000, 27000)]);
    expect(decoded.weekSegments, [(0, 10000), (15000, 40000)]);
    expect(() => decoded.daySegments.clear(), throwsUnsupportedError);
    expect(encodeCalendarEvidence(decoded), encoded);
    expect(encoded, canonicalJson(jsonDecode(encoded)));
  });

  test('intent pins both cadences and verifies stable period identities', () {
    final encoded = encodeQuestIntent(_captured);
    final result = decodeQuestIntent(encoded) as CapturedQuestIntent;
    expect(result.originOwnerId, 'A');
    expect(result.occurredAtUtcMs, 20);
    expect(result.rule.expiresUtcUs, 40000);
    expect(result.civilDay, '1970-01-01');
    expect(result.weekMonday, '1969-12-29');
    expect(result.daily.catalogVersion, 2);
    expect(result.weekly.catalogVersion, 1);
    expect(result.daily.definitionDigest, _digest);
    expect(result.weekly.definitionDigest, _digest);
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    expect(
      result.dailyPeriodId,
      hash('["A","rule-A","daily","1970-01-01","d"]'),
    );
    expect(
      result.weeklyPeriodId,
      hash('["A","rule-A","weekly","1969-12-29","w"]'),
    );
    expect(encodeQuestIntent(result), encoded);
    expect(encoded, canonicalJson(jsonDecode(encoded)));
    final forged = _object(encoded)..['dailyPeriodId'] = result.weeklyPeriodId;
    expect(() => decodeQuestIntent(jsonEncode(forged)), throwsFormatException);
  });

  test('unavailable and pending retain only their supported authorities', () {
    for (final rule in [null, _rule]) {
      final encoded = encodeCalendarEvidence(
        UnavailableCalendarEvidence(
          originOwnerId: 'A',
          occurredAtUtcMs: 20,
          rule: rule,
        ),
      );
      final decoded =
          decodeCalendarEvidence(encoded) as UnavailableCalendarEvidence;
      expect(decoded.rule?.ruleId, rule?.ruleId);
      expect(encodeCalendarEvidence(decoded), encoded);
    }
    const pending = PendingQuestIntent(
      originOwnerId: 'A',
      occurredAtUtcMs: 20,
      rule: _rule,
      daily: _daily,
      weekly: _weekly,
    );
    final encoded = encodeQuestIntent(pending);
    final decoded = decodeQuestIntent(encoded) as PendingQuestIntent;
    expect(decoded.rule.ruleId, 'rule-A');
    expect(decoded.daily.questId, 'd');
    expect(decoded.weekly.questId, 'w');
    expect(encodeQuestIntent(decoded), encoded);
    final missingWeekly = _object(encoded)..remove('weekly');
    expect(
      () => decodeQuestIntent(jsonEncode(missingWeekly)),
      throwsFormatException,
    );
    final unavailable = encodeQuestIntent(
      const UnavailableQuestIntent(originOwnerId: 'A', occurredAtUtcMs: 20),
    );
    expect(decodeQuestIntent(unavailable), isA<UnavailableQuestIntent>());
    final extra = _object(unavailable)..['xpAmount'] = 50;
    expect(() => decodeQuestIntent(jsonEncode(extra)), throwsFormatException);
    expect(() => decodeQuestIntent('null'), throwsFormatException);
  });

  test(
    'rejects foreign rule, invalid civil labels and broken segment unions',
    () {
      final encoded = encodeCalendarEvidence(_calendar());
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['v'] = 2,
        (m) => m['policyVersion'] = 999,
        (m) => m['originOwnerId'] = 'B',
        (m) => m['occurredAtUtcMs'] = 40,
        (m) => m['civilDay'] = '1970-02-31',
        (m) => m['weekMonday'] = '1970-01-01',
        (m) => m['weekMonday'] = '1970-01-05',
        (m) => m['offsetSeconds'] = '0',
        (m) => m['daySegments'] = [
          [0, 20000],
        ],
        (m) => m['daySegments'] = [
          [0, 22000],
          [22000, 24000],
        ],
        (m) => m['daySegments'] = [
          [0, 22000],
          [21999, 24000],
        ],
        (m) => m['daySegments'] = [
          [18000, 27000],
          [0, 8000],
        ],
        (m) => m['daySegments'] = [
          [5000, 27000],
        ],
        (m) => m['weekSegments'] = [
          [0, 19000],
        ],
        (m) => m['weekSegments'] = [
          [0, 40001],
        ],
        (m) => m['rule']['ruleId'] = ' ',
        (m) => m['rule']['effectiveUtcUs'] = 40001,
        (m) => m['rule']['expiresUtcUs'] = 20.0,
        (m) => m['rule']['extra'] = true,
      ]) {
        final wire = _object(encoded);
        mutate(wire);
        expect(
          () => decodeCalendarEvidence(jsonEncode(wire)),
          throwsFormatException,
          reason: jsonEncode(wire),
        );
      }
      expect(
        () => encodeCalendarEvidence(_calendar(day: [(0, 19000)])),
        throwsFormatException,
      );
    },
  );

  test(
    'independently decoded columns agree on owner, original instant and rule',
    () {
      final calendar = decodeCalendarEvidence(
        encodeCalendarEvidence(_calendar()),
      );
      final quest = decodeQuestIntent(encodeQuestIntent(_captured));
      expect(
        OriginalAnswerMetadata(calendar: calendar, quest: quest).quest,
        quest,
      );
      expect(OriginalAnswerMetadata(calendar: calendar).quest, isNull);
      for (final wrong in [
        const UnavailableQuestIntent(originOwnerId: 'B', occurredAtUtcMs: 20),
        const UnavailableQuestIntent(originOwnerId: 'A', occurredAtUtcMs: 19),
      ]) {
        expect(
          () => OriginalAnswerMetadata(calendar: calendar, quest: wrong),
          throwsFormatException,
        );
      }
      final modified = _object(encodeCalendarEvidence(_calendar()));
      modified['rule']['expiresUtcUs'] = 40001;
      final changedRule = decodeCalendarEvidence(jsonEncode(modified));
      expect(
        () => OriginalAnswerMetadata(calendar: changedRule, quest: quest),
        throwsFormatException,
      );
      const dayMismatch = CapturedQuestIntent(
        originOwnerId: 'A',
        occurredAtUtcMs: 20,
        rule: _rule,
        daily: _daily,
        weekly: _weekly,
        civilDay: '1970-01-02',
        weekMonday: '1969-12-29',
      );
      expect(
        () => OriginalAnswerMetadata(calendar: calendar, quest: dayMismatch),
        throwsFormatException,
      );
    },
  );

  test(
    'pending requires the retained calendar rule and cannot claim capture',
    () {
      const missing = UnavailableCalendarEvidence(
        originOwnerId: 'A',
        occurredAtUtcMs: 20,
      );
      const known = UnavailableCalendarEvidence(
        originOwnerId: 'A',
        occurredAtUtcMs: 20,
        rule: _rule,
      );
      const pending = PendingQuestIntent(
        originOwnerId: 'A',
        occurredAtUtcMs: 20,
        rule: _rule,
        daily: _daily,
        weekly: _weekly,
      );
      expect(
        OriginalAnswerMetadata(calendar: known, quest: pending).quest,
        pending,
      );
      expect(
        () => OriginalAnswerMetadata(calendar: missing, quest: pending),
        throwsFormatException,
      );
      expect(
        () => OriginalAnswerMetadata(calendar: known, quest: _captured),
        throwsFormatException,
      );
    },
  );

  test('rejects malformed pins, extra authority and bytes over each bound', () {
    final encoded = encodeQuestIntent(_captured);
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (m) => m['v'] = 2,
      (m) => m['daily']['questId'] = '',
      (m) => m['weekly']['questId'] = 'd',
      (m) => m['daily']['catalogVersion'] = 0,
      (m) => m['daily']['catalogVersion'] = 2.0,
      (m) => m['daily']['definitionDigest'] = _digest.toUpperCase(),
      (m) => m['weekly']['definitionDigest'] = 'short',
      (m) => m['daily']['award'] = 42,
      (m) => m['civilDay'] = '1970-1-1',
    ]) {
      final wire = _object(encoded);
      mutate(wire);
      expect(
        () => decodeQuestIntent(jsonEncode(wire)),
        throwsFormatException,
        reason: jsonEncode(wire),
      );
    }
    // A whitespace-padded valid document exercises the raw column limit.
    for (final (source, decode) in <(String, Object Function(String))>[
      (
        encodeQuestIntent(
          const UnavailableQuestIntent(originOwnerId: 'é', occurredAtUtcMs: 20),
        ),
        decodeQuestIntent,
      ),
      (
        encodeCalendarEvidence(
          const UnavailableCalendarEvidence(
            originOwnerId: 'é',
            occurredAtUtcMs: 20,
          ),
        ),
        decodeCalendarEvidence,
      ),
    ]) {
      final atLimit = source.padRight(
        source.length + 64 * 1024 - utf8.encode(source).length,
      );
      expect(decode(atLimit), isNotNull);
      expect(() => decode('$atLimit '), throwsFormatException);
    }
    final oversized = _calendar(
      day: [for (var i = 0; i < 20000; i += 2) (i, i + 1), (20000, 20002)],
      week: [(0, 40000)],
    );
    expect(() => encodeCalendarEvidence(oversized), throwsFormatException);
  });

  test(
    'canonical columns reject duplicate keys and retain exact UTC microseconds',
    () {
      final large = encodeCalendarEvidence(
        const UnavailableCalendarEvidence(
          originOwnerId: 'A',
          occurredAtUtcMs: 9007199254741,
          rule: OwnerCalendarRule(
            ruleId: 'A-UTC',
            originOwnerId: 'A',
            ianaId: 'UTC',
            tzdbRevision: 'archived',
            effectiveUtcUs: 9007199254740993,
            expiresUtcUs: 9007199254741001,
          ),
        ),
      );
      final decoded =
          decodeCalendarEvidence(large) as UnavailableCalendarEvidence;
      expect(decoded.rule!.effectiveUtcUs, 9007199254740993);
      expect(decoded.rule!.expiresUtcUs, 9007199254741001);
      expect(
        () =>
            decodeCalendarEvidence(large.replaceFirst('"v":1', '"v":1,"v":1')),
        throwsFormatException,
      );
      final quest = encodeQuestIntent(_captured);
      expect(
        () => decodeQuestIntent(
          quest.replaceFirst('"questId":"d"', '"questId":"d","questId":"d"'),
        ),
        throwsFormatException,
      );
      final deep = '${'[' * 5000}0${']' * 5000}';
      expect(
        () => decodeCalendarEvidence('{"invalid":$deep}'),
        throwsFormatException,
      );
    },
  );
}
