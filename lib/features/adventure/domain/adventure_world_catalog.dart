enum AdventureCatalogQaState { draft, internalApproved, pilotApproved }

enum AdventureNodeKind { resume, review, mission, rewardPreview }

final class AdventureAssetReference {
  const AdventureAssetReference({
    required this.assetId,
    required this.requiredRevision,
  });

  final String assetId;
  final int requiredRevision;

  Map<String, Object?> toJson() => <String, Object?>{
    'assetId': assetId,
    'requiredRevision': requiredRevision,
  };

  factory AdventureAssetReference.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{'assetId', 'requiredRevision'});
    return AdventureAssetReference(
      assetId: _string(json, 'assetId'),
      requiredRevision: _integer(json, 'requiredRevision'),
    );
  }
}

final class AdventureNodeDefinition {
  AdventureNodeDefinition({
    required this.nodeId,
    required this.kind,
    required this.revision,
    required List<String> prerequisiteNodeIds,
    required Map<String, String> labelsByLocale,
    required Map<String, String> accessibilityLabelsByLocale,
    required List<AdventureAssetReference> assetReferences,
  }) : prerequisiteNodeIds = List<String>.unmodifiable(prerequisiteNodeIds),
       labelsByLocale = Map<String, String>.unmodifiable(labelsByLocale),
       accessibilityLabelsByLocale = Map<String, String>.unmodifiable(
         accessibilityLabelsByLocale,
       ),
       assetReferences = List<AdventureAssetReference>.unmodifiable(
         assetReferences,
       );

  final String nodeId;
  final AdventureNodeKind kind;
  final int revision;
  final List<String> prerequisiteNodeIds;
  final Map<String, String> labelsByLocale;
  final Map<String, String> accessibilityLabelsByLocale;
  final List<AdventureAssetReference> assetReferences;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'kind': kind.name,
    'revision': revision,
    'prerequisiteNodeIds': prerequisiteNodeIds,
    'labelsByLocale': labelsByLocale,
    'accessibilityLabelsByLocale': accessibilityLabelsByLocale,
    'assetReferences': assetReferences
        .map((reference) => reference.toJson())
        .toList(growable: false),
  };

  factory AdventureNodeDefinition.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'nodeId',
      'kind',
      'revision',
      'prerequisiteNodeIds',
      'labelsByLocale',
      'accessibilityLabelsByLocale',
      'assetReferences',
    });
    return AdventureNodeDefinition(
      nodeId: _string(json, 'nodeId'),
      kind: _decodeEnum(
        _string(json, 'kind'),
        AdventureNodeKind.values,
        'kind',
      ),
      revision: _integer(json, 'revision'),
      prerequisiteNodeIds: _stringList(json, 'prerequisiteNodeIds'),
      labelsByLocale: _stringMap(json, 'labelsByLocale'),
      accessibilityLabelsByLocale: _stringMap(
        json,
        'accessibilityLabelsByLocale',
      ),
      assetReferences: _mapList(
        json,
        'assetReferences',
      ).map(AdventureAssetReference.fromJson).toList(growable: false),
    );
  }
}

final class AdventureWorldDefinition {
  AdventureWorldDefinition({
    required this.worldId,
    required this.revision,
    required List<AdventureNodeDefinition> nodes,
  }) : nodes = List<AdventureNodeDefinition>.unmodifiable(nodes);

  final String worldId;
  final int revision;
  final List<AdventureNodeDefinition> nodes;

  AdventureWorldDefinition copyWith({List<AdventureNodeDefinition>? nodes}) =>
      AdventureWorldDefinition(
        worldId: worldId,
        revision: revision,
        nodes: nodes ?? this.nodes,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'worldId': worldId,
    'revision': revision,
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
  };

  factory AdventureWorldDefinition.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{'worldId', 'revision', 'nodes'});
    return AdventureWorldDefinition(
      worldId: _string(json, 'worldId'),
      revision: _integer(json, 'revision'),
      nodes: _mapList(
        json,
        'nodes',
      ).map(AdventureNodeDefinition.fromJson).toList(growable: false),
    );
  }
}

