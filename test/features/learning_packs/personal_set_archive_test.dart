import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_set_archive.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';

void main() {
  PersonalSetRevision revision(
    int prior, {
    bool archived = false,
    String title = 'Books',
  }) => PersonalSetRevision.create(
    setId: 'books',
    operationId: 'op$prior',
    expectedPriorRevision: prior,
    createdAtUtcMs: 1000 + prior,
    title: title,
    archived: archived,
    crosswalkPin: SenseCrosswalkPin.fromJson({
      'corpusManifestHash': 'a' * 64,
      'revision': 1,
      'artifactHash': 'b' * 64,
    }),
    members: [
      SenseRef.fromJson({
        'corpusManifestHash': 'a' * 64,
        'wordId': 'book',
        'senseKey': 'object',
        'senseRevision': 1,
        'lexicalArtifactHash': 'c' * 64,
      }),
    ],
  );
  Map<String, Object?> envelope(Map<String, Object?> content) => {
    'content': content,
    'contentSha256': sha256
        .convert(utf8.encode(jsonEncode(content)))
        .toString(),
  };

  test('owner-bound full history roundtrips with exact revision hashes', () {
    final archive = PersonalSetArchive.create(
      ownerId: 'a',
      revisions: [revision(0), revision(1, archived: true)],
    );
    final decoded = PersonalSetArchive.fromJson(
      jsonDecode(jsonEncode(archive.toJson())) as Map<String, Object?>,
    );
    expect(decoded.ownerId, 'a');
    expect(decoded.revisions.map((r) => r.toJson()), [
      revision(0).toJson(),
      revision(1, archived: true).toJson(),
    ]);
    expect(() => decoded.revisions.clear(), throwsUnsupportedError);
  });
  test(
    'owner tampering and future schema fail even with recomputed checksum',
    () {
      final json = PersonalSetArchive.create(
        ownerId: 'a',
        revisions: [revision(0)],
      ).toJson();
      final content = Map<String, Object?>.from(json['content'] as Map);
      content['ownerId'] = 'b';
      expect(
        () => PersonalSetArchive.fromJson({...json, 'content': content}),
        throwsFormatException,
      );
      content['schemaVersion'] = 3;
      expect(
        () => PersonalSetArchive.fromJson(envelope(content)),
        throwsFormatException,
      );
    },
  );
  test('version one empty extension archive is explicitly decoded', () {
    final archive = PersonalSetArchive.fromJson(
      envelope({
        'schemaVersion': 1,
        'ownerId': 'a',
        'groups': <String, Object?>{},
      }),
    );
    expect(archive.revisions, isEmpty);
    expect(archive.ownerId, 'a');
  });
  test(
    'history rejects gaps duplicate operations and archive content changes',
    () {
      expect(
        () => PersonalSetArchive.create(ownerId: 'a', revisions: [revision(1)]),
        throwsFormatException,
      );
      expect(
        () => PersonalSetArchive.create(
          ownerId: 'a',
          revisions: [revision(0), revision(0)],
        ),
        throwsFormatException,
      );
      expect(
        () => PersonalSetArchive.create(
          ownerId: 'a',
          revisions: [
            revision(0),
            revision(1, archived: true, title: 'Changed'),
          ],
        ),
        throwsFormatException,
      );
    },
  );
  test('strict manifest rejects unknown groups and missing current groups', () {
    for (final groups in [
      <String, Object?>{},
      {'personalSetRevisions': <Object?>[], 'unknown': <Object?>[]},
    ]) {
      expect(
        () => PersonalSetArchive.fromJson(
          envelope({'schemaVersion': 2, 'ownerId': 'a', 'groups': groups}),
        ),
        throwsFormatException,
      );
    }
  });
}
