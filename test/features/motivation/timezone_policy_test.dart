import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tzdata;
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  // Bangkok = UTC+7 year-round (no DST)
  const bangkok = 'Asia/Bangkok';
  // New York observes DST; in August it is UTC-4
  const newYork = 'America/New_York';

  group('captureWindow', () {
    final utc = DateTime.utc;
    final capture = TimezonePolicy.captureWindow;

    void expectSegments(
      List<UtcSegment> actual,
      List<(DateTime, DateTime)> expected,
    ) {
      expect(actual, hasLength(expected.length));
      expect(actual.map((s) => (s.startUtc, s.endUtc)), expected);
      for (final segment in actual) {
        expect(segment.startUtc.isUtc && segment.endUtc.isUtc, isTrue);
        expect(segment.containsUtc(segment.startUtc), isTrue);
        expect(segment.containsUtc(segment.endUtc), isFalse);
      }
    }

    test('Bangkok midnight ends one civil day and starts the next', () {
      final before = capture(utc(2026, 8, 4, 16, 59), bangkok);
      final after = capture(utc(2026, 8, 4, 17, 1), bangkok);
      expect(before.civilDay, utc(2026, 8, 4));
      expect(after.civilDay, utc(2026, 8, 5));
      expectSegments(before.daySegments, [
        (utc(2026, 8, 3, 17), utc(2026, 8, 4, 17)),
      ]);
      expectSegments(after.daySegments, [
        (utc(2026, 8, 4, 17), utc(2026, 8, 5, 17)),
      ]);
      expect(after.weekMonday, utc(2026, 8, 3));
      expectSegments(after.weekSegments, [
        (utc(2026, 8, 2, 17), utc(2026, 8, 9, 17)),
      ]);
      expect(after.offsetSeconds, 7 * 3600);
      expect(after.timezoneId, bangkok);
    });

    test('explicit UTC and Monday week cross the year at the exact end', () {
      final sunday = capture(utc(2027, 1, 3, 23, 59, 59, 999, 999), 'UTC');
      final next = capture(utc(2027, 1, 4), 'UTC');
      expect(sunday.timezoneId, 'UTC');
      expect(sunday.offsetSeconds, 0);
      expect(sunday.weekMonday, utc(2026, 12, 28));
      expectSegments(sunday.weekSegments, [
        (utc(2026, 12, 28), utc(2027, 1, 4)),
      ]);
      expectSegments(sunday.daySegments, [(utc(2027, 1, 3), utc(2027, 1, 4))]);
      expect(next.civilDay, utc(2027, 1, 4));
      expect(next.weekMonday, next.civilDay);
      expectSegments(next.weekSegments, [(utc(2027, 1, 4), utc(2027, 1, 11))]);
      expectSegments(next.daySegments, [(utc(2027, 1, 4), utc(2027, 1, 5))]);
    });

    test('New York spring forward has a 23-hour Sunday', () {
      final window = capture(utc(2026, 3, 8, 7), newYork);
      expect(window.civilDay, utc(2026, 3, 8));
      expectSegments(window.daySegments, [
        (utc(2026, 3, 8, 5), utc(2026, 3, 9, 4)),
      ]);
      expectSegments(window.weekSegments, [
        (utc(2026, 3, 2, 5), utc(2026, 3, 9, 4)),
      ]);
      expect(window.offsetSeconds, -4 * 3600);
    });

    test('both New York 01:30s share a 25-hour day with distinct offsets', () {
      for (final (time, offset) in [
        (utc(2026, 11, 1, 5, 30), -4 * 3600),
        (utc(2026, 11, 1, 6, 30), -5 * 3600),
      ]) {
        final window = capture(time, newYork);
        expectSegments(window.daySegments, [
          (utc(2026, 11, 1, 4), utc(2026, 11, 2, 5)),
        ]);
        expectSegments(window.weekSegments, [
          (utc(2026, 10, 26, 4), utc(2026, 11, 2, 5)),
        ]);
        expect(window.offsetSeconds, offset);
      }
    });

    test(
      'westward change repeats Sunday in disjoint day and week segments',
      () {
        final cutover = utc(2026, 8, 2, 17); // Monday 00:00, Bangkok.
        final old = capture(
          cutover.subtract(const Duration(microseconds: 1)),
          bangkok,
          epochExpiresAtUtc: cutover,
        );
        final next = capture(cutover, newYork, epochEffectiveAtUtc: cutover);
        expect(next.civilDay, utc(2026, 8, 2));
        expect(next.civilDay, old.civilDay);
        expect(next.weekMonday, utc(2026, 7, 27));
        expectSegments(old.daySegments, [(utc(2026, 8, 1, 17), cutover)]);
        expectSegments(old.weekSegments, [(utc(2026, 7, 26, 17), cutover)]);
        expectSegments(next.daySegments, [(cutover, utc(2026, 8, 3, 4))]);
        expectSegments(next.weekSegments, [(cutover, utc(2026, 8, 3, 4))]);
      },
    );

    test('eastward change clips only the first day and week', () {
      final cutover = utc(2026, 8, 3, 4); // Monday 00:00, New York.
      final old = capture(
        cutover.subtract(const Duration(microseconds: 1)),
        newYork,
        epochExpiresAtUtc: cutover,
      );
      final first = capture(cutover, bangkok, epochEffectiveAtUtc: cutover);
      final nextWeek = capture(
        utc(2026, 8, 9, 17),
        bangkok,
        epochEffectiveAtUtc: cutover,
      );
      expectSegments(old.daySegments, [(utc(2026, 8, 2, 4), cutover)]);
      expectSegments(old.weekSegments, [(utc(2026, 7, 27, 4), cutover)]);
      expect(first.civilDay, utc(2026, 8, 3));
      expect(first.weekMonday, first.civilDay);
      expectSegments(first.daySegments, [(cutover, utc(2026, 8, 3, 17))]);
      expectSegments(first.weekSegments, [(cutover, utc(2026, 8, 9, 17))]);
      expectSegments(nextWeek.daySegments, [
        (utc(2026, 8, 9, 17), utc(2026, 8, 10, 17)),
      ]);
      expectSegments(nextWeek.weekSegments, [
        (utc(2026, 8, 9, 17), utc(2026, 8, 16, 17)),
      ]);
    });

    test('Gaza repeated midnight starts at the first 00:00', () {
      const gaza = 'Asia/Gaza';
      final start = utc(2020, 10, 23, 21);
      final end = utc(2020, 10, 24, 22);
      final previous = capture(
        start.subtract(const Duration(microseconds: 1)),
        gaza,
      );
      expect(previous.civilDay, utc(2020, 10, 23));
      expectSegments(previous.daySegments, [(utc(2020, 10, 22, 21), start)]);
      for (final (time, offset) in [
        (utc(2020, 10, 23, 21, 30), 10800),
        (utc(2020, 10, 23, 22, 30), 7200),
      ]) {
        final window = capture(time, gaza);
        expect(window.offsetSeconds, offset);
        expect(window.civilDay, utc(2020, 10, 24));
        expectSegments(window.daySegments, [(start, end)]);
        expect(window.daySegments.single.containsUtc(time), isTrue);
      }
      final next = capture(end, gaza);
      expect(next.civilDay, utc(2020, 10, 25));
      expectSegments(next.daySegments, [(end, utc(2020, 10, 25, 22))]);
    });

    test('St Johns returns to Saturday after Sunday has begun', () {
      const zone = 'America/St_Johns';
      final instants = [
        utc(2009, 11, 1, 2, 29),
        utc(2009, 11, 1, 2, 30),
        utc(2009, 11, 1, 2, 31),
        utc(2009, 11, 1, 3),
        utc(2009, 11, 1, 3, 30),
      ];
      final saturday = DateTime(2009, 10, 31);
      final sunday = DateTime(2009, 11, 1);
      final labels = [saturday, sunday, saturday, saturday, sunday];
      expect(
        instants.map((t) => TimezonePolicy.getLearningDay(t, zone)),
        labels,
      );
      final saturdaySegments = [
        (utc(2009, 10, 31, 2, 30), instants[1]),
        (instants[2], instants[4]),
      ];
      final sundaySegments = [
        (instants[1], instants[2]),
        (instants[4], utc(2009, 11, 2, 3, 30)),
      ];
      for (var i = 0; i < instants.length; i++) {
        final window = capture(instants[i], zone);
        final label = labels[i];
        expect(window.civilDay, utc(label.year, label.month, label.day));
        expectSegments(
          window.daySegments,
          label == saturday ? saturdaySegments : sundaySegments,
        );
        expectSegments(window.weekSegments, [
          (utc(2009, 10, 26, 2, 30), utc(2009, 11, 2, 3, 30)),
        ]);
        for (var j = 0; j < instants.length; j++) {
          expect(
            window.daySegments.any((s) => s.containsUtc(instants[j])),
            labels[j] == label,
          );
        }
      }
    });

    test('Apia skips December 30 without leaving a gap in UTC', () {
      const apia = 'Pacific/Apia';
      final jump = utc(2011, 12, 30, 10);
      final before = capture(
        jump.subtract(const Duration(microseconds: 1)),
        apia,
      );
      final after = capture(jump, apia);
      expect(before.civilDay, utc(2011, 12, 29));
      expect(before.offsetSeconds, -10 * 3600);
      expectSegments(before.daySegments, [(utc(2011, 12, 29, 10), jump)]);
      expect(after.civilDay, utc(2011, 12, 31));
      expect(after.offsetSeconds, 14 * 3600);
      expectSegments(after.daySegments, [(jump, utc(2011, 12, 31, 10))]);
      for (final window in [before, after]) {
        expectSegments(window.weekSegments, [
          (utc(2011, 12, 26, 10), utc(2012, 1, 1, 10)),
        ]);
      }
    });

    test('clips both epoch endpoints to exact microseconds and omits gaps', () {
      const zone = 'America/St_Johns';
      final start = utc(2009, 11, 1, 2, 30, 45, 0, 111);
      final end = utc(2009, 11, 1, 2, 31, 0, 0, 222);
      final saturday = capture(
        utc(2009, 11, 1, 2, 31),
        zone,
        epochEffectiveAtUtc: start,
        epochExpiresAtUtc: end,
      );
      expectSegments(saturday.daySegments, [(utc(2009, 11, 1, 2, 31), end)]);
      expectSegments(saturday.weekSegments, [(start, end)]);
      final sunday = capture(
        start,
        zone,
        epochEffectiveAtUtc: start,
        epochExpiresAtUtc: end,
      );
      expectSegments(sunday.daySegments, [(start, utc(2009, 11, 1, 2, 31))]);
      expect(() => saturday.daySegments.clear(), throwsUnsupportedError);
      expect(() => saturday.weekSegments.clear(), throwsUnsupportedError);
      expect(
        () => saturday.daySegments.single.containsUtc(DateTime(2009)),
        throwsArgumentError,
      );
    });

    test('pre-1970 Monday rollback splits both adjacent weeks', () {
      const name = 'Test/SyntheticMondayRollback';
      final transition = utc(
        1969,
        12,
        29,
        0,
        1,
      ); // Monday 00:01 -> Sunday 23:01.
      final locations = tzdata.timeZoneDatabase.locations;
      final original = locations[name];
      addTearDown(() {
        if (original == null) {
          locations.remove(name);
        } else {
          locations[name] = original;
        }
      });
      locations[name] = tzdata.Location(
        name,
        [transition.millisecondsSinceEpoch],
        [1],
        [
          const tzdata.TimeZone(0, isDst: false, abbreviation: 'TEST0'),
          const tzdata.TimeZone(-3600000, isDst: false, abbreviation: 'TEST1'),
        ],
      );

      final monday = utc(1969, 12, 29);
      final resumes = utc(1969, 12, 29, 1);
      final before = transition.subtract(const Duration(microseconds: 1));
      final windows = [
        capture(before, name),
        capture(transition, name),
        capture(resumes, name),
      ];
      final mondaySegments = [
        (monday, transition),
        (resumes, utc(1970, 1, 5, 1)),
      ];
      final previousSegments = [
        (utc(1969, 12, 22), monday),
        (transition, resumes),
      ];
      expect(windows[0].weekMonday, monday);
      expect(windows[1].weekMonday, utc(1969, 12, 22));
      expect(windows[2].weekMonday, monday);
      expect(windows[0].offsetSeconds, 0);
      expect(windows[1].offsetSeconds, -3600);
      expectSegments(windows[0].weekSegments, mondaySegments);
      expectSegments(windows[1].weekSegments, previousSegments);
      expectSegments(windows[2].weekSegments, mondaySegments);
      expect(
        windows[0].weekSegments.any((s) => s.containsUtc(transition)),
        isFalse,
      );
      expect(
        windows[1].weekSegments.any((s) => s.containsUtc(before)),
        isFalse,
      );
      expect(
        windows[1].weekSegments.any((s) => s.containsUtc(transition)),
        isTrue,
      );
    });

    test(
      'rejects unknown zones, host-local inputs and out-of-epoch events',
      () {
        final t = utc(2026, 8, 3, 4);
        final local = DateTime(2026, 8, 3, 4);
        expect(() => capture(t, 'Invalid/Unknown'), throwsArgumentError);
        expect(() => capture(local, 'UTC'), throwsArgumentError);
        expect(
          () => capture(t, bangkok, epochEffectiveAtUtc: local),
          throwsArgumentError,
        );
        expect(
          () => capture(t, bangkok, epochExpiresAtUtc: local),
          throwsArgumentError,
        );
        expect(
          () => capture(
            t.subtract(const Duration(microseconds: 1)),
            bangkok,
            epochEffectiveAtUtc: t,
          ),
          throwsArgumentError,
        );
        expect(
          () => capture(t, bangkok, epochExpiresAtUtc: t),
          throwsArgumentError,
        );
        expect(
          () => capture(
            t,
            bangkok,
            epochEffectiveAtUtc: t,
            epochExpiresAtUtc: t.subtract(const Duration(microseconds: 1)),
          ),
          throwsArgumentError,
        );
      },
    );

    test('rejects days whose full week is outside representable dates', () {
      for (final limit in [tzdata.minTime, tzdata.maxTime]) {
        final time = DateTime.fromMillisecondsSinceEpoch(limit, isUtc: true);
        expect(() => capture(time, 'UTC'), throwsRangeError);
      }
    });
  });

  group('getLearningDay', () {
    test('23:59 Bangkok maps to Aug 4', () {
      // 2026-08-04 23:59 Bangkok = 2026-08-04 16:59 UTC
      final utc = DateTime.utc(2026, 8, 4, 16, 59);
      expect(TimezonePolicy.getLearningDay(utc, bangkok), DateTime(2026, 8, 4));
    });

    test('00:01 Bangkok maps to Aug 5', () {
      // 2026-08-05 00:01 Bangkok = 2026-08-04 17:01 UTC
      final utc = DateTime.utc(2026, 8, 4, 17, 1);
      expect(TimezonePolicy.getLearningDay(utc, bangkok), DateTime(2026, 8, 5));
    });

    test('midnight UTC is Aug 4 in Bangkok (UTC+7)', () {
      final utc = DateTime.utc(2026, 8, 4, 0, 0);
      // 2026-08-04 07:00 Bangkok → still Aug 4
      expect(TimezonePolicy.getLearningDay(utc, bangkok), DateTime(2026, 8, 4));
    });

    test('New York 23:59 EDT (UTC-4) maps correctly', () {
      // 2026-08-04 23:59 EDT = 2026-08-05 03:59 UTC
      final utc = DateTime.utc(2026, 8, 5, 3, 59);
      expect(TimezonePolicy.getLearningDay(utc, newYork), DateTime(2026, 8, 4));
    });
  });

  group('isSameLearningDay', () {
    test(
      'learning day boundary is midnight in learner timezone — Golden Journey #11',
      () {
        // 2026-08-04 23:59 Bangkok = UTC 16:59
        final beforeMidnight = DateTime.utc(2026, 8, 4, 16, 59);
        // 2026-08-05 00:01 Bangkok = UTC 17:01
        final afterMidnight = DateTime.utc(2026, 8, 4, 17, 1);

        expect(
          TimezonePolicy.isSameLearningDay(
            beforeMidnight,
            afterMidnight,
            bangkok,
          ),
          isFalse,
          reason: '23:59 and 00:01 are on different learning days',
        );
      },
    );

    test('two UTC times mapping to same Bangkok day are same learning day', () {
      // Bangkok is UTC+7; Aug 4 in Bangkok spans UTC 2026-08-03 17:00 → 2026-08-04 16:59.
      // Both instants below land on Bangkok Aug 4.
      final t1 = DateTime.utc(2026, 8, 4, 0, 0); // Bangkok 07:00 Aug 4
      final t2 = DateTime.utc(2026, 8, 4, 9, 0); // Bangkok 16:00 Aug 4
      expect(TimezonePolicy.isSameLearningDay(t1, t2, bangkok), isTrue);
    });

    test('streak survives timezone change — Golden Journey #11', () {
      // Learn at 2026-08-04 23:00 Bangkok = UTC 16:00
      final session1 = DateTime.utc(2026, 8, 4, 16, 0);
      // Day 1 in Bangkok timezone
      expect(
        TimezonePolicy.getLearningDay(session1, bangkok),
        DateTime(2026, 8, 4),
      );

      // User flies to New York; learns at 2026-08-05 09:00 NY (UTC-4) = UTC 13:00
      final session2 = DateTime.utc(2026, 8, 5, 13, 0);
      // Day 2 in New York timezone (next calendar day → streak extends)
      expect(
        TimezonePolicy.getLearningDay(session2, newYork),
        DateTime(2026, 8, 5),
      );

      // The two sessions must be on *different* learning days in their
      // respective timezones — streak counter increments, not resets.
      expect(
        TimezonePolicy.isSameLearningDay(session1, session2, newYork),
        isFalse,
        reason: 'Aug 4 NY and Aug 5 NY are different — streak extends to 2',
      );
    });

    test('same moment is same learning day', () {
      final t = DateTime.utc(2026, 8, 4, 12, 0);
      expect(TimezonePolicy.isSameLearningDay(t, t, bangkok), isTrue);
    });
  });

  group('getNextDayBoundary', () {
    test('next boundary from Bangkok 23:59 is 17:00 UTC', () {
      // 2026-08-04 23:59 Bangkok = UTC 16:59
      final utc = DateTime.utc(2026, 8, 4, 16, 59);
      final boundary = TimezonePolicy.getNextDayBoundary(utc, bangkok);
      // Midnight Aug 5 Bangkok = 2026-08-04 17:00 UTC
      expect(boundary, DateTime.utc(2026, 8, 4, 17, 0));
    });

    test('next boundary from Bangkok midnight is exactly 24 h later', () {
      // 2026-08-05 00:00 Bangkok = 2026-08-04 17:00 UTC
      final utc = DateTime.utc(2026, 8, 4, 17, 0);
      final boundary = TimezonePolicy.getNextDayBoundary(utc, bangkok);
      // Next midnight Bangkok = 2026-08-05 17:00 UTC
      expect(boundary, DateTime.utc(2026, 8, 5, 17, 0));
    });

    test('returned boundary is in UTC', () {
      final utc = DateTime.utc(2026, 8, 4, 12, 0);
      final boundary = TimezonePolicy.getNextDayBoundary(utc, bangkok);
      expect(boundary.isUtc, isTrue);
    });
  });
}
