import 'evidence_context.dart';
import 'lesson_mode.dart';

enum HintKind { strategy, context }

enum HintAvailability { available, unavailable, unknown }

final class HintStep {
  const HintStep({
    required this.level,
    required this.kind,
    required this.content,
  });

  final int level;
  final HintKind kind;
  final String content;
}

final class HintState {
  const HintState._({
    required this.availability,
    required this.hintLevel,
    required this.revealedHints,
    required this.isExhausted,
  });

  const HintState.unknown()
    : availability = HintAvailability.unknown,
      hintLevel = 0,
      revealedHints = const <HintStep>[],
      isExhausted = true;

  final HintAvailability availability;
  final int hintLevel;
  final List<HintStep> revealedHints;
  final bool isExhausted;

  bool get contextRevealed =>
      revealedHints.any((hint) => hint.kind == HintKind.context);
}

final class HintRevealResult {
  const HintRevealResult({required this.state, required this.changed});

  final HintState state;
  final bool changed;
}

final class HintUsageSnapshot {
  const HintUsageSnapshot.known(int hintLevel)
    : assert(hintLevel >= 0),
      availability = HintAvailability.available,
      hintLevel = hintLevel;

  const HintUsageSnapshot.unavailable()
    : availability = HintAvailability.unavailable,
      hintLevel = 0;

  const HintUsageSnapshot.unknown()
    : availability = HintAvailability.unknown,
      hintLevel = null;

  final HintAvailability availability;
  final int? hintLevel;

  factory HintUsageSnapshot.fromRecordedLevel(int hintLevel) => hintLevel < 0
      ? const HintUsageSnapshot.unknown()
      : HintUsageSnapshot.known(hintLevel);
}

final class HintEvidenceClassification {
  const HintEvidenceClassification({
    required this.evidenceClass,
    required this.hintLevel,
  });

  final EvidenceClass evidenceClass;
  final int hintLevel;
}

final class HintPolicy {
  factory HintPolicy.staged({
    required String strategy,
    required String context,
  }) => HintPolicy._(
    _requiredContent(strategy, 'strategy'),
    _requiredContent(context, 'context'),
    true,
  );

  const HintPolicy._(this._strategy, this._context, this._available);

  const HintPolicy.unavailable()
    : _strategy = '',
      _context = '',
      _available = false;

  final String _strategy;
  final String _context;
  final bool _available;

  static String _requiredContent(String value, String field) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(value, field, 'must be nonblank and trimmed');
    }
    return value;
  }

  int get maximumHintLevel => _available ? 2 : 0;

  List<HintStep> get _steps => <HintStep>[
    HintStep(level: 1, kind: HintKind.strategy, content: _strategy),
    HintStep(level: 2, kind: HintKind.context, content: _context),
  ];

  HintState get initialState => _available
      ? const HintState._(
          availability: HintAvailability.available,
          hintLevel: 0,
          revealedHints: <HintStep>[],
          isExhausted: false,
        )
      : const HintState._(
          availability: HintAvailability.unavailable,
          hintLevel: 0,
          revealedHints: <HintStep>[],
          isExhausted: true,
        );

  HintRevealResult revealNext(HintState state) {
    if (state.availability == HintAvailability.unknown) {
      return HintRevealResult(state: state, changed: false);
    }
    if (!_isValid(state)) {
      const unknown = HintState.unknown();
      return const HintRevealResult(state: unknown, changed: true);
    }
    if (!_available || state.isExhausted) {
      return HintRevealResult(state: state, changed: false);
    }
    final steps = _steps;
    final next = steps[state.hintLevel];
    final revealed = List<HintStep>.unmodifiable(<HintStep>[
      ...state.revealedHints,
      next,
    ]);
    final nextState = HintState._(
      availability: HintAvailability.available,
      hintLevel: next.level,
      revealedHints: revealed,
      isExhausted: next.level == maximumHintLevel,
    );
    return HintRevealResult(state: nextState, changed: true);
  }

  HintUsageSnapshot snapshot(HintState state) {
    if (!_isValid(state)) return const HintUsageSnapshot.unknown();
    return switch (state.availability) {
      HintAvailability.available => HintUsageSnapshot.known(state.hintLevel),
      HintAvailability.unavailable => const HintUsageSnapshot.unavailable(),
      HintAvailability.unknown => const HintUsageSnapshot.unknown(),
    };
  }

  static HintEvidenceClassification classifyEvidence({
    required EvidenceClass declaredClass,
    required HintUsageSnapshot hint,
  }) {
    final recordedLevel = switch (hint.availability) {
      HintAvailability.available => hint.hintLevel,
      HintAvailability.unavailable => 0,
      HintAvailability.unknown => null,
    };
    if (recordedLevel == null || recordedLevel < 0) {
      return const HintEvidenceClassification(
        evidenceClass: EvidenceClass.guidedPractice,
        hintLevel: 2,
      );
    }
    return HintEvidenceClassification(
      evidenceClass:
          declaredClass == EvidenceClass.independentRecall && recordedLevel > 0
          ? EvidenceClass.guidedPractice
          : declaredClass,
      hintLevel: recordedLevel,
    );
  }

  static EvidenceContext applyToEvidence(
    EvidenceContext evidence,
    HintUsageSnapshot hint,
  ) {
    final classification = classifyEvidence(
      declaredClass: evidence.evidenceClass,
      hint: hint,
    );
    final json = Map<String, Object?>.of(evidence.toJson())
      ..['evidenceClass'] = classification.evidenceClass.name
      ..['hintLevel'] = classification.hintLevel;
    return EvidenceContext.fromJson(json);
  }

  bool _isValid(HintState state) {
    if (state.availability == HintAvailability.unknown) return false;
    if (!_available) {
      return state.availability == HintAvailability.unavailable &&
          state.hintLevel == 0 &&
          state.revealedHints.isEmpty &&
          state.isExhausted;
    }
    if (state.availability != HintAvailability.available ||
        state.hintLevel < 0 ||
        state.hintLevel > maximumHintLevel ||
        state.revealedHints.length != state.hintLevel ||
        state.isExhausted != (state.hintLevel == maximumHintLevel)) {
      return false;
    }
    final steps = _steps;
    for (var index = 0; index < state.revealedHints.length; index += 1) {
      final actual = state.revealedHints[index];
      final expected = steps[index];
      if (actual.level != expected.level ||
          actual.kind != expected.kind ||
          actual.content != expected.content) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is HintPolicy &&
      other._available == _available &&
      other._strategy == _strategy &&
      other._context == _context;

  @override
  int get hashCode => Object.hash(_available, _strategy, _context);
}

abstract interface class HintSupportingLessonModeAdapter
    implements LessonModeAdapter {
  HintPolicy get hintPolicy;
}
