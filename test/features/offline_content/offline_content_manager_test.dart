import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/data/drift_model_download_repository.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/data/model_download_adapter.dart';
import 'package:vocab_learning_app/features/offline_content/data/voice_pack_download_adapter.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';

void main() {
  late AppDatabase database;
  late Directory directory;
  late DriftOfflineContentRepository repository;
  late DateTime nowUtc;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('lexiquest-f44-');
    repository = DriftOfflineContentRepository(database);
    nowUtc = DateTime.utc(2026, 8, 30, 9);
  });

  tearDown(() async {
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('f44 verified download is atomic, pinned, and restart safe', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final identity = await _seedManifest(database, 'pack-a', bytes);
    final adapter = _BytesAdapter(bytes);
    final manager = VerifiedOfflineContentManager(
      repository: repository,
      adapters: <OfflineContentDownloadAdapter>[adapter],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => directory,
      nowUtc: () => nowUtc,
    );

    final first = manager.download(identity);
    final replay = manager.download(identity);
    expect(identical(first, replay), isTrue);
    final downloaded = await first;
    await replay;
    expect(downloaded.status, OfflineContentStatus.verified);
    expect(downloaded.identity, identity);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}${downloaded.localPath}',
      ).readAsBytes(),
      bytes,
    );
    expect(adapter.calls, 1);

    final reopened = VerifiedOfflineContentManager(
      repository: DriftOfflineContentRepository(database),
      adapters: <OfflineContentDownloadAdapter>[adapter],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => directory,
      nowUtc: () => nowUtc.add(const Duration(minutes: 1)),
    );
    expect(
      (await reopened.verify(identity)).status,
      OfflineContentStatus.verified,
    );
    expect(
      adapter.calls,
      1,
      reason: 'verified restart must not download again',
    );
  });

  test('f44 checksum mismatch quarantines and never publishes bytes', () async {
    final expected = Uint8List.fromList(<int>[1, 2, 3]);
    final identity = await _seedManifest(database, 'pack-b', expected);
    final manager = VerifiedOfflineContentManager(
      repository: repository,
      adapters: <OfflineContentDownloadAdapter>[
        _BytesAdapter(Uint8List.fromList(<int>[9, 9, 9])),
      ],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => directory,
      nowUtc: () => nowUtc,
    );

    await expectLater(
      manager.download(identity),
      throwsA(
        isA<OfflineContentFailure>().having(
          (failure) => failure.code,
          'code',
          OfflineContentFailureCode.checksumMismatch,
        ),
      ),
    );
    final state = await repository.state(identity);
    expect(state.status, OfflineContentStatus.quarantined);
    expect(state.localPath, isNull);
    expect(
      directory.listSync().whereType<File>().where(
        (file) => !file.path.endsWith('.partial'),
      ),
      isEmpty,
    );
  });

  test(
    'f44 interrupted download repairs once with the same identity',
    () async {
      final bytes = Uint8List.fromList(<int>[4, 5, 6]);
      final identity = await _seedManifest(database, 'pack-c', bytes);
      final adapter = _BytesAdapter(bytes, failFirst: true);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[adapter],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      await expectLater(manager.download(identity), throwsStateError);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.interrupted,
      );

      final repaired = await manager.repair(identity);
      expect(repaired.status, OfflineContentStatus.verified);
      expect(adapter.calls, 2);
      expect((await repository.catalog()).single.identity, identity);
    },
  );

  test(
    'f44 review publish failures after rename persist an interrupted state',
    () async {
      for (final persistFailure in <bool>[false, true]) {
        final bytes = Uint8List.fromList(<int>[21, 22, 23]);
        final identity = await _seedManifest(
          database,
          persistFailure ? 'persist-failure' : 'installed-bytes-failure',
          bytes,
        );
        final delegate = DriftOfflineContentRepository(database);
        final manager = VerifiedOfflineContentManager(
          repository: persistFailure
              ? _FailingPersistRepository(delegate)
              : delegate,
          adapters: <OfflineContentDownloadAdapter>[
            _BytesAdapter(
              bytes,
              installedBytesError: persistFailure
                  ? null
                  : StateError('installed bytes unavailable'),
            ),
          ],
          removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
          rootDirectory: () async => directory,
          nowUtc: () => nowUtc,
        );

        await expectLater(manager.download(identity), throwsStateError);

        final state = await delegate.state(identity);
        expect(state.status, OfflineContentStatus.interrupted);
        expect(state.failureCode, OfflineContentFailureCode.interrupted);
        final manifest = await delegate.requireManifest(identity);
        final published = File(
          '${directory.path}${Platform.pathSeparator}'
          '${OfflineContentArtifactKey.forManifest(manifest).publishedName}',
        );
        expect(await published.readAsBytes(), bytes);
      }
    },
  );

  test('f44 review rejects a noncanonical durable download-state id', () async {
    final bytes = Uint8List.fromList(<int>[24, 25, 26]);
    final identity = await _seedManifest(database, 'state-id', bytes);
    await database
        .into(database.contentDownloadStates)
        .insert(
          ContentDownloadStatesCompanion.insert(
            id: 'not-the-canonical-state-id',
            manifestId: 'manifest:state-id:r1',
            updatedAtUtcMs: 3,
          ),
        );

    await expectLater(
      repository.state(identity),
      throwsA(
        isA<OfflineContentFailure>().having(
          (failure) => failure.code,
          'code',
          OfflineContentFailureCode.invalidState,
        ),
      ),
    );
  });

  test(
    'f44 removal preserves manifest and cleanup skips pinned revision',
    () async {
      final firstBytes = Uint8List.fromList(<int>[1, 1, 1]);
      final secondBytes = Uint8List.fromList(<int>[2, 2, 2, 2]);
      final first = await _seedManifest(database, 'pack-d', firstBytes);
      final second = await _seedManifest(database, 'pack-e', secondBytes);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _IdentityBytesAdapter(<ContentIdentity, Uint8List>{
            first: firstBytes,
            second: secondBytes,
          }),
        ],
        removalAuthority: _MutableRemovalAuthority(<ContentIdentity>{second}),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      await manager.download(first);
      nowUtc = nowUtc.add(const Duration(minutes: 1));
      await manager.download(second);

      final freed = await manager.cleanupForDiskPressure(
        bytesToFree: firstBytes.length,
      );
      expect(freed, firstBytes.length);
      expect(
        (await repository.state(first)).status,
        OfflineContentStatus.notDownloaded,
      );
      expect(
        (await repository.state(second)).status,
        OfflineContentStatus.verified,
      );
      expect(
        await database.select(database.contentManifests).get(),
        hasLength(2),
      );

      await expectLater(
        manager.removeBytes(second),
        throwsA(
          isA<OfflineContentFailure>().having(
            (failure) => failure.code,
            'code',
            OfflineContentFailureCode.contentInUse,
          ),
        ),
      );
      expect(
        (await repository.state(second)).status,
        OfflineContentStatus.verified,
      );
      expect(
        await database.select(database.contentManifests).get(),
        hasLength(2),
      );
    },
  );

  test(
    'f44 review recovery publishes complete orphan bytes and interrupts partials',
    () async {
      final completeBytes = Uint8List.fromList(<int>[7, 8, 9, 10]);
      final complete = await _seedManifest(
        database,
        'recovery-a',
        completeBytes,
      );
      final incompleteBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final incomplete = await _seedManifest(
        database,
        'recovery-b',
        incompleteBytes,
      );
      final completeManifest = await repository.requireManifest(complete);
      final incompleteManifest = await repository.requireManifest(incomplete);
      final completeKey = OfflineContentArtifactKey.forManifest(
        completeManifest,
      );
      final incompleteKey = OfflineContentArtifactKey.forManifest(
        incompleteManifest,
      );
      await File(
        '${directory.path}${Platform.pathSeparator}${completeKey.partialName}',
      ).writeAsBytes(completeBytes, flush: true);
      await repository.markDownloading(
        completeManifest,
        downloadedBytes: completeBytes.length,
        updatedAtUtc: nowUtc,
      );
      await File(
        '${directory.path}${Platform.pathSeparator}${incompleteKey.partialName}',
      ).writeAsBytes(<int>[1], flush: true);
      await repository.markDownloading(
        incompleteManifest,
        downloadedBytes: 1,
        updatedAtUtc: nowUtc,
      );

      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _IdentityBytesAdapter(<ContentIdentity, Uint8List>{
            complete: completeBytes,
            incomplete: incompleteBytes,
          }),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      await manager.reconcile();

      final recovered = await repository.state(complete);
      final interrupted = await repository.state(incomplete);
      expect(recovered.status, OfflineContentStatus.verified);
      expect(recovered.localPath, completeKey.publishedName);
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}${completeKey.publishedName}',
        ).readAsBytes(),
        completeBytes,
      );
      expect(interrupted.status, OfflineContentStatus.interrupted);
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}${incompleteKey.partialName}',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'f44 review recovery adopts a verified final orphan without network',
    () async {
      final bytes = Uint8List.fromList(<int>[11, 12, 13]);
      final identity = await _seedManifest(database, 'orphan-final', bytes);
      final manifest = await repository.requireManifest(identity);
      final key = OfflineContentArtifactKey.forManifest(manifest);
      await File(
        '${directory.path}${Platform.pathSeparator}${key.publishedName}',
      ).writeAsBytes(bytes, flush: true);
      final adapter = _BytesAdapter(bytes);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[adapter],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      await manager.reconcile();

      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.verified,
      );
      expect(
        adapter.calls,
        0,
        reason: 'reconciliation must remain network-free',
      );
    },
  );

  test(
    'f44 review adapter authority must validate installed bytes before publish',
    () async {
      final bytes = Uint8List.fromList(<int>[14, 15, 16]);
      final identity = await _seedManifest(database, 'authority-gap', bytes);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _RejectingAuthorityAdapter(bytes),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      await expectLater(
        manager.download(identity),
        throwsA(
          isA<OfflineContentFailure>().having(
            (failure) => failure.code,
            'code',
            OfflineContentFailureCode.invalidState,
          ),
        ),
      );
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.quarantined,
      );
    },
  );

  test(
    'f44 review model adapter revalidates authoritative installed bytes offline',
    () async {
      final bytes = Uint8List.fromList(<int>[17, 18, 19, 20]);
      final model = _modelManifest(bytes);
      final identity = await _seedManifest(database, model.id, bytes);
      final modelDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}models',
      );
      final source = _ModelBytesSource(bytes);
      final modelManager = ModelDownloadManager(
        repository: DriftModelDownloadRepository(database),
        source: source,
        verifier: const _AcceptingModelVerifier(),
        modelDirectory: () async => modelDirectory,
        nowUtc: () => nowUtc,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          ModelDownloadAdapter(
            manager: modelManager,
            resolveManifest: (candidate) =>
                candidate == identity ? model : null,
          ),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async =>
            Directory('${directory.path}${Platform.pathSeparator}offline'),
        nowUtc: () => nowUtc,
      );
      await manager.download(identity);
      final installed = await modelManager.repository.find(model.recordId);
      await File(installed!.localPath!).writeAsBytes(<int>[0, 0, 0, 0]);

      await expectLater(
        manager.verify(identity),
        throwsA(
          isA<OfflineContentFailure>().having(
            (failure) => failure.code,
            'code',
            OfflineContentFailureCode.checksumMismatch,
          ),
        ),
      );
      expect(source.calls, 1, reason: 'verification must not redownload');
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.quarantined,
      );
    },
  );

  test(
    'f44 review catalog quarantines corrupted authoritative model and repair redownloads',
    () async {
      final bytes = Uint8List.fromList(<int>[17, 18, 19, 20]);
      final model = _modelManifest(bytes);
      final identity = await _seedManifest(database, model.id, bytes);
      final modelDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}catalog-models',
      );
      final source = _ModelBytesSource(bytes);
      final modelManager = ModelDownloadManager(
        repository: DriftModelDownloadRepository(database),
        source: source,
        verifier: const _AcceptingModelVerifier(),
        modelDirectory: () async => modelDirectory,
        nowUtc: () => nowUtc,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          ModelDownloadAdapter(
            manager: modelManager,
            resolveManifest: (candidate) =>
                candidate == identity ? model : null,
          ),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => Directory(
          '${directory.path}${Platform.pathSeparator}catalog-offline',
        ),
        nowUtc: () => nowUtc,
      );

      await manager.download(identity);
      final installed = await modelManager.repository.find(model.recordId);
      await File(installed!.localPath!).writeAsBytes(<int>[0, 0, 0, 0]);

      final catalog = await manager.catalog();

      expect(catalog, hasLength(1));
      expect(catalog.single.status, OfflineContentStatus.quarantined);
      expect(
        catalog.single.failureCode,
        OfflineContentFailureCode.checksumMismatch,
      );
      expect(source.calls, 1, reason: 'catalog verification must not download');

      final repaired = await manager.repair(identity);

      expect(repaired.status, OfflineContentStatus.verified);
      expect(source.calls, 2, reason: 'repair must use the adapter authority');
    },
  );

  test(
    'f44 review catalog quarantines a deleted verified receipt before repair',
    () async {
      final bytes = Uint8List.fromList(<int>[25, 26, 27, 28]);
      final identity = await _seedManifest(database, 'missing-receipt', bytes);
      final adapter = _BytesAdapter(bytes);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[adapter],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      final downloaded = await manager.download(identity);
      await File(
        '${directory.path}${Platform.pathSeparator}${downloaded.localPath}',
      ).delete();

      final catalog = await manager.catalog();

      expect(catalog, hasLength(1));
      expect(catalog.single.status, OfflineContentStatus.quarantined);
      expect(
        catalog.single.failureCode,
        OfflineContentFailureCode.missingArtifact,
      );
      expect(adapter.calls, 1, reason: 'catalog verification must not stage');

      final repaired = await manager.repair(identity);

      expect(repaired.status, OfflineContentStatus.verified);
      expect(adapter.calls, 2, reason: 'repair restages the missing receipt');
    },
  );

  test(
    'f44 review conflicting operations serialize while adjacent retries join',
    () async {
      final bytes = Uint8List.fromList(<int>[21, 22, 23]);
      final identity = await _seedManifest(database, 'queued', bytes);
      final staged = Completer<void>();
      final release = Completer<void>();
      final adapter = _BlockingAdapter(bytes, staged: staged, release: release);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[adapter],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );

      final first = manager.download(identity);
      final joined = manager.download(identity);
      expect(identical(first, joined), isTrue);
      await staged.future;
      final removal = manager.removeBytes(identity);
      var removed = false;
      removal.whenComplete(() => removed = true);
      await Future<void>.delayed(Duration.zero);
      expect(removed, isFalse, reason: 'remove must wait for download');

      release.complete();
      await first;
      await removal;

      expect(adapter.stageCalls, 1);
      expect(adapter.removeCalls, 1);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.notDownloaded,
      );
    },
  );

  test(
    'f44 review removal rechecks authoritative pins inside the lease',
    () async {
      final bytes = Uint8List.fromList(<int>[31, 32, 33]);
      final identity = await _seedManifest(database, 'leased', bytes);
      final authority = _MutableRemovalAuthority(<ContentIdentity>{});
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
        removalAuthority: authority,
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      await manager.download(identity);
      authority.onLease = () => authority.pinned.add(identity);

      await expectLater(
        manager.removeBytes(identity),
        throwsA(
          isA<OfflineContentFailure>().having(
            (failure) => failure.code,
            'code',
            OfflineContentFailureCode.contentInUse,
          ),
        ),
      );

      expect(authority.leaseCalls, 1);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.verified,
      );
    },
  );

  test(
    'f44 review Drift authority pins active paused and assessment revisions',
    () async {
      final packBytes = Uint8List.fromList(<int>[35, 36, 37]);
      final pack = await _seedManifest(
        database,
        'required-pack',
        packBytes,
        type: ContentType.learningPack,
      );
      final assessmentBytes = Uint8List.fromList(<int>[38, 39, 40]);
      final assessment = await _seedManifest(
        database,
        'required-form',
        assessmentBytes,
        type: ContentType.assessmentForm,
      );
      final authority = DriftOfflineContentRemovalAuthority(database);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _IdentityBytesAdapter(<ContentIdentity, Uint8List>{
            pack: packBytes,
            assessment: assessmentBytes,
          }),
        ],
        removalAuthority: authority,
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      await manager.download(pack);
      await manager.download(assessment);
      await _seedPinnedLearningSession(database, pack, state: 'active');
      await _seedPinnedAssessmentRun(
        database,
        assessment,
        sha256.convert(assessmentBytes).toString(),
      );

      expect(await manager.canRemove(pack), isFalse);
      expect(await manager.canRemove(assessment), isFalse);
      await database.customUpdate(
        "UPDATE learning_sessions SET state = 'paused' WHERE id = 'session:pinned'",
      );
      expect(await manager.canRemove(pack), isFalse);
      await database.customUpdate(
        "UPDATE learning_sessions SET state = 'completed' WHERE id = 'session:pinned'",
      );
      await database.customUpdate(
        "UPDATE assessment_runs SET state = 'completed', completed_at_utc_ms = 50 "
        "WHERE id = 'assessment:pinned'",
      );

      expect(await manager.canRemove(pack), isTrue);
      expect(await manager.canRemove(assessment), isTrue);
    },
  );

  test(
    'f44 review canonical artifact keys reject traversal and foreign rows',
    () async {
      final bytes = Uint8List.fromList(<int>[41, 42, 43]);
      final identity = await _seedManifest(database, 'safe-unicode-ไทย', bytes);
      final manifest = await repository.requireManifest(identity);
      final key = OfflineContentArtifactKey.forManifest(manifest);
      expect(key.publishedName, matches(RegExp(r'^[a-f0-9]{64}\.content$')));
      expect(key.partialName, matches(RegExp(r'^[a-f0-9]{64}\.partial$')));

      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      await manager.download(identity);
      final foreign = File(
        '${directory.parent.path}${Platform.pathSeparator}f44-foreign.content',
      );
      await foreign.writeAsBytes(<int>[99], flush: true);
      addTearDown(() async {
        if (await foreign.exists()) await foreign.delete();
      });
      await database.customUpdate(
        'UPDATE content_download_states SET local_path = ? WHERE manifest_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(foreign.path),
          Variable<String>(manifest.storageId),
        ],
      );

      await expectLater(
        repository.state(identity),
        throwsA(
          isA<OfflineContentFailure>().having(
            (failure) => failure.code,
            'code',
            OfflineContentFailureCode.invalidState,
          ),
        ),
      );
      await expectLater(
        manager.removeBytes(identity),
        throwsA(isA<OfflineContentFailure>()),
      );
      expect(await foreign.readAsBytes(), <int>[99]);
      expect(
        () => OfflineContentArtifactKey.requireCanonicalIdentity(
          const ContentIdentity(
            type: ContentType.offlineArtifact,
            id: '../escape',
            revision: 1,
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('f44 review rejects a symlinked artifact root', () async {
    final bytes = Uint8List.fromList(<int>[44, 45, 46]);
    final identity = await _seedManifest(database, 'linked-root', bytes);
    final target = await Directory.systemTemp.createTemp(
      'lexiquest-f44-link-target-',
    );
    final link = Link(
      '${directory.path}${Platform.pathSeparator}artifact-root-link',
    );
    addTearDown(() async {
      if (await link.exists()) await link.delete();
      if (await target.exists()) await target.delete(recursive: true);
    });
    try {
      await link.create(target.path);
    } on FileSystemException {
      markTestSkipped('symbolic links are unavailable on this platform');
      return;
    }
    final manager = VerifiedOfflineContentManager(
      repository: repository,
      adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
      removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
      rootDirectory: () async => Directory(link.path),
      nowUtc: () => nowUtc,
    );

    await expectLater(
      manager.download(identity),
      throwsA(
        isA<OfflineContentFailure>().having(
          (failure) => failure.code,
          'code',
          OfflineContentFailureCode.invalidState,
        ),
      ),
    );
    expect(target.listSync(), isEmpty);
  });

  test(
    'f44 second review corrupt verified final remains integrity quarantined on restart',
    () async {
      final bytes = Uint8List.fromList(<int>[47, 48, 49, 50]);
      final identity = await _seedManifest(database, 'restart-corrupt', bytes);
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      final downloaded = await manager.download(identity);
      await File(
        '${directory.path}${Platform.pathSeparator}${downloaded.localPath}',
      ).writeAsBytes(<int>[50, 49, 48, 47], flush: true);

      await manager.reconcile();

      final state = await repository.state(identity);
      expect(state.status, OfflineContentStatus.quarantined);
      expect(state.failureCode, OfflineContentFailureCode.checksumMismatch);
    },
  );

  test(
    'f44 second review cleanup counts authoritative model bytes and stops at real threshold',
    () async {
      final bytes = Uint8List.fromList(<int>[51, 52, 53, 54]);
      final model = _modelManifest(bytes);
      final identity = await _seedManifest(database, model.id, bytes);
      final modelDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}models-cleanup',
      );
      final modelRepository = DriftModelDownloadRepository(database);
      final modelManager = ModelDownloadManager(
        repository: modelRepository,
        source: _ModelBytesSource(bytes),
        verifier: const _AcceptingModelVerifier(),
        modelDirectory: () async => modelDirectory,
        nowUtc: () => nowUtc,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          ModelDownloadAdapter(
            manager: modelManager,
            resolveManifest: (candidate) =>
                candidate == identity ? model : null,
            removeModel: (manifest) async {
              await (database.delete(
                database.modelDownloads,
              )..where((row) => row.id.equals(manifest.recordId))).go();
            },
          ),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => Directory(
          '${directory.path}${Platform.pathSeparator}offline-model',
        ),
        nowUtc: () => nowUtc,
      );

      final installed = await manager.download(identity);
      expect(installed.downloadedBytes, bytes.length * 2);

      final freed = await manager.cleanupForDiskPressure(
        bytesToFree: bytes.length + 1,
      );

      expect(freed, installed.downloadedBytes);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.notDownloaded,
      );
      expect(await modelRepository.find(model.recordId), isNull);
    },
  );

  test(
    'f44 final review model removal waits outside the Drift pin transaction',
    () async {
      final bytes = Uint8List.fromList(<int>[81, 82, 83, 84]);
      final model = _modelManifest(bytes);
      final identity = await _seedManifest(database, model.id, bytes);
      final manifest = await repository.requireManifest(identity);
      final offlineRoot = Directory(
        '${directory.path}${Platform.pathSeparator}offline-model-deadlock',
      );
      await offlineRoot.create(recursive: true);
      final key = OfflineContentArtifactKey.forManifest(manifest);
      await File(
        '${offlineRoot.path}${Platform.pathSeparator}${key.publishedName}',
      ).writeAsBytes(bytes, flush: true);
      await repository.persistVerified(
        VerifiedDownloadedArtifact(
          manifest: manifest,
          localPath: key.publishedName,
          byteLength: bytes.length,
          totalInstalledBytes: bytes.length * 2,
          checksumSha256: manifest.checksumSha256,
          verifiedAtUtc: nowUtc,
        ),
      );
      final driftModelRepository = DriftModelDownloadRepository(database);
      final observingRepository = _BoundedDriftModelRepository(
        driftModelRepository,
      );
      final source = _BlockingModelBytesSource(bytes);
      final modelRoot = Directory(
        '${directory.path}${Platform.pathSeparator}models-deadlock',
      );
      final modelManager = ModelDownloadManager(
        repository: observingRepository,
        source: source,
        verifier: const _AcceptingModelVerifier(),
        modelDirectory: () async => modelRoot,
        nowUtc: () => nowUtc,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          ModelDownloadAdapter(
            manager: modelManager,
            resolveManifest: (candidate) =>
                candidate == identity ? model : null,
            removeModel: (candidate) async {
              await (database.delete(
                database.modelDownloads,
              )..where((row) => row.id.equals(candidate.recordId))).go();
            },
          ),
        ],
        removalAuthority: DriftOfflineContentRemovalAuthority(database),
        rootDirectory: () async => offlineRoot,
        nowUtc: () => nowUtc,
      );

      final activeDownload = modelManager.downloadAndActivate(model);
      await source.started.future;
      final removal = manager.removeBytes(identity);
      source.release.complete();

      final activated = await activeDownload;
      expect(observingRepository.readyWriteTimedOut, isFalse);
      expect(await File(activated.localPath!).exists(), isTrue);
      expect(await removal, bytes.length * 2);
      expect(await File(activated.localPath!).exists(), isFalse);
      expect(await driftModelRepository.find(model.recordId), isNull);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.notDownloaded,
      );
    },
  );

  test(
    'f44 second review cleanup counts authoritative voice install and receipt bytes',
    () async {
      final productionCatalog = OfflineVoicePackManifestCatalog.production;
      final audio = productionCatalog.requirePackagedFileBytes(
        productionCatalog
            .requireManifest(productionCatalog.identities.single)
            .files
            .single
            .uri,
      );
      final voiceManifest = _voiceManifest(audio);
      final receipt = Uint8List.fromList(
        utf8.encode(jsonEncode(voiceManifest.toJson())),
      );
      final identity = await _seedManifest(
        database,
        'voice-${voiceManifest.packId}',
        receipt,
      );
      final voiceRoot = Directory(
        '${directory.path}${Platform.pathSeparator}voice-packs',
      );
      final source = _VoiceBytesSource(audio);
      final voiceManager = StandardVoicePackDownloadManager(
        rootDirectory: () async => voiceRoot,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          VoicePackDownloadAdapter(
            manager: voiceManager,
            catalog: OfflineVoicePackManifestCatalog(
              <ContentIdentity, StandardVoicePackManifest>{
                identity: voiceManifest,
              },
            ),
          ),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => Directory(
          '${directory.path}${Platform.pathSeparator}offline-voice',
        ),
        nowUtc: () => nowUtc,
      );

      final installed = await manager.download(identity);
      expect(installed.downloadedBytes, greaterThan(receipt.length));
      await manager.verify(identity);
      expect(
        source.calls,
        1,
        reason: 'verified voice inspection is network-free',
      );

      final freed = await manager.cleanupForDiskPressure(
        bytesToFree: receipt.length + 1,
      );

      expect(freed, installed.downloadedBytes);
      expect(
        (await repository.state(identity)).status,
        OfflineContentStatus.notDownloaded,
      );
      expect(await voiceManager.findVerifiedInstalled(voiceManifest), isNull);
    },
  );

  test(
    'f44 review catalog quarantines corrupted authoritative voice with checksum evidence',
    () async {
      final productionCatalog = OfflineVoicePackManifestCatalog.production;
      final audio = productionCatalog.requirePackagedFileBytes(
        productionCatalog
            .requireManifest(productionCatalog.identities.single)
            .files
            .single
            .uri,
      );
      final voiceManifest = _voiceManifest(audio);
      final receipt = Uint8List.fromList(
        utf8.encode(jsonEncode(voiceManifest.toJson())),
      );
      final identity = await _seedManifest(
        database,
        'voice-corruption-${voiceManifest.packId}',
        receipt,
      );
      final voiceRoot = Directory(
        '${directory.path}${Platform.pathSeparator}voice-corruption-packs',
      );
      final source = _VoiceBytesSource(audio);
      final voiceManager = StandardVoicePackDownloadManager(
        rootDirectory: () async => voiceRoot,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          VoicePackDownloadAdapter(
            manager: voiceManager,
            catalog: OfflineVoicePackManifestCatalog(
              <ContentIdentity, StandardVoicePackManifest>{
                identity: voiceManifest,
              },
            ),
          ),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => Directory(
          '${directory.path}${Platform.pathSeparator}offline-voice-corruption',
        ),
        nowUtc: () => nowUtc,
      );

      await manager.download(identity);
      final installed = await voiceManager.findVerifiedInstalled(voiceManifest);
      await File(
        installed!.pathFor(voiceManifest.files.single.relativePath),
      ).writeAsBytes(<int>[0, 0, 0, 0]);

      final catalog = await manager.catalog();

      expect(catalog, hasLength(1));
      expect(catalog.single.status, OfflineContentStatus.quarantined);
      expect(
        catalog.single.failureCode,
        OfflineContentFailureCode.checksumMismatch,
      );
      expect(source.calls, 1, reason: 'catalog inspection stays offline');

      final repaired = await manager.repair(identity);

      expect(repaired.status, OfflineContentStatus.verified);
      expect(source.calls, 2, reason: 'repair reinstalls verified voice bytes');
    },
  );

  test('f44 review voice catalog rejects record and pack aliases', () {
    final audio = Uint8List.fromList(<int>[60, 61, 62]);
    final manifest = _voiceManifest(audio);
    final nextRevision = _voiceManifest(audio, version: '1.1.0');
    final first = ContentIdentity(
      type: ContentType.offlineArtifact,
      id: 'voice-alias-a',
      revision: 1,
    );
    final second = ContentIdentity(
      type: ContentType.offlineArtifact,
      id: 'voice-alias-b',
      revision: 1,
    );

    expect(
      () => OfflineVoicePackManifestCatalog(
        <ContentIdentity, StandardVoicePackManifest>{
          first: manifest,
          second: manifest,
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => OfflineVoicePackManifestCatalog(
        <ContentIdentity, StandardVoicePackManifest>{
          first: manifest,
          second: nextRevision,
        },
      ),
      throwsArgumentError,
      reason: 'one pack id cannot be owned by two offline identities',
    );
  });

  test(
    'f44 second review rejects linked published and partial leaves without touching targets',
    () async {
      for (final suffix in <String>['published', 'partial']) {
        final bytes = Uint8List.fromList(<int>[60, 61, 62]);
        final identity = await _seedManifest(database, 'linked-$suffix', bytes);
        final manifest = await repository.requireManifest(identity);
        final key = OfflineContentArtifactKey.forManifest(manifest);
        final target = File(
          '${directory.parent.path}${Platform.pathSeparator}f44-$suffix-target',
        );
        final link = Link(
          '${directory.path}${Platform.pathSeparator}'
          '${suffix == 'published' ? key.publishedName : key.partialName}',
        );
        addTearDown(() async {
          if (await link.exists()) await link.delete();
          if (await target.exists()) await target.delete();
        });
        try {
          await link.create(target.path);
        } on FileSystemException {
          markTestSkipped('symbolic links are unavailable on this platform');
          return;
        }
        final manager = VerifiedOfflineContentManager(
          repository: repository,
          adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
          removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
          rootDirectory: () async => directory,
          nowUtc: () => nowUtc,
        );

        await expectLater(
          manager.download(identity),
          throwsA(
            isA<OfflineContentFailure>().having(
              (failure) => failure.code,
              'code',
              OfflineContentFailureCode.invalidState,
            ),
          ),
        );
        expect(await target.exists(), isFalse);
      }
    },
  );

  test(
    'f44 second review model removal ignores foreign database path and confines deletion',
    () async {
      final bytes = Uint8List.fromList(<int>[63, 64, 65, 66]);
      final model = _modelManifest(bytes);
      final identity = await _seedManifest(database, 'model-confined', bytes);
      final modelDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}models-confined',
      );
      final modelRepository = DriftModelDownloadRepository(database);
      final modelManager = ModelDownloadManager(
        repository: modelRepository,
        source: _ModelBytesSource(bytes),
        verifier: const _AcceptingModelVerifier(),
        modelDirectory: () async => modelDirectory,
        nowUtc: () => nowUtc,
      );
      final adapter = ModelDownloadAdapter(
        manager: modelManager,
        resolveManifest: (candidate) => candidate == identity ? model : null,
        removeModel: (manifest) async {
          await (database.delete(
            database.modelDownloads,
          )..where((row) => row.id.equals(manifest.recordId))).go();
        },
      );
      final contentManifest = await repository.requireManifest(identity);
      await modelManager.downloadAndActivate(model);
      final canonical = File(
        '${modelDirectory.path}${Platform.pathSeparator}${model.fileStem}.tflite',
      );
      final foreign = File(
        '${directory.parent.path}${Platform.pathSeparator}foreign-model.tflite',
      );
      await foreign.writeAsBytes(<int>[99], flush: true);
      addTearDown(() async {
        if (await foreign.exists()) await foreign.delete();
      });
      await database.customUpdate(
        'UPDATE model_downloads SET local_path = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<String>(foreign.path),
          Variable<String>(model.recordId),
        ],
      );

      final removed = await adapter.removeInstalled(contentManifest);

      expect(removed, bytes.length);
      expect(await canonical.exists(), isFalse);
      expect(await foreign.readAsBytes(), <int>[99]);
    },
  );

  test(
    'f44 second review disposal drains in-flight work and rejects new work',
    () async {
      final bytes = Uint8List.fromList(<int>[67, 68, 69]);
      final identity = await _seedManifest(database, 'dispose-drain', bytes);
      final staged = Completer<void>();
      final release = Completer<void>();
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _BlockingAdapter(bytes, staged: staged, release: release),
        ],
        removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      final download = manager.download(identity);
      await staged.future;
      var disposed = false;
      final disposal = manager.dispose().whenComplete(() => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      release.complete();
      await download;
      await disposal;

      await expectLater(manager.catalog(), throwsStateError);
    },
  );

  test(
    'f44 second review successful removal preserves learning and research audit rows',
    () async {
      final packBytes = Uint8List.fromList(<int>[73, 74, 75]);
      final pack = await _seedManifest(
        database,
        'audit-pack',
        packBytes,
        type: ContentType.learningPack,
      );
      final formBytes = Uint8List.fromList(<int>[76, 77, 78]);
      final form = await _seedManifest(
        database,
        'audit-form',
        formBytes,
        type: ContentType.assessmentForm,
      );
      await _seedPinnedLearningSession(database, pack, state: 'completed');
      await _seedAuditAttemptAndEvent(database);
      await _seedPinnedAssessmentRun(
        database,
        form,
        sha256.convert(formBytes).toString(),
      );
      await database.customUpdate(
        "UPDATE assessment_runs SET state = 'completed', "
        'completed_at_utc_ms = 50 WHERE id = ?',
        variables: const <Variable<Object>>[
          Variable<String>('assessment:pinned'),
        ],
      );
      final before = <String, int>{
        'answer_attempts': await _tableCount(database, 'answer_attempts'),
        'learning_sessions': await _tableCount(database, 'learning_sessions'),
        'assessment_runs': await _tableCount(database, 'assessment_runs'),
        'events_v2': await _tableCount(database, 'events_v2'),
      };
      expect(before.values, everyElement(1));
      final manager = VerifiedOfflineContentManager(
        repository: repository,
        adapters: <OfflineContentDownloadAdapter>[
          _IdentityBytesAdapter(<ContentIdentity, Uint8List>{pack: packBytes}),
        ],
        removalAuthority: DriftOfflineContentRemovalAuthority(database),
        rootDirectory: () async => directory,
        nowUtc: () => nowUtc,
      );
      await manager.download(pack);

      expect(await manager.removeBytes(pack), packBytes.length);

      expect(<String, int>{
        'answer_attempts': await _tableCount(database, 'answer_attempts'),
        'learning_sessions': await _tableCount(database, 'learning_sessions'),
        'assessment_runs': await _tableCount(database, 'assessment_runs'),
        'events_v2': await _tableCount(database, 'events_v2'),
      }, before);
    },
  );
}

