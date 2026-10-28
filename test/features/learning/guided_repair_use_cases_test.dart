import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/guided_repair.dart';

void main() {
  test(
    'repair retains assistance and terminates after three wrong answers',
    () {
      var state = GuidedRepairState.start(
        originId: 'attempt',
        priorHintLevel: 1,
      );
      state = state.revealHint();
      expect(state.hintLevel, 2);
      expect(() => state.revealHint(), throwsStateError);
      for (var i = 0; i < 3; i++) {
        state = state.answer(correct: false);
        expect(state.hintLevel, 2);
      }
      expect(state.terminal, isTrue);
      expect(state.evidenceClass, 'guidedPractice');
      expect(() => state.answer(correct: true), throwsStateError);
      expect(
        GuidedRepairState.fromJson(state.toJson()).toJson(),
        state.toJson(),
      );
    },
  );

  test(
    'unknown assistance is conservative and success cannot reopen repair',
    () {
      final state = GuidedRepairState.start(
        originId: 'attempt',
        priorHintLevel: -1,
      );
      expect(state.hintLevel, 2);
      final done = state.answer(correct: true);
      expect(done.terminal, isTrue);
      expect(done.correct, isTrue);
      expect(state.attempts, 0);
      expect(() => done.answer(correct: true), throwsStateError);
    },
  );

  test('exit is terminal; future and malformed snapshots fail closed', () {
    final state = GuidedRepairState.start(
      originId: 'attempt',
      priorHintLevel: 0,
    ).exit();
    expect(state.terminal, isTrue);
    expect(() => state.revealHint(), throwsStateError);
    expect(
      () => GuidedRepairState.fromJson({...state.toJson(), 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => GuidedRepairState.fromJson({...state.toJson(), 'attempts': 4}),
      throwsFormatException,
    );
  });
}
