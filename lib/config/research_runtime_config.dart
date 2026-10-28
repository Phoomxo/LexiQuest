import '../features/learning/domain/evidence_context.dart';
import '../features/sync/domain/sync_entity.dart';

typedef ResearchRuntimeConfigLoader = ResearchRuntimeConfig Function();

/// Non-secret rollout configuration whose invariants guard research evidence
/// and the matching Firestore write contract as one fail-closed unit.
final class ResearchRuntimeConfig {
  const ResearchRuntimeConfig._({
    required this.evidenceRollout,
    required this.answerAttemptWriteVersion,
    required this.firestoreRulesRevision,
  });

  factory ResearchRuntimeConfig.legacySafe() =>
      ResearchRuntimeConfig.fromValues(
        evidenceRollout: EvidencePolicyRolloutMode.legacy.name,
        answerAttemptWriteVersion: '1',
        firestoreRulesRevision: legacyFirestoreRulesRevision,
      );

  factory ResearchRuntimeConfig.fromEnvironment({
    String evidenceRollout = const String.fromEnvironment(
      'LEXIQUEST_EVIDENCE_ROLLOUT',
      defaultValue: 'legacy',
    ),
    String answerAttemptWriteVersion = const String.fromEnvironment(
      'LEXIQUEST_ANSWER_ATTEMPT_WRITE_VERSION',
      defaultValue: '1',
    ),
    String firestoreRulesRevision = const String.fromEnvironment(
      'LEXIQUEST_FIRESTORE_RULES_REVISION',
      defaultValue: legacyFirestoreRulesRevision,
    ),
  }) => ResearchRuntimeConfig.fromValues(
    evidenceRollout: evidenceRollout,
    answerAttemptWriteVersion: answerAttemptWriteVersion,
    firestoreRulesRevision: firestoreRulesRevision,
  );

  factory ResearchRuntimeConfig.fromValues({
    required String evidenceRollout,
    required String answerAttemptWriteVersion,
    required String firestoreRulesRevision,
  }) {
    final rollout = switch (evidenceRollout) {
      'legacy' => EvidencePolicyRolloutMode.legacy,
      'shadow' => EvidencePolicyRolloutMode.shadow,
      'enforced' => EvidencePolicyRolloutMode.enforced,
      _ => throw const ResearchRuntimeConfigException(),
    };
    final writeVersion = switch (answerAttemptWriteVersion) {
      '1' => 1,
      '2' => 2,
      _ => throw const ResearchRuntimeConfigException(),
    };
    if (firestoreRulesRevision.trim() != firestoreRulesRevision ||
        firestoreRulesRevision.isEmpty ||
        firestoreRulesRevision.runes.length > 256) {
      throw const ResearchRuntimeConfigException();
    }

    final valid = switch (rollout) {
      EvidencePolicyRolloutMode.legacy =>
        writeVersion == 1 &&
            firestoreRulesRevision == legacyFirestoreRulesRevision,
      EvidencePolicyRolloutMode.shadow || EvidencePolicyRolloutMode.enforced =>
        writeVersion == 2 &&
            firestoreRulesRevision == answerAttemptV2RulesRevision,
    };
    if (!valid) throw const ResearchRuntimeConfigException();

    return ResearchRuntimeConfig._(
      evidenceRollout: rollout,
      answerAttemptWriteVersion: writeVersion,
      firestoreRulesRevision: firestoreRulesRevision,
    );
  }

  final EvidencePolicyRolloutMode evidenceRollout;
  final int answerAttemptWriteVersion;
  final String firestoreRulesRevision;

  SyncPayloadRollout get syncPayloadRollout =>
      switch (answerAttemptWriteVersion) {
        1 => const SyncPayloadRollout.productionDefault(),
        2 => const SyncPayloadRollout.answerAttemptV2(),
        _ => throw const ResearchRuntimeConfigException(),
      };
}

final class ResearchRuntimeConfigException implements Exception {
  const ResearchRuntimeConfigException();

  @override
  String toString() => 'ResearchRuntimeConfigException';
}
