import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';

void main() {
  test('learning timezone is optional and pins an exact known IANA name', () {
    LearningProfileDraft draft([String? zone]) => LearningProfileDraft(
      onboardingState: LearningOnboardingState.completed,
      learningTimezoneId: zone,
    );
    expect(draft().learningTimezoneId, isNull);
    for (final zone in ['UTC', 'Asia/Bangkok', 'America/New_York']) {
      expect(draft(zone).learningTimezoneId, zone);
    }
    expect(draft('UTC').sameFacts(draft('Asia/Bangkok')), isFalse);
    expect(draft('UTC').interestCodesJson, draft().interestCodesJson);
    for (final zone in [
      '',
      'EST',
      'GMT+7',
      ' Asia/Bangkok',
      'Asia/Unknown',
      'asia/bangkok',
    ]) {
      expect(
        () => draft(zone),
        throwsA(isA<LearningProfileException>()),
        reason: zone,
      );
    }
  });
  test('civil dates validate leap days and canonical format', () {
    expect(LearningCivilDate.parse('2028-02-29').toString(), '2028-02-29');
    for (final value in [
      '2026-02-29',
      '2026-04-31',
      '2026-2-01',
      '2026-12-32',
      '2026-00-01',
      '1969-12-31',
      '2026-11-01Z',
    ]) {
      expect(
        () => LearningCivilDate.parse(value),
        throwsA(isA<LearningProfileException>()),
        reason: value,
      );
    }
    expect(
      () => LearningCivilDate(1 << 60, 1, 1),
      throwsA(isA<LearningProfileException>()),
    );
  });
  test(
    'countdown compares civil dates independently of elapsed clock hours',
    () {
      expect(
        LearningCivilDate(2026, 3, 9).daysFrom(LearningCivilDate(2026, 3, 8)),
        1,
      );
      expect(
        LearningCivilDate(2026, 11, 1).daysFrom(LearningCivilDate(2026, 11, 1)),
        0,
      );
      expect(
        LearningCivilDate(
          2026,
          10,
          31,
        ).daysFrom(LearningCivilDate(2026, 11, 1)),
        -1,
      );
    },
  );
  test('draft owns canonical immutable bounded preferences', () {
    final interests = ['travel', 'exam'];
    final draft = LearningProfileDraft(
      onboardingState: LearningOnboardingState.completed,
      goalText: '  Example  ',
      interestCodes: interests,
    );
    interests.clear();
    expect(draft.goalText, 'Example');
    expect(draft.interestCodes, ['exam', 'travel']);
    expect(
      draft.interestCodesJson,
      '{"schemaVersion":1,"codes":["exam","travel"]}',
    );
    expect(() => draft.interestCodes.add('study'), throwsUnsupportedError);
    for (final value in [0, 181]) {
      expect(
        () => LearningProfileDraft(
          onboardingState: LearningOnboardingState.completed,
          dailyMinutes: value,
        ),
        throwsA(isA<LearningProfileException>()),
      );
    }
    expect(
      () => LearningProfileDraft(
        onboardingState: LearningOnboardingState.completed,
        interestCodes: ['exam', 'exam'],
      ),
      throwsA(isA<LearningProfileException>()),
    );
    expect(
      () => LearningProfileDraft(
        onboardingState: LearningOnboardingState.completed,
        goalText: 'a' * 121,
      ),
      throwsA(isA<LearningProfileException>()),
    );
    expect(
      () => LearningProfileDraft(
        onboardingState: LearningOnboardingState.completed,
        goalText: 'a\nb',
      ),
      throwsA(isA<LearningProfileException>()),
    );
  });
}