Future<void> _seedAuditAttemptAndEvent(AppDatabase database) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:f44',
          ownerId: 'owner:pinned',
          name: 'F44',
          normalizedName: 'f44',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:f44',
          ownerId: 'owner:pinned',
          categoryId: 'category:f44',
          spelling: 'offline',
          normalizedSpelling: 'offline',
          meaning: 'available without network',
          normalizedMeaning: 'available without network',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:f44',
          ownerId: 'owner:pinned',
          sessionId: 'session:pinned',
          wordId: 'word:f44',
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: 40,
        ),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: 'event:f44',
          eventType: 'QuizCompleted',
          eventVersion: 1,
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(40, isUtc: true),
          recordedAtUtc: DateTime.fromMillisecondsSinceEpoch(41, isUtc: true),
          actorIdentity: 'owner:pinned',
          ownerId: 'owner:pinned',
          aggregateType: 'LearningSession',
          aggregateId: 'session:pinned',
          idempotencyKey: 'attempt:f44:v1',
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'f44-review',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode(<String, Object>{'attemptId': 'attempt:f44'}),
        ),
      );
}

Future<int> _tableCount(AppDatabase database, String table) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS count FROM $table')
      .getSingle();
  return row.read<int>('count');
}

Future<ContentIdentity> _seedManifest(
  AppDatabase database,
  String id,
  Uint8List bytes, {
  ContentType type = ContentType.offlineArtifact,
}) async {
  final identity = ContentIdentity(type: type, id: id, revision: 1);
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'manifest:$id:r1',
          contentType: identity.type.name,
          contentId: identity.id,
          revision: identity.revision,
          checksumSha256: sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'https://example.invalid/$id.bin',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: 1,
          reviewedAtUtcMs: const Value(2),
          publishedAtUtcMs: const Value(3),
        ),
      );
  return identity;
}

