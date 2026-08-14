import 'feature_contract_models.dart';

final class AuthorityCompatibilityProfile {
  AuthorityCompatibilityProfile._({
    required this.id,
    required Set<DomainAuthority> writableAuthorities,
  }) : writableAuthorities = Set<DomainAuthority>.unmodifiable(
         writableAuthorities,
       );

  final AuthorityProfileId id;
  final Set<DomainAuthority> writableAuthorities;
}

final class EvidenceCompatibilityProfile {
  EvidenceCompatibilityProfile._({
    required this.id,
    required Set<ContractEvidenceClass> evidenceClasses,
  }) : evidenceClasses = Set<ContractEvidenceClass>.unmodifiable(
         evidenceClasses,
       );

  final EvidenceProfileId id;
  final Set<ContractEvidenceClass> evidenceClasses;
}

final class LifecycleCompatibilityProfile {
  const LifecycleCompatibilityProfile._({
    required this.id,
    required this.label,
  });

  final LifecycleProfileId id;
  final String label;
}

final class ActivationCompatibilityProfile {
  const ActivationCompatibilityProfile._({
    required this.id,
    required this.kind,
  });

  final ActivationProfileId id;
  final ActivationKind kind;
}

final class RolloutCompatibilityProfile {
  const RolloutCompatibilityProfile._({required this.id, required this.label});

  final RolloutProfileId id;
  final String label;
}

final class RollbackCompatibilityProfile {
  const RollbackCompatibilityProfile._({required this.id, required this.label});

  final RollbackProfileId id;
  final String label;
}

const readOnlyAuthorityProfileId = AuthorityProfileId('authority.read-only');
const vocabularyWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.vocabulary',
);
const responseEvidenceWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.response-evidence',
);
const masterySrsWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.mastery-srs',
);
const assessmentWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.assessment',
);
const streakWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.streak',
);
const lifetimeXpWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.lifetime-xp',
);
const spendableCoinsWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.spendable-coins',
);
const questWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.quest',
);
const historyWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.history',
);
const downloadStateWriterAuthorityProfileId = AuthorityProfileId(
  'authority.writer.download-state',
);

final Map<AuthorityProfileId, AuthorityCompatibilityProfile> authorityProfiles =
    Map<AuthorityProfileId, AuthorityCompatibilityProfile>.unmodifiable(
      <AuthorityProfileId, AuthorityCompatibilityProfile>{
        readOnlyAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: readOnlyAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{},
        ),
        vocabularyWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: vocabularyWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.vocabulary,
          },
        ),
        responseEvidenceWriterAuthorityProfileId:
            AuthorityCompatibilityProfile._(
              id: responseEvidenceWriterAuthorityProfileId,
              writableAuthorities: const <DomainAuthority>{
                DomainAuthority.responseEvidence,
              },
            ),
        masterySrsWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: masterySrsWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.masterySrs,
          },
        ),
        assessmentWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: assessmentWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.assessment,
          },
        ),
        streakWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: streakWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{DomainAuthority.streak},
        ),
        lifetimeXpWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: lifetimeXpWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.lifetimeXp,
          },
        ),
        spendableCoinsWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: spendableCoinsWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.spendableCoins,
          },
        ),
        questWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: questWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{DomainAuthority.quest},
        ),
        historyWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: historyWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{DomainAuthority.history},
        ),
        downloadStateWriterAuthorityProfileId: AuthorityCompatibilityProfile._(
          id: downloadStateWriterAuthorityProfileId,
          writableAuthorities: const <DomainAuthority>{
            DomainAuthority.downloadState,
          },
        ),
      },
    );

final Map<DomainAuthority, AuthorityProfileId> singleWriterAuthorityMatrix =
    Map<DomainAuthority, AuthorityProfileId>.unmodifiable(
      const <DomainAuthority, AuthorityProfileId>{
        DomainAuthority.vocabulary: vocabularyWriterAuthorityProfileId,
        DomainAuthority.responseEvidence:
            responseEvidenceWriterAuthorityProfileId,
        DomainAuthority.masterySrs: masterySrsWriterAuthorityProfileId,
        DomainAuthority.assessment: assessmentWriterAuthorityProfileId,
        DomainAuthority.streak: streakWriterAuthorityProfileId,
        DomainAuthority.lifetimeXp: lifetimeXpWriterAuthorityProfileId,
        DomainAuthority.spendableCoins: spendableCoinsWriterAuthorityProfileId,
        DomainAuthority.quest: questWriterAuthorityProfileId,
        DomainAuthority.history: historyWriterAuthorityProfileId,
        DomainAuthority.downloadState: downloadStateWriterAuthorityProfileId,
      },
    );

