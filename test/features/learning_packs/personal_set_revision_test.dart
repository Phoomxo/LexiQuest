import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';

void main() {
  final pin = SenseCrosswalkPin.fromJson({
    'corpusManifestHash': 'a' * 64,
    'revision': 1,
    'artifactHash': 'b' * 64,
  });
  SenseRef ref(String word, {String? artifact}) => SenseRef.fromJson({
    'corpusManifestHash': 'a' * 64,
    'wordId': word,
    'senseKey': 'object',
    'senseRevision': 1,
    'lexicalArtifactHash': artifact ?? 'c' * 64,
  });
  PersonalSetRevision create({
    List<SenseRef>? members,
    Map<String, String> filters = const {},
    String title = 'My objects',
    int prior = 0,
    bool archived = false,
  }) => PersonalSetRevision.create(
    setId: 'set:one',
    operationId: 'operation:one',
    expectedPriorRevision: prior,
    createdAtUtcMs: 1000,
    title: title,
    crosswalkPin: pin,
    members: members ?? [ref('book')],
    filterSnapshot: filters,
    archived: archived,
  );

  test('exact pin and ordered members survive a JSON restart roundtrip', () {
    final original = create(members: [ref('book'), ref('cup')]);
    final restored = PersonalSetRevision.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(original.toJson())) as Map,
      ),
    );
    expect(restored.toJson(), original.toJson());
    expect(restored.toJson()['crosswalkPin'], pin.toJson());
    expect(restored.toJson()['revision'], 1);
    expect(restored.members, [ref('book'), ref('cup')]);
    expect(restored.payloadHash, original.payloadHash);
  });
  test('caller mutation cannot change members filters or retry identity', () {
    final members = [ref('book')];
    final filters = {'query': 'book'};
    final saved = create(members: members, filters: filters);
    final hash = saved.payloadHash;
    members.add(ref('cup'));
    filters['query'] = 'cup';
    expect(saved.members, [ref('book')]);
    expect(saved.filterSnapshot, {'query': 'book'});
    expect(saved.payloadHash, hash);
    expect(() => saved.members.clear(), throwsUnsupportedError);
    expect(() => saved.filterSnapshot.clear(), throwsUnsupportedError);
  });
  test(
    'canonical filters ignore insertion order but content changes change hash',
    () {
      final first = create(filters: {'query': 'a', 'level': 'A1'});
      final second = create(filters: {'level': 'A1', 'query': 'a'});
      expect(first.payloadHash, second.payloadHash);
      expect(
        create(title: 'Different').payloadHash,
        isNot(create().payloadHash),
      );
      expect(create(prior: 1).payloadHash, isNot(create().payloadHash));
      expect(
        create(prior: 1, archived: true).payloadHash,
        isNot(create(prior: 1).payloadHash),
      );
    },
  );
  test(
    'reject empty exact duplicate and ambiguous semantic member identities',
    () {
      for (final members in <List<SenseRef>>[
        [],
        [ref('book'), ref('book')],
        [ref('book'), ref('book', artifact: 'd' * 64)],
      ]) {
        expect(() => create(members: members), throwsFormatException);
      }
    },
  );
  test('reject cross-corpus reference before persistence', () {
    final other = SenseRef.fromJson({
      ...ref('book').toJson(),
      'corpusManifestHash': 'd' * 64,
    });
    expect(() => create(members: [other]), throwsFormatException);
  });
  test('reject malformed titles revision and initial archive', () {
    for (final title in ['', ' spaced ', 'line\nbreak', 'x' * 121]) {
      expect(() => create(title: title), throwsFormatException);
    }
    expect(() => create(prior: -1), throwsFormatException);
    expect(() => create(prior: 0x7fffffff), throwsFormatException);
    expect(() => create(archived: true), throwsFormatException);
  });
  test(
    'strict decoder rejects unknown fields future schema and changed hash',
    () {
      final json = create().toJson();
      for (final bad in [
        {...json, 'unknown': true},
        {...json, 'schemaVersion': 2},
        {...json, 'payloadHash': '0' * 64},
        {...json, 'revision': 3},
        {...json, 'title': 'Changed'},
        {...json}..remove('crosswalkPin'),
      ]) {
        expect(() => PersonalSetRevision.fromJson(bad), throwsFormatException);
      }
    },
  );
  test('revision two preserves original revision and exact historical pin', () {
    final first = create();
    final second = create(prior: 1, members: [ref('book'), ref('cup')]);
    final archived = create(prior: 2, members: second.members, archived: true);
    expect(first.toJson()['revision'], 1);
    expect(first.members.length, 1);
    expect(second.toJson()['revision'], 2);
    expect(archived.toJson()['revision'], 3);
    expect(archived.toJson()['archived'], true);
    expect(archived.toJson()['crosswalkPin'], pin.toJson());
  });

  test('schema version is an integer and nested field failures are typed', () {
    final json = create().toJson();
    for (final bad in <Map<String, Object?>>[
      {...json, 'schemaVersion': 1.0},
      {
        ...json,
        'members': [null],
      },
      {
        ...json,
        'members': ['book'],
      },
      {
        ...json,
        'filterSnapshot': {'query': 1},
      },
      {
        ...json,
        'crosswalkPin': {1: 'wrong key'},
      },
      {...json, 'createdAtUtcMs': 1.0},
      {...json, 'archived': 'false'},
    ]) {
      expect(() => PersonalSetRevision.fromJson(bad), throwsFormatException);
    }
  });

  test(
    'bounded payload rejects excess members filters and oversized values',
    () {
      expect(
        () => create(members: List.generate(501, (i) => ref('word:$i'))),
        throwsFormatException,
      );
      expect(
        () => create(filters: {for (var i = 0; i < 17; i++) 'key:$i': 'v'}),
        throwsFormatException,
      );
      expect(
        () => create(filters: {'query': 'a' * 257}),
        throwsFormatException,
      );
      expect(() => create(filters: {'a' * 65: 'v'}), throwsFormatException);
    },
  );

  test('detached serialization mutation cannot alter retained revision', () {
    final saved = create();
    final hash = saved.payloadHash;
    final json = saved.toJson();
    (json['crosswalkPin'] as Map)['revision'] = 99;
    ((json['members'] as List).first as Map)['wordId'] = 'changed';
    expect(saved.payloadHash, hash);
    expect(saved.toJson()['crosswalkPin'], pin.toJson());
    expect(saved.members.single.wordId, 'book');
  });
}
