import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/achievement_policy.dart';

void main() {
  const policy = AchievementPolicy();

  test('same eligible evidence unlocks each milestone once', () {
    final first = AchievementEvidenceFact(
      sourceEventId: 'attempt-1',
      sessionId: 'session-1',
      occurredAtUtc: DateTime.utc(2026, 8, 28, 9),
      isCorrect: true,
      isEligible: true,
    );

    final decisions = policy.evaluate(evidence: [first, first]);

    expect(decisions.map((decision) => decision.achievementId), [
      'first_answer',
      'first_correct',
    ]);
    expect(decisions.map((decision) => decision.sourceEventId).toSet(), {
      'attempt-1',
    });
  });

  test('definition version changes do not re-award durable unlocks', () {
    final decisions = const AchievementPolicy(definitionVersion: 2).evaluate(
      evidence: [
        AchievementEvidenceFact(
          sourceEventId: 'attempt-2',
          sessionId: 'session-1',
          occurredAtUtc: DateTime.utc(2026, 8, 28, 9),
          isCorrect: true,
          isEligible: true,
        ),
      ],
      permanentlyUnlockedAchievementIds: const {
        'first_answer',
        'first_correct',
      },
    );

    expect(decisions, isEmpty);
  });

  test('denied evidence cannot unlock achievements', () {
    final decisions = policy.evaluate(
      evidence: [
        AchievementEvidenceFact(
          sourceEventId: 'assessment-1',
          sessionId: 'assessment-session',
          occurredAtUtc: DateTime.utc(2026, 8, 28, 9),
          isCorrect: true,
          isEligible: false,
        ),
        AchievementEvidenceFact(
          sourceEventId: 'guided-1',
          sessionId: 'guided-session',
          occurredAtUtc: DateTime.utc(2026, 8, 28, 10),
          isCorrect: true,
          isEligible: false,
        ),
        AchievementEvidenceFact(
          sourceEventId: 'recreational-1',
          sessionId: 'game-session',
          occurredAtUtc: DateTime.utc(2026, 8, 28, 11),
          isCorrect: true,
          isEligible: false,
        ),
      ],
      completedSessions: [
        AchievementCompletedSessionFact(
          sourceEventId: 'assessment-session',
          completedAtUtc: DateTime.utc(2026, 8, 28, 12),
        ),
      ],
    );

    expect(decisions, isEmpty);
  });

  test('milestone source identity follows canonical event order', () {
    final decisions = policy.evaluate(
      evidence: [
        for (var index = 10; index >= 1; index -= 1)
          AchievementEvidenceFact(
            sourceEventId: 'attempt-${index.toString().padLeft(2, '0')}',
            sessionId: 'session-1',
            occurredAtUtc: DateTime.utc(2026, 8, 28, 9, index),
            isCorrect: true,
            isEligible: true,
          ),
      ],
      completedSessions: [
        AchievementCompletedSessionFact(
          sourceEventId: 'session-1',
          completedAtUtc: DateTime.utc(2026, 8, 28, 10),
        ),
      ],
    );

    expect(
      {
        for (final decision in decisions)
          decision.achievementId: decision.sourceEventId,
      },
      {
        'first_answer': 'attempt-01',
        'first_correct': 'attempt-01',
        'ten_correct': 'attempt-10',
        'first_session': 'session-1',
        'perfect_session': 'session-1',
      },
    );
  });

  test('same source identity with different payload fails closed', () {
    expect(
      () => policy.evaluate(
        evidence: [
          AchievementEvidenceFact(
            sourceEventId: 'attempt-1',
            sessionId: 'session-1',
            occurredAtUtc: DateTime.utc(2026, 8, 28, 9),
            isCorrect: true,
            isEligible: true,
          ),
          AchievementEvidenceFact(
            sourceEventId: 'attempt-1',
            sessionId: 'session-1',
            occurredAtUtc: DateTime.utc(2026, 8, 28, 9),
            isCorrect: false,
            isEligible: true,
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('corrupt durable unlock identity fails closed', () {
    expect(
      () => policy.evaluate(
        evidence: const [],
        permanentlyUnlockedAchievementIds: const {' forged'},
      ),
      throwsStateError,
    );
  });
}