const noEvidenceProfileId = EvidenceProfileId('evidence.none');
const assessmentEvidenceProfileId = EvidenceProfileId('evidence.assessment');
const independentRecallEvidenceProfileId = EvidenceProfileId(
  'evidence.independent-recall',
);
const recognitionEvidenceProfileId = EvidenceProfileId('evidence.recognition');
const guidedPracticeEvidenceProfileId = EvidenceProfileId(
  'evidence.guided-practice',
);
const pronunciationEvidenceProfileId = EvidenceProfileId(
  'evidence.pronunciation',
);
const exposureEvidenceProfileId = EvidenceProfileId('evidence.exposure');
const recreationalEvidenceProfileId = EvidenceProfileId(
  'evidence.recreational',
);
const flashcardEvidenceProfileId = EvidenceProfileId(
  'evidence.flashcard-exposure-and-recall',
);
const clozeEvidenceProfileId = EvidenceProfileId(
  'evidence.cloze-recognition-and-recall',
);
const nativeModesEvidenceProfileId = EvidenceProfileId('evidence.native-modes');

final Map<EvidenceProfileId, EvidenceCompatibilityProfile> evidenceProfiles =
    Map<EvidenceProfileId, EvidenceCompatibilityProfile>.unmodifiable(
      <EvidenceProfileId, EvidenceCompatibilityProfile>{
        noEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: noEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{},
        ),
        assessmentEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: assessmentEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.assessment,
          },
        ),
        independentRecallEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: independentRecallEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.independentRecall,
          },
        ),
        recognitionEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: recognitionEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.recognition,
          },
        ),
        guidedPracticeEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: guidedPracticeEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.guidedPractice,
          },
        ),
        pronunciationEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: pronunciationEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.pronunciation,
          },
        ),
        exposureEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: exposureEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.exposure,
          },
        ),
        recreationalEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: recreationalEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.recreational,
          },
        ),
        flashcardEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: flashcardEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.exposure,
            ContractEvidenceClass.independentRecall,
          },
        ),
        clozeEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: clozeEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.recognition,
            ContractEvidenceClass.independentRecall,
          },
        ),
        nativeModesEvidenceProfileId: EvidenceCompatibilityProfile._(
          id: nativeModesEvidenceProfileId,
          evidenceClasses: const <ContractEvidenceClass>{
            ContractEvidenceClass.independentRecall,
            ContractEvidenceClass.recognition,
            ContractEvidenceClass.pronunciation,
            ContractEvidenceClass.exposure,
            ContractEvidenceClass.recreational,
          },
        ),
      },
    );

const existingLifecycleProfileId = LifecycleProfileId('lifecycle.existing');
const partialLifecycleProfileId = LifecycleProfileId('lifecycle.partial');
const newCapabilityLifecycleProfileId = LifecycleProfileId(
  'lifecycle.new-capability',
);
const experimentalLifecycleProfileId = LifecycleProfileId(
  'lifecycle.experimental',
);

const lifecycleProfiles = <LifecycleProfileId, LifecycleCompatibilityProfile>{
  existingLifecycleProfileId: LifecycleCompatibilityProfile._(
    id: existingLifecycleProfileId,
    label: 'Existing baseline capability',
  ),
  partialLifecycleProfileId: LifecycleCompatibilityProfile._(
    id: partialLifecycleProfileId,
    label: 'Partially covered baseline capability',
  ),
  newCapabilityLifecycleProfileId: LifecycleCompatibilityProfile._(
    id: newCapabilityLifecycleProfileId,
    label: 'New contracted capability',
  ),
  experimentalLifecycleProfileId: LifecycleCompatibilityProfile._(
    id: experimentalLifecycleProfileId,
    label: 'Experimental candidate outside the 8/44 catalog',
  ),
};

