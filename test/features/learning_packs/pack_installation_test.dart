import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show Value, Variable, QueryInterceptor, QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';

void main() {
  test(
    'install commits original canonical words and exact replay without duplicates',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final owner = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final intent = h.packs.prepareImport(
        scope: owner,
        pack: _pack(),
        pinned: true,
      );
      final installed = await h.packs.importPack(intent);
      expect(installed.ownerId, 'a');
      expect(installed.isInstalled, isTrue);
      expect(installed.cacheState, PackCacheState.verified);
      expect(installed.isPinned, isTrue);
      expect(installed.revision, 1);
      final rows = await h.rows('vocabulary_words');
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['spelling']).toSet(), {'cat', 'dog'});
      expect(rows.every((row) => row['owner_id'] == 'a'), isTrue);
      expect(await h.rows('vocabulary_import_rows'), hasLength(2));
      expect(await h.rows('lexical_content_snapshots'), hasLength(2));
      final beforeReplay = await h.snapshot();
      final replay = await h.packs.importPack(intent);
      expect(replay.id, installed.id);
      expect(replay.createdAtUtc, intent.atUtc);
      expect(replay.installedAtUtc, intent.atUtc);
      expect(replay.revision, 1);
      expect(await h.snapshot(), beforeReplay);
      final detail = await h.packs.detail(owner, installed.id);
      expect(
        detail.content!.manifest.payloadSha256,
        intent.pack.manifest.payloadSha256,
      );
      expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
      expect(detail.bindings, hasLength(2));
      for (final table in h.database.allTables) {
        if (!const {
          'local_owners',
          'vocabulary_categories',
          'vocabulary_words',
          'vocabulary_imports',
          'vocabulary_import_rows',
          'outbox_operations',
          'learning_pack_versions',
          'lexical_content_snapshots',
        }.contains(table.actualTableName)) {
          expect(
            await h.rows(table.actualTableName),
            isEmpty,
            reason: table.actualTableName,
          );
        }
      }
    },
  );
  test(
    'owner absence remains row-free and unavailable databases use the public failure',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final h = _Harness(database);
      await h.packs.watchActiveOwnerId().firstWhere((owner) => owner == null);
      final before = await h.snapshot();
      expect(await h.packs.captureOwner(stillCurrent: () => true), isNull);
      expect(await h.snapshot(), before);
      expect(before.values.every((rows) => rows.isEmpty), isTrue);
      await h.close();
      await expectLater(
        h.repository.readActiveOwnerId(),
        _failure(PackStorageFailureCode.unavailable),
      );
    },
  );

  test(
    'cache-only download materializes no words until explicit installation',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final pack = _pack();
      final before = await h.snapshot()
        ..remove('learning_pack_versions');
      final cached = await h.packs.importPack(
        h.packs.prepareImport(
          scope: scope,
          pack: pack,
          install: false,
          pinned: true,
        ),
      );
      expect(cached.isInstalled, isFalse);
      expect(cached.cacheState, PackCacheState.verified);
      expect(
        await h.snapshot()
          ..remove('learning_pack_versions'),
        before,
      );
      final detail = await h.packs.detail(scope, cached.id);
      expect(detail.bindings, isEmpty);
      expect(detail.content!.packageSha256, pack.packageSha256);
      final intent = h.packs.prepareImport(
        scope: scope,
        pack: pack,
        expectedRevision: cached.revision,
        pinned: true,
      );
      final installed = await h.packs.importPack(intent);
      expect(installed.id, cached.id);
      expect(installed.createdAtUtc, cached.createdAtUtc);
      expect(installed.installedAtUtc, intent.atUtc);
      expect(installed.revision, 2);
      expect(await h.rows('vocabulary_words'), hasLength(2));
      expect(await h.rows('lexical_content_snapshots'), hasLength(2));
      final acknowledged = await h.snapshot();
      await h.packs.importPack(intent);
      expect(await h.snapshot(), acknowledged);
    },
  );

  test(
    'same identity different digest rejects; a new version preserves the old version',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final first = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: _pack()),
      );
      final before = await h.snapshot();
      await expectLater(
        h.packs.importPack(
          h.packs.prepareImport(
            scope: scope,
            pack: _pack(catMeaning: 'แมวที่แก้ไข'),
          ),
        ),
        _failure(PackStorageFailureCode.conflict),
      );
      expect(await h.snapshot(), before);
      final oldRow = (await h.rows('learning_pack_versions')).single;
      final second = await h.packs.importPack(
        h.packs.prepareImport(
          scope: scope,
          pack: _pack(version: '1.0.1'),
        ),
      );
      expect(second.id, isNot(first.id));
      expect(
        (await h.rows(
          'learning_pack_versions',
        )).firstWhere((row) => row['id'] == first.id),
        oldRow,
      );
      expect(await h.rows('vocabulary_words'), hasLength(4));
      expect(await h.rows('lexical_content_snapshots'), hasLength(4));
    },
  );

  test(
    'changed replay of an acknowledged mutation conflicts without changing any table',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final first = h.packs.prepareImport(
        scope: scope,
        pack: _pack(),
        pinned: true,
      );
      await h.packs.importPack(first);
      final before = await h.snapshot();
      final changed = PackImportIntent(
        expectedOwnerId: first.expectedOwnerId,
        pack: first.pack,
        source: first.source,
        install: true,
        pinned: false,
        expectedRevision: first.expectedRevision,
        mutationId: first.mutationId,
        atUtc: first.atUtc,
        stillCurrent: () => scope.isCurrent,
      );
      await expectLater(
        h.repository.importPack(changed),
        _failure(PackStorageFailureCode.conflict),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'cache removal and exact repair preserve every canonical and lexical row',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final original = _pack();
      final pretty = const LearningPackCodec().decode(
        Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent(
              '  ',
            ).convert(jsonDecode(utf8.decode(original.bytes))),
          ),
        ),
      );
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: pretty, pinned: true),
      );
      final before = await h.snapshot()
        ..remove('learning_pack_versions');
      final remove = h.packs.prepareCacheChange(
        scope: scope,
        stored: installed,
        pinned: false,
        remove: true,
      );
      final removed = await h.packs.changeCache(remove);
      expect(removed.cacheState, PackCacheState.notCached);
      expect(removed.isPinned, isFalse);
      expect(removed.categoryId, installed.categoryId);
      expect(removed.importId, installed.importId);
      expect(removed.installedAtUtc, installed.installedAtUtc);
      expect(
        await h.snapshot()
          ..remove('learning_pack_versions'),
        before,
      );
      final removedSnapshot = await h.snapshot();
      await h.packs.changeCache(remove);
      expect(await h.snapshot(), removedSnapshot);
      final detail = await h.packs.detail(scope, installed.id);
      expect(
        detail.content!.manifest.payloadSha256,
        pretty.manifest.payloadSha256,
      );
      expect(detail.content!.packageSha256, isNot(pretty.packageSha256));
      final lexical = await h.packs.currentLexical(
        scope: scope,
        wordId: detail.bindings.first.wordId,
        packVersionId: installed.id,
      );
      expect(lexical, isNotNull);
      expect(
        () => h.packs.prepareCacheChange(
          scope: scope,
          stored: removed,
          pinned: true,
          repair: detail.content,
        ),
        _failure(PackStorageFailureCode.invalid),
      );
      final repair = h.packs.prepareCacheChange(
        scope: scope,
        stored: removed,
        pinned: true,
        repair: pretty,
      );
      final repaired = await h.packs.changeCache(repair);
      expect(repaired.cacheState, PackCacheState.verified);
      expect(repaired.packageSha256, pretty.packageSha256);
      expect(repaired.isPinned, isTrue);
      expect(
        await h.snapshot()
          ..remove('learning_pack_versions'),
        before,
      );
      final repairedSnapshot = await h.snapshot();
      await h.packs.changeCache(repair);
      expect(await h.snapshot(), repairedSnapshot);
      await expectLater(
        h.packs.changeCache(remove),
        _failure(PackStorageFailureCode.conflict),
      );
      expect(await h.snapshot(), repairedSnapshot);
    },
  );

  test(
    'device UTC clock rollback does not block cache removal or rewrite the original intent time',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: _pack()),
      );
      final before = await h.snapshot()
        ..remove('learning_pack_versions');
      h.clock = -1000;
      final intent = h.packs.prepareCacheChange(
        scope: scope,
        stored: installed,
        pinned: false,
        remove: true,
      );
      expect(intent.atUtc.isBefore(installed.updatedAtUtc), isTrue);
      final removed = await h.packs.changeCache(intent);
      expect(removed.updatedAtUtc, intent.atUtc);
      expect(removed.createdAtUtc, installed.createdAtUtc);
      expect(removed.revision, installed.revision + 1);
      expect(removed.cacheState, PackCacheState.notCached);
      expect(
        await h.snapshot()
          ..remove('learning_pack_versions'),
        before,
      );
    },
  );

  test(
    'a removed package retains one verified shared image for its lexical card',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final pack = _pack(includeImage: true);
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: pack),
      );
      await h.packs.changeCache(
        h.packs.prepareCacheChange(
          scope: scope,
          stored: installed,
          pinned: false,
          remove: true,
        ),
      );
      final detail = await h.packs.detail(scope, installed.id);
      final cat = detail.bindings.firstWhere(
        (binding) => binding.entry.code == 'cat',
      );
      final lexical = (await h.packs.currentLexical(
        scope: scope,
        wordId: cat.wordId,
        packVersionId: installed.id,
      ))!;
      expect(lexical.image!.bytes, pack.images.single.bytes);
      expect(lexical.image!.altText, 'Synthetic single-pixel cat swatch');
      expect(detail.content!.images, hasLength(1));
      expect(
        (await h.rows('learning_pack_versions')).single['package_bytes'],
        isNull,
      );
      expect(
        (await h.rows('learning_pack_versions')).single['retained_media_json'],
        LearningPackRetainedMedia.fromPack(pack).canonicalJson,
      );
    },
  );

  test(
    'corrupt cached bytes never become pinned healthy and matching repair restores bytes only',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final pack = _pack();
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: pack),
      );
      final broken = pack.bytes..[0] = 0;
      await h.database.customUpdate(
        'UPDATE learning_pack_versions SET package_bytes=? WHERE id=?',
        variables: [
          Variable<Uint8List>(broken),
          Variable<String>(installed.id),
        ],
        updates: {h.database.learningPackVersions},
      );
      final before = await h.snapshot();
      final detail = await h.packs.detail(scope, installed.id);
      expect(detail.pack.cacheState, PackCacheState.corrupt);
      expect(
        detail.content!.manifest.payloadSha256,
        pack.manifest.payloadSha256,
      );
      await expectLater(
        h.packs.changeCache(
          h.packs.prepareCacheChange(
            scope: scope,
            stored: detail.pack,
            pinned: true,
          ),
        ),
        _failure(PackStorageFailureCode.unavailable),
      );
      expect(await h.snapshot(), before);
      final repaired = await h.packs.changeCache(
        h.packs.prepareCacheChange(
          scope: scope,
          stored: detail.pack,
          pinned: true,
          repair: pack,
        ),
      );
      expect(repaired.cacheState, PackCacheState.verified);
      expect(
        await h.snapshot()
          ..remove('learning_pack_versions'),
        before..remove('learning_pack_versions'),
      );
    },
  );

  test(
    'list detail and lexical reads leave all tables unchanged and reject a foreign owner',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      expect(await h.packs.list(scope), isEmpty);
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: _pack()),
      );
      final before = await h.snapshot();
      final listed = await h.packs.list(scope);
      expect(listed.single.cacheState, PackCacheState.cached);
      final detail = await h.packs.detail(scope, installed.id);
      expect(detail.pack.cacheState, PackCacheState.verified);
      for (final binding in detail.bindings) {
        expect(
          (await h.packs.currentLexical(
            scope: scope,
            wordId: binding.wordId,
          ))!.entry.canonicalJson,
          binding.entry.canonicalJson,
        );
      }
      await expectLater(
        h.repository.detail(
          expectedOwnerId: 'b',
          packVersionId: installed.id,
          stillCurrent: () => true,
        ),
        _failure(PackStorageFailureCode.ownerChanged),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'A-B-A after decode retires the immutable import command before any write',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final decoded = _pack();
      final intent = h.packs.prepareImport(scope: scope, pack: decoded);
      final seenB = h.packs.watchActiveOwnerId().firstWhere((id) => id == 'b');
      await h.database.customUpdate(
        'UPDATE local_owners SET is_active=(id=?)',
        variables: [Variable<String>('b')],
        updates: {h.database.localOwners},
      );
      await seenB;
      final seenA = h.packs.watchActiveOwnerId().firstWhere((id) => id == 'a');
      await h.database.customUpdate(
        'UPDATE local_owners SET is_active=(id=?)',
        variables: [Variable<String>('a')],
        updates: {h.database.localOwners},
      );
      await seenA;
      final before = await h.snapshot();
      await expectLater(
        () => h.packs.importPack(intent),
        _failure(PackStorageFailureCode.ownerChanged),
      );
      expect(await h.snapshot(), before);
    },
  );

  test('ambient import transaction is rejected without writes', () async {
    final h = await _Harness.open();
    addTearDown(h.close);
    final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
    final intent = h.packs.prepareImport(scope: scope, pack: _pack());
    final before = await h.snapshot();
    await expectLater(
      h.database.transaction(() => h.repository.importPack(intent)),
      _failure(PackStorageFailureCode.unavailable),
    );
    expect(await h.snapshot(), before);
  });

  test(
    'deletion fence denies capture reads and writes without changing tables',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await (h.database.update(
        h.database.localOwners,
      )..where((row) => row.id.equals('a'))).write(
        const LocalOwnersCompanion(firebaseUid: Value('synthetic-pack-uid')),
      );
      await h.repository.ownerWrites.beginDeletion(
        ownerId: 'a',
        firebaseUid: 'synthetic-pack-uid',
        idempotencyKey: 'synthetic-pack-deletion',
      );
      final before = await h.snapshot();
      final intent = PackImportIntent(
        expectedOwnerId: 'a',
        pack: _pack(),
        source: const PackSourceDescriptor.userFile(),
        install: true,
        pinned: true,
        expectedRevision: 0,
        mutationId: 'synthetic-fenced-command',
        atUtc: DateTime.utc(2026, 11, 1),
        stillCurrent: () => true,
      );
      await expectLater(
        h.repository.importPack(intent),
        _failure(PackStorageFailureCode.unavailable),
      );
      await expectLater(
        h.repository.list(expectedOwnerId: 'a', stillCurrent: () => true),
        _failure(PackStorageFailureCode.unavailable),
      );
      await expectLater(
        h.repository.readActiveOwnerId(),
        _failure(PackStorageFailureCode.unavailable),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'failure after canonical import rolls back categories words receipts outbox and pack rows',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final intent = h.packs.prepareImport(scope: scope, pack: _pack());
      final before = await h.snapshot();
      await h.database.customStatement(
        "CREATE TRIGGER synthetic_pack_failure BEFORE INSERT "
        "ON lexical_content_snapshots BEGIN SELECT RAISE(ABORT,'synthetic late failure'); END",
      );
      await expectLater(
        h.packs.importPack(intent),
        _failure(PackStorageFailureCode.unavailable),
      );
      expect(await h.snapshot(), before);
      await h.database.customStatement('DROP TRIGGER synthetic_pack_failure');
      final recovered = await h.packs.importPack(intent);
      expect(recovered.isInstalled, isTrue);
      expect(await h.rows('vocabulary_words'), hasLength(2));
    },
  );

  for (final retireCaller in [false, true]) {
    test(
      '${retireCaller ? 'caller retirement' : 'owner switch'} after lexical insertion rolls back all writes',
      () async {
        final h = await _Harness.open();
        addTearDown(h.close);
        var current = true;
        final scope = (await h.packs.captureOwner(
          stillCurrent: () => current,
        ))!;
        final intent = h.packs.prepareImport(scope: scope, pack: _pack());
        final before = await h.snapshot();
        final interference = _AfterLexicalInsert(
          retire: retireCaller ? () => current = false : null,
        );
        await expectLater(
          h.database.runWithInterceptor(
            () => h.packs.importPack(intent),
            interceptor: interference,
          ),
          _failure(PackStorageFailureCode.ownerChanged),
        );
        expect(interference.fired, isTrue);
        expect(await h.snapshot(), before);
      },
    );
  }

  for (final field in ['part_of_speech', 'local_revision', 'meaning']) {
    test(
      'changed word $field is unavailable for new lexical practice without changing history',
      () async {
        final h = await _Harness.open();
        addTearDown(h.close);
        final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
        final installed = await h.packs.importPack(
          h.packs.prepareImport(scope: scope, pack: _pack()),
        );
        final first = (await h.packs.detail(
          scope,
          installed.id,
        )).bindings.first;
        final lexicalBefore = await h.rows('lexical_content_snapshots');
        await h.database.customUpdate(
          'UPDATE vocabulary_words SET $field=? WHERE id=?',
          variables: [
            if (field == 'local_revision')
              Variable<int>(2)
            else
              Variable<String>('synthetic change'),
            Variable<String>(first.wordId),
          ],
          updates: {h.database.vocabularyWords},
        );
        final before = await h.snapshot();
        await expectLater(
          h.packs.currentLexical(
            scope: scope,
            wordId: first.wordId,
            packVersionId: installed.id,
          ),
          _failure(PackStorageFailureCode.staleContent),
        );
        final detail = await h.packs.detail(scope, installed.id);
        expect(
          detail.bindings
              .firstWhere((binding) => binding.snapshotId == first.snapshotId)
              .isCurrent,
          isFalse,
        );
        expect(await h.rows('lexical_content_snapshots'), lexicalBefore);
        expect(await h.snapshot(), before);
      },
    );
  }

  test(
    'identical retained historical bindings collapse only during payload reconstruction',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final pack = _pack();
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: pack),
      );
      final snapshot = Map<String, Object?>.of(
        (await h.rows('lexical_content_snapshots')).first,
      )..['id'] = 'lexical:synthetic-retained-duplicate';
      await h.database.customStatement(
        'INSERT INTO lexical_content_snapshots (${snapshot.keys.join(',')}) '
        'VALUES (${List.filled(snapshot.length, '?').join(',')})',
        snapshot.values.toList(),
      );
      final before = await h.snapshot();
      final detail = await h.packs.detail(scope, installed.id);
      expect(detail.bindings, hasLength(3));
      expect(detail.content!.entries, hasLength(2));
      expect(
        detail.content!.manifest.payloadSha256,
        pack.manifest.payloadSha256,
      );
      expect(
        await h.packs.currentLexical(
          scope: scope,
          wordId: snapshot['word_id'] as String,
          packVersionId: installed.id,
        ),
        isNotNull,
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'a changed duplicate entry under the same package hash fails closed',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final installed = await h.packs.importPack(
        h.packs.prepareImport(scope: scope, pack: _pack()),
      );
      final snapshot = Map<String, Object?>.of(
        (await h.rows('lexical_content_snapshots')).first,
      );
      final entry = const LearningPackCodec().decodeEntry(
        snapshot['lexical_json'] as String,
      );
      final altered = LearningPackEntry(
        code: entry.code,
        spelling: entry.spelling,
        meaning: entry.meaning,
        partOfSpeech: entry.partOfSpeech,
        definition: 'A different synthetic authored definition.',
      );
      snapshot['id'] = 'lexical:synthetic-conflicting-duplicate';
      snapshot['lexical_json'] = altered.canonicalJson;
      snapshot['lexical_sha256'] = altered.contentSha256;
      await h.database.customStatement(
        'INSERT INTO lexical_content_snapshots (${snapshot.keys.join(',')}) '
        'VALUES (${List.filled(snapshot.length, '?').join(',')})',
        snapshot.values.toList(),
      );
      final before = await h.snapshot();
      await expectLater(
        h.packs.detail(scope, installed.id),
        _failure(PackStorageFailureCode.corrupt),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'file-backed restart preserves exact original IDs timestamps and acknowledged intent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-pack-installation-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      final first = await _Harness.open(file: file);
      _Harness? reopened;
      try {
        final scope = (await first.packs.captureOwner(
          stillCurrent: () => true,
        ))!;
        final intent = first.packs.prepareImport(
          scope: scope,
          pack: _pack(),
          pinned: true,
        );
        final installed = await first.packs.importPack(intent);
        final before = await first.snapshot();
        await first.close();
        reopened = await _Harness.open(file: file, seedOwners: false);
        final newScope = (await reopened.packs.captureOwner(
          stillCurrent: () => true,
        ))!;
        final reconciled = PackImportIntent(
          expectedOwnerId: intent.expectedOwnerId,
          pack: intent.pack,
          source: intent.source,
          install: intent.install,
          pinned: intent.pinned,
          expectedRevision: intent.expectedRevision,
          mutationId: intent.mutationId,
          atUtc: intent.atUtc,
          stillCurrent: () => newScope.isCurrent,
        );
        final replay = await reopened.repository.importPack(reconciled);
        expect(replay.id, installed.id);
        expect(replay.createdAtUtc, intent.atUtc);
        expect(replay.installedAtUtc, intent.atUtc);
        expect(await reopened.snapshot(), before);
        reopened.sequence = 100;
        await reopened.packs.importPack(
          reopened.packs.prepareImport(
            scope: newScope,
            pack: intent.pack,
            pinned: true,
          ),
        );
        expect(await reopened.snapshot(), before);
      } finally {
        await reopened?.close();
        await first.close();
        final resolved = await directory.resolveSymbolicLinks();
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$temp${Platform.pathSeparator}lexiquest-pack-installation-',
          ),
        );
        for (final item in directory.listSync()) {
          expect(item, isA<File>());
          expect(item.parent.absolute.path, directory.absolute.path);
          await item.delete();
        }
        await directory.delete();
      }
    },
  );
}