Future<void> _seedPinnedLearningSession(
  AppDatabase database,
  ContentIdentity identity, {
  required String state,
}) async {
  await database.customInsert(
    "INSERT INTO local_owners "
    "(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('owner:pinned', 'localGuest', 1, 1)",
  );
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: 'owner:pinned',
    mode: LessonMode.meaningQuiz,
    itemCount: 1,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 0,
    timing: const SessionTiming.untimedAlternative(
      maximumActiveEffort: Duration(minutes: 5),
    ),
    packIdentity: identity,
    protocolId: 'protocol:f44',
    protocolVersion: '1',
    protocolLimitsIdentity: 'sha256:f44-limits',
  );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:pinned',
          ownerId: 'owner:pinned',
          activityType: 'researchAssessment',
          state: state,
          startedAtUtcMs: 20,
          appVersion: '1.0.0',
          buildId: 'f44-review',
          sessionConfigurationIdentity: Value(configuration.contentIdentity),
          sessionConfigurationJson: Value(configuration.stableSerialization),
        ),
      );
}

Future<void> _seedPinnedAssessmentRun(
  AppDatabase database,
  ContentIdentity identity,
  String checksum,
) async {
  await database.customInsert(
    "INSERT INTO experiment_assignments "
    "(id, owner_id, experiment_id, experiment_version, cohort, "
    "protocol_version, assigned_at_utc_ms) VALUES "
    "('assignment:pinned', 'owner:pinned', 'experiment:f44', 1, "
    "'enforced', '1.0.0', 10)",
  );
  await database.customInsert(
    "INSERT INTO assessment_runs "
    "(id, owner_id, learning_session_id, study_cycle_id, phase, state, "
    "protocol_id, protocol_version, experiment_id, experiment_version, "
    "assignment_id, cohort, consent_version, consent_decided_at_utc_ms, "
    "instrument_id, instrument_version, form_id, form_version, "
    "instrument_checksum_sha256, form_checksum_sha256, app_version, "
    "build_id, database_schema_version, content_revision, "
    "evidence_policy_version, feature_contract_revision, "
    "feature_contract_hash, started_at_utc_ms, completed_at_utc_ms, "
    "abandoned_at_utc_ms) VALUES (?, 'owner:pinned', 'session:pinned', "
    "'cycle:f44', 'pre', 'active', 'protocol:f44', '1.0.0', "
    "'experiment:f44', 1, 'assignment:pinned', 'enforced', 1, 5, "
    "'instrument:f44', '1', ?, '1', ?, ?, '1.0.0', 'f44-review', "
    "22, 'content:f44', 'evidence-v1', '1.0.0', ?, 30, NULL, NULL)",
    variables: [
      const Variable<String>('assessment:pinned'),
      Variable<String>(identity.id),
      Variable<String>(checksum),
      Variable<String>(checksum),
      Variable<String>(List<String>.filled(64, 'a').join()),
    ],
  );
}

