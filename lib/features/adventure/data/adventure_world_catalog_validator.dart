import 'package:crypto/crypto.dart';

import '../domain/adventure_world_catalog.dart';

final class AdventureCatalogViolation {
  const AdventureCatalogViolation({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is AdventureCatalogViolation &&
      other.code == code &&
      other.path == path &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, path, message);

  @override
  String toString() => '$code@$path: $message';
}

final class AdventureCatalogValidationResult {
  AdventureCatalogValidationResult(List<AdventureCatalogViolation> violations)
    : violations = List<AdventureCatalogViolation>.unmodifiable(violations);

  final List<AdventureCatalogViolation> violations;
  bool get isValid => violations.isEmpty;
}

final class AdventureCatalogValidationException implements Exception {
  AdventureCatalogValidationException(this.violations);

  final List<AdventureCatalogViolation> violations;

  @override
  String toString() => 'AdventureCatalogValidationException($violations)';
}

final class AdventureWorldCatalogValidator {
  const AdventureWorldCatalogValidator();

  AdventureCatalogValidationResult validate(
    AdventureWorldCatalog catalog, {
    required Map<String, List<int>> packagedBytes,
  }) {
    final violations = <AdventureCatalogViolation>[];
    void add(String code, String path, String message) {
      violations.add(
        AdventureCatalogViolation(code: code, path: path, message: message),
      );
    }

    if (catalog.schemaVersion != AdventureWorldCatalog.currentSchemaVersion) {
      add('schema_mismatch', 'schemaVersion', 'Unsupported catalog schema.');
    }
    _checkCanonicalId(catalog.catalogId, 'catalogId', add);
    if (!_semanticVersion.hasMatch(catalog.catalogVersion)) {
      add('invalid_version', 'catalogVersion', 'Version must be semantic.');
    }
    if (!_supportedLocales.contains(catalog.locale)) {
      add('missing_locale', 'locale', 'Catalog locale is unsupported.');
    }
    if (catalog.qaState == AdventureCatalogQaState.draft) {
      add('invalid_qa_state', 'qaState', 'Draft catalogs cannot be delivered.');
    }
    final manifest = catalog.assetManifest;
    if (manifest.catalogVersion != catalog.catalogVersion) {
      add(
        'version_mismatch',
        'assetManifest.catalogVersion',
        'Manifest and catalog versions differ.',
      );
    }
    if (manifest.locale != catalog.locale) {
      add(
        'missing_locale',
        'assetManifest.locale',
        'Manifest and catalog locales differ.',
      );
    }
    if (manifest.revision <= 0) {
      add(
        'invalid_revision',
        'assetManifest.revision',
        'Revision must be positive.',
      );
    }

    final identities = <String, String>{};
    void registerId(String id, String path) {
      _checkCanonicalId(id, path, add);
      final prior = identities[id];
      if (prior != null) {
        add('duplicate_id', path, 'Identity is already declared at $prior.');
      } else {
        identities[id] = path;
      }
    }

    registerId(catalog.catalogId, 'catalogId');
    registerId(manifest.manifestId, 'assetManifest.manifestId');

    final assetsById = <String, AdventureAssetDefinition>{};
    for (var index = 0; index < manifest.assets.length; index++) {
      final asset = manifest.assets[index];
      final path = 'assetManifest.assets.${asset.assetId}';
      registerId(asset.assetId, '$path.assetId');
      assetsById.putIfAbsent(asset.assetId, () => asset);
      _validateAsset(asset, path, packagedBytes, add);
    }

    final nodesById = <String, AdventureNodeDefinition>{};
    for (var worldIndex = 0; worldIndex < catalog.worlds.length; worldIndex++) {
      final world = catalog.worlds[worldIndex];
      final worldPath = 'worlds.${world.worldId}';
      registerId(world.worldId, '$worldPath.worldId');
      if (world.revision <= 0) {
        add(
          'invalid_revision',
          '$worldPath.revision',
          'Revision must be positive.',
        );
      }
      for (var nodeIndex = 0; nodeIndex < world.nodes.length; nodeIndex++) {
        final node = world.nodes[nodeIndex];
        final nodePath = '$worldPath.nodes.${node.nodeId}';
        registerId(node.nodeId, '$nodePath.nodeId');
        nodesById.putIfAbsent(node.nodeId, () => node);
        _validateNodeCopy(node, nodePath, add);
        if (node.revision <= 0) {
          add(
            'invalid_revision',
            '$nodePath.revision',
            'Revision must be positive.',
          );
        }
        for (
          var refIndex = 0;
          refIndex < node.assetReferences.length;
          refIndex++
        ) {
          final reference = node.assetReferences[refIndex];
          final refPath = '$nodePath.assetReferences.${reference.assetId}';
          final asset = assetsById[reference.assetId];
          if (asset == null) {
            add(
              'unresolved_reference',
              '$refPath.assetId',
              'Asset identity does not resolve.',
            );
          } else if (asset.contentRevision != reference.requiredRevision) {
            add(
              'revision_mismatch',
              '$refPath.requiredRevision',
              'Required and packaged asset revisions differ.',
            );
          }
        }
      }
    }

    for (var worldIndex = 0; worldIndex < catalog.worlds.length; worldIndex++) {
      final world = catalog.worlds[worldIndex];
      for (var nodeIndex = 0; nodeIndex < world.nodes.length; nodeIndex++) {
        final node = world.nodes[nodeIndex];
        for (
          var refIndex = 0;
          refIndex < node.prerequisiteNodeIds.length;
          refIndex++
        ) {
          if (!nodesById.containsKey(node.prerequisiteNodeIds[refIndex])) {
            add(
              'unresolved_reference',
              'worlds.${world.worldId}.nodes.${node.nodeId}.'
                  'prerequisiteNodeIds.${node.prerequisiteNodeIds[refIndex]}',
              'Prerequisite node does not resolve.',
            );
          }
        }
      }
    }
    _findCycles(nodesById, add);

    for (var index = 0; index < catalog.reactions.length; index++) {
      final reaction = catalog.reactions[index];
      final path = 'reactions.${reaction.reactionId}';
      registerId(reaction.reactionId, '$path.reactionId');
      _validateLocalizedMap(
        reaction.copyByLocale,
        '$path.copyByLocale',
        'missing_locale',
        add,
      );
      _validateLocalizedMap(
        reaction.accessibilityTextByLocale,
        '$path.accessibilityTextByLocale',
        'missing_accessibility_label',
        add,
      );
      for (final assetId in <String?>[
        reaction.visualPoseAssetId,
        reaction.audioAssetId,
      ]) {
        if (assetId != null && !assetsById.containsKey(assetId)) {
          add(
            'unresolved_reference',
            '$path.assetId',
            'Companion asset identity does not resolve.',
          );
        }
      }
    }

    violations.sort((left, right) {
      final byCode = left.code.compareTo(right.code);
      if (byCode != 0) return byCode;
      final byPath = left.path.compareTo(right.path);
      if (byPath != 0) return byPath;
      return left.message.compareTo(right.message);
    });
    return AdventureCatalogValidationResult(violations);
  }

