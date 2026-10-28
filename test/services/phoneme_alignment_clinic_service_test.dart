import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/phoneme_alignment_clinic_service.dart';

void main() {
  test('analyzeAlignment produces exact match when spoken matches target', () {
    final result = PhonemeAlignmentClinicService.analyzeAlignment(
      targetWord: 'think',
      targetIpa: '/θɪŋk/',
      spokenText: 'think',
    );

    expect(result.errorPhonemes, isEmpty);
    expect(result.diagnosticTip, contains('ถูกต้อง'));
  });

  test('analyzeAlignment pinpoints missing or substituted phonemes', () {
    final result = PhonemeAlignmentClinicService.analyzeAlignment(
      targetWord: 'think',
      targetIpa: '/θɪŋk/',
      spokenText: 'sink',
    );

    expect(result.errorPhonemes, isNotEmpty);
    expect(result.diagnosticTip, contains('คลาดเคลื่อน'));
  });
}
