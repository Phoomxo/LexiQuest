import '../../runtime/registries/feature.dart';

enum FeatureContractId {
  f01,
  f02,
  f03,
  f04,
  f05,
  f06,
  f07,
  f08,
  f09,
  f10,
  f11,
  f12,
  f13,
  f14,
  f15,
  f16,
  f17,
  f18,
  f19,
  f20,
  f21,
  f22,
  f23,
  f24,
  f25,
  f26,
  f27,
  f28,
  f29,
  f30,
  f31,
  f32,
  f33,
  f34,
  f35,
  f36,
  f37,
  f38,
  f39,
  f40,
  f41,
  f42,
  f43,
  f44,
}

extension FeatureContractIdX on FeatureContractId {
  int get ordinal => index + 1;
}

enum CompletionContractId { c1, c2, c3, c4, c5, c6, c7, c8 }

enum FeatureDomain {
  learningContentAndPacks(CompletionContractId.c1),
  unifiedLearningExperience(CompletionContractId.c2),
  recallFeedbackAndControl(CompletionContractId.c3),
  reviewTimeAndAssessment(CompletionContractId.c4),
  motivationAndEngagement(CompletionContractId.c5),
  personalizationAndAccessibility(CompletionContractId.c6),
  localReliabilityOfflineAndRollout(CompletionContractId.c7),
  dailyContinuityAndHistory(CompletionContractId.c8);

  const FeatureDomain(this.completionContract);

  final CompletionContractId completionContract;
}

enum FeatureProvenance {
  alltcasConfirmed,
  adaptedToLexiQuest,
  lexiQuestControl,
}

enum FeatureCoverage { existing, partial, newCapability }

enum ResearchRole {
  neutral,
  infrastructure,
  intervention,
  measurement,
  engagement,
}

enum ContractEvidenceClass {
  assessment,
  independentRecall,
  recognition,
  guidedPractice,
  pronunciation,
  exposure,
  recreational,
}

enum ProjectionFamily {
  sessionOutcome,
  masterySrs,
  assessmentOutcome,
  activeLearningEffort,
  history,
  pronunciation,
  quest,
  streak,
  achievement,
  xp,
  coins,
}

enum ProjectionDecision { allow, deny, protocolControlled }

enum ActivationKind {
  alwaysOnFoundation,
  runtimeFlagged,
  protocolAssigned,
  readModelOnly,
}

enum DomainAuthority {
  vocabulary,
  responseEvidence,
  masterySrs,
  assessment,
  streak,
  lifetimeXp,
  spendableCoins,
  quest,
  history,
  downloadState,
}

enum ExperimentalCandidateId { expP1, expP2 }

extension type const ProductionEntryId(String value) {}

extension type const VerificationRef(String value) {}

extension type const AuthorityProfileId(String value) {}

extension type const EvidenceProfileId(String value) {}

extension type const LifecycleProfileId(String value) {}

extension type const ActivationProfileId(String value) {}

extension type const RolloutProfileId(String value) {}

extension type const RollbackProfileId(String value) {}

final class ProductFeatureContract {
  const ProductFeatureContract({
    required this.id,
    required this.name,
    required this.purpose,
    required this.domain,
    required this.provenance,
    required this.coverage,
    required this.researchRole,
    required this.runtimeFeatures,
    required this.dependencies,
    required this.authorityDependencies,
    required this.authorityProfileId,
    required this.evidenceProfileId,
    required this.lifecycleProfileId,
    required this.activationProfileId,
    required this.rolloutProfileId,
    required this.rollbackProfileId,
    required this.productionEntryIds,
    required this.verificationRefs,
    required this.introductionRevision,
  });

