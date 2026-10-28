/// Supplemental practice only. Never a canonical answer or scoring command.
final class GuidedRepairState {
  const GuidedRepairState._(
    this.originId,
    this.hintLevel,
    this.attempts,
    this.correct,
    this.exited,
  );

  factory GuidedRepairState.start({
    required String originId,
    required int priorHintLevel,
  }) {
    if (originId.trim().isEmpty || originId.length > 256) {
      throw ArgumentError.value(originId, 'originId');
    }
    return GuidedRepairState._(
      originId,
      priorHintLevel < 0 || priorHintLevel > 2 ? 2 : priorHintLevel,
      0,
      false,
      false,
    );
  }
  static const maximumAttempts = 3;
  static const maximumHints = 2;
  final String originId;
  final int hintLevel;
  final int attempts;
  final bool correct;
  final bool exited;
  String get evidenceClass => 'guidedPractice';
  bool get terminal => correct || exited || attempts == maximumAttempts;

  GuidedRepairState revealHint() {
    if (terminal || hintLevel >= maximumHints) {
      throw StateError('Hint budget exhausted');
    }
    return GuidedRepairState._(
      originId,
      hintLevel + 1,
      attempts,
      correct,
      exited,
    );
  }

  GuidedRepairState answer({required bool correct}) {
    if (terminal) throw StateError('Repair is complete');
    return GuidedRepairState._(
      originId,
      hintLevel,
      attempts + 1,
      correct,
      false,
    );
  }

  GuidedRepairState exit() =>
      GuidedRepairState._(originId, hintLevel, attempts, correct, true);
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'originId': originId,
    'hintLevel': hintLevel,
    'attempts': attempts,
    'correct': correct,
    'exited': exited,
    'evidenceClass': evidenceClass,
  };
  factory GuidedRepairState.fromJson(Map<String, Object?> json) {
    if (json.length != 7 ||
        json['schemaVersion'] != 1 ||
        json['originId'] is! String ||
        (json['originId'] as String).trim().isEmpty ||
        (json['originId'] as String).length > 256 ||
        json['hintLevel'] is! int ||
        (json['hintLevel'] as int) < 0 ||
        (json['hintLevel'] as int) > maximumHints ||
        json['attempts'] is! int ||
        (json['attempts'] as int) < 0 ||
        (json['attempts'] as int) > maximumAttempts ||
        json['correct'] is! bool ||
        json['exited'] is! bool ||
        (json['correct'] == true && json['attempts'] == 0) ||
        json['evidenceClass'] != 'guidedPractice') {
      throw const FormatException('Unsupported guided repair state');
    }
    return GuidedRepairState._(
      json['originId'] as String,
      json['hintLevel'] as int,
      json['attempts'] as int,
      json['correct'] as bool,
      json['exited'] as bool,
    );
  }
}
