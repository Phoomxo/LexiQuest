import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';

void main() {
  setUpAll(tz.initializeTimeZones);

  // Bangkok = UTC+7 year-round (no DST)
  const bangkok = 'Asia/Bangkok';
  // New York observes DST; in August it is UTC-4
  const newYork = 'America/New_York';

  group('getLearningDay', () {
    test('23:59 Bangkok maps to Aug 4', () {
      // 2026-08-04 23:59 Bangkok = 2026-08-04 16:59 UTC
      final utc = DateTime.utc(2026, 8, 4, 16, 59);
      expect(
        TimezonePolicy.getLearningDay(utc, bangkok),
        DateTime(2026, 8, 4),
      );
    });

    test('00:01 Bangkok maps to Aug 5', () {
      // 2026-08-05 00:01 Bangkok = 2026-08-04 17:01 UTC
      final utc = DateTime.utc(2026, 8, 4, 17, 1);
      expect(
        TimezonePolicy.getLearningDay(utc, bangkok),
        DateTime(2026, 8, 5),
      );
    });

    test('midnight UTC is Aug 4 in Bangkok (UTC+7)', () {
      final utc = DateTime.utc(2026, 8, 4, 0, 0);
      // 2026-08-04 07:00 Bangkok → still Aug 4
      expect(
        TimezonePolicy.getLearningDay(utc, bangkok),
        DateTime(2026, 8, 4),
      );
    });

    test('New York 23:59 EDT (UTC-4) maps correctly', () {
      // 2026-08-04 23:59 EDT = 2026-08-05 03:59 UTC
      final utc = DateTime.utc(2026, 8, 5, 3, 59);
      expect(
        TimezonePolicy.getLearningDay(utc, newYork),
        DateTime(2026, 8, 4),
      );
    });
  });

  group('isSameLearningDay', () {
    test('learning day boundary is midnight in learner timezone — Golden Journey #11', () {
      // 2026-08-04 23:59 Bangkok = UTC 16:59
      final beforeMidnight = DateTime.utc(2026, 8, 4, 16, 59);
      // 2026-08-05 00:01 Bangkok = UTC 17:01
      final afterMidnight = DateTime.utc(2026, 8, 4, 17, 1);

      expect(
        TimezonePolicy.isSameLearningDay(beforeMidnight, afterMidnight, bangkok),
        isFalse,
        reason: '23:59 and 00:01 are on different learning days',
      );
    });

    test('two UTC times mapping to same Bangkok day are same learning day', () {
      // Bangkok is UTC+7; Aug 4 in Bangkok spans UTC 2026-08-03 17:00 → 2026-08-04 16:59.
      // Both instants below land on Bangkok Aug 4.
      final t1 = DateTime.utc(2026, 8, 4, 0, 0);  // Bangkok 07:00 Aug 4
      final t2 = DateTime.utc(2026, 8, 4, 9, 0);  // Bangkok 16:00 Aug 4
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
