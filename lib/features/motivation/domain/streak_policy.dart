import 'timezone_policy.dart';

/// Pure, timezone-aware policy for a learner's durable streak authority.
abstract final class StreakPolicy {
  static const int version = 2;

  /// Future issuance is capped; grandfathered inventory is never confiscated.
  static const int maxFreezeInventory = 3;

  /// Evaluate one eligible learning projection at [nowUtc].
  ///
  /// A duplicate local day is idempotent. A single missed day consumes one
  /// available freeze; otherwise the learner begins a calm recovery at one
  /// day while their all-time best remains intact.
  static StreakUpdate evaluate({
    required StreakState current,
    required DateTime nowUtc,
    required String timezoneId,
  }) {
    _requireUtc(nowUtc);
    _validateState(current);
    final today = _learningDay(nowUtc, timezoneId);

    if (current.lastLearnedAtUtcMs == null) {
      final next = current.copyWith(
        currentStreakDays: 1,
        longestStreakDays: 1,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
      );
      return _update(
        before: current,
        after: next,
        outcome: StreakOutcome.started,
        learningDay: today,
      );
    }

    final lastInstant = DateTime.fromMillisecondsSinceEpoch(
      current.lastLearnedAtUtcMs!,
      isUtc: true,
    );
    if (nowUtc.isBefore(lastInstant)) {
      throw StateError('streak event predates the durable streak authority');
    }
    final lastDay = _learningDay(lastInstant, timezoneId);
    final dayDiff = today.difference(lastDay).inDays;
    if (dayDiff < 0) {
      throw StateError('streak learning day moved backwards');
    }

    if (dayDiff == 0) {
      return _update(
        before: current,
        after: current,
        outcome: StreakOutcome.sameDay,
        learningDay: today,
      );
    }

    if (dayDiff == 1) {
      final newStreak = current.currentStreakDays + 1;
      final next = current.copyWith(
        currentStreakDays: newStreak,
        longestStreakDays: newStreak > current.longestStreakDays
            ? newStreak
            : current.longestStreakDays,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
      );
      return _update(
        before: current,
        after: next,
        outcome: StreakOutcome.extended,
        learningDay: today,
      );
    }

    if (dayDiff == 2 && current.freezeCount > 0) {
      final next = current.copyWith(
        freezeCount: current.freezeCount - 1,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
      );
      return _update(
        before: current,
        after: next,
        outcome: StreakOutcome.froze,
        learningDay: today,
      );
    }

    final next = current.copyWith(
      currentStreakDays: 1,
      lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
    );
    return _update(
      before: current,
      after: next,
      outcome: StreakOutcome.recovered,
      learningDay: today,
    );
  }

  /// Derive calm read-only presentation state without changing counters.
  static GentleStreakSnapshot snapshot({
    required StreakState current,
    required DateTime nowUtc,
    required String timezoneId,
  }) {
    _requireUtc(nowUtc);
    _validateState(current);
    final lastLearnedAtUtcMs = current.lastLearnedAtUtcMs;
    if (lastLearnedAtUtcMs == null) {
      return GentleStreakSnapshot.fromState(
        current,
        phase: GentleStreakPhase.empty,
      );
    }
    final lastInstant = DateTime.fromMillisecondsSinceEpoch(
      lastLearnedAtUtcMs,
      isUtc: true,
    );
    if (nowUtc.isBefore(lastInstant)) {
      throw StateError('streak clock predates the durable streak authority');
    }
    final today = _learningDay(nowUtc, timezoneId);
    final lastDay = _learningDay(lastInstant, timezoneId);
    final dayDiff = today.difference(lastDay).inDays;
    if (dayDiff < 0) {
      throw StateError('streak learning day moved backwards');
    }
    return GentleStreakSnapshot.fromState(
      current,
      phase: switch (dayDiff) {
        0 => GentleStreakPhase.steady,
        1 => GentleStreakPhase.grace,
        _ => GentleStreakPhase.recovery,
      },
    );
  }

