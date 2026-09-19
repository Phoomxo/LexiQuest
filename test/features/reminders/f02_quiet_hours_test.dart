import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';

void main() {
  setUpAll(data.initializeTimeZones);
  for (final start in [0, 22 * 60]) {
    for (final hour in [5, 6]) {
      test('F02 quiet hours $start preserve fold $hour lower bound', () {
        final requested = DateTime.utc(2026, 11, 1, hour, 15, 30);
        final quiet = ReminderQuietHours(startMinutes: start, endMinutes: 90);
        final actual = quiet.shiftOutside(requested, 'America/New_York');
        expect(actual.isBefore(requested), isFalse);
        expect(actual, DateTime.utc(2026, 11, 1, hour, 30));
        final local = tz.TZDateTime.from(
          actual,
          tz.getLocation('America/New_York'),
        );
        expect(quiet.contains(local.hour * 60 + local.minute), isFalse);
        expect(quiet.shiftOutside(actual, 'America/New_York'), actual);
      });
    }
  }
}
