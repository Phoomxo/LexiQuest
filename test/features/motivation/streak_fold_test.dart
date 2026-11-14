import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';

// Position 1 is Monday, 2027-01-04; instants are noon on each named day.
DateTime _day(int position) => DateTime.utc(2027, 1, position + 3);
int _time(int position) =>
    _day(position).add(const Duration(hours: 12)).millisecondsSinceEpoch;

StreakDayFact _fact(int position, {String origin = 'target', String? id}) =>
    StreakDayFact(
      id: id ?? '$origin-$position',
      occurredAtUtcMs: _time(position),
      day: _day(position),
      originOwnerId: origin,
      calendarRuleId: 'rule-$origin',
      precedingCivilDayExists: true,
    );

StreakState _state(int current, int longest, int tokens, {int? lastDay}) =>
    StreakState(
      ownerId: 'target',
      currentStreakDays: current,
      longestStreakDays: longest,
      freezeCount: tokens,
      lastLearnedAtUtcMs: lastDay == null ? null : _time(lastDay),
      updatedAtUtcMs: _time(lastDay ?? 0),
    );

StreakOpening _opening(
  int tokens, {
  String origin = 'target',
  int current = 0,
  int longest = 0,
  int? lastDay,
  bool controls = true,
}) => StreakOpening(
  raw: _state(current, longest, tokens, lastDay: lastDay),
  originOwnerId: origin,
  cutoffUtcMs: _time(0),
  controlsContinuity: controls,
  lastDay: lastDay == null ? null : _day(lastDay),
);

StreakFoldInput _input(
  List<StreakDayFact> facts, {
  List<StreakOpening> openings = const [],
  List<StreakMovement> movements = const [],
  StreakState? settled,
  int asOf = 4,
  Map<String, int> transfer = const {},
}) => StreakFoldInput(
  ownerId: 'target',
  asOfUtcMs: _time(asOf),
  today: _day(asOf),
  facts: facts,
  openings: openings,
  movements: movements,
  settled: settled,
  transferAtUtcMs: transfer,
);

StreakMovement _protect(int day, {String owner = 'target'}) => StreakMovement(
  originOwnerId: owner,
  commandId: 'autoProtect:${_day(day).toIso8601String().substring(0, 10)}',
  kind: StreakMovementKind.autoProtect,
  delta: -1,
  occurredAtUtcMs: _time(day + 1),
  protectedDay: _day(day),
);