final class _BytesAdapter implements OfflineContentDownloadAdapter {
  _BytesAdapter(this.bytes, {this.failFirst = false, this.installedBytesError});

  final Uint8List bytes;
  final bool failFirst;
  final Object? installedBytesError;
  int calls = 0;

  @override
  bool supports(ContentManifest manifest) => true;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    calls += 1;
    if (failFirst && calls == 1) throw StateError('interrupted');
    await temporaryFile.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async {
    final error = installedBytesError;
    if (error != null) throw error;
    return 0;
  }

  @override
  Future<int> removeInstalled(ContentManifest manifest) async => 0;

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {}
}

final class _FailingPersistRepository implements OfflineContentRepository {
  const _FailingPersistRepository(this.delegate);

  final OfflineContentRepository delegate;

  @override
  Future<List<OfflineContentState>> catalog() => delegate.catalog();

  @override
  Future<void> markDownloading(
    ContentManifest manifest, {
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  }) => delegate.markDownloading(
    manifest,
    downloadedBytes: downloadedBytes,
    updatedAtUtc: updatedAtUtc,
  );

  @override
  Future<void> markFailure(
    ContentManifest manifest, {
    required OfflineContentStatus status,
    required OfflineContentFailureCode failureCode,
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  }) => delegate.markFailure(
    manifest,
    status: status,
    failureCode: failureCode,
    downloadedBytes: downloadedBytes,
    updatedAtUtc: updatedAtUtc,
  );

