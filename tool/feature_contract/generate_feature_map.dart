import 'dart:convert';
import 'dart:io' as io;

import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';

const _markdownRelativePath =
    'docs/generated/alltcas-idea-integration-feature-map.md';
const _jsonRelativePath =
    'docs/generated/alltcas-idea-integration-feature-map.json';

final class FeatureMapArtifacts {
  const FeatureMapArtifacts({
    required this.markdown,
    required this.normalizedJson,
    required this.semanticHash,
  });

  final String markdown;
  final String normalizedJson;
  final String semanticHash;
}

FeatureMapArtifacts buildFeatureMapArtifacts(ProductFeatureCatalog catalog) {
  final semanticHash = catalogSemanticSha256(catalog);
  final records = catalog.records.toList(growable: false)
    ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
  final candidates = catalog.experimentalCandidates.toList(growable: false)
    ..sort((left, right) => left.id.name.compareTo(right.id.name));
  final normalizedJson =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object>{'schemaVersion': featureContractSchemaVersion, 'revision': catalog.revision, 'baselineCommit': featureContractBaselineCommit, 'generatorVersion': featureContractGeneratorVersion, 'semanticHash': semanticHash, 'records': records.map(_artifactRecordJson).toList(growable: false), 'experimentalCandidates': candidates.map(_artifactCandidateJson).toList(growable: false)})}\n';

  return FeatureMapArtifacts(
    markdown: _buildMarkdown(catalog, records, candidates, semanticHash),
    normalizedJson: normalizedJson,
    semanticHash: semanticHash,
  );
}

int runFeatureMapGenerator(
  List<String> arguments, {
  io.Directory? repositoryRoot,
  void Function(String message)? stdout,
  void Function(String message)? stderr,
}) {
  final void Function(String) writeOutput =
      stdout ?? (message) => io.stdout.writeln(message);
  final void Function(String) writeError =
      stderr ?? (message) => io.stderr.writeln(message);
  if (arguments.length != 1 ||
      (arguments.single != '--write' && arguments.single != '--check')) {
    writeError(
      'Usage: dart run tool/feature_contract/generate_feature_map.dart '
      '<--write|--check>',
    );
    return 64;
  }

  final root = repositoryRoot ?? io.Directory.current;
  final markdownFile = io.File(_join(root.path, _markdownRelativePath));
  final jsonFile = io.File(_join(root.path, _jsonRelativePath));
  final artifacts = buildFeatureMapArtifacts(allTcasIdeaIntegrationCatalog);

  if (arguments.single == '--check') {
    var drifted = false;
    drifted =
        _checkArtifact(
          markdownFile,
          artifacts.markdown,
          _markdownRelativePath,
          writeError,
        ) ||
        drifted;
    drifted =
        _checkArtifact(
          jsonFile,
          artifacts.normalizedJson,
          _jsonRelativePath,
          writeError,
        ) ||
        drifted;
    if (drifted) {
      return 1;
    }
    writeOutput(
      'Feature-map artifacts are current '
      '(${artifacts.semanticHash}, revision ${featureContractRevision}).',
    );
    return 0;
  }

  final identityCheck = _validateExistingIdentity(
    jsonFile,
    artifacts.semanticHash,
    writeError,
  );
  if (!identityCheck.mayWrite) {
    return 1;
  }
  if (identityCheck.revisionOnlyChange) {
    writeError(
      'Warning: revision-only feature contract change '
      '(${identityCheck.previousRevision} -> ${featureContractRevision}); '
      'semantic hash is unchanged.',
    );
  }

  markdownFile.parent.createSync(recursive: true);
  _writeUtf8(markdownFile, artifacts.markdown);
  _writeUtf8(jsonFile, artifacts.normalizedJson);
  writeOutput(
    'Wrote $_markdownRelativePath and $_jsonRelativePath '
    '(${artifacts.semanticHash}, revision ${featureContractRevision}).',
  );
  return 0;
}

void main(List<String> arguments) {
  io.exitCode = runFeatureMapGenerator(arguments);
}

bool _checkArtifact(
  io.File file,
  String expected,
  String relativePath,
  void Function(String message) writeError,
) {
  if (!file.existsSync()) {
    writeError('Generated feature-map artifact is missing: $relativePath');
    return true;
  }
  final actualBytes = file.readAsBytesSync();
  final expectedBytes = utf8.encode(expected);
  if (!_bytesEqual(actualBytes, expectedBytes)) {
    writeError('Generated feature-map artifact has drifted: $relativePath');
    return true;
  }
  return false;
}

