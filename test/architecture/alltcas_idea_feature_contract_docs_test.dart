import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';

import '../../tool/feature_contract/generate_feature_map.dart';

void main() {
  group('AllTCAS feature-map artifacts', () {
    test(
      'render deterministically with ordered JSON and complete provenance',
      () {
        final first = buildFeatureMapArtifacts(allTcasIdeaIntegrationCatalog);
        final second = buildFeatureMapArtifacts(allTcasIdeaIntegrationCatalog);

        expect(second.markdown, first.markdown);
        expect(second.normalizedJson, first.normalizedJson);
        expect(second.semanticHash, first.semanticHash);
        expect(first.semanticHash, matches(RegExp(r'^[0-9a-f]{64}$')));

        final decoded =
            jsonDecode(first.normalizedJson) as Map<String, dynamic>;
        expect(decoded.keys, <String>[
          'schemaVersion',
          'revision',
          'baselineCommit',
          'generatorVersion',
          'semanticHash',
          'records',
          'experimentalCandidates',
        ]);
        expect(decoded['schemaVersion'], featureContractSchemaVersion);
        expect(decoded['revision'], featureContractRevision);
        expect(decoded['baselineCommit'], featureContractBaselineCommit);
        expect(decoded['generatorVersion'], featureContractGeneratorVersion);
        expect(decoded['semanticHash'], first.semanticHash);
        for (final provenanceLine in <String>[
          '- Contract revision: `$featureContractRevision`',
          '- Baseline commit: `$featureContractBaselineCommit`',
          '- Generator version: `$featureContractGeneratorVersion`',
          '- Semantic SHA-256: `${first.semanticHash}`',
        ]) {
          expect(first.markdown, contains(provenanceLine));
        }
        final records = decoded['records'] as List<dynamic>;
        expect(
          records.map((record) => (record as Map<String, dynamic>)['id']),
          FeatureContractId.values.map((id) => id.name),
        );
        expect(
          first.normalizedJson.indexOf('"id": "f09"'),
          lessThan(first.normalizedJson.indexOf('"id": "f10"')),
        );
      },
    );

    test('render LF-only text with exactly one final newline', () {
      final artifacts = buildFeatureMapArtifacts(allTcasIdeaIntegrationCatalog);

      for (final output in <String>[
        artifacts.markdown,
        artifacts.normalizedJson,
      ]) {
        expect(output, isNot(contains('\r')));
        expect(output.endsWith('\n'), isTrue);
        expect(output.endsWith('\n\n'), isFalse);
      }
    });

    test('keep every domain table contiguous before record details', () {
      final markdown = buildFeatureMapArtifacts(
        allTcasIdeaIntegrationCatalog,
      ).markdown;

      for (final domain in FeatureDomain.values) {
        final heading = '## Domain ${domain.index + 1}:';
        final sectionStart = markdown.indexOf(heading);
        final nextHeading = markdown.indexOf('\n## ', sectionStart + 1);
        final section = markdown.substring(
          sectionStart,
          nextHeading < 0 ? markdown.length : nextHeading,
        );
        final lines = section.split('\n');
        final tableRows = <int>[
          for (var index = 0; index < lines.length; index += 1)
            if (RegExp(r'^\| f\d{2} \|').hasMatch(lines[index])) index,
        ];
        final firstDetail = lines.indexWhere(
          (line) => RegExp(r'^\*\*f\d{2} purpose:').hasMatch(line),
        );

        expect(
          tableRows.length,
          allTcasIdeaIntegrationCatalog.records
              .where((record) => record.domain == domain)
              .length,
        );
        expect(tableRows.last, lessThan(firstDetail));
      }
    });

    test('semantic identity excludes the catalog revision', () {
      final revisionOnlyChange = ProductFeatureCatalog.validated(
        revision: '99.0.0',
        records: allTcasIdeaIntegrationCatalog.records,
        experimentalCandidates:
            allTcasIdeaIntegrationCatalog.experimentalCandidates,
      );

      expect(
        canonicalSemanticCatalogJson(revisionOnlyChange),
        canonicalSemanticCatalogJson(allTcasIdeaIntegrationCatalog),
      );
      expect(
        catalogSemanticSha256(revisionOnlyChange),
        catalogSemanticSha256(allTcasIdeaIntegrationCatalog),
      );
    });

    test('exposes the current identity in the supported replay registry', () {
      expect(currentFeatureContractIdentity.revision, featureContractRevision);
      expect(
        currentFeatureContractIdentity.semanticHash,
        catalogSemanticSha256(allTcasIdeaIntegrationCatalog),
      );
      expect(
        supportedFeatureContractIdentities,
        contains(currentFeatureContractIdentity),
      );
      expect(
        supportedFeatureContractIdentities.toSet().length,
        supportedFeatureContractIdentities.length,
      );
      expect(
        () => supportedFeatureContractIdentities.add(
          currentFeatureContractIdentity,
        ),
        throwsUnsupportedError,
      );
    });

    test('keeps the reusable digest free of file-system and CLI imports', () {
      final source = File(
        'lib/product/feature_contract/feature_contract_digest.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('generate_feature_map.dart')));
    });
  });

  group('feature-map generator modes', () {
    late Directory repositoryRoot;

    setUp(() {
      repositoryRoot = Directory.systemTemp.createTempSync(
        'lexiquest-feature-map-',
      );
    });

    tearDown(() {
      repositoryRoot.deleteSync(recursive: true);
    });

    test('--check detects absent artifacts without creating them', () {
      final errors = <String>[];

      final exitCode = runFeatureMapGenerator(
        const <String>['--check'],
        repositoryRoot: repositoryRoot,
        stderr: errors.add,
      );

      expect(exitCode, 1);
      expect(errors.join('\n'), contains('missing'));
      expect(_markdownFile(repositoryRoot).existsSync(), isFalse);
      expect(_jsonFile(repositoryRoot).existsSync(), isFalse);
    });

    test('--check detects tampering and never repairs either artifact', () {
      expect(
        runFeatureMapGenerator(const <String>[
          '--write',
        ], repositoryRoot: repositoryRoot),
        0,
      );
      final markdown = _markdownFile(repositoryRoot);
      final json = _jsonFile(repositoryRoot);
      markdown.writeAsStringSync('tampered markdown\n');
      final beforeMarkdown = markdown.readAsBytesSync();
      final beforeJson = json.readAsBytesSync();

      expect(
        runFeatureMapGenerator(const <String>[
          '--check',
        ], repositoryRoot: repositoryRoot),
        1,
      );
      expect(markdown.readAsBytesSync(), beforeMarkdown);
      expect(json.readAsBytesSync(), beforeJson);
    });

    test(
      '--check accepts byte-equivalent CRLF artifacts without rewriting',
      () {
        expect(
          runFeatureMapGenerator(const <String>[
            '--write',
          ], repositoryRoot: repositoryRoot),
          0,
        );
        final markdown = _markdownFile(repositoryRoot);
        final json = _jsonFile(repositoryRoot);
        markdown.writeAsBytesSync(
          utf8.encode(markdown.readAsStringSync().replaceAll('\n', '\r\n')),
        );
        json.writeAsBytesSync(
          utf8.encode(json.readAsStringSync().replaceAll('\n', '\r\n')),
        );
        final beforeMarkdown = markdown.readAsBytesSync();
        final beforeJson = json.readAsBytesSync();

        expect(
          runFeatureMapGenerator(const <String>[
            '--check',
          ], repositoryRoot: repositoryRoot),
          0,
        );
        expect(markdown.readAsBytesSync(), beforeMarkdown);
        expect(json.readAsBytesSync(), beforeJson);
      },
    );

    test('unsupported arguments exit 64 without creating artifacts', () {
      final errors = <String>[];

      final exitCode = runFeatureMapGenerator(
        const <String>['--unknown'],
        repositoryRoot: repositoryRoot,
        stderr: errors.add,
      );

      expect(exitCode, 64);
      expect(errors.join('\n'), contains('Usage:'));
      expect(_markdownFile(repositoryRoot).existsSync(), isFalse);
      expect(_jsonFile(repositoryRoot).existsSync(), isFalse);
    });

    test('--write fails closed on same-revision semantic hash drift', () {
      final json = _jsonFile(repositoryRoot)..createSync(recursive: true);
      final markdown = _markdownFile(repositoryRoot)
        ..createSync(recursive: true)
        ..writeAsStringSync('preserve me\n');
      json.writeAsStringSync(
        '${jsonEncode(<String, Object>{'revision': featureContractRevision, 'semanticHash': ''.padLeft(64, '0')})}\n',
      );
      final beforeMarkdown = markdown.readAsBytesSync();
      final beforeJson = json.readAsBytesSync();
      final errors = <String>[];

      final exitCode = runFeatureMapGenerator(
        const <String>['--write'],
        repositoryRoot: repositoryRoot,
        stderr: errors.add,
      );

      expect(exitCode, 1);
      expect(errors.join('\n'), contains('same revision'));
      expect(markdown.readAsBytesSync(), beforeMarkdown);
      expect(json.readAsBytesSync(), beforeJson);
    });

    test('--write permits a revision-only change with a warning', () {
      expect(
        runFeatureMapGenerator(const <String>[
          '--write',
        ], repositoryRoot: repositoryRoot),
        0,
      );
      final json = _jsonFile(repositoryRoot);
      final prior = jsonDecode(json.readAsStringSync()) as Map<String, dynamic>;
      prior['revision'] = '0.9.0';
      json.writeAsStringSync('${_prettyJson(prior)}\n');
      final warnings = <String>[];

      final exitCode = runFeatureMapGenerator(
        const <String>['--write'],
        repositoryRoot: repositoryRoot,
        stderr: warnings.add,
      );

      expect(exitCode, 0);
      expect(warnings.join('\n'), contains('revision-only'));
      final rewritten =
          jsonDecode(json.readAsStringSync()) as Map<String, dynamic>;
      expect(rewritten['revision'], featureContractRevision);
      expect(rewritten['semanticHash'], prior['semanticHash']);
    });
  });
}

File _markdownFile(Directory root) =>
    File('${root.path}/docs/generated/alltcas-idea-integration-feature-map.md');

File _jsonFile(Directory root) => File(
  '${root.path}/docs/generated/alltcas-idea-integration-feature-map.json',
);

String _prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