  @override
  Future<void> markNotDownloaded(
    ContentManifest manifest, {
    required DateTime updatedAtUtc,
  }) => delegate.markNotDownloaded(manifest, updatedAtUtc: updatedAtUtc);

  @override
  Future<void> persistVerified(VerifiedDownloadedArtifact artifact) {
    throw StateError('persist verified failed');
  }

  @override
  Future<ContentManifest> requireManifest(ContentIdentity identity) =>
      delegate.requireManifest(identity);

  @override
  Future<OfflineContentState> state(ContentIdentity identity) =>
      delegate.state(identity);
}

final class _IdentityBytesAdapter implements OfflineContentDownloadAdapter {
  _IdentityBytesAdapter(this.bytesByIdentity);

  final Map<ContentIdentity, Uint8List> bytesByIdentity;

  @override
  bool supports(ContentManifest manifest) =>
      bytesByIdentity.containsKey(manifest.identity);

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    await temporaryFile.writeAsBytes(
      bytesByIdentity[manifest.identity]!,
      flush: true,
    );
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;

  @override
  Future<int> removeInstalled(ContentManifest manifest) async => 0;

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {}
}

final class _BlockingAdapter implements OfflineContentDownloadAdapter {
  _BlockingAdapter(this.bytes, {required this.staged, required this.release});