_ExistingIdentityCheck _validateExistingIdentity(
  io.File jsonFile,
  String newSemanticHash,
  void Function(String message) writeError,
) {
  if (!jsonFile.existsSync()) {
    return const _ExistingIdentityCheck(mayWrite: true);
  }

  late final Object? decoded;
  try {
    decoded = jsonDecode(jsonFile.readAsStringSync(encoding: utf8));
  } on FormatException {
    writeError(
      'Existing generated JSON has no trustworthy contract identity; '
      'refusing to overwrite it.',
    );
    return const _ExistingIdentityCheck(mayWrite: false);
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['revision'] is! String ||
      decoded['semanticHash'] is! String) {
    writeError(
      'Existing generated JSON has no trustworthy contract identity; '
      'refusing to overwrite it.',
    );
    return const _ExistingIdentityCheck(mayWrite: false);
  }

  final previousRevision = decoded['revision'] as String;
  final previousSemanticHash = decoded['semanticHash'] as String;
  if (previousRevision == featureContractRevision &&
      previousSemanticHash != newSemanticHash) {
    writeError(
      'Feature contract semantic hash changed under the same revision '
      '$featureContractRevision; refusing to write either artifact.',
    );
    return const _ExistingIdentityCheck(mayWrite: false);
  }
  return _ExistingIdentityCheck(
    mayWrite: true,
    revisionOnlyChange:
        previousRevision != featureContractRevision &&
        previousSemanticHash == newSemanticHash,
    previousRevision: previousRevision,
  );
}

void _writeUtf8(io.File file, String contents) {
  file.writeAsBytesSync(utf8.encode(contents), flush: true);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _join(String root, String relativePath) =>
    '$root${io.Platform.pathSeparator}${relativePath.replaceAll('/', io.Platform.pathSeparator)}';

String _buildMarkdown(
  ProductFeatureCatalog catalog,
  List<ProductFeatureContract> records,
  List<ExperimentalCandidate> candidates,
  String semanticHash,
) {
  final buffer = StringBuffer()
    ..writeln('# AllTCAS Idea Integration Feature Map')
    ..writeln()
    ..writeln(
      '<!-- Generated by tool/feature_contract/generate_feature_map.dart. -->',
    )
    ..writeln()
    ..writeln('- Contract revision: `${catalog.revision}`')
    ..writeln('- Baseline commit: `$featureContractBaselineCommit`')
    ..writeln('- Generator version: `$featureContractGeneratorVersion`')
    ..writeln('- Semantic SHA-256: `$semanticHash`')
    ..writeln('- Product features: ${records.length}')
    ..writeln('- Experimental candidates: ${candidates.length}');

  for (final domain in FeatureDomain.values) {
    final domainRecords = records
        .where((record) => record.domain == domain)
        .toList(growable: false);
    buffer
      ..writeln()
      ..writeln(
        '## Domain ${domain.index + 1}: ${_displayName(domain.name)} '
        '(${domain.completionContract.name.toUpperCase()})',
      )
      ..writeln()
      ..writeln(
        '| ID | Feature | Coverage | Provenance | Research role | Dependencies | Runtime features |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final record in domainRecords) {
      buffer.writeln(
        '| ${record.id.name} | ${_markdownCell(record.name)} | '
        '${record.coverage.name} | ${record.provenance.name} | '
        '${record.researchRole.name} | '
        '${_markdownList(_sortedNames(record.dependencies.map((it) => it.name)))} | '
        '${_markdownList(_sortedNames(record.runtimeFeatures.map((it) => it.name)))} |',
      );
    }
    for (final record in domainRecords) {
      buffer
        ..writeln()
        ..writeln('**${record.id.name} purpose:** ${record.purpose}')
        ..writeln()
        ..writeln(
          '- Profiles: authority `${record.authorityProfileId.value}`; '
          'evidence `${record.evidenceProfileId.value}`; '
          'lifecycle `${record.lifecycleProfileId.value}`; '
          'activation `${record.activationProfileId.value}`; '
          'rollout `${record.rolloutProfileId.value}`; '
          'rollback `${record.rollbackProfileId.value}`.',
        )
        ..writeln(
          '- Authorities: '
          '${_markdownList(_sortedNames(record.authorityDependencies.map((it) => it.name)))}. '
          'Production entries: '
          '${_markdownList(record.productionEntryIds.map((it) => it.value).toList(growable: false))}.',
        );
    }
  }

  buffer
    ..writeln()
    ..writeln('## Experimental candidates')
    ..writeln()
    ..writeln('| ID | Candidate | Research role | Dependencies |')
    ..writeln('| --- | --- | --- | --- |');
  for (final candidate in candidates) {
    buffer.writeln(
      '| ${candidate.id.name} | ${_markdownCell(candidate.name)} | '
      '${candidate.researchRole.name} | '
      '${_markdownList(_sortedNames(candidate.dependencies.map((it) => it.name)))} |',
    );
  }
  return '${buffer.toString().trimRight()}\n';
}

Map<String, Object> _artifactRecordJson(
  ProductFeatureContract record,
) => <String, Object>{
  'id': record.id.name,
  'ordinal': record.ordinal,
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
  'introductionRevision': record.introductionRevision,
};

Map<String, Object> _artifactCandidateJson(ExperimentalCandidate candidate) =>
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
      'introductionRevision': candidate.introductionRevision,
    };

List<String> _sortedNames(Iterable<String> values) =>
    values.toList(growable: false)..sort();

String _displayName(String enumName) => enumName
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

String _markdownCell(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\r', ' ').replaceAll('\n', ' ');

String _markdownList(List<String> values) =>
    values.isEmpty ? 'none' : values.map((value) => '`$value`').join(', ');

final class _ExistingIdentityCheck {
  const _ExistingIdentityCheck({
    required this.mayWrite,
    this.revisionOnlyChange = false,
    this.previousRevision,
  });

  final bool mayWrite;
  final bool revisionOnlyChange;
  final String? previousRevision;
}
