import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

const _seedProductFeature = ProductFeatureContract(
  id: FeatureContractId.f01,
  name: 'Vocabulary Catalog',
  purpose: 'Provide stable vocabulary identities.',
  domain: FeatureDomain.learningContentAndPacks,
  provenance: FeatureProvenance.adaptedToLexiQuest,
  coverage: FeatureCoverage.partial,
  researchRole: ResearchRole.infrastructure,
  runtimeFeatures: <Feature>{Feature.vocabulary},
  dependencies: <FeatureContractId>{},
  authorityDependencies: <DomainAuthority>{DomainAuthority.vocabulary},
  authorityProfileId: AuthorityProfileId('authority-v1'),
  evidenceProfileId: EvidenceProfileId('evidence-v1'),
  lifecycleProfileId: LifecycleProfileId('lifecycle-v1'),
  activationProfileId: ActivationProfileId('activation-v1'),
  rolloutProfileId: RolloutProfileId('rollout-v1'),
  rollbackProfileId: RollbackProfileId('rollback-v1'),
  productionEntryIds: <ProductionEntryId>[ProductionEntryId('home/vocabulary')],
  verificationRefs: <VerificationRef>[
    VerificationRef('architecture:vocabulary-catalog'),
  ],
  introductionRevision: '1.0.0',
);

const _seedExperimentalCandidate = ExperimentalCandidate(
  id: ExperimentalCandidateId.expP1,
  name: 'Local Same-Device Party Game',
  purpose: 'Evaluate an explicitly isolated local experimental mode.',
  researchRole: ResearchRole.intervention,
  dependencies: <FeatureContractId>{FeatureContractId.f01},
  activationProfileId: ActivationProfileId('protocol-only-v1'),
  rolloutProfileId: RolloutProfileId('experimental-v1'),
  rollbackProfileId: RollbackProfileId('experimental-off-v1'),
  verificationRefs: <VerificationRef>[
    VerificationRef('architecture:experimental-isolation'),
  ],
  introductionRevision: '1.0.0',
);

const _seedCatalog = ProductFeatureCatalog(
  revision: '1.0.0',
  records: <ProductFeatureContract>[_seedProductFeature],
  experimentalCandidates: <ExperimentalCandidate>[_seedExperimentalCandidate],
);