const foundationActivationProfileId = ActivationProfileId(
  'activation.always-on-foundation',
);
const runtimeFlaggedActivationProfileId = ActivationProfileId(
  'activation.runtime-flagged',
);
const protocolAssignedActivationProfileId = ActivationProfileId(
  'activation.protocol-assigned',
);
const readModelOnlyActivationProfileId = ActivationProfileId(
  'activation.read-model-only',
);

const activationProfiles =
    <ActivationProfileId, ActivationCompatibilityProfile>{
      foundationActivationProfileId: ActivationCompatibilityProfile._(
        id: foundationActivationProfileId,
        kind: ActivationKind.alwaysOnFoundation,
      ),
      runtimeFlaggedActivationProfileId: ActivationCompatibilityProfile._(
        id: runtimeFlaggedActivationProfileId,
        kind: ActivationKind.runtimeFlagged,
      ),
      protocolAssignedActivationProfileId: ActivationCompatibilityProfile._(
        id: protocolAssignedActivationProfileId,
        kind: ActivationKind.protocolAssigned,
      ),
      readModelOnlyActivationProfileId: ActivationCompatibilityProfile._(
        id: readModelOnlyActivationProfileId,
        kind: ActivationKind.readModelOnly,
      ),
    };

const foundationRolloutProfileId = RolloutProfileId('rollout.foundation');
const existingRolloutProfileId = RolloutProfileId('rollout.existing-runtime');
const controlledRolloutProfileId = RolloutProfileId('rollout.controlled');
const experimentalRolloutProfileId = RolloutProfileId('rollout.experimental');

const rolloutProfiles = <RolloutProfileId, RolloutCompatibilityProfile>{
  foundationRolloutProfileId: RolloutCompatibilityProfile._(
    id: foundationRolloutProfileId,
    label: 'Foundation metadata only',
  ),
  existingRolloutProfileId: RolloutCompatibilityProfile._(
    id: existingRolloutProfileId,
    label: 'Existing runtime registry control',
  ),
  controlledRolloutProfileId: RolloutCompatibilityProfile._(
    id: controlledRolloutProfileId,
    label: 'Controlled rollout required before activation',
  ),
  experimentalRolloutProfileId: RolloutCompatibilityProfile._(
    id: experimentalRolloutProfileId,
    label: 'Experimental protocol only',
  ),
};

const metadataOnlyRollbackProfileId = RollbackProfileId(
  'rollback.metadata-only',
);
const runtimeFlagRollbackProfileId = RollbackProfileId('rollback.runtime-flag');
const protocolRollbackProfileId = RollbackProfileId('rollback.protocol');

const rollbackProfiles = <RollbackProfileId, RollbackCompatibilityProfile>{
  metadataOnlyRollbackProfileId: RollbackCompatibilityProfile._(
    id: metadataOnlyRollbackProfileId,
    label: 'Remove the metadata reference without runtime mutation',
  ),
  runtimeFlagRollbackProfileId: RollbackCompatibilityProfile._(
    id: runtimeFlagRollbackProfileId,
    label: 'Use the existing runtime kill switch',
  ),
  protocolRollbackProfileId: RollbackCompatibilityProfile._(
    id: protocolRollbackProfileId,
    label: 'End protocol assignment without changing historical evidence',
  ),
};