  void requireValid(
    AdventureWorldCatalog catalog, {
    required Map<String, List<int>> packagedBytes,
  }) {
    final result = validate(catalog, packagedBytes: packagedBytes);
    if (!result.isValid) {
      throw AdventureCatalogValidationException(result.violations);
    }
  }
}

typedef _AddViolation = void Function(String code, String path, String message);

const Set<String> _supportedLocales = <String>{'th', 'en'};
final RegExp _canonicalId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,127}$');
final RegExp _semanticVersion = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');
final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

void _checkCanonicalId(String value, String path, _AddViolation add) {
  if (!_canonicalId.hasMatch(value)) {
    add('invalid_id', path, 'Identity is not canonical.');
  }
}

void _validateNodeCopy(
  AdventureNodeDefinition node,
  String path,
  _AddViolation add,
) {
  _validateLocalizedMap(
    node.labelsByLocale,
    '$path.labelsByLocale',
    'missing_locale',
    add,
  );
  _validateLocalizedMap(
    node.accessibilityLabelsByLocale,
    '$path.accessibilityLabelsByLocale',
    'missing_accessibility_label',
    add,
  );
}

void _validateLocalizedMap(
  Map<String, String> values,
  String path,
  String code,
  _AddViolation add,
) {
  for (final locale in _supportedLocales) {
    final value = values[locale];
    if (value == null || value.trim().isEmpty || value.runes.length > 240) {
      add(code, '$path.$locale', 'Required bounded locale copy is missing.');
    }
  }
  for (final locale in values.keys) {
    if (!_supportedLocales.contains(locale)) {
      add('missing_locale', '$path.$locale', 'Locale is unsupported.');
    }
  }
}