  factory ProductFeatureContract.validated({
    required FeatureContractId id,
    required String name,
    required String purpose,
    required FeatureDomain domain,
    required FeatureProvenance provenance,
    required FeatureCoverage coverage,
    required ResearchRole researchRole,
    required Set<Feature> runtimeFeatures,
    required Set<FeatureContractId> dependencies,
    required Set<DomainAuthority> authorityDependencies,
    required AuthorityProfileId authorityProfileId,
    required EvidenceProfileId evidenceProfileId,
    required LifecycleProfileId lifecycleProfileId,
    required ActivationProfileId activationProfileId,
    required RolloutProfileId rolloutProfileId,
    required RollbackProfileId rollbackProfileId,
    required List<ProductionEntryId> productionEntryIds,
    required List<VerificationRef> verificationRefs,
    required String introductionRevision,
  }) => ProductFeatureContract(
    id: id,
    name: name,
    purpose: purpose,
    domain: domain,
    provenance: provenance,
    coverage: coverage,
    researchRole: researchRole,
    runtimeFeatures: Set<Feature>.unmodifiable(runtimeFeatures),
    dependencies: Set<FeatureContractId>.unmodifiable(dependencies),
    authorityDependencies: Set<DomainAuthority>.unmodifiable(
      authorityDependencies,
    ),
    authorityProfileId: authorityProfileId,
    evidenceProfileId: evidenceProfileId,
    lifecycleProfileId: lifecycleProfileId,
    activationProfileId: activationProfileId,
    rolloutProfileId: rolloutProfileId,
    rollbackProfileId: rollbackProfileId,
    productionEntryIds: List<ProductionEntryId>.unmodifiable(
      productionEntryIds,
    ),
    verificationRefs: List<VerificationRef>.unmodifiable(verificationRefs),
    introductionRevision: introductionRevision,
  );

  final FeatureContractId id;
  final String name;
  final String purpose;
  final FeatureDomain domain;
  final FeatureProvenance provenance;
  final FeatureCoverage coverage;
  final ResearchRole researchRole;
  final Set<Feature> runtimeFeatures;
  final Set<FeatureContractId> dependencies;
  final Set<DomainAuthority> authorityDependencies;
  final AuthorityProfileId authorityProfileId;
  final EvidenceProfileId evidenceProfileId;
  final LifecycleProfileId lifecycleProfileId;
  final ActivationProfileId activationProfileId;
  final RolloutProfileId rolloutProfileId;
  final RollbackProfileId rollbackProfileId;
  final List<ProductionEntryId> productionEntryIds;
  final List<VerificationRef> verificationRefs;
  final String introductionRevision;

  int get ordinal => id.ordinal;
  CompletionContractId get completionContract => domain.completionContract;
}

final class ExperimentalCandidate {
  const ExperimentalCandidate({
    required this.id,
    required this.name,
    required this.purpose,
    required this.researchRole,
    required this.dependencies,
    required this.activationProfileId,
    required this.rolloutProfileId,
    required this.rollbackProfileId,
    required this.verificationRefs,
    required this.introductionRevision,
  });

  factory ExperimentalCandidate.validated({
    required ExperimentalCandidateId id,
    required String name,
    required String purpose,
    required ResearchRole researchRole,
    required Set<FeatureContractId> dependencies,
    required ActivationProfileId activationProfileId,
    required RolloutProfileId rolloutProfileId,
    required RollbackProfileId rollbackProfileId,
    required List<VerificationRef> verificationRefs,
    required String introductionRevision,
  }) => ExperimentalCandidate(
    id: id,
    name: name,
    purpose: purpose,
    researchRole: researchRole,
    dependencies: Set<FeatureContractId>.unmodifiable(dependencies),
    activationProfileId: activationProfileId,
    rolloutProfileId: rolloutProfileId,
    rollbackProfileId: rollbackProfileId,
    verificationRefs: List<VerificationRef>.unmodifiable(verificationRefs),
    introductionRevision: introductionRevision,
  );

  final ExperimentalCandidateId id;
  final String name;
  final String purpose;
  final ResearchRole researchRole;
  final Set<FeatureContractId> dependencies;
  final ActivationProfileId activationProfileId;
  final RolloutProfileId rolloutProfileId;
  final RollbackProfileId rollbackProfileId;
  final List<VerificationRef> verificationRefs;
  final String introductionRevision;
}

final class ProductFeatureCatalog {
  const ProductFeatureCatalog({
    required this.revision,
    required this.records,
    required this.experimentalCandidates,
  });

  factory ProductFeatureCatalog.validated({
    required String revision,
    required List<ProductFeatureContract> records,
    required List<ExperimentalCandidate> experimentalCandidates,
  }) => ProductFeatureCatalog(
    revision: revision,
    records: List<ProductFeatureContract>.unmodifiable(records),
    experimentalCandidates: List<ExperimentalCandidate>.unmodifiable(
      experimentalCandidates,
    ),
  );

  final String revision;
  final List<ProductFeatureContract> records;
  final List<ExperimentalCandidate> experimentalCandidates;
}