void main() {
  test('runtime feature identities remain the exact persisted 19 names', () {
    expect(Feature.values.map((value) => value.name), const <String>[
      'vocabulary',
      'quiz',
      'srs',
      'reading',
      'mastery',
      'weakness',
      'ghostDuel',
      'achievements',
      'shop',
      'objectScanner',
      'speechPractice',
      'aiTutor',
      'export',
      'shadowRewardV2',
      'questV2',
      'studyPlanning',
      'researchAssessment',
      'dailyContinuity',
      'offlineContent',
    ]);
  });

  test('product contract identities are the exact f01 through f44 range', () {
    expect(FeatureContractId.values, hasLength(44));
    expect(FeatureContractId.values.first.name, 'f01');
    expect(FeatureContractId.values.last.name, 'f44');
    expect(
      FeatureContractId.values.map((value) => value.ordinal),
      List<int>.generate(44, (index) => index + 1),
    );
  });

  test('eight product domains map one-to-one to C1 through C8', () {
    expect(FeatureDomain.values, hasLength(8));
    expect(
      FeatureDomain.values.map((value) => value.completionContract),
      CompletionContractId.values,
    );
  });

  test('product feature validation copies and freezes every collection', () {
    final runtimeFeatures = <Feature>{Feature.vocabulary};
    final dependencies = <FeatureContractId>{FeatureContractId.f01};
    final authorityDependencies = <DomainAuthority>{DomainAuthority.vocabulary};
    final productionEntryIds = <ProductionEntryId>[
      const ProductionEntryId('home/vocabulary'),
    ];
    final verificationRefs = <VerificationRef>[
      const VerificationRef('architecture:vocabulary-catalog'),
    ];
    final contract = ProductFeatureContract.validated(
      id: FeatureContractId.f02,
      name: 'Learning Pack',
      purpose: 'Compose a versioned learning pack.',
      domain: FeatureDomain.learningContentAndPacks,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      runtimeFeatures: runtimeFeatures,
      dependencies: dependencies,
      authorityDependencies: authorityDependencies,
      authorityProfileId: const AuthorityProfileId('authority-v1'),
      evidenceProfileId: const EvidenceProfileId('evidence-v1'),
      lifecycleProfileId: const LifecycleProfileId('lifecycle-v1'),
      activationProfileId: const ActivationProfileId('activation-v1'),
      rolloutProfileId: const RolloutProfileId('rollout-v1'),
      rollbackProfileId: const RollbackProfileId('rollback-v1'),
      productionEntryIds: productionEntryIds,
      verificationRefs: verificationRefs,
      introductionRevision: '1.0.0',
    );

    runtimeFeatures.add(Feature.quiz);
    dependencies.add(FeatureContractId.f02);
    authorityDependencies.add(DomainAuthority.responseEvidence);
    productionEntryIds.add(const ProductionEntryId('home/learn/quiz'));
    verificationRefs.add(const VerificationRef('architecture:learning-pack'));

    expect(contract.runtimeFeatures, <Feature>{Feature.vocabulary});
    expect(contract.dependencies, <FeatureContractId>{FeatureContractId.f01});
    expect(contract.authorityDependencies, <DomainAuthority>{
      DomainAuthority.vocabulary,
    });
    expect(contract.productionEntryIds, const <ProductionEntryId>[
      ProductionEntryId('home/vocabulary'),
    ]);
    expect(contract.verificationRefs, const <VerificationRef>[
      VerificationRef('architecture:vocabulary-catalog'),
    ]);
    expect(
      () => contract.runtimeFeatures.add(Feature.quiz),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => contract.dependencies.add(FeatureContractId.f02),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () =>
          contract.authorityDependencies.add(DomainAuthority.responseEvidence),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => contract.productionEntryIds.add(
        const ProductionEntryId('home/learn/quiz'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => contract.verificationRefs.add(
        const VerificationRef('architecture:learning-pack'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('experimental validation copies and freezes every collection', () {
    final dependencies = <FeatureContractId>{FeatureContractId.f01};
    final verificationRefs = <VerificationRef>[
      const VerificationRef('architecture:experimental-isolation'),
    ];
    final candidate = ExperimentalCandidate.validated(
      id: ExperimentalCandidateId.expP1,
      name: 'Local Same-Device Party Game',
      purpose: 'Evaluate an explicitly isolated local experimental mode.',
      researchRole: ResearchRole.intervention,
      dependencies: dependencies,
      activationProfileId: const ActivationProfileId('protocol-only-v1'),
      rolloutProfileId: const RolloutProfileId('experimental-v1'),
      rollbackProfileId: const RollbackProfileId('experimental-off-v1'),
      verificationRefs: verificationRefs,
      introductionRevision: '1.0.0',
    );

    dependencies.add(FeatureContractId.f02);
    verificationRefs.add(const VerificationRef('architecture:party-game'));

    expect(candidate.dependencies, <FeatureContractId>{FeatureContractId.f01});
    expect(candidate.verificationRefs, const <VerificationRef>[
      VerificationRef('architecture:experimental-isolation'),
    ]);
    expect(
      () => candidate.dependencies.add(FeatureContractId.f02),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => candidate.verificationRefs.add(
        const VerificationRef('architecture:party-game'),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('catalog validation copies and freezes every collection', () {
    final records = <ProductFeatureContract>[_seedProductFeature];
    final experimentalCandidates = <ExperimentalCandidate>[
      _seedExperimentalCandidate,
    ];
    final catalog = ProductFeatureCatalog.validated(
      revision: '1.0.0',
      records: records,
      experimentalCandidates: experimentalCandidates,
    );

    records.add(_seedProductFeature);
    experimentalCandidates.add(_seedExperimentalCandidate);

    expect(catalog.records, const <ProductFeatureContract>[
      _seedProductFeature,
    ]);
    expect(catalog.experimentalCandidates, const <ExperimentalCandidate>[
      _seedExperimentalCandidate,
    ]);
    expect(
      () => catalog.records.add(_seedProductFeature),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => catalog.experimentalCandidates.add(_seedExperimentalCandidate),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('const seed constructors accept deeply const collections', () {
    expect(_seedCatalog.records.single, same(_seedProductFeature));
    expect(
      _seedCatalog.experimentalCandidates.single,
      same(_seedExperimentalCandidate),
    );
    expect(_seedProductFeature.runtimeFeatures, const <Feature>{
      Feature.vocabulary,
    });
    expect(_seedExperimentalCandidate.dependencies, const <FeatureContractId>{
      FeatureContractId.f01,
    });
  });
}
