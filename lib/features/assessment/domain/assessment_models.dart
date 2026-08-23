enum AssessmentPhase { pre, post }

enum AssessmentRunState { active, completed, abandoned }

final class AssessmentStartCommand {
  const AssessmentStartCommand({
    required this.runId,
    required this.learningSessionId,
    required this.studyCycleId,
    required this.phase,
    required this.instrumentId,
    required this.instrumentVersion,
    required this.formId,
    required this.formVersion,
  });

  final String runId;
  final String learningSessionId;
  final String studyCycleId;
  final AssessmentPhase phase;
  final String instrumentId;
  final String instrumentVersion;
  final String formId;
  final String formVersion;
}

final class AssessmentResponseResult {
  const AssessmentResponseResult({
    required this.sourceEvidenceId,
    required this.responseCode,
    required this.isCorrect,
    required this.inserted,
  });

  final String sourceEvidenceId;
  final String responseCode;
  final bool isCorrect;
  final bool inserted;
}

final class AssessmentRun {
  factory AssessmentRun({
    required String id,
    required String ownerId,
    required String learningSessionId,
    required String studyCycleId,
    required AssessmentPhase phase,
    required AssessmentRunState state,
    required String protocolId,
    required String protocolVersion,
    required String experimentId,
    required int experimentVersion,
    required String assignmentId,
    required String cohort,
    required int consentVersion,
    required DateTime consentDecidedAtUtc,
    required String instrumentId,
    required String instrumentVersion,
    required String formId,
    required String formVersion,
    required String instrumentChecksumSha256,
    required String formChecksumSha256,
    required String appVersion,
    required String buildId,
    required int databaseSchemaVersion,
    required String contentRevision,
    required String evidencePolicyVersion,
    required String featureContractRevision,
    required String featureContractHash,
    required DateTime startedAtUtc,
    required DateTime? completedAtUtc,
    required DateTime? abandonedAtUtc,
  }) {
    final run = AssessmentRun._(
      id: id,
      ownerId: ownerId,
      learningSessionId: learningSessionId,
      studyCycleId: studyCycleId,
      phase: phase,
      state: state,
      protocolId: protocolId,
      protocolVersion: protocolVersion,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      assignmentId: assignmentId,
      cohort: cohort,
      consentVersion: consentVersion,
      consentDecidedAtUtc: consentDecidedAtUtc,
      instrumentId: instrumentId,
      instrumentVersion: instrumentVersion,
      formId: formId,
      formVersion: formVersion,
      instrumentChecksumSha256: instrumentChecksumSha256,
      formChecksumSha256: formChecksumSha256,
      appVersion: appVersion,
      buildId: buildId,
      databaseSchemaVersion: databaseSchemaVersion,
      contentRevision: contentRevision,
      evidencePolicyVersion: evidencePolicyVersion,
      featureContractRevision: featureContractRevision,
      featureContractHash: featureContractHash,
      startedAtUtc: startedAtUtc,
      completedAtUtc: completedAtUtc,
      abandonedAtUtc: abandonedAtUtc,
    );
    run._validate();
    return run;
  }

  const AssessmentRun._({
    required this.id,
    required this.ownerId,
    required this.learningSessionId,
    required this.studyCycleId,
    required this.phase,
    required this.state,
    required this.protocolId,
    required this.protocolVersion,
    required this.experimentId,
    required this.experimentVersion,
    required this.assignmentId,
    required this.cohort,
    required this.consentVersion,
    required this.consentDecidedAtUtc,
    required this.instrumentId,
    required this.instrumentVersion,
    required this.formId,
    required this.formVersion,
    required this.instrumentChecksumSha256,
    required this.formChecksumSha256,
    required this.appVersion,
    required this.buildId,
    required this.databaseSchemaVersion,
    required this.contentRevision,
    required this.evidencePolicyVersion,
    required this.featureContractRevision,
    required this.featureContractHash,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.abandonedAtUtc,
  });