  final Uint8List bytes;
  final Completer<void> staged;
  final Completer<void> release;
  int stageCalls = 0;
  int removeCalls = 0;

  @override
  bool supports(ContentManifest manifest) => true;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    stageCalls += 1;
    if (!staged.isCompleted) staged.complete();
    await release.future;
    await temporaryFile.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {}

  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;

  @override
  Future<int> removeInstalled(ContentManifest manifest) async {
    removeCalls += 1;
    return 0;
  }
}

final class _RejectingAuthorityAdapter
    implements OfflineContentDownloadAdapter {
  const _RejectingAuthorityAdapter(this.bytes);

  final Uint8List bytes;

  @override
  bool supports(ContentManifest manifest) => true;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    await temporaryFile.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) {
    throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;

  @override
  Future<int> removeInstalled(ContentManifest manifest) async => 0;
}

ModelManifest _modelManifest(Uint8List bytes) => ModelManifest(
  id: 'f44-model',
  version: '1.0.0',
  minimumAppVersion: '1.0.0+1',
  sourceUri: Uri.https('models.example', '/f44-model.tflite'),
  license: 'Apache-2.0',
  licenseUri: Uri.https('models.example', '/LICENSE'),
  expectedSha256: sha256.convert(bytes).toString(),
  expectedBytes: bytes.length,
  inputShape: const <int>[1, 1, 1, 1],
  inputType: ModelTensorType.uint8,
  outputShape: const <int>[1, 1],
  outputType: ModelTensorType.uint8,
  inputEncoding: ModelInputEncoding.rawUint8Rgb,
  labelAssetName: 'labels.txt',
  supportedDelegates: const <ModelDelegate>{ModelDelegate.cpu},
);

