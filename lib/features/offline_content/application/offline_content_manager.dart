import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../domain/offline_content_repository.dart';
import '../domain/offline_content_state.dart';

abstract interface class OfflineContentDownloadAdapter {
  bool supports(ContentManifest manifest);

  Future<void> stage(ContentManifest manifest, File temporaryFile);

  /// Revalidates adapter-owned authoritative bytes. A copied cache or receipt
  /// is not sufficient for model and voice adapters.
  Future<void> requireInstalledValid(ContentManifest manifest);

  /// Bytes held by the adapter-owned authoritative installation, excluding
  /// the manager-owned verified receipt.
  Future<int> installedBytes(ContentManifest manifest);

  /// Removes only adapter-owned authoritative bytes and returns the exact
  /// number of bytes deleted.
  Future<int> removeInstalled(ContentManifest manifest);
}

typedef OfflineInstalledContentRemoval = Future<int> Function();

/// Optional adapter boundary for authorities whose file-operation lease must
/// be acquired before the Drift pin transaction. The supplied remover is valid
/// only while the lease callback is active.
abstract interface class OfflineContentRemovalLeaseAdapter {
  Future<T> withRemovalLease<T>(
    ContentManifest manifest,
    Future<T> Function(OfflineInstalledContentRemoval removeInstalled)
    operation,
  );
}

abstract interface class OfflineContentManager {
  Future<List<OfflineContentState>> catalog();

  Future<OfflineContentState> download(ContentIdentity identity);

  Future<OfflineContentState> verify(ContentIdentity identity);

  Future<OfflineContentState> repair(ContentIdentity identity);

  Future<bool> canRemove(ContentIdentity identity);

  Future<int> removeBytes(ContentIdentity identity);

  Future<int> cleanupForDiskPressure({required int bytesToFree});

  /// Network-free bootstrap repair for state/file crash windows.
  Future<void> reconcile();

  /// Stops new work and drains every queued file/database operation.
  Future<void> dispose();
}

final class VerifiedOfflineContentManager implements OfflineContentManager {
  VerifiedOfflineContentManager({
    required this.repository,
    required List<OfflineContentDownloadAdapter> adapters,
    required this.removalAuthority,
    required this.rootDirectory,
    required this.nowUtc,
    this.qualityPolicy = const ContentQualityPolicy(),
  }) : adapters = List<OfflineContentDownloadAdapter>.unmodifiable(adapters);

  final OfflineContentRepository repository;
  final List<OfflineContentDownloadAdapter> adapters;
  final OfflineContentRemovalAuthority removalAuthority;
  final Future<Directory> Function() rootDirectory;
  final DateTime Function() nowUtc;
  final ContentQualityPolicy qualityPolicy;
  final _OfflineContentOperationQueue _operations =
      _OfflineContentOperationQueue();
  bool _disposed = false;

  @override
  Future<List<OfflineContentState>> catalog() async {
    _requireOpen();
    final states = await repository.catalog();
    final supported = <OfflineContentState>[];
    for (final initial in states) {
      var state = initial;
      final manifest = await repository.requireManifest(state.identity);
      if (adapters.where((adapter) => adapter.supports(manifest)).length == 1) {
        if (state.status == OfflineContentStatus.verified) {
          await _operations.run<void>(
            state.identity,
            _OfflineOperation.catalog,
            () => _verifyPublished(
              state.identity,
              quarantine: true,
              persist: false,
            ),
          );
          state = await repository.state(state.identity);
        }
        supported.add(state);
      }
    }
    return List<OfflineContentState>.unmodifiable(supported);
  }

