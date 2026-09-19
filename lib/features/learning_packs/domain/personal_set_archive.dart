import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'personal_sets.dart';

/// Local personal-set backup, deliberately separate from the redacted owner
/// export. Its checksum detects corruption; it is not authentication. Restore
/// additionally requires the active owner and canonical operation lease.
final class PersonalSetArchive {
  PersonalSetArchive._(this.ownerId, this.revisions);

  factory PersonalSetArchive.create({
    required String ownerId,
    required List<PersonalSetRevision> revisions,
  }) {
    if (ownerId.isEmpty ||
        ownerId != ownerId.trim() ||
        ownerId.length > 200 ||
        ownerId.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        revisions.length > 10000) {
      throw const FormatException('Invalid personal set archive bounds');
    }
    final ordered = revisions.toList()
      ..sort((a, b) {
        final set = a.setId.compareTo(b.setId);
        return set == 0 ? a.revision.compareTo(b.revision) : set;
      });
    final latest = <String, PersonalSetRevision>{};
    final operations = <String>{};
    for (final revision in ordered) {
      final prior = latest[revision.setId];
      if (revision.expectedPriorRevision != (prior?.revision ?? 0) ||
          !operations.add(revision.operationId) ||
          (revision.archived &&
              (prior == null || !samePersonalSetContents(prior, revision)))) {
        throw const FormatException('Invalid personal set archive history');
      }
      latest[revision.setId] = revision;
    }
    return PersonalSetArchive._(ownerId, List.unmodifiable(ordered));
  }

  factory PersonalSetArchive.fromJson(Map<String, Object?> json) {
    try {
      if (json.length != 2 ||
          json['content'] is! Map ||
          json['contentSha256'] is! String) {
        throw const FormatException('Invalid personal set archive envelope');
      }
      final content = Map<String, Object?>.from(json['content'] as Map);
      if (sha256.convert(utf8.encode(jsonEncode(content))).toString() !=
              json['contentSha256'] ||
          content.length != 3 ||
          content['schemaVersion'] is! int ||
          content['ownerId'] is! String ||
          content['groups'] is! Map) {
        throw const FormatException('Invalid personal set archive integrity');
      }
      final version = content['schemaVersion'];
      final groups = Map<String, Object?>.from(content['groups'] as Map);
      // The v1 extension envelope has no groups. This is not a claim that the
      // legacy redacted lifecycle export can restore an entire database.
      if (version == 1 && groups.isEmpty) {
        return PersonalSetArchive.create(
          ownerId: content['ownerId'] as String,
          revisions: [],
        );
      }
      if (version != 2 ||
          groups.length != 1 ||
          groups['personalSetRevisions'] is! List) {
        throw const FormatException(
          'Unsupported personal set archive manifest',
        );
      }
      final records = groups['personalSetRevisions'] as List;
      if (records.length > 10000) {
        throw const FormatException('Archive too large');
      }
      return PersonalSetArchive.create(
        ownerId: content['ownerId'] as String,
        revisions: records
            .map(
              (r) => PersonalSetRevision.fromJson(
                Map<String, Object?>.from(r as Map),
              ),
            )
            .toList(),
      );
    } on TypeError {
      throw const FormatException('Invalid personal set archive field type');
    }
  }

  final String ownerId;
  final List<PersonalSetRevision> revisions;
  Map<String, Object?> toJson() {
    final content = <String, Object?>{
      'schemaVersion': 2,
      'ownerId': ownerId,
      'groups': {
        'personalSetRevisions': revisions.map((r) => r.toJson()).toList(),
      },
    };
    return {
      'content': content,
      'contentSha256': sha256
          .convert(utf8.encode(jsonEncode(content)))
          .toString(),
    };
  }
}

bool samePersonalSetContents(PersonalSetRevision a, PersonalSetRevision b) =>
    a.title == b.title &&
    jsonEncode(a.crosswalkPin.toJson()) ==
        jsonEncode(b.crosswalkPin.toJson()) &&
    jsonEncode(a.members.map((r) => r.toJson()).toList()) ==
        jsonEncode(b.members.map((r) => r.toJson()).toList()) &&
    jsonEncode(a.filterSnapshot) == jsonEncode(b.filterSnapshot);
