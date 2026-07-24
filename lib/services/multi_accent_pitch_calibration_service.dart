enum VoiceGenderProfile { male, female, youth }

enum SpeechAccent { us, uk, au }

class CalibratedPitchCurve {
  final SpeechAccent accent;
  final VoiceGenderProfile genderProfile;
  final List<double> normalizedPoints;
  final String accentLabel;

  const CalibratedPitchCurve({
    required this.accent,
    required this.genderProfile,
    required this.normalizedPoints,
    required this.accentLabel,
  });
}

/// Multi-Accent Speech & Pitch Calibration Service (Acoustic Phonetics Standard).
class MultiAccentPitchCalibrationService {
  const MultiAccentPitchCalibrationService();

  /// Normalizes pitch points based on accent and user's fundamental voice frequency (F0)
  static CalibratedPitchCurve calibratePitch({
    required List<double> rawPitchPoints,
    required SpeechAccent accent,
    VoiceGenderProfile profile = VoiceGenderProfile.female,
  }) {
    if (rawPitchPoints.isEmpty) {
      return CalibratedPitchCurve(
        accent: accent,
        genderProfile: profile,
        normalizedPoints: const [],
        accentLabel: _accentLabel(accent),
      );
    }

    final double factor;
    switch (profile) {
      case VoiceGenderProfile.male:
        factor = 0.85;
        break;
      case VoiceGenderProfile.female:
        factor = 1.0;
        break;
      case VoiceGenderProfile.youth:
        factor = 1.15;
        break;
    }

    final normalized = rawPitchPoints.map((p) => (p * factor).clamp(0.0, 1.0)).toList();

    return CalibratedPitchCurve(
      accent: accent,
      genderProfile: profile,
      normalizedPoints: normalized,
      accentLabel: _accentLabel(accent),
    );
  }

  static String _accentLabel(SpeechAccent accent) {
    switch (accent) {
      case SpeechAccent.us:
        return 'สำเนียงอเมริกัน (General American - US)';
      case SpeechAccent.uk:
        return 'สำเนียงอังกฤษ (Received Pronunciation - UK)';
      case SpeechAccent.au:
        return 'สำเนียงออสเตรเลีย (Australian English - AU)';
    }
  }
}