  /// UTC midnight carrying the local calendar date in [timezoneId].
  static DateTime learningDayBoundary(DateTime utcNow, String timezoneId) {
    _requireUtc(utcNow);
    final localDay = timezoneId == 'UTC'
        ? utcNow
        : TimezonePolicy.getLearningDay(utcNow, timezoneId);
    return DateTime.utc(localDay.year, localDay.month, localDay.day);
  }

  static DateTime _learningDay(DateTime utcNow, String timezoneId) =>
      learningDayBoundary(utcNow, timezoneId);

  static StreakUpdate _update({
    required StreakState before,
    required StreakState after,
    required StreakOutcome outcome,
    required DateTime learningDay,
  }) => StreakUpdate(
    before: before,
    after: after,
    outcome: outcome,
    learningDay: learningDay,
    reaction: StreakReaction.forOutcome(outcome),
    receipt: StreakPolicyReceipt(
      ownerId: after.ownerId,
      learningDay: _formatDay(learningDay),
      policyVersion: version,
      currentStreakDays: after.currentStreakDays,
      longestStreakDays: after.longestStreakDays,
      freezeCount: after.freezeCount,
    ),
  );

  static String _formatDay(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }

  static void _requireUtc(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
  }

  static void _validateState(StreakState state) {
    if (state.ownerId.trim() != state.ownerId ||
        state.ownerId.isEmpty ||
        state.currentStreakDays < 0 ||
        state.longestStreakDays < state.currentStreakDays ||
        state.freezeCount < 0 ||
        (state.lastLearnedAtUtcMs != null && state.lastLearnedAtUtcMs! < 0) ||
        state.updatedAtUtcMs < 0) {
      throw StateError('invalid durable streak authority state');
    }
  }
}

/// Current persisted streak counters for one owner.
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

/// Result of applying one eligible learning projection.
final class StreakUpdate {
  const StreakUpdate({
    required this.before,
    required this.after,
    required this.outcome,
    required this.learningDay,
    required this.reaction,
    required this.receipt,
  });

  final StreakState before;
  final StreakState after;
  final StreakOutcome outcome;
  final DateTime learningDay;
  final StreakReaction reaction;
  final StreakPolicyReceipt receipt;

  bool get changed => outcome != StreakOutcome.sameDay;

  /// Pins an exact replay to the day already held by LearningDayLog.
  StreakUpdate pinLearningDay(String dayLabel) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dayLabel)) {
      throw StateError('invalid durable streak learning day');
    }
    final parsed = DateTime.tryParse('${dayLabel}T00:00:00Z');
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != dayLabel) {
      throw StateError('invalid durable streak learning day');
    }
    return StreakUpdate(
      before: before,
      after: after,
      outcome: outcome,
      learningDay: parsed,
      reaction: reaction,
      receipt: receipt.withLearningDay(dayLabel),
    );
  }
}

enum StreakOutcome { started, sameDay, extended, froze, recovered }

/// Non-punitive learner-facing reaction selected by the policy outcome.
final class StreakReaction {
  const StreakReaction({required this.title, required this.message});

  final String title;
  final String message;

  static StreakReaction forOutcome(StreakOutcome outcome) => switch (outcome) {
    StreakOutcome.started => const StreakReaction(
      title: 'A gentle start',
      message: 'Today is your first learning day.',
    ),
    StreakOutcome.sameDay => const StreakReaction(
      title: 'Learning day noted',
      message: 'Every bit of practice can belong to the same day.',
    ),
    StreakOutcome.extended => const StreakReaction(
      title: 'Your rhythm continues',
      message: 'Another learning day is part of your journey.',
    ),
    StreakOutcome.froze => const StreakReaction(
      title: 'A gentle freeze helped',
      message: 'Your learning rhythm has room for a day away.',
    ),
    StreakOutcome.recovered => const StreakReaction(
      title: 'Welcome back',
      message: 'Today is a fresh step, and your best stays with you.',
    ),
  };
}

