import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/zpd_auto_tuner_service.dart';

void main() {
  const tuner = ZpdAutoTunerService();

  test(
    'tuneLevel promotes CEFR level +1 after 3 consecutive correct answers',
    () {
      expect(tuner.tuneLevel(currentLevel: 'A2', consecutiveCorrect: 3), 'B1');
      expect(tuner.tuneLevel(currentLevel: 'A2', consecutiveCorrect: 2), 'A2');
      expect(tuner.tuneLevel(currentLevel: 'C2', consecutiveCorrect: 5), 'C2');
    },
  );
}