  @override
  Future<OfflineContentState> download(ContentIdentity identity) {
    _requireOpen();
    return _operations.run(
      identity,
      _OfflineOperation.download,
      () => _download(identity),
    );
  }

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) {
    _requireOpen();
    return _operations.run(identity, _OfflineOperation.repair, () async {
      final recovered = await _verifyPublished(identity, quarantine: false);
      if (recovered != null) return recovered;
      return _download(identity);
    });
  }

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) {
    _requireOpen();
    return _operations.run(identity, _OfflineOperation.verify, () async {
      final verified = await _verifyPublished(identity, quarantine: true);
      if (verified != null) return verified;
      final current = await repository.state(identity);
      if (current.status == OfflineContentStatus.quarantined) {
        throw OfflineContentFailure(
          current.failureCode ?? OfflineContentFailureCode.invalidState,
        );
      }
      if (current.status == OfflineContentStatus.verified) {
        final manifest = await repository.requireManifest(identity);
        await _quarantine(manifest, OfflineContentFailureCode.missingArtifact);
      }
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    });
  }

  @override
  Future<bool> canRemove(ContentIdentity identity) async {
    _requireOpen();
    return !(await removalAuthority.isRequired(identity));
  }

  @override
  Future<int> removeBytes(ContentIdentity identity) {
    _requireOpen();
    return _operations.run(identity, _OfflineOperation.remove, () async {
      final manifest = await repository.requireManifest(identity);
      final adapter = _adapterFor(manifest);
      if (adapter is OfflineContentRemovalLeaseAdapter) {
        final leaseAdapter = adapter as OfflineContentRemovalLeaseAdapter;
        return leaseAdapter.withRemovalLease(
          manifest,
          (removeInstalled) =>
              _removeWithPinLease(identity, manifest, removeInstalled),
        );
      }
      return _removeWithPinLease(
        identity,
        manifest,
        () => adapter.removeInstalled(manifest),
      );
    });
  }

  Future<int> _removeWithPinLease(
    ContentIdentity identity,
    ContentManifest manifest,
    OfflineInstalledContentRemoval removeInstalled,
  ) => removalAuthority.withRemovalLease(identity, () async {
    final paths = await _paths(manifest);
    final current = await repository.state(identity);
    if (current.status == OfflineContentStatus.verified &&
        current.localPath != paths.key.publishedName) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    await _requireSafeLeaf(paths, paths.temporary);
    await _requireSafeLeaf(paths, paths.published);
    final adapterBytes = await removeInstalled();
    if (adapterBytes < 0) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final temporaryBytes = await _deleteIfPresent(paths, paths.temporary);
    final publishedBytes = await _deleteIfPresent(paths, paths.published);
    await repository.markNotDownloaded(manifest, updatedAtUtc: _currentUtc());
    return adapterBytes + temporaryBytes + publishedBytes;
  });

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async {
    _requireOpen();
    if (bytesToFree < 0) {
      throw ArgumentError.value(bytesToFree, 'bytesToFree');
    }
    if (bytesToFree == 0) return 0;
    final candidates =
        (await catalog())
            .where((state) => state.status == OfflineContentStatus.verified)
            .toList(growable: false)
          ..sort((left, right) {
            final byTime = left.updatedAtUtc.compareTo(right.updatedAtUtc);
            if (byTime != 0) return byTime;
            return left.manifestId.compareTo(right.manifestId);
          });
    var freed = 0;
    for (final candidate in candidates) {
      try {
        final removed = await removeBytes(candidate.identity);
        freed += removed;
      } on OfflineContentFailure catch (error) {
        if (error.code == OfflineContentFailureCode.contentInUse) continue;
        rethrow;
      }
      if (freed >= bytesToFree) break;
    }
    return freed;
  }

  @override
  Future<void> reconcile() async {
    _requireOpen();
    final states = await catalog();
    for (final state in states) {
      await _operations.run<void>(
        state.identity,
        _OfflineOperation.reconcile,
        () => _reconcileOne(state),
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _operations.dispose();
  }

  Future<void> _reconcileOne(OfflineContentState initial) async {
    final manifest = await repository.requireManifest(initial.identity);
    final paths = await _paths(manifest);
    final adapter = _adapterFor(manifest);
    final publishedFailure = await _verificationFailure(
      paths,
      paths.published,
      manifest,
    );
    if (publishedFailure == null) {
      try {
        await adapter.requireInstalledValid(manifest);
        await _deleteIfPresent(paths, paths.temporary);
        await _persistPublished(manifest, paths);
        return;
      } on Object {
        await _deleteIfPresent(paths, paths.published);
        await _deleteIfPresent(paths, paths.temporary);
        await _quarantine(manifest, OfflineContentFailureCode.invalidState);
        return;
      }
    }
    final publishedType = await FileSystemEntity.type(
      paths.published.path,
      followLinks: false,
    );
    if (publishedType != FileSystemEntityType.notFound) {
      await _deleteIfPresent(paths, paths.published);
      await _deleteIfPresent(paths, paths.temporary);
      await _quarantine(manifest, publishedFailure);
      return;
    }
    final partialFailure = await _verificationFailure(
      paths,
      paths.temporary,
      manifest,
    );
    if (partialFailure == null) {
      try {
        await adapter.requireInstalledValid(manifest);
        await _requireSafeLeaf(paths, paths.published);
        await paths.temporary.rename(paths.published.path);
        await _persistPublished(manifest, paths);
        return;
      } on Object {
        await _deleteIfPresent(paths, paths.temporary);
        await _quarantine(manifest, OfflineContentFailureCode.invalidState);
        return;
      }
    }
    final partialType = await FileSystemEntity.type(
      paths.temporary.path,
      followLinks: false,
    );
    final hadPartial = partialType != FileSystemEntityType.notFound;
    await _deleteIfPresent(paths, paths.temporary);
    if (initial.status == OfflineContentStatus.downloading || hadPartial) {
      await repository.markFailure(
        manifest,
        status: OfflineContentStatus.interrupted,
        failureCode: OfflineContentFailureCode.interrupted,
        downloadedBytes: 0,
        updatedAtUtc: _currentUtc(),
      );
    } else if (initial.status == OfflineContentStatus.verified) {
      await _quarantine(manifest, OfflineContentFailureCode.missingArtifact);
    }
  }

  Future<OfflineContentState> _download(ContentIdentity identity) async {
    final manifest = await repository.requireManifest(identity);
    final paths = await _paths(manifest);
    final adapter = _adapterFor(manifest);
    if (await _verificationFailure(paths, paths.published, manifest) == null) {
      await adapter.requireInstalledValid(manifest);
      return _persistPublished(manifest, paths);
    }
    await _deleteIfPresent(paths, paths.published);
    await _deleteIfPresent(paths, paths.temporary);
    try {
      await repository.markDownloading(
        manifest,
        downloadedBytes: 0,
        updatedAtUtc: _currentUtc(),
      );
      await _requireSafeLeaf(paths, paths.temporary);
      await adapter.stage(manifest, paths.temporary);
      await adapter.requireInstalledValid(manifest);
      await _requireVerifiedFile(paths, paths.temporary, manifest);
      await _requireSafeLeaf(paths, paths.published);
      await paths.temporary.rename(paths.published.path);
      return await _persistPublished(manifest, paths);
    } on ContentQualityFailure catch (error) {
      await _deleteIfPresent(paths, paths.temporary);
      final code = switch (error.code) {
        ContentQualityFailureCode.checksumMismatch ||
        ContentQualityFailureCode.invalidChecksum =>
          OfflineContentFailureCode.checksumMismatch,
        ContentQualityFailureCode.invalidByteLength =>
          OfflineContentFailureCode.sizeMismatch,
        _ => OfflineContentFailureCode.invalidState,
      };
      await _quarantine(manifest, code);
      throw OfflineContentFailure(code, error);
    } on OfflineContentFailure catch (error) {
      await _deleteIfPresent(paths, paths.temporary);
      await _quarantine(manifest, error.code);
      rethrow;
    } on Object catch (error, stackTrace) {
      final downloadedBytes = await _safeLength(paths, paths.temporary);
      await repository.markFailure(
        manifest,
        status: OfflineContentStatus.interrupted,
        failureCode: OfflineContentFailureCode.interrupted,
        downloadedBytes: downloadedBytes,
        updatedAtUtc: _currentUtc(),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<OfflineContentState?> _verifyPublished(
    ContentIdentity identity, {
    required bool quarantine,
    bool persist = true,
  }) async {
    final manifest = await repository.requireManifest(identity);
    final paths = await _paths(manifest);
    final failure = await _verificationFailure(
      paths,
      paths.published,
      manifest,
    );
    if (failure == null) {
      try {
        await _adapterFor(manifest).requireInstalledValid(manifest);
        return persist
            ? await _persistPublished(manifest, paths)
            : repository.state(identity);
      } on OfflineContentFailure catch (error) {
        await _deleteIfPresent(paths, paths.published);
        if (quarantine) await _quarantine(manifest, error.code);
        return null;
      } on Object {
        await _deleteIfPresent(paths, paths.published);
        if (quarantine) {
          await _quarantine(manifest, OfflineContentFailureCode.invalidState);
        }
        return null;
      }
    }
    final publishedType = await FileSystemEntity.type(
      paths.published.path,
      followLinks: false,
    );
    if (publishedType != FileSystemEntityType.notFound) {
      await _deleteIfPresent(paths, paths.published);
    }
    if (quarantine) await _quarantine(manifest, failure);
    return null;
  }

  Future<void> _requireVerifiedFile(
    _ArtifactPaths paths,
    File file,
    ContentManifest manifest,
  ) async {
    await _requireSafeLeaf(paths, file);
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    }
    if (await file.length() != manifest.byteLength) {
      throw const OfflineContentFailure(OfflineContentFailureCode.sizeMismatch);
    }
    final digest = await file.openRead().transform(sha256).single;
    if (digest.toString() != manifest.checksumSha256) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.checksumMismatch,
      );
    }
  }

  Future<OfflineContentFailureCode?> _verificationFailure(
    _ArtifactPaths paths,
    File file,
    ContentManifest manifest,
  ) async {
    try {
      await _requireVerifiedFile(paths, file, manifest);
      return null;
    } on OfflineContentFailure catch (error) {
      return error.code;
    }
  }

  Future<OfflineContentState> _persistPublished(
    ContentManifest manifest,
    _ArtifactPaths paths,
  ) async {
    final adapterBytes = await _adapterFor(manifest).installedBytes(manifest);
    if (adapterBytes < 0) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    await repository.persistVerified(
      VerifiedDownloadedArtifact(
        manifest: manifest,
        localPath: paths.key.publishedName,
        byteLength: manifest.byteLength,
        totalInstalledBytes: manifest.byteLength + adapterBytes,
        checksumSha256: manifest.checksumSha256,
        verifiedAtUtc: _currentUtc(),
      ),
    );
    return repository.state(manifest.identity);
  }

  Future<void> _quarantine(
    ContentManifest manifest,
    OfflineContentFailureCode code,
  ) => repository.markFailure(
    manifest,
    status: OfflineContentStatus.quarantined,
    failureCode: code,
    downloadedBytes: 0,
    updatedAtUtc: _currentUtc(),
  );

  OfflineContentDownloadAdapter _adapterFor(ContentManifest manifest) {
    final matches = adapters
        .where((candidate) => candidate.supports(manifest))
        .toList(growable: false);
    if (matches.length == 1) return matches.single;
    throw const OfflineContentFailure(
      OfflineContentFailureCode.unsupportedContent,
    );
  }

  Future<_ArtifactPaths> _paths(ContentManifest manifest) async {
    final configuredRoot = await rootDirectory();
    await configuredRoot.create(recursive: true);
    final absoluteRoot = configuredRoot.absolute;
    final resolvedRoot = Directory(await absoluteRoot.resolveSymbolicLinks());
    if (_normalizedPath(absoluteRoot.path) !=
        _normalizedPath(resolvedRoot.path)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final key = OfflineContentArtifactKey.forManifest(manifest);
    return _ArtifactPaths(
      key: key,
      root: resolvedRoot,
      temporary: File(
        '${resolvedRoot.path}${Platform.pathSeparator}${key.partialName}',
      ),
      published: File(
        '${resolvedRoot.path}${Platform.pathSeparator}${key.publishedName}',
      ),
    );
  }

  String _normalizedPath(String value) {
    var result = value.replaceAll('\\', '/');
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return Platform.isWindows ? result.toLowerCase() : result;
  }

  Future<int> _deleteIfPresent(_ArtifactPaths paths, File file) async {
    await _requireSafeLeaf(paths, file);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 0;
    final bytes = await file.length();
    await file.delete();
    return bytes;
  }

  Future<int> _safeLength(_ArtifactPaths paths, File file) async {
    await _requireSafeLeaf(paths, file);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 0;
    return file.length();
  }

  Future<void> _requireSafeLeaf(_ArtifactPaths paths, File file) async {
    final expectedParent = _normalizedPath(paths.root.path);
    if (_normalizedPath(file.parent.path) != expectedParent) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final resolved = await file.absolute.resolveSymbolicLinks();
    if (_normalizedPath(resolved) != _normalizedPath(file.absolute.path)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
  }

  void _requireOpen() {
    if (_disposed) throw StateError('Offline content manager is disposed.');
  }

  DateTime _currentUtc() {
    final value = nowUtc();
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, 'nowUtc', 'must return UTC');
    }
    return value;
  }
}

enum _OfflineOperation { catalog, download, verify, repair, remove, reconcile }

final class _OfflineContentOperationQueue {
  final Map<ContentIdentity, _QueuedOfflineOperation> _tails = {};
  bool _disposed = false;

  Future<T> run<T>(
    ContentIdentity identity,
    _OfflineOperation kind,
    Future<T> Function() operation,
  ) {
    if (_disposed) {
      throw StateError('Offline content operation queue disposed.');
    }
    final previous = _tails[identity];
    if (previous != null && previous.kind == kind) {
      return previous.future as Future<T>;
    }
    late final Future<T> future;
    if (previous == null) {
      future = Future<T>.sync(operation);
    } else {
      future = previous.future.then<T>(
        (_) => operation(),
        onError: (Object _, StackTrace _) => operation(),
      );
    }
    final queued = _QueuedOfflineOperation(kind, future);
    _tails[identity] = queued;
    future.then<void>(
      (_) {
        if (identical(_tails[identity], queued)) _tails.remove(identity);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_tails[identity], queued)) _tails.remove(identity);
      },
    );
    return future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _tails.values.map((entry) => entry.future).toSet();
    for (final future in pending) {
      try {
        await future;
      } on Object {
        // Shutdown drains writes; operation failures remain owned by callers.
      }
    }
  }
}

final class _QueuedOfflineOperation {
  const _QueuedOfflineOperation(this.kind, this.future);

  final _OfflineOperation kind;
  final Future<Object?> future;
}

final class _ArtifactPaths {
  const _ArtifactPaths({
    required this.key,
    required this.root,
    required this.temporary,
    required this.published,
  });

  final OfflineContentArtifactKey key;
  final Directory root;
  final File temporary;
  final File published;
}
