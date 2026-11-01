import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../progress/data/drift_review_center_queries.dart';
import '../../progress/domain/review_center_models.dart';
import '../../vocabulary/application/import_vocabulary.dart';
import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/data/drift_vocabulary_import_repository.dart';
import '../../vocabulary/data/drift_vocabulary_repository.dart';
import '../../vocabulary/domain/vocabulary_category.dart';
import '../../vocabulary/domain/vocabulary_import.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../domain/learning_pack.dart';
import '../domain/learning_pack_repository.dart';

final class DriftLearningPackRepository implements LearningPackRepository {
  DriftLearningPackRepository({
    required this.database,
    required this.ownerWrites,
  }) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Packs require the same owner-write database');
    }
  }
  final AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;
  static const _codec = LearningPackCodec();
  static const _conflict =
      '(SELECT COUNT(*) FROM learning_pack_versions other '
      'WHERE other.owner_id=p.owner_id AND other.pack_id=p.pack_id '
      'AND other.pack_version=p.pack_version)>1 AS identity_conflict';

  @override
  Future<String?> readActiveOwnerId() async {
    var valid = true;
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen((_) => valid = false, onError: (Object _) => valid = false);
    try {
      final rows = await database
          .customSelect('SELECT id FROM local_owners WHERE is_active=1 LIMIT 2')
          .get();
      if (!valid) _fail(PackStorageFailureCode.ownerChanged);
      if (rows.isEmpty) return null;
      if (rows.length != 1) _fail(PackStorageFailureCode.ownerChanged);
      final owner = rows.single.read<String>('id');
      await _requireOwner(owner, () => valid);
      return owner;
    } on PackStorageException {
      rethrow;
    } on ReviewCenterReadException {
      _fail(PackStorageFailureCode.ownerChanged);
    } on Object {
      _fail(PackStorageFailureCode.unavailable);
    } finally {
      await changes.cancel();
    }
  }

  @override
  Stream<String?> watchActiveOwnerId() => Stream<String?>.multi((events) {
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen((_) => events.add(null), onError: events.addError);
    final rows =
        (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .watch()
            .listen(
              (owners) =>
                  events.add(owners.length == 1 ? owners.single.id : null),
              onError: events.addError,
              onDone: events.close,
            );
    events.onCancel = () async {
      await Future.wait([changes.cancel(), rows.cancel()]);
    };
  }, isBroadcast: true);

  @override
  Future<List<StoredLearningPack>> list({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _read(expectedOwnerId, stillCurrent, () async {
    final rows = await database
        .customSelect(
          'SELECT p.id,p.owner_id,p.pack_id,p.pack_version,p.manifest_json,p.manifest_sha256,'
          'p.package_sha256,p.package_byte_count,p.source_descriptor_json,p.is_pinned,'
          'p.category_id,p.import_id,p.installed_at_utc_ms,p.revision,p.created_at_utc_ms,'
          'p.updated_at_utc_ms,p.package_bytes IS NOT NULL AS cache_present,$_conflict '
          'FROM learning_pack_versions p WHERE p.owner_id=? ORDER BY p.created_at_utc_ms,p.id',
          variables: [Variable<String>(expectedOwnerId)],
        )
        .get();
    return List.unmodifiable([
      for (final row in rows) _stored(row, expectedOwnerId),
    ]);
  });
  @override
  Future<PackDetail> detail({
    required String expectedOwnerId,
    required String packVersionId,
    required bool Function() stillCurrent,
  }) => _read(
    expectedOwnerId,
    stillCurrent,
    () => _detail(expectedOwnerId, packVersionId),
  );
  @override
  Future<StoredLearningPack> importPack(
    PackImportIntent intent,
  ) => _write(intent.expectedOwnerId, intent.stillCurrent, (current) async {
    final pack = intent.pack;
    final manifest = pack.manifest;
    final matches = await database
        .customSelect(
          'SELECT id,package_sha256 FROM learning_pack_versions '
          'WHERE owner_id=? AND pack_id=? AND pack_version=?',
          variables: [
            Variable<String>(intent.expectedOwnerId),
            Variable<String>(manifest.packId),
            Variable<String>(manifest.version),
          ],
        )
        .get();
    if (matches.any(
          (row) => row.read<String>('package_sha256') != pack.packageSha256,
        ) ||
        matches.length > 1) {
      _fail(PackStorageFailureCode.conflict);
    }
    final previous = matches.isEmpty
        ? null
        : await _row(intent.expectedOwnerId, matches.single.read<String>('id'));
    final fingerprint = _hash(
      jsonEncode({
        'kind': 'import',
        'owner': intent.expectedOwnerId,
        'packageSha256': pack.packageSha256,
        'source': intent.source.canonicalJson,
        'install': intent.install,
        'pinned': intent.pinned,
        'expectedRevision': intent.expectedRevision,
        'atUtcMs': intent.atUtc.millisecondsSinceEpoch,
      }),
    );
    final id =
        previous?.read<String>('id') ??
        _id('pack', [
          intent.expectedOwnerId,
          manifest.packId,
          manifest.version,
          pack.packageSha256,
        ]);
    if (previous != null) {
      final old = await _detail(intent.expectedOwnerId, id);
      _matchPackage(previous, pack);
      if (_replay(
        previous,
        intent.mutationId,
        fingerprint,
        intent.expectedRevision,
      )) {
        return old.pack;
      }
      if (intent.expectedRevision == 0 &&
          (!intent.install || old.pack.isInstalled) &&
          old.pack.cacheState == PackCacheState.verified &&
          old.pack.isPinned == intent.pinned) {
        return old.pack;
      }
      if (old.pack.revision != intent.expectedRevision) {
        _fail(PackStorageFailureCode.conflict);
      }
    } else if (intent.expectedRevision != 0) {
      _fail(PackStorageFailureCode.conflict);
    }
    var categoryId = previous?.readNullable<String>('category_id');
    var importId = previous?.readNullable<String>('import_id');
    var installedAt = previous?.readNullable<int>('installed_at_utc_ms');
    PreparedVocabularyImport? materialized;
    if (intent.install && categoryId == null) {
      categoryId = _id('category', [id]);
      importId = _id('import', [id]);
      installedAt = intent.atUtc.millisecondsSinceEpoch;
      final suffix = ' [${pack.packageSha256.substring(0, 12)}]';
      var title = manifest.title;
      while (title.length + suffix.length > maxCategoryNameLength) {
        title = String.fromCharCodes(title.runes.take(title.runes.length - 1));
      }
      final name = '$title$suffix';
      final category = await DriftVocabularyRepository(database).createCategory(
        VocabularyCategory(
          id: categoryId,
          ownerId: intent.expectedOwnerId,
          name: name,
          normalizedName: normalizeVocabularyText(name),
          sortOrder: 0,
          localRevision: 1,
          isDeleted: false,
          createdAtUtc: intent.atUtc,
          updatedAtUtc: intent.atUtc,
        ),
      );
      if (category.id != categoryId ||
          category.ownerId != intent.expectedOwnerId ||
          category.isDeleted) {
        _fail(PackStorageFailureCode.corrupt);
      }
      materialized = _prepareImport(intent, id, categoryId, importId);
      final result = await DriftVocabularyImportRepository(
        database,
      ).persist(materialized, isCancelled: () => !current());
      if (result.importId != importId ||
          result.accepted != pack.entries.length ||
          result.duplicates != 0 ||
          result.rejected.isNotEmpty) {
        _fail(PackStorageFailureCode.conflict);
      }
    }
    await _requireOwner(intent.expectedOwnerId, current);
    final media = LearningPackRetainedMedia.fromPack(pack).canonicalJson;
    final at = intent.atUtc.millisecondsSinceEpoch;
    final revision = (previous?.read<int>('revision') ?? 0) + 1;
    final fields = <Variable>[
      Variable<String>(manifest.canonicalJson),
      Variable<String>(_hash(manifest.canonicalJson)),
      Variable<int>(pack.byteCount),
      Variable<Uint8List>(pack.bytes),
      Variable<String>(media),
      Variable<String>(_hash(media)),
      Variable<bool>(intent.pinned),
      Variable<String>(categoryId),
      Variable<String>(importId),
      Variable<int>(installedAt),
      Variable<int>(revision),
      Variable<String>(intent.mutationId),
      Variable<String>(fingerprint),
      Variable<int>(at),
    ];
    if (previous == null) {
      await database.customInsert(
        'INSERT INTO learning_pack_versions '
        '(manifest_json,manifest_sha256,package_byte_count,package_bytes,retained_media_json,'
        'retained_media_sha256,is_pinned,category_id,import_id,installed_at_utc_ms,revision,'
        'last_mutation_id,last_mutation_sha256,updated_at_utc_ms,id,owner_id,pack_id,pack_version,'
        'package_sha256,source_descriptor_json,created_at_utc_ms) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        variables: [
          ...fields,
          Variable<String>(id),
          Variable<String>(intent.expectedOwnerId),
          Variable<String>(manifest.packId),
          Variable<String>(manifest.version),
          Variable<String>(pack.packageSha256),
          Variable<String>(intent.source.canonicalJson),
          Variable<int>(at),
        ],
        updates: {database.learningPackVersions},
      );
    } else {
      final changed = await database.customUpdate(
        'UPDATE learning_pack_versions SET manifest_json=?,manifest_sha256=?,package_byte_count=?,'
        'package_bytes=?,retained_media_json=?,retained_media_sha256=?,is_pinned=?,category_id=?,'
        'import_id=?,installed_at_utc_ms=?,revision=?,last_mutation_id=?,last_mutation_sha256=?,'
        'updated_at_utc_ms=? WHERE id=? AND owner_id=? AND revision=?',
        variables: [
          ...fields,
          Variable<String>(id),
          Variable<String>(intent.expectedOwnerId),
          Variable<int>(intent.expectedRevision),
        ],
        updates: {database.learningPackVersions},
      );
      if (changed != 1) _fail(PackStorageFailureCode.conflict);
    }
    if (materialized != null) {
      final receipts = await database
          .customSelect(
            'SELECT row_number,payload_hash,status,word_id FROM vocabulary_import_rows '
            'WHERE import_id=? ORDER BY row_number',
            variables: [Variable<String>(importId)],
          )
          .get();
      if (receipts.length != pack.entries.length) {
        _fail(PackStorageFailureCode.corrupt);
      }
      for (var index = 0; index < pack.entries.length; index++) {
        final entry = pack.entries[index];
        final expected = materialized.rows[index];
        final receipt = receipts[index];
        final word = expected.word!;
        if (receipt.read<int>('row_number') != index + 1 ||
            receipt.read<String>('status') != 'accepted' ||
            receipt.read<String>('payload_hash') != expected.payloadHash ||
            receipt.readNullable<String>('word_id') != word.id) {
          _fail(PackStorageFailureCode.corrupt);
        }
        final actual = await _word(word.ownerId, word.id);
        if (actual == null || !_sameImportedWord(actual, word)) {
          _fail(PackStorageFailureCode.corrupt);
        }
        await database.customInsert(
          'INSERT INTO lexical_content_snapshots '
          '(id,owner_id,pack_version_id,word_id,bound_word_revision,bound_word_sha256,'
          'entry_code,lexical_json,lexical_sha256,created_at_utc_ms) VALUES (?,?,?,?,?,?,?,?,?,?)',
          variables: [
            Variable<String>(_id('lexical', [id, entry.code])),
            Variable<String>(word.ownerId),
            Variable<String>(id),
            Variable<String>(word.id),
            Variable<int>(word.localRevision),
            Variable<String>(_wordHash(actual)),
            Variable<String>(entry.code),
            Variable<String>(entry.canonicalJson),
            Variable<String>(entry.contentSha256),
            Variable<int>(at),
          ],
          updates: {database.lexicalContentSnapshots},
        );
      }
    }
    await _requireOwner(intent.expectedOwnerId, current);
    final result = await _detail(intent.expectedOwnerId, id);
    if (result.pack.revision != revision ||
        result.pack.isInstalled != (categoryId != null) ||
        result.pack.isPinned != intent.pinned ||
        result.pack.cacheState != PackCacheState.verified) {
      _fail(PackStorageFailureCode.corrupt);
    }
    return result.pack;
  });
  @override
  Future<StoredLearningPack> changeCache(
    PackCacheIntent intent,
  ) => _write(intent.expectedOwnerId, intent.stillCurrent, (current) async {
    final row = await _row(intent.expectedOwnerId, intent.packVersionId);
    if (row == null) _fail(PackStorageFailureCode.notFound);
    final stored = await _detail(intent.expectedOwnerId, intent.packVersionId);
    if (stored.pack.packageSha256 != intent.expectedPackageSha256) {
      _fail(PackStorageFailureCode.conflict);
    }
    final fingerprint = _hash(
      jsonEncode({
        'kind': 'cache',
        'owner': intent.expectedOwnerId,
        'packVersionId': intent.packVersionId,
        'packageSha256': intent.expectedPackageSha256,
        'expectedRevision': intent.expectedRevision,
        'pinned': intent.pinned,
        'remove': intent.remove,
        'repair': intent.repair?.packageSha256,
        'atUtcMs': intent.atUtc.millisecondsSinceEpoch,
      }),
    );
    if (_replay(row, intent.mutationId, fingerprint, intent.expectedRevision)) {
      return stored.pack;
    }
    if (stored.pack.revision != intent.expectedRevision) {
      _fail(PackStorageFailureCode.conflict);
    }
    var bytes = row.readNullable<Uint8List>('package_bytes');
    if (intent.remove) {
      bytes = null;
    } else if (intent.repair case final repair?) {
      _matchPackage(row, repair);
      bytes = repair.bytes;
    } else if (intent.pinned &&
        stored.pack.cacheState != PackCacheState.verified) {
      _fail(PackStorageFailureCode.unavailable);
    }
    if (intent.pinned && bytes == null) {
      _fail(PackStorageFailureCode.unavailable);
    }
    final changed = await database.customUpdate(
      'UPDATE learning_pack_versions SET package_bytes=?,is_pinned=?,revision=?,'
      'last_mutation_id=?,last_mutation_sha256=?,updated_at_utc_ms=? '
      'WHERE id=? AND owner_id=? AND revision=?',
      variables: [
        Variable<Uint8List>(bytes),
        Variable<bool>(intent.pinned),
        Variable<int>(intent.expectedRevision + 1),
        Variable<String>(intent.mutationId),
        Variable<String>(fingerprint),
        Variable<int>(intent.atUtc.millisecondsSinceEpoch),
        Variable<String>(intent.packVersionId),
        Variable<String>(intent.expectedOwnerId),
        Variable<int>(intent.expectedRevision),
      ],
      updates: {database.learningPackVersions},
    );
    if (changed != 1) _fail(PackStorageFailureCode.conflict);
    await _requireOwner(intent.expectedOwnerId, current);
    return (await _detail(intent.expectedOwnerId, intent.packVersionId)).pack;
  });
  @override
  Future<CurrentLexicalContent?> currentLexical({
    required String expectedOwnerId,
    required String wordId,
    String? packVersionId,
    required bool Function() stillCurrent,
  }) => _read(expectedOwnerId, stillCurrent, () async {
    requirePackStorageId(wordId);
    final rows = await database
        .customSelect(
          'SELECT DISTINCT pack_version_id FROM lexical_content_snapshots '
          'WHERE owner_id=? AND word_id=?${packVersionId == null ? '' : ' AND pack_version_id=?'} '
          'ORDER BY pack_version_id',
          variables: [
            Variable<String>(expectedOwnerId),
            Variable<String>(wordId),
            if (packVersionId != null) Variable<String>(packVersionId),
          ],
        )
        .get();
    final choices = <CurrentLexicalContent>[];
    for (final row in rows) {
      final detail = await _detail(
        expectedOwnerId,
        row.read<String>('pack_version_id'),
      );
      if (packVersionId == null && detail.pack.identityConflict) {
        _fail(PackStorageFailureCode.conflict);
      }
      final unique = <String, PackLexicalBinding>{};
      for (final binding in detail.bindings) {
        if (binding.wordId == wordId && binding.isCurrent) {
          unique.putIfAbsent(
            jsonEncode([
              binding.wordId,
              binding.wordRevision,
              binding.entry.canonicalJson,
            ]),
            () => binding,
          );
        }
      }
      for (final binding in unique.values) {
        final word = binding.word;
        if (detail.content != null && word != null) {
          choices.add(
            CurrentLexicalContent(
              pack: detail.pack,
              binding: binding,
              content: detail.content!,
              word: word,
            ),
          );
        }
      }
    }
    if (choices.length > 1) _fail(PackStorageFailureCode.conflict);
    if (choices.isEmpty && rows.isNotEmpty) {
      _fail(PackStorageFailureCode.staleContent);
    }
    return choices.isEmpty ? null : choices.single;
  });

  Future<PackDetail> _detail(String owner, String id) async {
    requirePackStorageId(id);
    final row = await _row(owner, id);
    if (row == null) _fail(PackStorageFailureCode.notFound);
    final initial = _stored(row, owner);
    final mediaJson = row.read<String>('retained_media_json');
    if (_hash(mediaJson) != row.read<String>('retained_media_sha256')) {
      _fail(PackStorageFailureCode.corrupt);
    }
    final media = _codec.decodeRetainedMedia(mediaJson);
    if (media.canonicalJson != mediaJson ||
        media.entryCodes.length != initial.manifest.entryCount) {
      _fail(PackStorageFailureCode.corrupt);
    }
    var state = PackCacheState.notCached;
    LearningPack? cached;
    final bytes = row.readNullable<Uint8List>('package_bytes');
    if (bytes != null) {
      state = PackCacheState.corrupt;
      try {
        final decoded = _codec.decode(
          bytes,
          expectedPackageSha256: initial.packageSha256,
        );
        if (decoded.byteCount == initial.packageByteCount &&
            decoded.manifest.canonicalJson == initial.manifest.canonicalJson &&
            LearningPackRetainedMedia.fromPack(decoded).canonicalJson ==
                mediaJson) {
          cached = decoded;
          state = PackCacheState.verified;
        }
      } on LearningPackException {
        state = PackCacheState.corrupt;
      }
    }
    final pack = _stored(row, owner, cacheState: state);
    final snapshots = await database
        .customSelect(
          'SELECT * FROM lexical_content_snapshots WHERE owner_id=? AND pack_version_id=? ORDER BY id',
          variables: [Variable<String>(owner), Variable<String>(id)],
        )
        .get();
    if (!pack.isInstalled && snapshots.isNotEmpty) {
      _fail(PackStorageFailureCode.corrupt);
    }
    final bindings = <PackLexicalBinding>[];
    final entries = <String, LearningPackEntry>{};
    for (final snapshot in snapshots) {
      final json = snapshot.read<String>('lexical_json');
      final entry = _codec.decodeEntry(json);
      if (entry.canonicalJson != json ||
          entry.code != snapshot.read<String>('entry_code') ||
          entry.contentSha256 != snapshot.read<String>('lexical_sha256') ||
          !media.entryCodes.contains(entry.code)) {
        _fail(PackStorageFailureCode.corrupt);
      }
      final previous = entries[entry.code];
      if (previous != null && previous.canonicalJson != json) {
        _fail(PackStorageFailureCode.corrupt);
      }
      entries[entry.code] = entry;
      final snapshotId = snapshot.read<String>('id');
      final wordId = snapshot.read<String>('word_id');
      final revision = snapshot.read<int>('bound_word_revision');
      final boundHash = snapshot.read<String>('bound_word_sha256');
      requirePackStorageId(snapshotId);
      requirePackStorageId(wordId);
      if (revision < 1 ||
          revision > maxLearningPackRevision ||
          !_isHash(boundHash) ||
          !_validMilliseconds(snapshot.read<int>('created_at_utc_ms'))) {
        _fail(PackStorageFailureCode.corrupt);
      }
      final backed = await database
          .customSelect(
            'SELECT r.id FROM vocabulary_import_rows r JOIN vocabulary_imports i ON i.id=r.import_id '
            "WHERE i.owner_id=? AND r.word_id=? AND r.status='accepted' AND r.payload_hash=? LIMIT 1",
            variables: [
              Variable<String>(owner),
              Variable<String>(wordId),
              Variable<String>(_entryImportHash(entry)),
            ],
          )
          .get();
      if (backed.isEmpty) _fail(PackStorageFailureCode.corrupt);
      final word = await _word(owner, wordId);
      bindings.add(
        PackLexicalBinding(
          snapshotId: snapshotId,
          wordId: wordId,
          wordRevision: revision,
          entry: entry,
          word: word == null
              ? null
              : DriftVocabularyRepository.wordToDomain(
                  database.vocabularyWords.map(word.data),
                ),
          isCurrent:
              word != null &&
              word.read<int>('local_revision') == revision &&
              !word.read<bool>('is_deleted') &&
              word.read<int>('category_active') == 1 &&
              _wordHash(word) == boundHash &&
              _matchesEntry(word, entry),
        ),
      );
    }
    LearningPack? content = cached;
    if (pack.isInstalled) {
      if (entries.length != pack.manifest.entryCount) {
        _fail(PackStorageFailureCode.corrupt);
      }
      final imported = await database
          .customSelect(
            'SELECT * FROM vocabulary_imports WHERE id=? AND owner_id=?',
            variables: [
              Variable<String>(pack.importId),
              Variable<String>(owner),
            ],
          )
          .getSingleOrNull();
      if (imported == null ||
          imported.read<String>('category_id') != pack.categoryId ||
          imported.read<String>('status') != 'completed' ||
          imported.read<int>('accepted_count') != pack.manifest.entryCount ||
          imported.read<int>('duplicate_count') != 0 ||
          imported.read<int>('rejected_count') != 0) {
        _fail(PackStorageFailureCode.corrupt);
      }
      final receipts = await database
          .customSelect(
            'SELECT * FROM vocabulary_import_rows WHERE import_id=? ORDER BY row_number',
            variables: [Variable<String>(pack.importId)],
          )
          .get();
      if (receipts.length != pack.manifest.entryCount) {
        _fail(PackStorageFailureCode.corrupt);
      }
      for (var index = 0; index < receipts.length; index++) {
        final receipt = receipts[index];
        final code = media.entryCodes[index];
        if (receipt.read<int>('row_number') != index + 1 ||
            receipt.read<String>('status') != 'accepted' ||
            receipt.read<String>('payload_hash') !=
                _entryImportHash(entries[code]!) ||
            !bindings.any(
              (binding) =>
                  binding.entry.code == code &&
                  binding.wordId == receipt.readNullable<String>('word_id'),
            )) {
          _fail(PackStorageFailureCode.corrupt);
        }
      }
      content = _codec.restoreContent(
        manifest: pack.manifest,
        entries: entries.values.toList(),
        media: media,
      );
    }
    return PackDetail(pack: pack, content: content, bindings: bindings);
  }

  Future<QueryRow?> _row(String owner, String id) => database
      .customSelect(
        'SELECT p.*,p.package_bytes IS NOT NULL AS cache_present,$_conflict '
        'FROM learning_pack_versions p WHERE p.owner_id=? AND p.id=?',
        variables: [Variable<String>(owner), Variable<String>(id)],
      )
      .getSingleOrNull();

  StoredLearningPack _stored(
    QueryRow row,
    String owner, {
    PackCacheState? cacheState,
  }) {
    final manifestJson = row.read<String>('manifest_json');
    final manifest = _codec.decodeManifest(manifestJson);
    final id = row.read<String>('id');
    requirePackStorageId(id);
    final revision = row.read<int>('revision');
    final count = row.read<int>('package_byte_count');
    final category = row.readNullable<String>('category_id');
    final import = row.readNullable<String>('import_id');
    final installed = row.readNullable<int>('installed_at_utc_ms');
    final created = row.read<int>('created_at_utc_ms');
    final updated = row.read<int>('updated_at_utc_ms');
    if (row.read<String>('owner_id') != owner ||
        _hash(manifestJson) != row.read<String>('manifest_sha256') ||
        manifest.canonicalJson != manifestJson ||
        manifest.packId != row.read<String>('pack_id') ||
        manifest.version != row.read<String>('pack_version') ||
        !_isHash(row.read<String>('package_sha256')) ||
        count < 1 ||
        count > maxLearningPackBytes ||
        revision < 1 ||
        revision > maxLearningPackRevision ||
        !_validMilliseconds(created) ||
        !_validMilliseconds(updated) ||
        ((category == null) != (import == null)) ||
        ((category == null) != (installed == null)) ||
        (installed != null && !_validMilliseconds(installed))) {
      _fail(PackStorageFailureCode.corrupt);
    }
    if (category != null) requirePackStorageId(category);
    if (import != null) requirePackStorageId(import);
    final cached = row.read<int>('cache_present') == 1;
    final pinned = row.read<bool>('is_pinned');
    if (pinned && !cached) _fail(PackStorageFailureCode.corrupt);
    return StoredLearningPack(
      id: id,
      ownerId: owner,
      manifest: manifest,
      packageSha256: row.read<String>('package_sha256'),
      packageByteCount: count,
      source: PackSourceDescriptor.parse(
        row.read<String>('source_descriptor_json'),
      ),
      cacheState:
          cacheState ??
          (cached ? PackCacheState.cached : PackCacheState.notCached),
      isPinned: pinned,
      categoryId: category,
      importId: import,
      installedAtUtc: installed == null ? null : _utc(installed),
      revision: revision,
      createdAtUtc: _utc(created),
      updatedAtUtc: _utc(updated),
      identityConflict: row.read<int>('identity_conflict') == 1,
    );
  }

  PreparedVocabularyImport _prepareImport(
    PackImportIntent intent,
    String packRowId,
    String categoryId,
    String importId,
  ) {
    final rows = <PreparedVocabularyImportRow>[];
    for (var index = 0; index < intent.pack.entries.length; index++) {
      final entry = intent.pack.entries[index];
      final row = _entryRow(entry);
      if (validateVocabularyImportRow(row) != null) {
        _fail(PackStorageFailureCode.invalid);
      }
      rows.add(
        PreparedVocabularyImportRow(
          rowNumber: index + 1,
          payloadHash: _hash(canonicalImportRow(row)),
          word: VocabularyWord(
            id: _id('word', [packRowId, entry.code]),
            ownerId: intent.expectedOwnerId,
            categoryId: categoryId,
            spelling: entry.spelling,
            normalizedSpelling: normalizeVocabularyText(entry.spelling),
            meaning: entry.meaning,
            normalizedMeaning: normalizeVocabularyText(entry.meaning),
            partOfSpeech: entry.partOfSpeech,
            source: 'import',
            isGlobal: false,
            localRevision: 1,
            isDeleted: false,
            createdAtUtc: intent.atUtc,
            updatedAtUtc: intent.atUtc,
          ),
        ),
      );
    }
    return PreparedVocabularyImport(
      importId: importId,
      ownerId: intent.expectedOwnerId,
      categoryId: categoryId,
      sourceName: 'learning-pack:${intent.pack.manifest.packId}',
      sourceHash: _hash(
        jsonEncode(['learning-pack-v1', packRowId, intent.pack.packageSha256]),
      ),
      rows: List.unmodifiable(rows),
      nowUtc: intent.atUtc,
    );
  }

  Future<QueryRow?> _word(String owner, String wordId) => database
      .customSelect(
        'SELECT w.*,EXISTS(SELECT 1 FROM vocabulary_categories c '
        'WHERE c.id=w.category_id AND c.owner_id=w.owner_id AND c.is_deleted=0) AS category_active '
        'FROM vocabulary_words w WHERE w.owner_id=? AND w.id=?',
        variables: [Variable<String>(owner), Variable<String>(wordId)],
      )
      .getSingleOrNull();

  bool _sameImportedWord(QueryRow actual, VocabularyWord expected) =>
      actual.read<String>('id') == expected.id &&
      actual.read<String>('owner_id') == expected.ownerId &&
      actual.read<String>('category_id') == expected.categoryId &&
      actual.read<String>('spelling') == expected.spelling &&
      actual.read<String>('normalized_spelling') ==
          expected.normalizedSpelling &&
      actual.read<String>('meaning') == expected.meaning &&
      actual.read<String>('normalized_meaning') == expected.normalizedMeaning &&
      actual.read<String>('part_of_speech') == expected.partOfSpeech &&
      actual.read<int>('local_revision') == 1 &&
      !actual.read<bool>('is_deleted') &&
      actual.read<String>('source') == 'import' &&
      actual.readNullable<String>('cefr_level') == null &&
      actual.read<int>('created_at_utc_ms') ==
          expected.createdAtUtc.millisecondsSinceEpoch &&
      actual.read<int>('updated_at_utc_ms') ==
          expected.updatedAtUtc.millisecondsSinceEpoch;

  String _wordHash(QueryRow word) => _hash(
    jsonEncode({
      'normalizedSpelling': normalizeVocabularyText(
        word.read<String>('spelling'),
      ),
      'normalizedMeaning': normalizeVocabularyText(
        word.read<String>('meaning'),
      ),
      'partOfSpeech': normalizeVocabularyText(
        word.read<String>('part_of_speech'),
      ),
      'cefrLevel': word.readNullable<String>('cefr_level'),
    }),
  );

  bool _matchesEntry(QueryRow word, LearningPackEntry entry) =>
      word.read<String>('normalized_spelling') ==
          normalizeVocabularyText(word.read<String>('spelling')) &&
      word.read<String>('normalized_meaning') ==
          normalizeVocabularyText(word.read<String>('meaning')) &&
      word.read<String>('normalized_spelling') ==
          normalizeVocabularyText(entry.spelling) &&
      word.read<String>('normalized_meaning') ==
          normalizeVocabularyText(entry.meaning) &&
      normalizeVocabularyText(word.read<String>('part_of_speech')) ==
          normalizeVocabularyText(entry.partOfSpeech);

  Map<String, String> _entryRow(LearningPackEntry entry) => {
    'word': entry.spelling,
    'meaning': entry.meaning,
    'partOfSpeech': entry.partOfSpeech,
  };
  String _entryImportHash(LearningPackEntry entry) =>
      _hash(canonicalImportRow(_entryRow(entry)));

  void _matchPackage(QueryRow row, LearningPack pack) {
    final media = LearningPackRetainedMedia.fromPack(pack).canonicalJson;
    if (row.read<String>('package_sha256') != pack.packageSha256 ||
        row.read<int>('package_byte_count') != pack.byteCount ||
        row.read<String>('manifest_json') != pack.manifest.canonicalJson ||
        row.read<String>('retained_media_json') != media ||
        row.read<String>('retained_media_sha256') != _hash(media)) {
      _fail(PackStorageFailureCode.corrupt);
    }
  }

  bool _replay(
    QueryRow row,
    String mutationId,
    String fingerprint,
    int revision,
  ) {
    if (row.read<String>('last_mutation_id') != mutationId) return false;
    if (row.read<String>('last_mutation_sha256') != fingerprint ||
        row.read<int>('revision') != revision + 1) {
      _fail(PackStorageFailureCode.conflict);
    }
    return true;
  }

  Future<T> _read<T>(
    String owner,
    bool Function() stillCurrent,
    Future<T> Function() action,
  ) => _guard(owner, stillCurrent, (current) async {
    await _requireOwner(owner, current);
    final result = await database.transaction(() async {
      await _requireOwner(owner, current);
      return action();
    });
    await _requireOwner(owner, current);
    return result;
  });

  Future<T> _write<T>(
    String owner,
    bool Function() stillCurrent,
    Future<T> Function(bool Function() current) action,
  ) => _guard(owner, stillCurrent, (current) async {
    if (await ownerWrites.hasAmbientTransaction()) {
      _fail(PackStorageFailureCode.unavailable);
    }
    await _requireOwner(owner, current);
    return ownerWrites.writeForActiveOwner(
      expectedOwnerId: owner,
      write: () async {
        await _requireOwner(owner, current);
        final result = await action(current);
        await _requireOwner(owner, current);
        return result;
      },
    );
  });

  Future<T> _guard<T>(
    String owner,
    bool Function() stillCurrent,
    Future<T> Function(bool Function() current) action,
  ) async {
    requirePackStorageId(owner);
    var valid = true;
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    try {
      if (!current()) _fail(PackStorageFailureCode.ownerChanged);
      final result = await action(current);
      if (!current()) _fail(PackStorageFailureCode.ownerChanged);
      return result;
    } on PackStorageException {
      rethrow;
    } on ReviewCenterReadException {
      _fail(PackStorageFailureCode.ownerChanged);
    } on LearningPackException {
      _fail(PackStorageFailureCode.corrupt);
    } on AccountDeletionException {
      _fail(PackStorageFailureCode.unavailable);
    } on Object {
      _fail(PackStorageFailureCode.unavailable);
    } finally {
      await changes.cancel();
    }
  }

  Future<void> _requireOwner(String owner, bool Function() current) async {
    await requireReviewReadOwner(
      database,
      expectedOwnerId: owner,
      stillCurrent: current,
    );
    final fence = await ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(owner) ||
            (fence.cloudReceipt != null &&
                owner ==
                    accountDeletionReplacementGuestOwnerId(
                      fence.cloudReceipt!,
                    )))) {
      _fail(PackStorageFailureCode.unavailable);
    }
    if (!current()) _fail(PackStorageFailureCode.ownerChanged);
  }

  String _id(String prefix, List<Object?> parts) =>
      '$prefix:${_hash(jsonEncode(parts))}';
  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
  bool _isHash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  bool _validMilliseconds(int value) => value >= 0 && value <= 8640000000000000;
  DateTime _utc(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  Never _fail(PackStorageFailureCode code) => throw PackStorageException(code);
}