Matcher _failure(PackStorageFailureCode code) => throwsA(
  isA<PackStorageException>().having((error) => error.code, 'code', code),
);

LearningPack _pack({
  String version = '1.0.0',
  String catMeaning = 'แมว',
  bool includeImage = false,
}) => const LearningPackCodec().decode(
  const LearningPackCodec().encode(
    metadata: LearningPackMetadata(
      packId: 'synthetic-animals',
      version: version,
      title: 'Synthetic authored animals',
      objectives: ['Practice two animals'],
      cefrLevel: 'A1',
      language: 'en',
      meaningLanguage: 'th',
      provenance: const LearningPackProvenance(
        author: 'Synthetic test author',
        source: 'Synthetic test fixture',
        license: 'Synthetic test only',
        attribution: 'No real publisher',
      ),
    ),
    entries: [
      LearningPackEntry(
        code: 'cat',
        spelling: 'cat',
        meaning: catMeaning,
        partOfSpeech: 'noun',
        definition: 'A small animal often kept as a pet.',
        hint: 'Think of a pet that meows.',
        strategy: 'Read the whole definition.',
        imageId: includeImage ? 'cat-picture' : null,
      ),
      LearningPackEntry(
        code: 'dog',
        spelling: 'dog',
        meaning: 'สุนัข',
        partOfSpeech: 'noun',
        definition: 'An animal that often barks.',
      ),
    ],
    images: includeImage
        ? [
            LearningPackImage(
              id: 'cat-picture',
              mimeType: 'image/png',
              width: 1,
              height: 1,
              altText: 'Synthetic single-pixel cat swatch',
              bytes: Uint8List.fromList(
                image.encodePng(image.Image(width: 1, height: 1)),
              ),
            ),
          ]
        : const [],
  ),
);

