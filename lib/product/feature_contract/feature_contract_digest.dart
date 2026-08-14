import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'alltcas_idea_integration_catalog.dart';
import 'feature_contract_models.dart';

final class FeatureContractIdentity {
  const FeatureContractIdentity({
    required this.revision,
    required this.semanticHash,
  });

  final String revision;
  final String semanticHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureContractIdentity &&
          revision == other.revision &&
          semanticHash == other.semanticHash;

  @override
  int get hashCode => Object.hash(revision, semanticHash);
}

String canonicalSemanticCatalogJson(ProductFeatureCatalog catalog) {
  final records = catalog.records.toList(growable: false)
    ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
  final candidates = catalog.experimentalCandidates.toList(growable: false)
    ..sort((left, right) => left.id.name.compareTo(right.id.name));

  return jsonEncode(<String, Object>{
    'records': records.map(_semanticRecordJson).toList(growable: false),
    'experimentalCandidates': candidates
        .map(_semanticCandidateJson)
        .toList(growable: false),
  });
}

String catalogSemanticSha256(ProductFeatureCatalog catalog) => sha256
    .convert(utf8.encode(canonicalSemanticCatalogJson(catalog)))
    .toString();

final FeatureContractIdentity currentFeatureContractIdentity =
    FeatureContractIdentity(
      revision: featureContractRevision,
      semanticHash: catalogSemanticSha256(allTcasIdeaIntegrationCatalog),
    );

// Persisted evidence may refer to any identity in this append-only registry.
// When the contract changes, retain every existing entry and append the new one.
const List<FeatureContractIdentity> supportedFeatureContractIdentities =
    <FeatureContractIdentity>[
      FeatureContractIdentity(
        revision: '1.0.0',
        semanticHash:
            'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
      ),
    ];

Map<String, Object> _semanticRecordJson(
  ProductFeatureContract record,
) => <String, Object>{
  'id': record.id.name,
  'name': record.name,
  'purpose': record.purpose,
  'domain': record.domain.name,
  'completionContract': record.completionContract.name,
  'provenance': record.provenance.name,
  'coverage': record.coverage.name,
  'researchRole': record.researchRole.name,
  'runtimeFeatures': _sortedNames(record.runtimeFeatures.map((it) => it.name)),
  'dependencies': _sortedNames(record.dependencies.map((it) => it.name)),
  'authorityDependencies': _sortedNames(
    record.authorityDependencies.map((it) => it.name),
  ),
  'authorityProfileId': record.authorityProfileId.value,
  'evidenceProfileId': record.evidenceProfileId.value,
  'lifecycleProfileId': record.lifecycleProfileId.value,
  'activationProfileId': record.activationProfileId.value,
  'rolloutProfileId': record.rolloutProfileId.value,
  'rollbackProfileId': record.rollbackProfileId.value,
  'productionEntryIds': record.productionEntryIds
      .map((it) => it.value)
      .toList(growable: false),
  'verificationRefs': record.verificationRefs
      .map((it) => it.value)
      .toList(growable: false),
};

Map<String, Object> _semanticCandidateJson(ExperimentalCandidate candidate) =>
    <String, Object>{
      'id': candidate.id.name,
      'name': candidate.name,
      'purpose': candidate.purpose,
      'researchRole': candidate.researchRole.name,
      'dependencies': _sortedNames(candidate.dependencies.map((it) => it.name)),
      'activationProfileId': candidate.activationProfileId.value,
      'rolloutProfileId': candidate.rolloutProfileId.value,
      'rollbackProfileId': candidate.rollbackProfileId.value,
      'verificationRefs': candidate.verificationRefs
          .map((it) => it.value)
          .toList(growable: false),
    };

List<String> _sortedNames(Iterable<String> values) =>
    values.toList(growable: false)..sort();
