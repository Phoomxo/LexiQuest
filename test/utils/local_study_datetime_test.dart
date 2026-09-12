import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/utils/local_study_datetime.dart';

void main() {
  test('Bangkok midnight preserves exact UTC and display fields', () {
    final candidates = resolveLocalStudyDateTime(
      DateTime.utc(2026, 9, 1, 0, 30),
      'Asia/Bangkok',
    );
    expect(candidates, [DateTime.utc(2026, 8, 31, 17, 30)]);
    expect(
      formatLocalStudyDateTime(candidates.single, 'Asia/Bangkok'),
      '1 ก.ย. 2569 เวลา 00:30 · ประเทศไทย (UTC+07:00)',
    );
  });
  test('DST gap rejects and fold enumerates exact UTC candidates', () {
    expect(
      resolveLocalStudyDateTime(
        DateTime.utc(2026, 3, 8, 2, 30),
        'America/New_York',
      ),
      isEmpty,
    );
    expect(
      resolveLocalStudyDateTime(
        DateTime.utc(2026, 11, 1, 1, 30),
        'America/New_York',
      ),
      [DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6, 30)],
    );
  });
  test('calendar helper does not treat a calendar date as an instant', () {
    expect(formatStudyCalendarDate(DateTime.utc(2026, 9, 8)), '8 ก.ย. 2569');
    expect(formatStudyClockMinutes(1320), '22:00');
    expect(formatStudyClockMinutes(420), '07:00');
  });
}
