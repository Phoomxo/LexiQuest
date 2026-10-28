final class AchievementEvidenceFact {
  const AchievementEvidenceFact({
    required this.sourceEventId,
    required this.sessionId,
    required this.occurredAtUtc,
    required this.isCorrect,
    required this.isEligible,
  });

  final String sourceEventId;
  final String sessionId;
  final DateTime occurredAtUtc;
  final bool isCorrect;
  final bool isEligible;
}

final class AchievementCompletedSessionFact {
  const AchievementCompletedSessionFact({
    required this.sourceEventId,
    required this.completedAtUtc,
  });

  final String sourceEventId;
  final DateTime completedAtUtc;
}

final class AchievementUnlockDecision {
  const AchievementUnlockDecision({
    required this.achievementId,
    required this.definitionVersion,
    required this.sourceEventId,
    required this.unlockedAtUtc,
  });

  final String achievementId;
  final int definitionVersion;
  final String sourceEventId;
  final DateTime unlockedAtUtc;
}

/// Pure authority for deriving durable achievement unlocks from evidence whose
/// eligibility has already been resolved by the canonical evidence policy.
final class AchievementPolicy {
  const AchievementPolicy({this.definitionVersion = 1})
    : assert(definitionVersion > 0);

  final int definitionVersion;

  List<AchievementUnlockDecision> evaluate({
    required Iterable<AchievementEvidenceFact> evidence,
    Iterable<AchievementCompletedSessionFact> completedSessions = const [],
    Set<String> permanentlyUnlockedAchievementIds = const {},
  }) {
    if (definitionVersion <= 0) {
      throw StateError('achievement definition version must be positive');
    }
    for (final achievementId in permanentlyUnlockedAchievementIds) {
      _validateIdentifier(achievementId, 'durable achievementId');
    }
    final canonicalEvidence = _canonicalEvidence(evidence);
    final eligible = canonicalEvidence
        .where((fact) => fact.isEligible)
        .toList(growable: false);
    final correct = eligible
        .where((fact) => fact.isCorrect)
        .toList(growable: false);
    final sessions = _canonicalSessions(completedSessions);
    final eligibleBySession = <String, List<AchievementEvidenceFact>>{};
    for (final fact in eligible) {
      (eligibleBySession[fact.sessionId] ??= []).add(fact);
    }

    final decisions = <AchievementUnlockDecision>[];
    void unlock(
      String achievementId,
      String sourceEventId,
      DateTime unlockedAtUtc,
    ) {
      if (permanentlyUnlockedAchievementIds.contains(achievementId)) return;
      decisions.add(
        AchievementUnlockDecision(
          achievementId: achievementId,
          definitionVersion: definitionVersion,
          sourceEventId: sourceEventId,
          unlockedAtUtc: unlockedAtUtc,
        ),
      );
    }

    if (eligible.isNotEmpty) {
      final first = eligible.first;
      unlock('first_answer', first.sourceEventId, first.occurredAtUtc);
    }
    if (correct.isNotEmpty) {
      final first = correct.first;
      unlock('first_correct', first.sourceEventId, first.occurredAtUtc);
    }
    if (correct.length >= 10) {
      final tenth = correct[9];
      unlock('ten_correct', tenth.sourceEventId, tenth.occurredAtUtc);
    }

    final completedWithEvidence = sessions
        .where(
          (session) =>
              eligibleBySession[session.sourceEventId]?.isNotEmpty ?? false,
        )
        .toList(growable: false);
    if (completedWithEvidence.isNotEmpty) {
      final first = completedWithEvidence.first;
      unlock('first_session', first.sourceEventId, first.completedAtUtc);
    }
    final perfect = completedWithEvidence.where((session) {
      final attempts = eligibleBySession[session.sourceEventId]!;
      return attempts.every((attempt) => attempt.isCorrect);
    }).firstOrNull;
    if (perfect != null) {
      unlock('perfect_session', perfect.sourceEventId, perfect.completedAtUtc);
    }

    return List<AchievementUnlockDecision>.unmodifiable(decisions);
  }

  List<AchievementEvidenceFact> _canonicalEvidence(
    Iterable<AchievementEvidenceFact> evidence,
  ) {
    final bySource = <String, AchievementEvidenceFact>{};
    for (final fact in evidence) {
      _validateIdentifier(fact.sourceEventId, 'sourceEventId');
      _validateIdentifier(fact.sessionId, 'sessionId');
      _validateUtc(fact.occurredAtUtc, 'occurredAtUtc');
      final existing = bySource[fact.sourceEventId];
      if (existing != null &&
          (existing.sessionId != fact.sessionId ||
              existing.occurredAtUtc != fact.occurredAtUtc ||
              existing.isCorrect != fact.isCorrect ||
              existing.isEligible != fact.isEligible)) {
        throw StateError('achievement evidence identity is ambiguous');
      }
      bySource.putIfAbsent(fact.sourceEventId, () => fact);
    }
    return bySource.values.toList(growable: false)..sort((left, right) {
      final time = left.occurredAtUtc.compareTo(right.occurredAtUtc);
      return time != 0
          ? time
          : left.sourceEventId.compareTo(right.sourceEventId);
    });
  }

  List<AchievementCompletedSessionFact> _canonicalSessions(
    Iterable<AchievementCompletedSessionFact> sessions,
  ) {
    final bySource = <String, AchievementCompletedSessionFact>{};
    for (final session in sessions) {
      _validateIdentifier(session.sourceEventId, 'session sourceEventId');
      _validateUtc(session.completedAtUtc, 'completedAtUtc');
      final existing = bySource[session.sourceEventId];
      if (existing != null &&
          existing.completedAtUtc != session.completedAtUtc) {
        throw StateError('achievement session identity is ambiguous');
      }
      bySource.putIfAbsent(session.sourceEventId, () => session);
    }
    return bySource.values.toList(growable: false)..sort((left, right) {
      final time = left.completedAtUtc.compareTo(right.completedAtUtc);
      return time != 0
          ? time
          : left.sourceEventId.compareTo(right.sourceEventId);
    });
  }

  static void _validateIdentifier(String value, String field) {
    if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
      throw StateError('invalid achievement $field');
    }
  }

  static void _validateUtc(DateTime value, String field) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw StateError('invalid achievement $field');
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