final class CompanionScriptDefinition {
  CompanionScriptDefinition({
    required this.reactionId,
    required this.revision,
    required Map<String, String> copyByLocale,
    required Map<String, String> accessibilityTextByLocale,
    required this.visualPoseAssetId,
    this.audioAssetId,
  }) : copyByLocale = Map<String, String>.unmodifiable(copyByLocale),
       accessibilityTextByLocale = Map<String, String>.unmodifiable(
         accessibilityTextByLocale,
       );

  final String reactionId;
  final int revision;
  final Map<String, String> copyByLocale;
  final Map<String, String> accessibilityTextByLocale;
  final String visualPoseAssetId;
  final String? audioAssetId;

  Map<String, Object?> toJson() => <String, Object?>{
    'reactionId': reactionId,
    'revision': revision,
    'copyByLocale': copyByLocale,
    'accessibilityTextByLocale': accessibilityTextByLocale,
    'visualPoseAssetId': visualPoseAssetId,
    'audioAssetId': audioAssetId,
  };

  factory CompanionScriptDefinition.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'reactionId',
      'revision',
      'copyByLocale',
      'accessibilityTextByLocale',
      'visualPoseAssetId',
      'audioAssetId',
    });
    return CompanionScriptDefinition(
      reactionId: _string(json, 'reactionId'),
      revision: _integer(json, 'revision'),
      copyByLocale: _stringMap(json, 'copyByLocale'),
      accessibilityTextByLocale: _stringMap(json, 'accessibilityTextByLocale'),
      visualPoseAssetId: _string(json, 'visualPoseAssetId'),
      audioAssetId: _nullableString(json, 'audioAssetId'),
    );
  }
}

final class AdventureAssetDefinition {
  const AdventureAssetDefinition({
    required this.assetId,
    required this.path,
    required this.mediaType,
    required this.contentRevision,
    required this.byteSize,
    required this.checksumSha256,
  });

  final String assetId;
  final String path;
  final String mediaType;
  final int contentRevision;
  final int byteSize;
  final String checksumSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'assetId': assetId,
    'path': path,
    'mediaType': mediaType,
    'contentRevision': contentRevision,
    'byteSize': byteSize,
    'checksumSha256': checksumSha256,
  };

  factory AdventureAssetDefinition.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'assetId',
      'path',
      'mediaType',
      'contentRevision',
      'byteSize',
      'checksumSha256',
    });
    return AdventureAssetDefinition(
      assetId: _string(json, 'assetId'),
      path: _string(json, 'path'),
      mediaType: _string(json, 'mediaType'),
      contentRevision: _integer(json, 'contentRevision'),
      byteSize: _integer(json, 'byteSize'),
      checksumSha256: _string(json, 'checksumSha256'),
    );
  }
}

final class AdventureAssetManifest {
  AdventureAssetManifest({
    required this.manifestId,
    required this.catalogVersion,
    required this.locale,
    required this.revision,
    required List<AdventureAssetDefinition> assets,
  }) : assets = List<AdventureAssetDefinition>.unmodifiable(assets);

  final String manifestId;
  final String catalogVersion;
  final String locale;
  final int revision;
  final List<AdventureAssetDefinition> assets;

  AdventureAssetManifest copyWith({List<AdventureAssetDefinition>? assets}) =>
      AdventureAssetManifest(
        manifestId: manifestId,
        catalogVersion: catalogVersion,
        locale: locale,
        revision: revision,
        assets: assets ?? this.assets,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'manifestId': manifestId,
    'catalogVersion': catalogVersion,
    'locale': locale,
    'revision': revision,
    'assets': assets.map((asset) => asset.toJson()).toList(growable: false),
  };

