import 'dart:convert';

import 'quest_models.dart';

enum QuestDefinitionSnapshotOrigin { capturedAssignment, migrationCatalog }

final class QuestDefinitionSnapshot {
  const QuestDefinitionSnapshot({
    required this.definition,
    required this.origin,
  });
  final QuestDefinition definition;
  final QuestDefinitionSnapshotOrigin origin;
}

/// One bounded encoding for catalog storage and immutable assignment history.
abstract final class QuestDefinitionCodec {
  static const maximumBytes = 65536;

  static String encode(QuestDefinitionSnapshot snapshot) {
    validate(snapshot.definition);
    final encoded = jsonEncode({
      'version': 1,
      'origin': snapshot.origin.name,
      'definition': definitionMap(snapshot.definition),
    });
    _requireBudget(encoded);
    return encoded;
  }

  static QuestDefinitionSnapshot decode(String source) {
    _requireBudget(source);
    try {
      final value = _map(jsonDecode(source), {
        'version',
        'origin',
        'definition',
      });
      if (value['version'] != 1)
        throw const FormatException('unknown quest snapshot version');
      final origin = QuestDefinitionSnapshotOrigin.values.byName(
        value['origin'] as String,
      );
      return QuestDefinitionSnapshot(
        definition: _definition(value['definition']),
        origin: origin,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('invalid quest snapshot');
    }
  }

  static QuestDefinition fromStorage(Map<String, Object?> row) {
    try {
      return _definition({
        'questId': row['quest_id'],
        'catalogVersion': row['catalog_version'],
        'title': row['title'],
        'description': row['description'],
        'type': row['type'],
        'objectives': jsonDecode(row['objectives_json'] as String),
        'reward': jsonDecode(row['reward_json'] as String),
        'expiresInMs': row['expires_in_ms'],
        'tags': jsonDecode(row['tags_json'] as String),
      });
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('invalid stored quest definition');
    }
  }

  static Map<String, Object?> definitionMap(QuestDefinition definition) => {
    'questId': definition.questId,
    'catalogVersion': definition.catalogVersion,
    'title': definition.title,
    'description': definition.description,
    'type': definition.type.name,
    'objectives': objectivesMap(definition.objectives),
    'reward': rewardMap(definition.reward),
    'expiresInMs': definition.expiresIn?.inMilliseconds,
    'tags': definition.tags,
  };

  static List<Map<String, Object?>> objectivesMap(
    List<QuestObjective> objectives,
  ) => [
    for (final objective in objectives)
      {
        'objectiveId': objective.objectiveId,
        'description': objective.description,
        'targetCount': objective.targetCount,
        'eventType': objective.criteria.eventType,
        'filters': objective.criteria.filters,
      },
  ];
  static Map<String, Object?> rewardMap(RewardSpec reward) => {
    'xpAmount': reward.xpAmount,
    'rewardItemId': reward.rewardItemId,
  };

  static bool sameDefinition(QuestDefinition left, QuestDefinition right) =>
      _same(definitionMap(left), definitionMap(right));

  static bool matchesProgress(
    QuestDefinition definition,
    List<ObjectiveProgress> progress,
  ) {
    if (progress.length != definition.objectives.length) return false;
    final byId = <String, ObjectiveProgress>{};
    for (final item in progress) {
      if (byId.containsKey(item.objectiveId) ||
          item.currentCount < 0 ||
          item.currentCount > item.targetCount ||
          item.sourceEventIds.toSet().length != item.sourceEventIds.length)
        return false;
      byId[item.objectiveId] = item;
    }
    return definition.objectives.every(
      (objective) =>
          byId[objective.objectiveId]?.targetCount == objective.targetCount,
    );
  }

  static bool matchesStoredProgress(
    QuestDefinition definition,
    List<Map<String, Object?>> rows,
  ) => matchesProgress(
    definition,
    rows
        .map(
          (row) => ObjectiveProgress(
            objectiveId: row['objective_id'] as String,
            currentCount: row['current_count'] as int,
            targetCount: row['target_count'] as int,
            sourceEventIds:
                (jsonDecode(row['source_event_ids_json'] as String) as List)
                    .cast<String>(),
          ),
        )
        .toList(growable: false),
  );

  static void validate(QuestDefinition definition) {
    if (!_identifier(definition.questId) ||
        definition.catalogVersion < 1 ||
        definition.objectives.isEmpty ||
        definition.objectives.length > 64 ||
        definition.reward.xpAmount < 0 ||
        (definition.reward.rewardItemId != null &&
            !_identifier(definition.reward.rewardItemId!)) ||
        (definition.expiresIn != null &&
            (definition.expiresIn!.inMilliseconds <= 0 ||
                definition.expiresIn!.inMilliseconds > 8640000000000000))) {
      throw const FormatException('invalid quest definition');
    }
    final ids = <String>{};
    for (final objective in definition.objectives) {
      if (!_identifier(objective.objectiveId) ||
          !_identifier(objective.criteria.eventType) ||
          objective.targetCount < 1 ||
          !ids.add(objective.objectiveId)) {
        throw const FormatException('invalid quest objective');
      }
      _jsonValue(objective.criteria.filters, 0);
    }
  }

  static QuestDefinition _definition(Object? raw) {
    final value = _map(raw, {
      'questId',
      'catalogVersion',
      'title',
      'description',
      'type',
      'objectives',
      'reward',
      'expiresInMs',
      'tags',
    });
    final reward = _map(value['reward'], {'xpAmount', 'rewardItemId'});
    final objectives = value['objectives'] as List;
    if (objectives.isEmpty || objectives.length > 64)
      throw const FormatException('invalid quest objective count');
    final duration = value['expiresInMs'] as int?;
    if (duration != null && (duration <= 0 || duration > 8640000000000000))
      throw const FormatException('invalid quest duration');
    final result = QuestDefinition(
      questId: value['questId'] as String,
      catalogVersion: value['catalogVersion'] as int,
      title: value['title'] as String,
      description: value['description'] as String,
      type: QuestType.values.byName(value['type'] as String),
      objectives: List.unmodifiable(
        objectives.map((raw) {
          final item = _map(raw, {
            'objectiveId',
            'description',
            'targetCount',
            'eventType',
            'filters',
          });
          final filters = item['filters'];
          if (filters != null && filters is! Map<String, dynamic>)
            throw const FormatException('invalid quest filters');
          return QuestObjective(
            objectiveId: item['objectiveId'] as String,
            description: item['description'] as String,
            targetCount: item['targetCount'] as int,
            criteria: ObjectiveCriteria(
              eventType: item['eventType'] as String,
              filters: filters == null
                  ? null
                  : _freeze(filters) as Map<String, dynamic>,
            ),
          );
        }),
      ),
      reward: RewardSpec(
        xpAmount: reward['xpAmount'] as int,
        rewardItemId: reward['rewardItemId'] as String?,
      ),
      expiresIn: duration == null ? null : Duration(milliseconds: duration),
      tags: List<String>.unmodifiable((value['tags'] as List).cast<String>()),
    );
    validate(result);
    _requireBudget(jsonEncode(definitionMap(result)));
    return result;
  }

  static Map<String, dynamic> _map(Object? value, Set<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !keys.every(value.containsKey)) {
      throw const FormatException('invalid quest object shape');
    }
    return value;
  }

  static void _requireBudget(String value) {
    if (utf8.encode(value).length > maximumBytes)
      throw const FormatException('quest snapshot exceeds 64 KiB');
  }

  static bool _identifier(String value) =>
      value.isNotEmpty && value.trim() == value && value.runes.length <= 256;
  static void _jsonValue(Object? value, int depth) {
    if (depth > 16)
      throw const FormatException('quest filter nesting exceeds limit');
    if (value == null || value is String || value is bool || value is int)
      return;
    if (value is double && value.isFinite) return;
    if (value is List) {
      for (final item in value) {
        _jsonValue(item, depth + 1);
      }
      return;
    }
    if (value is Map<String, dynamic>) {
      for (final item in value.values) {
        _jsonValue(item, depth + 1);
      }
      return;
    }
    throw const FormatException('invalid quest filter value');
  }

  static Object? _freeze(Object? value) => value is Map<String, dynamic>
      ? Map<String, dynamic>.unmodifiable(
          value.map((key, item) => MapEntry(key, _freeze(item))),
        )
      : value is List
      ? List<Object?>.unmodifiable(value.map(_freeze))
      : value;
  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map)
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
    if (a is List && b is List)
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    return a == b;
  }
}