void main() {
  test(
    'Apia nonexistent civil date is no missed learning opportunity and cannot consume a token',
    () {
      final firstTime = DateTime.utc(2011, 12, 29, 12).millisecondsSinceEpoch;
      final nextTime = DateTime.utc(2011, 12, 30, 12).millisecondsSinceEpoch;
      final cutoff = DateTime.utc(2011, 12, 28).millisecondsSinceEpoch;
      StreakFoldInput apia({
        bool? preceding = false,
        String nextRule = 'apia-home',
      }) => StreakFoldInput(
        ownerId: 'target',
        asOfUtcMs: nextTime,
        today: DateTime.utc(2011, 12, 31),
        facts: [
          StreakDayFact(
            id: 'apia-dec29',
            occurredAtUtcMs: firstTime,
            day: DateTime.utc(2011, 12, 29),
            originOwnerId: 'target',
            calendarRuleId: 'apia-home',
            precedingCivilDayExists: true,
          ),
          StreakDayFact(
            id: 'apia-dec31',
            occurredAtUtcMs: nextTime,
            day: DateTime.utc(2011, 12, 31),
            originOwnerId: 'target',
            calendarRuleId: nextRule,
            precedingCivilDayExists: preceding,
          ),
        ],
        openings: [
          StreakOpening(
            raw: StreakState(
              ownerId: 'target',
              currentStreakDays: 0,
              longestStreakDays: 0,
              freezeCount: 1,
              lastLearnedAtUtcMs: null,
              updatedAtUtcMs: cutoff,
            ),
            originOwnerId: 'target',
            cutoffUtcMs: cutoff,
            controlsContinuity: true,
          ),
        ],
      );
      final actual = StreakPolicy.evaluateForward(apia());
      expect(actual.result.currentStreakDays, 2);
      expect(actual.autoDebits, isEmpty);
      expect(actual.result.state.freezeCount, 1);
      final skipped = actual.result.days.singleWhere(
        (d) => d.day == DateTime.utc(2011, 12, 30),
      );
      expect((skipped.studied, skipped.protected), (false, false));

      final unknown = StreakPolicy.evaluateForward(apia(preceding: null));
      expect(unknown.autoDebits, isEmpty);
      expect(unknown.result.state.freezeCount, 1);
      expect(unknown.result.status, StreakFoldStatus.unavailable);
      final changedRule = StreakPolicy.evaluateForward(
        apia(nextRule: 'another-home-rule'),
      );
      expect(changedRule.autoDebits, isEmpty);
      expect(changedRule.result.currentStreakDays, 1);
      expect(changedRule.result.state.freezeCount, 1);
      final conflictingProof = StreakPolicy.evaluateForward(
        _input([
          _fact(1),
          StreakDayFact(
            id: 'target-1',
            occurredAtUtcMs: _time(1),
            day: _day(1),
            originOwnerId: 'target',
            calendarRuleId: 'rule-target',
            precedingCivilDayExists: false,
          ),
        ], asOf: 2),
      );
      expect(conflictingProof.result.status, StreakFoldStatus.unavailable);
      expect(conflictingProof.autoDebits, isEmpty);
    },
  );

  test(
    'unmerged UTC-only attendance preserves its legacy streak without calendar authority or merged continuity',
    () {
      StreakDayFact legacy(int day, {String? origin, String? rule}) =>
          StreakDayFact(
            id: 'legacy-$day',
            occurredAtUtcMs: _time(day),
            day: _day(day),
            originOwnerId: origin,
            calendarRuleId: rule,
            legacyUtcAttendance: true,
          );
      final facts = [legacy(1), legacy(2)];
      final view = StreakPolicy.fold(_input(facts, asOf: 2));
      expect(view.currentStreakDays, 2);
      expect(view.uncertainHistory, isTrue);
      expect(view.days.where((d) => d.studied).map((d) => d.day), [
        _day(1),
        _day(2),
      ]);
      expect(view.days.any((d) => d.protected), isFalse);

      final fundedGap = StreakPolicy.evaluateForward(
        _input([legacy(1), legacy(3)], openings: [_opening(1)], asOf: 3),
      );
      expect(fundedGap.autoDebits, isEmpty);
      expect(
        (
          fundedGap.result.currentStreakDays,
          fundedGap.result.state.freezeCount,
        ),
        (1, 1),
      );
      expect(fundedGap.result.uncertainHistory, isTrue);
      expect(fundedGap.result.days.any((d) => d.protected), isFalse);

      for (final merged in [
        _input(
          facts,
          asOf: 2,
          openings: [_opening(3, origin: 'guest', controls: false)],
        ),
        _input(facts, asOf: 2, transfer: {'guest': _time(0)}),
        _input([...facts, _fact(2, origin: 'guest')], asOf: 2),
        _input(
          facts,
          asOf: 2,
          movements: [
            StreakMovement(
              originOwnerId: 'guest',
              commandId: 'synthetic-incoming-grant',
              kind: StreakMovementKind.grant,
              delta: 1,
              occurredAtUtcMs: _time(1),
            ),
          ],
        ),
      ]) {
        final isolated = StreakPolicy.evaluateForward(merged);
        expect(isolated.result.currentStreakDays, 0);
        expect(isolated.autoDebits, isEmpty);
        expect(isolated.result.uncertainHistory, isTrue);
      }
      for (final fake in [
        legacy(1, origin: 'target'),
        legacy(1, rule: 'invented-rule'),
        legacy(1, origin: 'target', rule: 'invented-rule'),
      ]) {
        final invalid = StreakPolicy.evaluateForward(_input([fake], asOf: 2));
        expect(invalid.result.status, StreakFoldStatus.unavailable);
        expect(invalid.autoDebits, isEmpty);
      }
      final conflictingEligibility = StreakPolicy.evaluateForward(
        _input([
          legacy(1),
          StreakDayFact(
            id: 'legacy-1',
            occurredAtUtcMs: _time(1),
            day: _day(1),
          ),
        ], asOf: 2),
      );
      expect(
        conflictingEligibility.result.status,
        StreakFoldStatus.unavailable,
      );
      expect(conflictingEligibility.autoDebits, isEmpty);
    },
  );

  test(
    'each studied civil day counts once and a long gap keeps the previous longest',
    () {
      final facts = [
        _fact(7),
        _fact(4, id: 'wrong-answer'),
        _fact(3),
        _fact(2),
        _fact(1),
        _fact(2, id: 'another-answer'),
        _fact(1),
      ];
      final early = StreakPolicy.fold(_input(facts, asOf: 4));
      expect((early.currentStreakDays, early.state.longestStreakDays), (4, 4));
      expect(early.days.map((d) => d.day), [
        for (var i = 1; i <= 7; i++) _day(i),
      ]);
      expect(early.days.map((d) => d.studied), [
        true,
        true,
        true,
        true,
        false,
        false,
        false,
      ]);
      expect(early.days.any((d) => d.protected), isFalse);
      final reset = StreakPolicy.fold(_input(facts, asOf: 7));
      expect((reset.currentStreakDays, reset.state.longestStreakDays), (1, 4));
      expect(reset.state.lastLearnedAtUtcMs, _time(7));
    },
  );

  test(
    'persisted protection preserves length; later attendance on the protected day never refunds it',
    () {
      final debit = _protect(3);
      final studied = [_fact(1), _fact(2), _fact(4)];
      final before = StreakPolicy.fold(
        _input(studied, openings: [_opening(1)], movements: [debit]),
      );
      expect((before.currentStreakDays, before.state.freezeCount), (2, 0));
      expect((before.days[2].studied, before.days[2].protected), (false, true));
      final late = StreakPolicy.evaluateForward(
        _input(
          [...studied, _fact(3)],
          openings: [_opening(1)],
          movements: [debit],
          settled: before.state,
        ),
      );
      expect(late.autoDebits, isEmpty);
      expect(
        (late.result.currentStreakDays, late.result.state.freezeCount),
        (4, 0),
      );
      expect(
        (late.result.days[2].studied, late.result.days[2].protected),
        (true, true),
      );
    },
  );

  test(
    'identical final facts distinguish an unsettled forward gap from a settled gap followed by backfill',
    () {
      final same = [_fact(1), _fact(3), _fact(4)];
      final opening = [_opening(1)];
      final unposted = _input(same, openings: opening);
      final view = StreakPolicy.fold(unposted);
      expect(view.status, StreakFoldStatus.pending);
      expect((view.state.freezeCount, view.days[1].protected), (1, false));
      final h1 = StreakPolicy.evaluateForward(unposted);
      final proposed = h1.autoDebits.single;
      expect(
        (
          proposed.kind,
          proposed.originOwnerId,
          proposed.commandId,
          proposed.protectedDay,
          proposed.delta,
          proposed.occurredAtUtcMs,
        ),
        (
          StreakMovementKind.autoProtect,
          'target',
          'autoProtect:2027-01-05',
          _day(2),
          -1,
          _time(3),
        ),
      );
      expect(
        (h1.result.currentStreakDays, h1.result.state.freezeCount),
        (2, 0),
      );
      final h2 = StreakPolicy.evaluateForward(
        _input(same, openings: opening, settled: _state(1, 1, 1, lastDay: 4)),
      );
      expect(h2.autoDebits, isEmpty);
      expect(
        (h2.result.currentStreakDays, h2.result.state.freezeCount),
        (2, 1),
      );
      expect(h2.result.days[2].studied, isTrue);
      expect(StreakPolicy.fold(unposted).state.freezeCount, 1);
    },
  );

  test(
    'manual spending already committed later has priority over a newly recovered automatic debit',
    () {
      final manual = StreakMovement(
        originOwnerId: 'target',
        commandId: 'manual',
        kind: StreakMovementKind.manualDebit,
        delta: -1,
        occurredAtUtcMs: _time(4),
      );
      final grant = StreakMovement(
        originOwnerId: 'target',
        commandId: 'later',
        kind: StreakMovementKind.grant,
        delta: 1,
        occurredAtUtcMs: _time(5),
      );
      final settled = StreakPolicy.evaluateForward(
        _input(
          [_fact(1), _fact(3)],
          openings: [_opening(1)],
          movements: [grant, manual],
          asOf: 5,
        ),
      );
      expect(settled.autoDebits, isEmpty);
      expect(
        (
          settled.result.state.currentStreakDays,
          settled.result.state.freezeCount,
        ),
        (1, 1),
      );
      expect(settled.result.days.any((d) => d.protected), isFalse);
      final earlier = StreakPolicy.evaluateForward(
        _input([_fact(1), _fact(3)], movements: [grant], asOf: 5),
      );
      expect(earlier.autoDebits, isEmpty);
    },
  );

  test(
    'merged assets include independent debits but target alone supplies continuity',
    () {
      final input = _input(
        [
          _fact(1),
          _fact(2, origin: 'guest'),
          _fact(3),
          _fact(3, origin: 'guest'),
        ],
        openings: [
          _opening(3, current: 4, longest: 7, lastDay: 0),
          _opening(
            4,
            origin: 'guest',
            current: 8,
            longest: 11,
            lastDay: 0,
            controls: false,
          ),
        ],
        movements: [
          _protect(2),
          _protect(2, owner: 'guest'),
        ],
        transfer: {'guest': _time(4)},
      );
      final result = StreakPolicy.fold(input);
      expect(
        (
          result.currentStreakDays,
          result.state.longestStreakDays,
          result.state.freezeCount,
        ),
        (5, 11, 5),
      );
      expect((result.days[1].studied, result.days[1].protected), (true, true));
      expect(result.uncertainHistory, isTrue);
    },
  );

  test(
    'negative raw assets and an unverified baseline bridge cannot authorize a debit',
    () {
      final negative = StreakPolicy.evaluateForward(
        _input([_fact(1), _fact(3)], openings: [_opening(-2)]),
      );
      expect(negative.autoDebits, isEmpty);
      expect(negative.result.status, StreakFoldStatus.unavailable);
      expect(negative.result.state.freezeCount, -2);
      final unknown = StreakOpening(
        raw: _state(6, 9, 1, lastDay: 0),
        originOwnerId: 'target',
        cutoffUtcMs: _time(0),
        controlsContinuity: true,
      );
      final uncertain = StreakPolicy.evaluateForward(
        _input([_fact(2)], openings: [unknown]),
      );
      expect(uncertain.autoDebits, isEmpty);
      expect(uncertain.result.uncertainHistory, isTrue);
      expect(uncertain.result.state.longestStreakDays, greaterThanOrEqualTo(9));
    },
  );

  test(
    'two missed home dates expire the headline without spending or resetting the saved learning event',
    () {
      final facts = [_fact(1), _fact(2)];
      final observedAt = _day(
        3,
      ).add(const Duration(hours: 22)).millisecondsSinceEpoch;
      StreakFoldResult view(int homeDay) => StreakPolicy.fold(
        StreakFoldInput(
          ownerId: 'target',
          asOfUtcMs: observedAt,
          today: _day(homeDay),
          facts: facts,
          openings: [_opening(1)],
          settled: _state(2, 2, 1, lastDay: 2),
        ),
      );
      expect(view(3).currentStreakDays, 2);
      final expired = view(4);
      expect(expired.currentStreakDays, 0);
      expect(
        (
          expired.state.currentStreakDays,
          expired.state.longestStreakDays,
          expired.state.freezeCount,
          expired.state.lastLearnedAtUtcMs,
        ),
        (2, 2, 1, _time(2)),
      );
      expect(expired.days.any((d) => d.protected), isFalse);
      expect(expired.days.where((d) => d.studied).map((d) => d.day), [
        _day(1),
        _day(2),
      ]);
    },
  );
}
