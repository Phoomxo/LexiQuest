import 'pair_matching_launch.dart';
import 'pair_matching_checkpoint_budget.dart';
import 'pair_matching_plan.dart';

enum PairTimerMode {
  off,
  running,
  timeoutDecision,
  extendedRunning,
  continuedUntimed,
}

enum PairPauseReason {
  recovery,
  boardUnavailable,
  background,
  modal,
  persistence,
  narration,
  clockFault,
  capacity,
}

/// Folded active time only. No process-local monotonic anchor is serialized.
final class PairTimerState {
  PairTimerState({
    required this.mode,
    required this.remainingActiveMs,
    this.elapsedActiveMs = 0,
    this.interactiveElapsedMs,
    this.extensionUsed = false,
    Set<PairPauseReason> reasons = const {},
    this.lastOperationId,
    this.lastFingerprint,
  }) : reasons = Set.unmodifiable(reasons);
  factory PairTimerState.initial(PairTimerPreset preset) => PairTimerState(
    mode: preset == PairTimerPreset.off
        ? PairTimerMode.off
        : PairTimerMode.running,
    remainingActiveMs: switch (preset) {
      PairTimerPreset.off => 0,
      PairTimerPreset.seconds60 => 60000,
      PairTimerPreset.seconds90 => 90000,
      PairTimerPreset.seconds120 => 120000,
    },
  );
  final PairTimerMode mode;
  final int remainingActiveMs, elapsedActiveMs;

  /// Full observed interactive duration; null means coverage is unavailable.
  /// It is descriptive only and never feeds learning-time or rewards.
  final int? interactiveElapsedMs;
  final bool extensionUsed;
  final Set<PairPauseReason> reasons;
  final String? lastOperationId, lastFingerprint;
  bool get timed =>
      mode == PairTimerMode.running || mode == PairTimerMode.extendedRunning;
  int get decisionReserve => timed
      ? 2
      : mode == PairTimerMode.timeoutDecision ||
            reasons.contains(PairPauseReason.clockFault)
      ? 1
      : 0;
  PairTimerState copy({
    PairTimerMode? mode,
    int? remainingActiveMs,
    int? elapsedActiveMs,
    int? interactiveElapsedMs,
    bool loseInteractiveCoverage = false,
    bool? extensionUsed,
    Set<PairPauseReason>? reasons,
    String? lastOperationId,
    String? lastFingerprint,
  }) => PairTimerState(
    mode: mode ?? this.mode,
    remainingActiveMs: remainingActiveMs ?? this.remainingActiveMs,
    elapsedActiveMs: elapsedActiveMs ?? this.elapsedActiveMs,
    interactiveElapsedMs: loseInteractiveCoverage
        ? null
        : interactiveElapsedMs ?? this.interactiveElapsedMs,
    extensionUsed: extensionUsed ?? this.extensionUsed,
    reasons: Set.unmodifiable(reasons ?? this.reasons),
    lastOperationId: lastOperationId ?? this.lastOperationId,
    lastFingerprint: lastFingerprint ?? this.lastFingerprint,
  );
  Map<String, Object?> toJson({bool includeInteractiveElapsed = true}) => {
    'mode': mode.name,
    'remainingActiveMs': remainingActiveMs,
    'elapsedActiveMs': elapsedActiveMs,
    if (includeInteractiveElapsed) 'interactiveElapsedMs': interactiveElapsedMs,
    'extensionUsed': extensionUsed,
    'reasons': reasons.map((r) => r.name).toList()..sort(),
    'lastOperationId': lastOperationId,
    'lastFingerprint': lastFingerprint,
  };
  static PairTimerState fromJson(
    Object? value, {
    bool includesInteractiveElapsed = true,
  }) {
    final j = pairJson(value, {
      'mode',
      'remainingActiveMs',
      'elapsedActiveMs',
      if (includesInteractiveElapsed) 'interactiveElapsedMs',
      'extensionUsed',
      'reasons',
      'lastOperationId',
      'lastFingerprint',
    });
    final state = PairTimerState(
      mode: PairTimerMode.values.byName(j['mode'] as String),
      remainingActiveMs: j['remainingActiveMs'] as int,
      elapsedActiveMs: j['elapsedActiveMs'] as int,
      interactiveElapsedMs: includesInteractiveElapsed
          ? j['interactiveElapsedMs'] as int?
          : null,
      extensionUsed: j['extensionUsed'] as bool,
      reasons: Set.unmodifiable(
        (j['reasons'] as List).map(
          (v) => PairPauseReason.values.byName(v as String),
        ),
      ),
      lastOperationId: j['lastOperationId'] as String?,
      lastFingerprint: j['lastFingerprint'] as String?,
    );
    if (state.remainingActiveMs < 0 ||
        state.remainingActiveMs > 120000 ||
        state.elapsedActiveMs < 0 ||
        state.elapsedActiveMs > PairMatchingCheckpointBudget.maximumCounter ||
        (state.interactiveElapsedMs != null &&
            (state.interactiveElapsedMs! < 0 ||
                state.interactiveElapsedMs! >
                    PairMatchingCheckpointBudget.maximumCounter)) ||
        (state.mode == PairTimerMode.timeoutDecision &&
            state.remainingActiveMs != 0) ||
        ((state.mode == PairTimerMode.off ||
                state.mode == PairTimerMode.continuedUntimed) &&
            state.remainingActiveMs != 0) ||
        (state.mode == PairTimerMode.extendedRunning &&
            (!state.extensionUsed || state.remainingActiveMs > 30000)) ||
        (state.lastOperationId == null) != (state.lastFingerprint == null) ||
        (state.lastOperationId != null &&
            (state.lastOperationId!.length > 128 ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(state.lastFingerprint!))) ||
        (j['reasons'] as List).length != state.reasons.length) {
      throw const FormatException('Invalid Pair timer');
    }
    return state;
  }
}

