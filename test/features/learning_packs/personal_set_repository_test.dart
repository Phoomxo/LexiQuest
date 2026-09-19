import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late File file;
  late DriftPersonalSetRepository repository;
  late List<SenseRef> refs;
  var available = true;
  Future<void> Function()? beforeLoad;
  final now = DateTime.utc(2026, 9, 20);
  final pin = SenseCrosswalkPin.fromJson({
    'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
    'revision': 1,
    'artifactHash': PackagedSenseCrosswalk.artifactHash,
  });
  void wire() {
    repository = DriftPersonalSetRepository(
      database,
      SenseCrosswalkRepository(
        DriftContentManifestRepository(
          database,
          loadArtifactBytes: (identity) async {
            await beforeLoad?.call();
            return available
                ? File(PackagedSenseCrosswalk.assetPath).readAsBytes()
                : null;
          },
        ),
      ),
      nowUtc: () => now,
    );
  }

  PersonalSetRevision value({
    String set = 'set',
    String operation = 'op1',
    int prior = 0,
    bool archived = false,
    List<SenseRef>? members,
    String title = 'Objects',
  }) => PersonalSetRevision.create(
    setId: set,
    operationId: operation,
    expectedPriorRevision: prior,
    createdAtUtcMs: now.millisecondsSinceEpoch,
    title: title,
    crosswalkPin: pin,
    members: members ?? refs.take(2).toList(),
    archived: archived,
  );
  Future<PersonalSetRevision> save(
    PersonalSetRevision value, {
    String owner = 'a',
    String token = 'lease',
  }) => repository.save(ownerId: owner, leaseToken: token, revision: value);
  Future<PersonalSetRevision?> read(int revision, {String owner = 'a'}) =>
      repository.readExact(ownerId: owner, setId: 'set', revision: revision);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-set-');
    file = File('${directory.path}/data.sqlite');
    database = AppDatabase(NativeDatabase(file));
    available = true;
    beforeLoad = null;
    wire();
    await database.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1), ('b', 1, 0)",
    );
    final artifact = PackagedSenseCrosswalk.verify(
      await File(PackagedSenseCrosswalk.assetPath).readAsBytes(),
    );
    await DriftContentManifestRepository(
      database,
    ).provisionPackagedArtifact(artifact);
    refs = (await repository.crosswalks.requirePinned(
      pin,
    )).entries.map((e) => e.ref).toList();
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'lease',
        nowUtc: now,
        leaseDuration: const Duration(hours: 1),
      ),
      isTrue,
    );
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'owner archive exports exact history and erasure preserves other owner',
    () async {
      await save(value());
      await save(value(operation: 'op2', prior: 1, archived: true));
      final artifact = await OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => now,
      ).prepareActive();
      final content =
          (jsonDecode(utf8.decode(artifact.bytes)) as Map)['content'] as Map;
      final tables = content['tables'] as List;
      final records =
          (tables.cast<Map>().singleWhere(
                (r) => r['alias'] == 'personalSetRevisions',
              )['records']
              as List);
      expect(records.map((r) => r['revision']), [
        value().toJson(),
        value(operation: 'op2', prior: 1, archived: true).toJson(),
      ]);
      await database.customStatement(
        "UPDATE local_owners SET is_active = CASE WHEN id = 'b' THEN 1 ELSE 0 END",
      );
      await save(value(), owner: 'b');
      await LocalDataDeletion(
        database,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'a');
      expect(await read(1), isNull);
      expect((await read(1, owner: 'b'))!.payloadHash, value().payloadHash);
      expect(
        (await database.customSelect('PRAGMA foreign_key_check').get()),
        isEmpty,
      );
    },
  );

  test(
    'actual guest upgrade moves revisions and members atomically without rehash',
    () async {
      await save(value());
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = 'uid', account_state = 'firebaseBound' WHERE id = 'b'",
      );
      await DriftOwnerOperationGate(database).release(token: 'lease');
      final upgrade = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => now,
        generateConflictId: () => 'conflict',
        generateOwnerId: () => 'guest',
        generateOwnerOperationToken: () => 'upgrade',
        deleteOwnerSecrets: (_) async {},
      );
      final result = await upgrade.upgrade(
        activeOwnerId: 'a',
        firebaseUid: 'uid',
      );
      expect(result.targetOwnerId, 'b');
      expect(await read(1), isNull);
      expect((await read(1, owner: 'b'))!.toJson(), value().toJson());
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'lease loss across asynchronous load rejects A to B to A late save',
    () async {
      beforeLoad = () async {
        await DriftOwnerOperationGate(database).release(token: 'lease');
        await database.customStatement(
          "UPDATE local_owners SET is_active = CASE WHEN id = 'b' THEN 1 ELSE 0 END",
        );
        await database.customStatement(
          "UPDATE local_owners SET is_active = CASE WHEN id = 'a' THEN 1 ELSE 0 END",
        );
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'new-generation',
            nowUtc: now,
            leaseDuration: const Duration(hours: 1),
          ),
          isTrue,
        );
      };
      await expectLater(save(value()), throwsStateError);
      expect(await read(1), isNull);
    },
  );

  test('failure on second member rolls back revision and first member', () async {
    await database.customStatement(
      "CREATE TRIGGER inject_member_failure BEFORE INSERT ON personal_set_members WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(save(value()), throwsA(anything));
    expect(await read(1), isNull);
    expect(await database.select(database.personalSetMembers).get(), isEmpty);
    await database.customStatement('DROP TRIGGER inject_member_failure');
    expect((await save(value())).revision, 1);
  });

  test(
    'two competing saves admit one revision and retain its complete members',
    () async {
      final outcomes = await Future.wait([
        save(value()).then<Object>((r) => r).catchError((Object e) => e),
        save(
          value(operation: 'competitor', members: [refs.last]),
        ).then<Object>((r) => r).catchError((Object e) => e),
      ]);
      expect(outcomes.whereType<PersonalSetRevision>(), hasLength(1));
      expect(outcomes.whereType<StateError>(), hasLength(1));
      final winner = outcomes.whereType<PersonalSetRevision>().single;
      expect((await read(1))!.toJson(), winner.toJson());
    },
  );

  test(
    'atomic save survives restart and exact lost-ack replay without content',
    () async {
      final first = value();
      expect((await save(first)).toJson(), first.toJson());
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      wire();
      available = false;
      expect((await read(1))!.toJson(), first.toJson());
      expect((await save(first)).toJson(), first.toJson());
      expect(await read(1, owner: 'b'), isNull);
      expect(await repository.listLatest(ownerId: 'b'), isEmpty);
      expect(
        (await database
                .customSelect('SELECT COUNT(*) AS n FROM personal_set_members')
                .getSingle())
            .read<int>('n'),
        2,
      );
    },
  );

  test(
    'guest merge key collision rolls back both owners without discarding history',
    () async {
      await save(value());
      await database.customStatement(
        "UPDATE local_owners SET is_active = CASE WHEN id = 'b' THEN 1 ELSE 0 END",
      );
      await save(value(title: 'Different target history'), owner: 'b');
      await database.customStatement(
        "UPDATE local_owners SET is_active = CASE WHEN id = 'a' THEN 1 ELSE 0 END",
      );
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = 'uid', account_state = 'firebaseBound' WHERE id = 'b'",
      );
      await DriftOwnerOperationGate(database).release(token: 'lease');
      final upgrade = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => now,
        generateConflictId: () => 'conflict',
        generateOwnerId: () => 'guest',
        generateOwnerOperationToken: () => 'upgrade',
        deleteOwnerSecrets: (_) async {},
      );
      await expectLater(
        upgrade.upgrade(activeOwnerId: 'a', firebaseUid: 'uid'),
        throwsA(anything),
      );
      expect((await read(1))!.toJson(), value().toJson());
      expect(
        (await read(1, owner: 'b'))!.toJson(),
        value(title: 'Different target history').toJson(),
      );
      final active = await database
          .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
          .getSingle();
      expect(active.read<String>('id'), 'a');
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'damaged member projection cannot be read exported or accepted as replay',
    () async {
      await save(value());
      await database.customStatement(
        'DELETE FROM personal_set_members WHERE position = 1',
      );
      await expectLater(read(1), throwsStateError);
      await expectLater(save(value()), throwsStateError);
      await expectLater(
        OwnerLifecycleArchiveExporter(
          database: database,
          nowUtc: () => now,
        ).prepareActive(),
        throwsStateError,
      );
    },
  );
  test(
    'operation collision and stale CAS preserve prior immutable data',
    () async {
      await save(value());
      await expectLater(save(value(title: 'Changed')), throwsStateError);
      await expectLater(save(value(set: 'other')), throwsStateError);
      await expectLater(save(value(operation: 'new')), throwsStateError);
      final next = value(operation: 'op2', prior: 1, members: [refs.last]);
      await save(next);
      expect((await read(1))!.members, refs.take(2));
      expect((await read(2))!.toJson(), next.toJson());
      expect((await repository.listLatest(ownerId: 'a')).single.revision, 2);
    },
  );
  test(
    'archive retains members pin and metadata; old revisions reopen',
    () async {
      await save(value());
      await expectLater(
        save(
          value(
            operation: 'bad',
            prior: 1,
            archived: true,
            members: [refs.last],
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        save(
          value(
            operation: 'bad2',
            prior: 1,
            archived: true,
            title: 'Replacement',
          ),
        ),
        throwsStateError,
      );
      available = false;
      await save(value(operation: 'archive', prior: 1, archived: true));
      expect(await repository.listLatest(ownerId: 'a'), isEmpty);
      expect(
        (await repository.listLatest(
          ownerId: 'a',
          includeArchived: true,
        )).single.archived,
        isTrue,
      );
      expect((await read(1))!.archived, isFalse);
    },
  );
  test('missing pin and unknown sense never leave partial rows', () async {
    available = false;
    await expectLater(save(value()), throwsA(anything));
    expect(await read(1), isNull);
    available = true;
    final unknown = SenseRef.fromJson({
      ...refs.first.toJson(),
      'senseKey': 'unknown',
    });
    await expectLater(
      save(value(members: [refs.first, unknown])),
      throwsA(anything),
    );
    expect(await read(1), isNull);
    expect(
      (await database
              .customSelect('SELECT COUNT(*) AS n FROM personal_set_members')
              .getSingle())
          .read<int>('n'),
      0,
    );
  });
  test('wrong owner and expired lease cannot write or replay', () async {
    await expectLater(save(value(), owner: 'b'), throwsStateError);
    await expectLater(save(value(), token: 'wrong'), throwsStateError);
    await save(value());
    await DriftOwnerOperationGate(database).release(token: 'lease');
    await expectLater(save(value()), throwsStateError);
    expect((await read(1))!.operationId, 'op1');
  });
  test('SQL cannot replace or mutate revision and member payloads', () async {
    await save(value());
    await expectLater(
      database.customStatement(
        "UPDATE personal_set_revisions SET payload_json = '{}'",
      ),
      throwsA(anything),
    );
    await expectLater(
      database.customStatement(
        "UPDATE personal_set_members SET sense_ref_json = '{}'",
      ),
      throwsA(anything),
    );
    await expectLater(
      database.customStatement(
        'INSERT OR REPLACE INTO personal_set_revisions SELECT * FROM personal_set_revisions',
      ),
      throwsA(anything),
    );
    await expectLater(
      database.customStatement(
        'INSERT OR REPLACE INTO personal_set_members SELECT * FROM personal_set_members',
      ),
      throwsA(anything),
    );
    expect((await read(1))!.toJson(), value().toJson());
  });
}