void _validateAsset(
  AdventureAssetDefinition asset,
  String path,
  Map<String, List<int>> packagedBytes,
  _AddViolation add,
) {
  final lowerPath = asset.path.toLowerCase();
  final lowerType = asset.mediaType.toLowerCase();
  final isRemote =
      lowerPath.startsWith('http://') || lowerPath.startsWith('https://');
  final isExecutable =
      lowerType.contains('javascript') ||
      lowerType.contains('executable') ||
      lowerPath.endsWith('.js') ||
      lowerPath.endsWith('.wasm') ||
      lowerPath.endsWith('.exe');
  if (isRemote && isExecutable) {
    add(
      'remote_executable_content',
      '$path.path',
      'Remote executable assets are forbidden.',
    );
  }
  final segments = asset.path.replaceAll('\\', '/').split('/');
  if (asset.path.startsWith('/') ||
      asset.path.contains('\\') ||
      asset.path.contains(':') ||
      segments.contains('..') ||
      !asset.path.startsWith('assets/adventure/')) {
    add('unsafe_asset_path', '$path.path', 'Asset path is not package-local.');
  }
  if (asset.contentRevision <= 0) {
    add(
      'invalid_revision',
      '$path.contentRevision',
      'Revision must be positive.',
    );
  }
  final expectedType = switch (lowerPath.split('.').lastOrNull) {
    'svg' => 'image/svg+xml',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'mp3' => 'audio/mpeg',
    'ogg' => 'audio/ogg',
    _ => null,
  };
  if (expectedType == null || lowerType != expectedType) {
    add('type_mismatch', '$path.mediaType', 'Media type does not match path.');
  }
  final bytes = packagedBytes[asset.path];
  if (bytes == null) {
    add('missing_asset', '$path.path', 'Packaged asset bytes are unavailable.');
    return;
  }
  if (asset.byteSize != bytes.length) {
    add(
      'size_mismatch',
      '$path.byteSize',
      'Declared byte size does not match.',
    );
  }
  if (!_sha256.hasMatch(asset.checksumSha256) ||
      sha256.convert(bytes).toString() != asset.checksumSha256) {
    add(
      'checksum_mismatch',
      '$path.checksumSha256',
      'Declared SHA-256 does not match.',
    );
  }
}

void _findCycles(
  Map<String, AdventureNodeDefinition> nodesById,
  _AddViolation add,
) {
  final states = <String, int>{};
  final cycleNodes = <String>{};

  void visit(String nodeId, List<String> stack) {
    final state = states[nodeId] ?? 0;
    if (state == 2) return;
    if (state == 1) {
      final start = stack.indexOf(nodeId);
      cycleNodes.addAll(start < 0 ? <String>[nodeId] : stack.sublist(start));
      return;
    }
    states[nodeId] = 1;
    final nextStack = <String>[...stack, nodeId];
    final refs = nodesById[nodeId]?.prerequisiteNodeIds.toList() ?? <String>[];
    refs.sort();
    for (final ref in refs) {
      if (nodesById.containsKey(ref)) visit(ref, nextStack);
    }
    states[nodeId] = 2;
  }

  final nodeIds = nodesById.keys.toList()..sort();
  for (final nodeId in nodeIds) {
    visit(nodeId, const <String>[]);
  }
  for (final nodeId in cycleNodes.toList()..sort()) {
    add('graph_cycle', 'nodes.$nodeId', 'Prerequisite graph contains a cycle.');
  }
}