/// Deterministic policy result embedded in the durable projection receipt.
final class StreakPolicyReceipt {
  const StreakPolicyReceipt({
    required this.ownerId,
    required this.learningDay,
    required this.policyVersion,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeCount,
  });

  final String ownerId;
  final String learningDay;
  final int policyVersion;
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeCount;

  String get receiptId => 'gentle-streak:$ownerId:$learningDay:v$policyVersion';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'receiptId': receiptId,
    'ownerId': ownerId,
    'learningDay': learningDay,
    'policyVersion': policyVersion,
    'currentStreakDays': currentStreakDays,
    'longestStreakDays': longestStreakDays,
    'freezeCount': freezeCount,
  };

  factory StreakPolicyReceipt.fromJson(Map<String, dynamic> json) {
    const keys = <String>{
      'receiptId',
      'ownerId',
      'learningDay',
      'policyVersion',
      'currentStreakDays',
      'longestStreakDays',
      'freezeCount',
    };
    final ownerId = json['ownerId'];
    final learningDay = json['learningDay'];
    final policyVersion = json['policyVersion'];
    final currentStreakDays = json['currentStreakDays'];
    final longestStreakDays = json['longestStreakDays'];
    final freezeCount = json['freezeCount'];
    if (json.keys.toSet().length != keys.length ||
        !json.keys.toSet().containsAll(keys) ||
        ownerId is! String ||
        ownerId.trim() != ownerId ||
        ownerId.isEmpty ||
        learningDay is! String ||
        policyVersion is! int ||
        policyVersion <= 0 ||
        currentStreakDays is! int ||
        currentStreakDays < 0 ||
        longestStreakDays is! int ||
        longestStreakDays < currentStreakDays ||
        freezeCount is! int ||
        freezeCount < 0) {
      throw StateError('invalid durable streak policy receipt');
    }
    final receipt = StreakPolicyReceipt(
      ownerId: ownerId,
      learningDay: learningDay,
      policyVersion: policyVersion,
      currentStreakDays: currentStreakDays,
      longestStreakDays: longestStreakDays,
      freezeCount: freezeCount,
    );
    if (json['receiptId'] != receipt.receiptId) {
      throw StateError('invalid durable streak policy receipt identity');
    }
    receipt._requireLearningDay();
    return receipt;
  }

  void _requireLearningDay() {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(learningDay)) {
      throw StateError('invalid durable streak learning day');
    }
    final parsed = DateTime.tryParse('${learningDay}T00:00:00Z');
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != learningDay) {
      throw StateError('invalid durable streak learning day');
    }
  }

  StreakPolicyReceipt withLearningDay(String value) => StreakPolicyReceipt(
    ownerId: ownerId,
    learningDay: value,
    policyVersion: policyVersion,
    currentStreakDays: currentStreakDays,
    longestStreakDays: longestStreakDays,
    freezeCount: freezeCount,
  );
}

enum GentleStreakPhase { empty, steady, grace, recovery }

/// Read-only state for the f42-owned Gentle Streak card.
final class GentleStreakSnapshot {
  const GentleStreakSnapshot({
    required this.ownerId,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeCount,
    required this.phase,
    required this.policyVersion,
  });

  factory GentleStreakSnapshot.fromState(
    StreakState state, {
    required GentleStreakPhase phase,
  }) => GentleStreakSnapshot(
    ownerId: state.ownerId,
    currentStreakDays: state.currentStreakDays,
    longestStreakDays: state.longestStreakDays,
    freezeCount: state.freezeCount,
    phase: phase,
    policyVersion: StreakPolicy.version,
  );

  final String ownerId;
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeCount;
  final GentleStreakPhase phase;
  final int policyVersion;

  bool get recoveryPromptVisible => phase == GentleStreakPhase.recovery;
}
