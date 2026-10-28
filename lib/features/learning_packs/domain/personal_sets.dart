import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'sense_crosswalk.dart';
import 'sense_crosswalk_repository.dart';

/// Immutable input retained across retries, including a lost acknowledgement.
final class PersonalSetRevision {
  PersonalSetRevision._({
    required this.setId,
    required this.operationId,
    required this.expectedPriorRevision,
    required this.createdAtUtcMs,
    required this.title,
    required this.crosswalkPin,
    required this.members,
    required this.archived,
    required this.filterSnapshot,
  });

  factory PersonalSetRevision.fromJson(Map<String, Object?> json) {
    const keys = {
      'schemaVersion',
      'setId',
      'operationId',
      'expectedPriorRevision',
      'revision',
      'createdAtUtcMs',
      'title',
      'crosswalkPin',
      'members',
      'archived',
      'filterSnapshot',
      'payloadHash',
    };
    if (json.length != keys.length ||
        !keys.containsAll(json.keys) ||
        json['schemaVersion'] is! int ||
        json['schemaVersion'] != 1 ||
        json['setId'] is! String ||
        json['operationId'] is! String ||
        json['expectedPriorRevision'] is! int ||
        json['createdAtUtcMs'] is! int ||
        json['title'] is! String ||
        json['crosswalkPin'] is! Map ||
        json['members'] is! List ||
        json['archived'] is! bool ||
        json['filterSnapshot'] is! Map) {
      throw const FormatException('Invalid personal set revision');
    }
    try {
      final result = PersonalSetRevision.create(
        setId: json['setId'] as String,
        operationId: json['operationId'] as String,
        expectedPriorRevision: json['expectedPriorRevision'] as int,
        createdAtUtcMs: json['createdAtUtcMs'] as int,
        title: json['title'] as String,
        crosswalkPin: SenseCrosswalkPin.fromJson(
          Map<String, Object?>.from(json['crosswalkPin'] as Map),
        ),
        members: (json['members'] as List)
            .map(
              (value) =>
                  SenseRef.fromJson(Map<String, Object?>.from(value as Map)),
            )
            .toList(),
        archived: json['archived'] as bool,
        filterSnapshot: Map<String, String>.from(json['filterSnapshot'] as Map),
      );
      if (json['revision'] is! int ||
          json['revision'] != result.revision ||
          json['payloadHash'] != result.payloadHash) {
        throw const FormatException('Personal set revision integrity mismatch');
      }
      return result;
    } on TypeError {
      throw const FormatException('Invalid personal set field type');
    }
  }

  factory PersonalSetRevision.create({
    required String setId,
    required String operationId,
    required int expectedPriorRevision,
    required int createdAtUtcMs,
    required String title,
    required SenseCrosswalkPin crosswalkPin,
    required List<SenseRef> members,
    bool archived = false,
    Map<String, String> filterSnapshot = const {},
  }) {
    _text(setId, 200);
    _text(operationId, 200);
    _text(title, 120);
    if (expectedPriorRevision < 0 ||
        expectedPriorRevision >= 0x7fffffff ||
        createdAtUtcMs < 0 ||
        createdAtUtcMs > 8640000000000000 ||
        (archived && expectedPriorRevision == 0) ||
        members.isEmpty ||
        members.length > 500 ||
        filterSnapshot.length > 16) {
      throw const FormatException('Invalid personal set bounds');
    }
    final identities = <String>{};
    for (final ref in members) {
      final semanticIdentity = jsonEncode([
        ref.wordId,
        ref.senseKey,
        ref.senseRevision,
      ]);
      if (ref.corpusManifestHash != crosswalkPin.corpusManifestHash ||
          !identities.add(semanticIdentity)) {
        throw const FormatException('Duplicate or cross-corpus set member');
      }
    }
    final keys = filterSnapshot.keys.toList()..sort();
    final filters = <String, String>{};
    for (final key in keys) {
      _text(key, 64);
      _text(filterSnapshot[key]!, 256);
      filters[key] = filterSnapshot[key]!;
    }
    return PersonalSetRevision._(
      setId: setId,
      operationId: operationId,
      expectedPriorRevision: expectedPriorRevision,
      createdAtUtcMs: createdAtUtcMs,
      title: title,
      crosswalkPin: crosswalkPin,
      members: List.unmodifiable(members),
      archived: archived,
      filterSnapshot: Map.unmodifiable(filters),
    );
  }

  final String setId, operationId, title;
  final int expectedPriorRevision, createdAtUtcMs;
  final SenseCrosswalkPin crosswalkPin;
  final bool archived;
  final List<SenseRef> members;
  final Map<String, String> filterSnapshot;
  int get revision => expectedPriorRevision + 1;

  // Owner identity is the enclosing repository key. Keeping it outside this
  // immutable payload permits transactional guest remapping without rehashing.
  Map<String, Object?> _payload() => {
    'schemaVersion': 1,
    'setId': setId,
    'operationId': operationId,
    'expectedPriorRevision': expectedPriorRevision,
    'revision': revision,
    'createdAtUtcMs': createdAtUtcMs,
    'title': title,
    'crosswalkPin': crosswalkPin.toJson(),
    'members': members.map((ref) => ref.toJson()).toList(),
    'archived': archived,
    'filterSnapshot': filterSnapshot,
  };
  Map<String, Object?> toJson() => {..._payload(), 'payloadHash': payloadHash};
  String get payloadHash =>
      sha256.convert(utf8.encode(jsonEncode(_payload()))).toString();
}

void _text(String value, int maximum) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > maximum ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw const FormatException('Invalid personal set text');
  }
}