  factory AdventureAssetManifest.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'manifestId',
      'catalogVersion',
      'locale',
      'revision',
      'assets',
    });
    return AdventureAssetManifest(
      manifestId: _string(json, 'manifestId'),
      catalogVersion: _string(json, 'catalogVersion'),
      locale: _string(json, 'locale'),
      revision: _integer(json, 'revision'),
      assets: _mapList(
        json,
        'assets',
      ).map(AdventureAssetDefinition.fromJson).toList(growable: false),
    );
  }
}

final class AdventureWorldCatalog {
  AdventureWorldCatalog({
    required this.schemaVersion,
    required this.catalogId,
    required this.catalogVersion,
    required this.locale,
    required this.qaState,
    required List<AdventureWorldDefinition> worlds,
    required List<CompanionScriptDefinition> reactions,
    required this.assetManifest,
  }) : worlds = List<AdventureWorldDefinition>.unmodifiable(worlds),
       reactions = List<CompanionScriptDefinition>.unmodifiable(reactions);

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String catalogId;
  final String catalogVersion;
  final String locale;
  final AdventureCatalogQaState qaState;
  final List<AdventureWorldDefinition> worlds;
  final List<CompanionScriptDefinition> reactions;
  final AdventureAssetManifest assetManifest;

  AdventureWorldCatalog copyWith({
    List<AdventureWorldDefinition>? worlds,
    AdventureAssetManifest? assetManifest,
  }) => AdventureWorldCatalog(
    schemaVersion: schemaVersion,
    catalogId: catalogId,
    catalogVersion: catalogVersion,
    locale: locale,
    qaState: qaState,
    worlds: worlds ?? this.worlds,
    reactions: reactions,
    assetManifest: assetManifest ?? this.assetManifest,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'catalogId': catalogId,
    'catalogVersion': catalogVersion,
    'locale': locale,
    'qaState': qaState.name,
    'worlds': worlds.map((world) => world.toJson()).toList(growable: false),
    'reactions': reactions
        .map((reaction) => reaction.toJson())
        .toList(growable: false),
    'assetManifest': assetManifest.toJson(),
  };

  factory AdventureWorldCatalog.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'schemaVersion',
      'catalogId',
      'catalogVersion',
      'locale',
      'qaState',
      'worlds',
      'reactions',
      'assetManifest',
    });
    return AdventureWorldCatalog(
      schemaVersion: _integer(json, 'schemaVersion'),
      catalogId: _string(json, 'catalogId'),
      catalogVersion: _string(json, 'catalogVersion'),
      locale: _string(json, 'locale'),
      qaState: _decodeEnum(
        _string(json, 'qaState'),
        AdventureCatalogQaState.values,
        'qaState',
      ),
      worlds: _mapList(
        json,
        'worlds',
      ).map(AdventureWorldDefinition.fromJson).toList(growable: false),
      reactions: _mapList(
        json,
        'reactions',
      ).map(CompanionScriptDefinition.fromJson).toList(growable: false),
      assetManifest: AdventureAssetManifest.fromJson(
        _map(json, 'assetManifest'),
      ),
    );
  }
}

T _decodeEnum<T extends Enum>(String value, List<T> values, String field) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('Unknown $field: $value');
}

void _requireExactKeys(Map<String, Object?> json, Set<String> expected) {
  final actual = json.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException(
      'Unexpected object keys. Expected ${expected.toList()..sort()}, '
      'received ${actual.toList()..sort()}.',
    );
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null.');
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object.');
  return Map<String, Object?>.from(value);
}

List<Map<String, Object?>> _mapList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key must be a list.');
  try {
    return value
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList(growable: false);
  } on Object catch (error) {
    throw FormatException('$key must contain objects.', error);
  }
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must contain strings.');
  }
  return value.cast<String>().toList(growable: false);
}

Map<String, String> _stringMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map ||
      value.keys.any((item) => item is! String) ||
      value.values.any((item) => item is! String)) {
    throw FormatException('$key must be a string map.');
  }
  return Map<String, String>.from(value);
}