  static const int maxCanonicalRunes = 256;
  static const int maxRunIdRunes = 240;
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  final String id;
  final String ownerId;
  final String learningSessionId;
  final String studyCycleId;
  final AssessmentPhase phase;
  final AssessmentRunState state;
  final String protocolId;
  final String protocolVersion;
  final String experimentId;
  final int experimentVersion;
  final String assignmentId;
  final String cohort;
  final int consentVersion;
  final DateTime consentDecidedAtUtc;
  final String instrumentId;
  final String instrumentVersion;
  final String formId;
  final String formVersion;
  final String instrumentChecksumSha256;
  final String formChecksumSha256;
  final String appVersion;
  final String buildId;
  final int databaseSchemaVersion;
  final String contentRevision;
  final String evidencePolicyVersion;
  final String featureContractRevision;
  final String featureContractHash;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final DateTime? abandonedAtUtc;

  AssessmentRun withTerminalState({
    required AssessmentRunState state,
    required DateTime terminalAtUtc,
  }) {
    if (state == AssessmentRunState.active) {
      throw ArgumentError.value(state, 'state', 'must be terminal');
    }
    return AssessmentRun(
      id: id,
      ownerId: ownerId,
      learningSessionId: learningSessionId,
      studyCycleId: studyCycleId,
      phase: phase,
      state: state,
      protocolId: protocolId,
      protocolVersion: protocolVersion,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      assignmentId: assignmentId,
      cohort: cohort,
      consentVersion: consentVersion,
      consentDecidedAtUtc: consentDecidedAtUtc,
      instrumentId: instrumentId,
      instrumentVersion: instrumentVersion,
      formId: formId,
      formVersion: formVersion,
      instrumentChecksumSha256: instrumentChecksumSha256,
      formChecksumSha256: formChecksumSha256,
      appVersion: appVersion,
      buildId: buildId,
      databaseSchemaVersion: databaseSchemaVersion,
      contentRevision: contentRevision,
      evidencePolicyVersion: evidencePolicyVersion,
      featureContractRevision: featureContractRevision,
      featureContractHash: featureContractHash,
      startedAtUtc: startedAtUtc,
      completedAtUtc: state == AssessmentRunState.completed
          ? terminalAtUtc
          : null,
      abandonedAtUtc: state == AssessmentRunState.abandoned
          ? terminalAtUtc
          : null,
    );
  }

  void _validate() {
    validateRunId(id);
    final canonicalValues = <String, String>{
      'ownerId': ownerId,
      'learningSessionId': learningSessionId,
      'studyCycleId': studyCycleId,
      'protocolId': protocolId,
      'protocolVersion': protocolVersion,
      'experimentId': experimentId,
      'assignmentId': assignmentId,
      'cohort': cohort,
      'instrumentId': instrumentId,
      'instrumentVersion': instrumentVersion,
      'formId': formId,
      'formVersion': formVersion,
      'appVersion': appVersion,
      'buildId': buildId,
      'contentRevision': contentRevision,
      'evidencePolicyVersion': evidencePolicyVersion,
      'featureContractRevision': featureContractRevision,
    };
    for (final entry in canonicalValues.entries) {
      validateCanonicalText(entry.value, entry.key);
    }
    _validatePositive(experimentVersion, 'experimentVersion');
    _validatePositive(consentVersion, 'consentVersion');
    _validatePositive(databaseSchemaVersion, 'databaseSchemaVersion');
    _validateSha256(instrumentChecksumSha256, 'instrumentChecksumSha256');
    _validateSha256(formChecksumSha256, 'formChecksumSha256');
    _validateSha256(featureContractHash, 'featureContractHash');
    validateUtcTimestamp(consentDecidedAtUtc, 'consentDecidedAtUtc');
    validateUtcTimestamp(startedAtUtc, 'startedAtUtc');
    if (consentDecidedAtUtc.isAfter(startedAtUtc)) {
      throw ArgumentError.value(
        consentDecidedAtUtc,
        'consentDecidedAtUtc',
        'must not be after startedAtUtc',
      );
    }

    switch (state) {
      case AssessmentRunState.active:
        if (completedAtUtc != null || abandonedAtUtc != null) {
          throw ArgumentError.value(
            state,
            'state',
            'Active must not have a terminal timestamp',
          );
        }
        break;
      case AssessmentRunState.completed:
        if (completedAtUtc == null || abandonedAtUtc != null) {
          throw ArgumentError.value(
            state,
            'state',
            'Completed requires only completedAtUtc',
          );
        }
        _validateTerminalTimestamp(completedAtUtc!, 'completedAtUtc');
        break;
      case AssessmentRunState.abandoned:
        if (abandonedAtUtc == null || completedAtUtc != null) {
          throw ArgumentError.value(
            state,
            'state',
            'Abandoned requires only abandonedAtUtc',
          );
        }
        _validateTerminalTimestamp(abandonedAtUtc!, 'abandonedAtUtc');
        break;
    }
  }