final class _ModelBytesSource implements ModelByteSource {
  _ModelBytesSource(this.bytes);

  final Uint8List bytes;
  int calls = 0;

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    calls += 1;
    return ModelByteResponse(
      statusCode: 200,
      bytes: Stream<List<int>>.value(bytes),
    );
  }
}

StandardVoicePackManifest _voiceManifest(
  Uint8List bytes, {
  String version = '1.0.0',
}) => StandardVoicePackManifest.fromJson(<String, Object>{
  'schemaVersion': 1,
  'packId': 'core-en',
  'version': version,
  'locale': 'en',
  'voiceId': 'teacher-female',
  'engine': 'voxcpm2',
  'modelVersion': '2.0.3',
  'license': 'Apache-2.0',
  'licenseUri': 'https://example.invalid/LICENSE',
  'minimumAppVersion': '1.0.0+1',
  'baseUri': 'https://example.invalid/voice/',
  'generatedAtUtc': '2026-08-30T00:00:00.000Z',
  'totalBytes': bytes.length,
  'files': <Object>[
    <String, Object>{
      'contentId': 'word-cat',
      'normalizedTextSha256':
          '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045',
      'relativePath': 'words/cat.wav',
      'byteSize': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    },
  ],
});

final class _VoiceBytesSource implements StandardVoicePackByteSource {
  _VoiceBytesSource(this.bytes);

