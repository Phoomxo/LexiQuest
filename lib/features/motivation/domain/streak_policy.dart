/// Canonical learning-day projection result.
final class StreakState {
  const StreakState({
    required this.ownerId,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeCount,
    required this.lastLearnedAtUtcMs,
    required this.updatedAtUtcMs,
  });

  const StreakState.initial({required String ownerId, required int nowMs})
    : this(
        ownerId: ownerId,
        currentStreakDays: 0,
        longestStreakDays: 0,
        freezeCount: 0,
        lastLearnedAtUtcMs: null,
        updatedAtUtcMs: nowMs,
      );

  final String ownerId;
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeCount;

  /// `null` before the learner's first session.
  final int? lastLearnedAtUtcMs;
  final int updatedAtUtcMs;

  StreakState copyWith({
    int? currentStreakDays,
    int? longestStreakDays,
    int? freezeCount,
    int? lastLearnedAtUtcMs,
    int? updatedAtUtcMs,
  }) => StreakState(
    ownerId: ownerId,
    currentStreakDays: currentStreakDays ?? this.currentStreakDays,
    longestStreakDays: longestStreakDays ?? this.longestStreakDays,
    freezeCount: freezeCount ?? this.freezeCount,
    lastLearnedAtUtcMs: lastLearnedAtUtcMs ?? this.lastLearnedAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
}