  void _validateTerminalTimestamp(DateTime value, String argumentName) {
    validateUtcTimestamp(value, argumentName);
    if (value.isBefore(startedAtUtc)) {
      throw ArgumentError.value(
        value,
        argumentName,
        'must not be before startedAtUtc',
      );
    }
  }

  static void validateCanonicalText(String value, String argumentName) {
    if (value.isEmpty ||
        value != value.trim() ||
        value.runes.length > maxCanonicalRunes) {
      throw ArgumentError.value(value, argumentName, 'must be canonical');
    }
  }

  static void validateRunId(String value) {
    if (value.isEmpty ||
        value != value.trim() ||
        value.runes.length > maxRunIdRunes) {
      throw ArgumentError.value(
        value,
        'runId',
        'must be canonical and at most $maxRunIdRunes runes',
      );
    }
  }

  static void _validatePositive(int value, String argumentName) {
    if (value <= 0) {
      throw ArgumentError.value(value, argumentName, 'must be positive');
    }
  }

  static void _validateSha256(String value, String argumentName) {
    if (!_sha256Pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        argumentName,
        'must be a lowercase SHA-256 digest',
      );
    }
  }

  static void validateUtcTimestamp(DateTime value, String argumentName) {
    if (!value.isUtc ||
        value.millisecondsSinceEpoch < 0 ||
        value.microsecondsSinceEpoch % Duration.microsecondsPerMillisecond !=
            0) {
      throw ArgumentError.value(
        value,
        argumentName,
        'must be UTC, millisecond-precise, and not before the Unix epoch',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AssessmentRun &&
            other.id == id &&
            other.ownerId == ownerId &&
            other.learningSessionId == learningSessionId &&
            other.studyCycleId == studyCycleId &&
            other.phase == phase &&
            other.state == state &&
            other.protocolId == protocolId &&
            other.protocolVersion == protocolVersion &&
            other.experimentId == experimentId &&
            other.experimentVersion == experimentVersion &&
            other.assignmentId == assignmentId &&
            other.cohort == cohort &&
            other.consentVersion == consentVersion &&
            other.consentDecidedAtUtc == consentDecidedAtUtc &&
            other.instrumentId == instrumentId &&
            other.instrumentVersion == instrumentVersion &&
            other.formId == formId &&
            other.formVersion == formVersion &&
            other.instrumentChecksumSha256 == instrumentChecksumSha256 &&
            other.formChecksumSha256 == formChecksumSha256 &&
            other.appVersion == appVersion &&
            other.buildId == buildId &&
            other.databaseSchemaVersion == databaseSchemaVersion &&
            other.contentRevision == contentRevision &&
            other.evidencePolicyVersion == evidencePolicyVersion &&
            other.featureContractRevision == featureContractRevision &&
            other.featureContractHash == featureContractHash &&
            other.startedAtUtc == startedAtUtc &&
            other.completedAtUtc == completedAtUtc &&
            other.abandonedAtUtc == abandonedAtUtc;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    ownerId,
    learningSessionId,
    studyCycleId,
    phase,
    state,
    protocolId,
    protocolVersion,
    experimentId,
    experimentVersion,
    assignmentId,
    cohort,
    consentVersion,
    consentDecidedAtUtc,
    instrumentId,
    instrumentVersion,
    formId,
    formVersion,
    instrumentChecksumSha256,
    formChecksumSha256,
    appVersion,
    buildId,
    databaseSchemaVersion,
    contentRevision,
    evidencePolicyVersion,
    featureContractRevision,
    featureContractHash,
    startedAtUtc,
    completedAtUtc,
    abandonedAtUtc,
  ]);
}
