import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/multi_accent_pitch_calibration_service.dart';

void main() {
  test('calibratePitch normalizes pitch points by gender factor', () {
    final result = MultiAccentPitchCalibrationService.calibratePitch(
      rawPitchPoints: [0.5, 0.8, 0.6],
      accent: SpeechAccent.us,
      profile: VoiceGenderProfile.male,
    );

    expect(result.accentLabel, contains('General American'));
    expect(result.normalizedPoints.first, 0.5 * 0.85);
  });

  test('calibratePitch handles empty points safely', () {
    final result = MultiAccentPitchCalibrationService.calibratePitch(
      rawPitchPoints: [],
      accent: SpeechAccent.uk,
    );

    expect(result.normalizedPoints, isEmpty);
    expect(result.accentLabel, contains('UK'));
  });
}