const evidenceCompatibilityMatrix =
    <ContractEvidenceClass, Map<ProjectionFamily, ProjectionDecision>>{
      ContractEvidenceClass.assessment: <ProjectionFamily, ProjectionDecision>{
        ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
        ProjectionFamily.masterySrs: ProjectionDecision.deny,
        ProjectionFamily.assessmentOutcome: ProjectionDecision.allow,
        ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
        ProjectionFamily.history: ProjectionDecision.allow,
        ProjectionFamily.pronunciation: ProjectionDecision.deny,
        ProjectionFamily.quest: ProjectionDecision.deny,
        ProjectionFamily.streak: ProjectionDecision.deny,
        ProjectionFamily.achievement: ProjectionDecision.deny,
        ProjectionFamily.xp: ProjectionDecision.deny,
        ProjectionFamily.coins: ProjectionDecision.deny,
      },
      ContractEvidenceClass.independentRecall:
          <ProjectionFamily, ProjectionDecision>{
            ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
            ProjectionFamily.masterySrs: ProjectionDecision.allow,
            ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
            ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
            ProjectionFamily.history: ProjectionDecision.allow,
            ProjectionFamily.pronunciation: ProjectionDecision.deny,
            ProjectionFamily.quest: ProjectionDecision.protocolControlled,
            ProjectionFamily.streak: ProjectionDecision.protocolControlled,
            ProjectionFamily.achievement: ProjectionDecision.protocolControlled,
            ProjectionFamily.xp: ProjectionDecision.protocolControlled,
            ProjectionFamily.coins: ProjectionDecision.protocolControlled,
          },
      ContractEvidenceClass.recognition: <ProjectionFamily, ProjectionDecision>{
        ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
        ProjectionFamily.masterySrs: ProjectionDecision.deny,
        ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
        ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
        ProjectionFamily.history: ProjectionDecision.allow,
        ProjectionFamily.pronunciation: ProjectionDecision.deny,
        ProjectionFamily.quest: ProjectionDecision.protocolControlled,
        ProjectionFamily.streak: ProjectionDecision.protocolControlled,
        ProjectionFamily.achievement: ProjectionDecision.protocolControlled,
        ProjectionFamily.xp: ProjectionDecision.protocolControlled,
        ProjectionFamily.coins: ProjectionDecision.protocolControlled,
      },
      ContractEvidenceClass.guidedPractice:
          <ProjectionFamily, ProjectionDecision>{
            ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
            ProjectionFamily.masterySrs: ProjectionDecision.deny,
            ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
            ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
            ProjectionFamily.history: ProjectionDecision.allow,
            ProjectionFamily.pronunciation: ProjectionDecision.deny,
            ProjectionFamily.quest: ProjectionDecision.deny,
            ProjectionFamily.streak: ProjectionDecision.deny,
            ProjectionFamily.achievement: ProjectionDecision.deny,
            ProjectionFamily.xp: ProjectionDecision.deny,
            ProjectionFamily.coins: ProjectionDecision.deny,
          },
      ContractEvidenceClass.pronunciation:
          <ProjectionFamily, ProjectionDecision>{
            ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
            ProjectionFamily.masterySrs: ProjectionDecision.deny,
            ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
            ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
            ProjectionFamily.history: ProjectionDecision.allow,
            ProjectionFamily.pronunciation: ProjectionDecision.allow,
            ProjectionFamily.quest: ProjectionDecision.deny,
            ProjectionFamily.streak: ProjectionDecision.deny,
            ProjectionFamily.achievement: ProjectionDecision.deny,
            ProjectionFamily.xp: ProjectionDecision.deny,
            ProjectionFamily.coins: ProjectionDecision.deny,
          },
      ContractEvidenceClass.exposure: <ProjectionFamily, ProjectionDecision>{
        ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
        ProjectionFamily.masterySrs: ProjectionDecision.deny,
        ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
        ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
        ProjectionFamily.history: ProjectionDecision.allow,
        ProjectionFamily.pronunciation: ProjectionDecision.deny,
        ProjectionFamily.quest: ProjectionDecision.deny,
        ProjectionFamily.streak: ProjectionDecision.deny,
        ProjectionFamily.achievement: ProjectionDecision.deny,
        ProjectionFamily.xp: ProjectionDecision.deny,
        ProjectionFamily.coins: ProjectionDecision.deny,
      },
      ContractEvidenceClass.recreational:
          <ProjectionFamily, ProjectionDecision>{
            ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
            ProjectionFamily.masterySrs: ProjectionDecision.deny,
            ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
            ProjectionFamily.activeLearningEffort: ProjectionDecision.deny,
            ProjectionFamily.history: ProjectionDecision.allow,
            ProjectionFamily.pronunciation: ProjectionDecision.deny,
            ProjectionFamily.quest: ProjectionDecision.deny,
            ProjectionFamily.streak: ProjectionDecision.deny,
            ProjectionFamily.achievement: ProjectionDecision.deny,
            ProjectionFamily.xp: ProjectionDecision.deny,
            ProjectionFamily.coins: ProjectionDecision.deny,
          },
    };
