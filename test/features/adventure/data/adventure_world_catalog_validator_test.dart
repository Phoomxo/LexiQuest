import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/data/adventure_world_catalog_validator.dart';
import 'package:vocab_learning_app/features/adventure/data/packaged_adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_world_catalog.dart';

void main() {
  const validator = AdventureWorldCatalogValidator();

  test('packaged Thai and English three-node catalogs are valid', () {
    for (final locale in <String>['th', 'en']) {
      final catalog = PackagedAdventureWorldCatalog.forLocale(locale);
      final result = validator.validate(
        catalog,
        packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
      );

      expect(result.isValid, isTrue, reason: result.violations.toString());
      expect(catalog.worlds.single.nodes, hasLength(3));
      expect(catalog.worlds.single.nodes.map((node) => node.nodeId), <String>[
        'resume-review',
        'today-mission',
        'next-preview',
      ]);
      expect(catalog.catalogId, 'lexiquest.adventure.world-v1');
      expect(catalog.catalogVersion, '1.0.0');
    }
  });

  test('catalog codec is exact and rejects unknown enum or object keys', () {
    final json = PackagedAdventureWorldCatalog.forLocale('en').toJson();
    expect(AdventureWorldCatalog.fromJson(json).toJson(), json);

    expect(
      () => AdventureWorldCatalog.fromJson(<String, Object?>{
        ...json,
        'futureKey': true,
      }),
      throwsFormatException,
    );

    expect(
      () => AdventureWorldCatalog.fromJson(<String, Object?>{
        ...json,
        'qaState': 'futureApproved',
      }),
      throwsFormatException,
    );
  });

  test('catalog collections are deep immutable', () {
    final catalog = PackagedAdventureWorldCatalog.forLocale('th');

    expect(
      () => catalog.worlds.add(catalog.worlds.single),
      throwsUnsupportedError,
    );
    expect(() => catalog.worlds.single.nodes.clear(), throwsUnsupportedError);
    expect(
      () => catalog.worlds.single.nodes.first.labelsByLocale['th'] = 'x',
      throwsUnsupportedError,
    );
    expect(() => catalog.assetManifest.assets.clear(), throwsUnsupportedError);
  });

  group('negative validation matrix', () {
    test('rejects duplicate stable IDs', () {
      final json = _fixtureJson();
      final worlds = _listOfMaps(json['worlds']);
      final nodes = _listOfMaps(worlds.single['nodes']);
      nodes.add(Map<String, Object?>.from(nodes.first));
      worlds.single['nodes'] = nodes;
      json['worlds'] = worlds;

      expect(_codes(json), contains('duplicate_id'));
    });

    test('rejects unresolved prerequisites and cycles', () {
      final unresolved = _fixtureJson();
      _node(unresolved, 'today-mission')['prerequisiteNodeIds'] = <String>[
        'missing-node',
      ];
      expect(_codes(unresolved), contains('unresolved_reference'));

      final cyclic = _fixtureJson();
      _node(cyclic, 'resume-review')['prerequisiteNodeIds'] = <String>[
        'next-preview',
      ];
      expect(_codes(cyclic), contains('graph_cycle'));
    });

    test('rejects missing locale and accessibility labels', () {
      final missingLocale = _fixtureJson();
      _node(missingLocale, 'today-mission')['labelsByLocale'] =
          <String, String>{'en': 'Today mission'};
      expect(_codes(missingLocale), contains('missing_locale'));

      final missingA11y = _fixtureJson();
      _node(missingA11y, 'today-mission')['accessibilityLabelsByLocale'] =
          <String, String>{'th': ''};
      expect(_codes(missingA11y), contains('missing_accessibility_label'));
    });

    test('rejects path traversal and remote executable content', () {
      final traversal = _fixtureJson();
      _asset(traversal)['path'] = '../private/key';
      expect(_codes(traversal), contains('unsafe_asset_path'));

      final remoteExecutable = _fixtureJson();
      _asset(remoteExecutable)
        ..['path'] = 'https://cdn.example.test/mission.js'
        ..['mediaType'] = 'application/javascript';
      expect(_codes(remoteExecutable), contains('remote_executable_content'));
    });

    test('rejects checksum, size, type and revision mismatches', () {
      final checksum = _fixtureJson();
      _asset(checksum)['checksumSha256'] =
          '0000000000000000000000000000000000000000000000000000000000000000';
      expect(_codes(checksum), contains('checksum_mismatch'));

      final size = _fixtureJson();
      _asset(size)['byteSize'] = 999;
      expect(_codes(size), contains('size_mismatch'));

      final type = _fixtureJson();
      _asset(type)['mediaType'] = 'image/png';
      expect(_codes(type), contains('type_mismatch'));

      final revision = _fixtureJson();
      _assetReference(_node(revision, 'resume-review'))['requiredRevision'] = 2;
      expect(_codes(revision), contains('revision_mismatch'));
    });
  });

  test('validation output is deterministic for shuffled input order', () {
    final source = _fixtureJson();
    final worlds = _listOfMaps(source['worlds']);
    final nodes = _listOfMaps(worlds.single['nodes']);
    nodes.add(Map<String, Object?>.from(nodes.first));
    nodes.last['prerequisiteNodeIds'] = <String>['missing-node'];
    worlds.single['nodes'] = nodes;
    source['worlds'] = worlds;
    _asset(source)['checksumSha256'] = sha256
        .convert(utf8.encode('wrong'))
        .toString();

    final first = validator.validate(
      AdventureWorldCatalog.fromJson(source),
      packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
    );

    final reversed = AdventureWorldCatalog.fromJson(source);
    final shuffled = reversed.copyWith(
      worlds: reversed.worlds.reversed
          .map((world) => world.copyWith(nodes: world.nodes.reversed.toList()))
          .toList(),
      assetManifest: reversed.assetManifest.copyWith(
        assets: reversed.assetManifest.assets.reversed.toList(),
      ),
    );
    final second = validator.validate(
      shuffled,
      packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
    );

    expect(second.violations, first.violations);
  });
}

Map<String, Object?> _fixtureJson() => Map<String, Object?>.from(
  jsonDecode(jsonEncode(PackagedAdventureWorldCatalog.forLocale('th').toJson()))
      as Map,
);

List<Map<String, Object?>> _listOfMaps(Object? value) => (value! as List)
    .map((item) => Map<String, Object?>.from(item as Map))
    .toList();

Map<String, Object?> _node(Map<String, Object?> json, String nodeId) {
  final worlds = _listOfMaps(json['worlds']);
  final nodes = _listOfMaps(worlds.single['nodes']);
  final node = nodes.singleWhere((item) => item['nodeId'] == nodeId);
  worlds.single['nodes'] = nodes;
  json['worlds'] = worlds;
  return node;
}

Map<String, Object?> _asset(Map<String, Object?> json) {
  final manifest = Map<String, Object?>.from(json['assetManifest']! as Map);
  final assets = _listOfMaps(manifest['assets']);
  manifest['assets'] = assets;
  json['assetManifest'] = manifest;
  return assets.first;
}

Map<String, Object?> _assetReference(Map<String, Object?> node) {
  final references = _listOfMaps(node['assetReferences']);
  node['assetReferences'] = references;
  return references.first;
}

List<String> _codes(Map<String, Object?> json) {
  const validator = AdventureWorldCatalogValidator();
  final result = validator.validate(
    AdventureWorldCatalog.fromJson(json),
    packagedBytes: PackagedAdventureWorldCatalog.assetBytes,
  );
  return result.violations.map((violation) => violation.code).toList();
}