final class _Harness {
  _Harness(this.database) {
    repository = DriftLearningPackRepository(
      database: database,
      ownerWrites: DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
      ),
    );
    packs = LearningPackUseCases(
      repository: repository,
      nowUtc: () =>
          DateTime.utc(2026, 11, 1).add(Duration(milliseconds: ++clock)),
      generateId: () => 'synthetic-pack-operation:${++sequence}',
    );
  }
  final AppDatabase database;
  late final DriftLearningPackRepository repository;
  late final LearningPackUseCases packs;
  var sequence = 0;
  var clock = 0;
  Future<void>? _closing;

  static Future<_Harness> open({File? file, bool seedOwners = true}) async {
    final database = AppDatabase(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
    );
    await database.customStatement('PRAGMA foreign_keys = ON');
    if (seedOwners) {
      for (final id in ['a', 'b']) {
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: id,
                createdAtUtcMs: 1,
                isActive: Value(id == 'a'),
              ),
            );
      }
    }
    final h = _Harness(database);
    await h.packs.watchActiveOwnerId().firstWhere((owner) => owner == 'a');
    return h;
  }

  Future<List<Map<String, Object?>>> rows(String table) async =>
      (await database
              .customSelect('SELECT * FROM "$table" ORDER BY rowid')
              .get())
          .map((row) => Map<String, Object?>.of(row.data))
          .toList();

  Future<Map<String, List<String>>> snapshot() async => {
    for (final table in database.allTables)
      table.actualTableName: [
        for (final row in await rows(table.actualTableName)) jsonEncode(row),
      ],
  };

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await packs.dispose();
    await database.close();
  }
}

final class _AfterLexicalInsert extends QueryInterceptor {
  _AfterLexicalInsert({this.retire});
  final void Function()? retire;
  var fired = false;
  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!fired &&
        statement.toLowerCase().startsWith(
          'insert into lexical_content_snapshots',
        )) {
      fired = true;
      if (retire case final callback?) {
        callback();
      } else {
        await executor.runUpdate('UPDATE local_owners SET is_active=(id=?)', [
          'b',
        ]);
      }
    }
    return result;
  }
}