  final Uint8List bytes;
  int calls = 0;

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    calls += 1;
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: Stream<List<int>>.value(bytes.sublist(start)),
    );
  }
}

final class _AcceptingModelVerifier implements ModelFileVerifier {
  const _AcceptingModelVerifier();

  @override
  Future<void> verify(String path, ModelManifest manifest) async {}
}

final class _BlockingModelBytesSource implements ModelByteSource {
  _BlockingModelBytesSource(this.bytes);

  final Uint8List bytes;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        if (!started.isCompleted) started.complete();
        await release.future;
        controller.add(bytes.sublist(start));
        await controller.close();
      },
    );
    return ModelByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: controller.stream,
    );
  }
}

final class _BoundedDriftModelRepository implements ModelDownloadRepository {
  _BoundedDriftModelRepository(this.delegate);

  final DriftModelDownloadRepository delegate;
  bool readyWriteTimedOut = false;
  bool _observedReadyWrite = false;

  @override
  Future<void> activate(ModelDownloadRecord record) =>
      _write(record, () => delegate.activate(record));

  @override
  Future<ModelDownloadRecord?> find(String id) => delegate.find(id);

  @override
  Future<void> save(ModelDownloadRecord record) =>
      _write(record, () => delegate.save(record));

  Future<void> _write(
    ModelDownloadRecord record,
    Future<void> Function() write,
  ) async {
    final operation = write();
    if (record.state != ModelDownloadState.ready || _observedReadyWrite) {
      await operation;
      return;
    }
    _observedReadyWrite = true;
    try {
      await operation.timeout(const Duration(milliseconds: 100));
    } on TimeoutException {
      readyWriteTimedOut = true;
      throw StateError('model write blocked by the removal transaction');
    }
  }
}

final class _MutableRemovalAuthority implements OfflineContentRemovalAuthority {
  _MutableRemovalAuthority(this.pinned);

  final Set<ContentIdentity> pinned;
  void Function()? onLease;
  int leaseCalls = 0;

  @override
  Future<bool> isRequired(ContentIdentity identity) async =>
      pinned.contains(identity);

  @override
  Future<T> withRemovalLease<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  ) async {
    leaseCalls += 1;
    onLease?.call();
    if (pinned.contains(identity)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.contentInUse);
    }
    return operation();
  }
}
