import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/adaptive_associative_scheduler.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/recall_attempt.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13);
  MemoryState state({String owner = 'a', String word = 'w',
    double stability = 2, double difficulty = 5, double cue = 0,
    int lapses = 0}) => MemoryState(ownerId: owner, wordKey: word,
      stability: stability, difficulty: difficulty, cueDependency: cue,
      lapseCount: lapses, nextDueAt: now);
  RecallAttempt attempt({String word = 'w', int latency = 10,
    int confidence = 3, DateTime? at}) => RecallAttempt(attemptId: 'attempt',
      sessionId: 'session', wordKey: word, recallMode: RecallMode.unaided,
      cueLevel: CueLevel.none, correctness: true, responseTimeMs: latency,
      confidence: confidence, occurredAt: at ?? now);
  final invalid = <String, MemoryState>{
    'empty owner': state(owner: ' '),
    'wrong word': state(word: 'other'),
    'NaN stability': state(stability: double.nan),
    'infinite stability': state(stability: double.infinity),
    'negative stability': state(stability: -1),
    'NaN difficulty': state(difficulty: double.nan),
    'out of range difficulty': state(difficulty: 11),
    'invalid cue': state(cue: -0.1),
    'negative lapse': state(lapses: -1),
  };
  for (final entry in invalid.entries) {
    test('B03 scheduler rejects ${entry.key}', () {
      expect(() => AdaptiveAssociativeScheduler().updateMemoryState(
        currentState: entry.value, attempt: attempt(), now: now),
        throwsArgumentError);
    });
  }
  test('B03 scheduler requires UTC at computation boundary', () {
    expect(() => AdaptiveAssociativeScheduler().updateMemoryState(
      currentState: state(), attempt: attempt(), now: DateTime(2026, 9, 13)),
      throwsArgumentError);
  });
  test('B03 recall rejects invalid latency and confidence', () {
    expect(() => attempt(latency: -1), throwsArgumentError);
    expect(() => attempt(confidence: 0), throwsArgumentError);
    expect(() => attempt(confidence: 6), throwsArgumentError);
  });
  test('B03 valid v1 formula and prior snapshot stay unchanged', () {
    final prior = state();
    final before = prior.toJson();
    final result = AdaptiveAssociativeScheduler().updateMemoryState(
      currentState: prior, attempt: attempt(confidence: 5), now: now);
    expect(result.stability, closeTo(3.2, 0.00001));
    expect(result.nextDueAt, now.add(const Duration(days: 3)));
    expect(result.algorithmVersion, 'v1.0.0');
    expect(prior.toJson(), before);
  });
}