final class PairPauseLease {
  PairPauseLease._(this.reason);
  final PairPauseReason reason;
}

/// One runtime owner. Leases are identity objects, never transferable between
/// restored clocks; old callbacks cannot release a newer reason's ownership.
final class PairActiveClock {
  PairActiveClock(this._state, this.monotonicMicros) {
    _recovery = pause(PairPauseReason.recovery);
    for (final reason in _state.reasons) {
      if (reason == PairPauseReason.clockFault) {
        _leases.add(PairPauseLease._(reason));
      }
    }
  }
  final int Function() monotonicMicros;
  PairTimerState _state;
  final _leases = <PairPauseLease>{};
  late final PairPauseLease _recovery;
  int? _anchor;
  int _carryMicros = 0;
  bool get isPaused => _leases.isNotEmpty;
  Set<PairPauseReason> get reasons =>
      Set.unmodifiable(_leases.map((l) => l.reason));
  PairTimerState get value {
    fold();
    return _state.copy(reasons: reasons);
  }

  /// Does not sample or mutate the clock; operational queries use this view.
  PairTimerState get snapshot => _state.copy(reasons: reasons);

  void replace(PairTimerState value) {
    _state = value;
    if (value.mode == PairTimerMode.continuedUntimed) {
      _leases.removeWhere((l) => l.reason == PairPauseReason.clockFault);
    }
    _anchor = null;
    _open();
  }

  bool owns(PairPauseLease lease) => _leases.contains(lease);
  void resumeInteraction() => release(_recovery);
  PairPauseLease pause(PairPauseReason reason) {
    fold();
    final lease = PairPauseLease._(reason);
    _leases.add(lease);
    _anchor = null;
    return lease;
  }

  void release(PairPauseLease lease) {
    if (!_leases.remove(lease)) return;
    _open();
  }

  void _open() {
    if (isPaused || !_measuring || _anchor != null) return;
    try {
      final n = monotonicMicros();
      if (n < 0) throw StateError('clock');
      _anchor = n;
    } catch (_) {
      _fault();
    }
  }

  void _fault() {
    _anchor = null;
    _state = _state.copy(loseInteractiveCoverage: true);
    if (_state.timed && !reasons.contains(PairPauseReason.clockFault)) {
      _leases.add(PairPauseLease._(PairPauseReason.clockFault));
    }
  }

  void fold() {
    final anchor = _anchor;
    if (anchor == null || isPaused || !_measuring) return;
    try {
      final now = monotonicMicros();
      if (now < anchor) {
        _fault();
        return;
      }
      final total = now - anchor + _carryMicros;
      final delta = total ~/ 1000;
      final used = _state.timed && delta > _state.remainingActiveMs
          ? _state.remainingActiveMs
          : delta;
      final interactive = _state.interactiveElapsedMs;
      final overflow =
          interactive != null &&
          interactive > PairMatchingCheckpointBudget.maximumCounter - used;
      _state = _state.copy(
        remainingActiveMs: _state.timed
            ? _state.remainingActiveMs - used
            : _state.remainingActiveMs,
        elapsedActiveMs: _state.timed
            ? _state.elapsedActiveMs + used
            : _state.elapsedActiveMs,
        interactiveElapsedMs: interactive == null || overflow
            ? null
            : interactive + used,
        loseInteractiveCoverage: overflow,
      );
      _carryMicros = _state.timed && _state.remainingActiveMs == 0
          ? 0
          : total % 1000;
      _anchor = now;
    } catch (_) {
      _fault();
    }
  }

  bool get _measuring =>
      _state.timed ||
      (_state.interactiveElapsedMs != null &&
          (_state.mode == PairTimerMode.off ||
              _state.mode == PairTimerMode.continuedUntimed));

  /// Drop only the optional measurement when coverage cannot be guaranteed.
  /// Timed challenge accounting and its pause/recovery policy remain intact.
  void loseInteractiveCoverage() {
    fold();
    _state = _state.copy(loseInteractiveCoverage: true);
    if (!_state.timed) _anchor = null;
  }
}
