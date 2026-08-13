import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/model_lifecycle.dart';
import '../domain/model_manifest.dart';

abstract interface class ModelDownloadRepository {
  Future<ModelDownloadRecord?> find(String id);

  Future<void> save(ModelDownloadRecord record);

  Future<void> activate(ModelDownloadRecord record);
}

final class ModelByteResponse {
  const ModelByteResponse({
    required this.statusCode,
    required this.bytes,
    this.contentRangeStart,
  });

  final int statusCode;
  final Stream<List<int>> bytes;
  final int? contentRangeStart;
}

abstract interface class ModelByteSource {
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  });
}

abstract interface class ModelFileVerifier {
  Future<void> verify(String path, ModelManifest manifest);
}

typedef ModelVerifiedActivationRecorder =
    Future<void> Function({
      required String modelVersion,
      required String completionId,
    });

final class ModelDownloadManager {
  ModelDownloadManager({
    required this.repository,
    required this.source,
    required this.verifier,
    required this.modelDirectory,
    required this.nowUtc,
    this.lockTimeout = const Duration(seconds: 30),
    this.lockRetryDelay = const Duration(milliseconds: 50),
    this.onDownloadCompleted,
    this.onVerifiedActivation,
    this.onCachedArtifactVerified,
  });

  final ModelDownloadRepository repository;
  final ModelByteSource source;
  final ModelFileVerifier verifier;
  final Future<Directory> Function() modelDirectory;
  final DateTime Function() nowUtc;
  final Duration lockTimeout;
  final Duration lockRetryDelay;
  final Future<void> Function(String modelVersion)? onDownloadCompleted;
  final ModelVerifiedActivationRecorder? onVerifiedActivation;
  final ModelVerifiedActivationRecorder? onCachedArtifactVerified;
  Future<ModelDownloadRecord>? _inFlight;
  ModelCancellation? _activeCancellation;
  bool _disposed = false;

  Future<ModelDownloadRecord> downloadAndActivate(
    ModelManifest manifest, {
    ModelCancellation? cancellation,
  }) {
    if (_disposed) {
      throw StateError('ModelDownloadManager is disposed.');
    }
    final running = _inFlight;
    if (running != null) return running;
    final effectiveCancellation = cancellation ?? ModelCancellation();
    _activeCancellation = effectiveCancellation;
    late final Future<ModelDownloadRecord> operation;
    operation =
        _performWithModelLock(
          manifest,
          cancellation: effectiveCancellation,
        ).whenComplete(() {
          if (identical(_inFlight, operation)) {
            _inFlight = null;
            _activeCancellation = null;
          }
        });
    _inFlight = operation;
    return operation;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeCancellation?.cancel();
    final running = _inFlight;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // Disposal waits for all file/database writes but does not rethrow the
        // operation result into application shutdown.
      }
    }
  }

  Future<ModelDownloadRecord> _performWithModelLock(
    ModelManifest manifest, {
    required ModelCancellation cancellation,
  }) async {
    final directory = await modelDirectory();
    await directory.create(recursive: true);
    final separator = Platform.pathSeparator;
    final lockFile = File(
      '${directory.path}$separator${manifest.fileStem}.lock',
    );
    final lock = await _acquireLock(lockFile, cancellation);
    try {
      return await _performDownloadAndActivateLocked(
        manifest,
        directory,
        cancellation,
      );
    } finally {
      try {
        lock.unlockSync();
      } finally {
        await lock.close();
      }
    }
  }

  Future<RandomAccessFile> _acquireLock(
    File file,
    ModelCancellation cancellation,
  ) async {
    final handle = await file.open(mode: FileMode.append);
    final elapsed = Stopwatch()..start();
    while (true) {
      if (cancellation.isCancelled || _disposed) {
        await handle.close();
        throw const ModelLifecycleException(ModelFailureCode.cancelled);
      }
      try {
        handle.lockSync(FileLock.exclusive);
        return handle;
      } on FileSystemException {
        if (elapsed.elapsed >= lockTimeout) {
          await handle.close();
          throw const ModelLifecycleException(ModelFailureCode.busy);
        }
        await Future.any<void>([
          Future<void>.delayed(lockRetryDelay),
          cancellation.whenCancelled,
        ]);
      }
    }
  }

  Future<ModelDownloadRecord> _performDownloadAndActivateLocked(
    ModelManifest manifest,
    Directory directory,
    ModelCancellation cancellation,
  ) async {
    final separator = Platform.pathSeparator;
    final partial = File(
      '${directory.path}$separator${manifest.fileStem}.tflite.partial',
    );
    final finalFile = File(
      '${directory.path}$separator${manifest.fileStem}.tflite',
    );
    var existing = await repository.find(manifest.recordId);
    if (await finalFile.exists()) {
      if (await _isValidModelFile(finalFile, manifest)) {
        if (_isPreviouslyVerifiedArtifact(existing, manifest, finalFile)) {
          if (existing!.state == ModelDownloadState.ready) {
            await repository.activate(existing);
          }
          await _recordVerifiedActivation(
            manifest,
            existing,
            allowLegacy: false,
            cachedArtifact: true,
          );
          return existing.copyWith(state: ModelDownloadState.active);
        }
        final recoveredBase = existing ?? _newRecord(manifest, finalFile.path);
        final recovered = recoveredBase.copyWith(
          state: ModelDownloadState.ready,
          downloadedBytes: manifest.expectedBytes,
          updatedAtUtc: _nextUpdatedAt(recoveredBase.updatedAtUtc),
          localPath: finalFile.path,
          clearFailure: true,
        );
        await repository.activate(recovered);
        await _recordVerifiedActivation(manifest, recovered, allowLegacy: true);
        return recovered.copyWith(state: ModelDownloadState.active);
      }
      await finalFile.delete();
      if (existing != null) {
        existing = existing.copyWith(
          state: ModelDownloadState.failed,
          downloadedBytes: 0,
          updatedAtUtc: _nextUpdatedAt(existing.updatedAtUtc),
          localPath: partial.path,
          failureCode: ModelFailureCode.checksumMismatch,
        );
        await repository.save(existing);
      }
    }

    var downloaded = await partial.exists() ? await partial.length() : 0;
    if (downloaded > manifest.expectedBytes) {
      await partial.delete();
      downloaded = 0;
    }
    var record =
        existing ??
        _newRecord(manifest, partial.path, downloadedBytes: downloaded);
    record = record.copyWith(
      downloadedBytes: downloaded,
      state: ModelDownloadState.downloading,
      updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
      localPath: partial.path,
      clearFailure: true,
    );
    await repository.save(record);

    try {
      if (cancellation.isCancelled || _disposed) {
        throw const ModelLifecycleException(ModelFailureCode.cancelled);
      }
      final response = await source.open(
        manifest.sourceUri,
        start: downloaded,
        cancellation: cancellation,
      );
      final isResume =
          downloaded > 0 &&
          response.statusCode == 206 &&
          response.contentRangeStart == downloaded;
      final isRestart = response.statusCode == 200;
      if (!isResume && !isRestart) {
        throw const ModelLifecycleException(ModelFailureCode.invalidResponse);
      }
      if (isRestart) {
        downloaded = 0;
      }
      final sink = partial.openWrite(
        mode: isResume ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.bytes) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (downloaded > manifest.expectedBytes) {
            throw const ModelLifecycleException(ModelFailureCode.sizeMismatch);
          }
          record = record.copyWith(
            downloadedBytes: downloaded,
            updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
          );
          await repository.save(record);
          if (cancellation.isCancelled || _disposed) {
            throw const ModelLifecycleException(ModelFailureCode.cancelled);
          }
        }
        await sink.flush();
      } on FileSystemException {
        throw const ModelLifecycleException(ModelFailureCode.writeFailed);
      } finally {
        await sink.close();
      }

      if (downloaded != manifest.expectedBytes) {
        throw const ModelLifecycleException(ModelFailureCode.sizeMismatch);
      }
      record = record.copyWith(
        state: ModelDownloadState.verifying,
        downloadedBytes: downloaded,
        updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
      );
      await repository.save(record);
      final digest = await partial.openRead().transform(sha256).single;
      if (digest.toString() != manifest.expectedSha256) {
        await partial.delete();
        downloaded = 0;
        throw const ModelLifecycleException(ModelFailureCode.checksumMismatch);
      }
      try {
        await verifier.verify(partial.path, manifest);
      } on ModelLifecycleException {
        rethrow;
      } catch (_) {
        throw const ModelLifecycleException(
          ModelFailureCode.interpreterRejected,
        );
      }
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partial.rename(finalFile.path);
      record = record.copyWith(
        state: ModelDownloadState.ready,
        downloadedBytes: downloaded,
        updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
        localPath: finalFile.path,
        clearFailure: true,
      );
      await repository.activate(record);
      await _recordVerifiedActivation(manifest, record, allowLegacy: true);
      return record.copyWith(state: ModelDownloadState.active);
    } on ModelLifecycleException catch (error) {
      final state = error.code == ModelFailureCode.cancelled
          ? ModelDownloadState.cancelled
          : ModelDownloadState.failed;
      record = record.copyWith(
        state: state,
        downloadedBytes: downloaded,
        retryCount: error.code == ModelFailureCode.cancelled
            ? record.retryCount
            : record.retryCount + 1,
        updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
        localPath: partial.path,
        failureCode: error.code,
      );
      await repository.save(record);
      rethrow;
    } on SocketException {
      return _failAndThrow(
        record,
        downloaded,
        partial.path,
        ModelFailureCode.network,
      );
    } on HttpException {
      return _failAndThrow(
        record,
        downloaded,
        partial.path,
        ModelFailureCode.network,
      );
    } on FileSystemException {
      return _failAndThrow(
        record,
        downloaded,
        partial.path,
        ModelFailureCode.writeFailed,
      );
    }
  }

  ModelDownloadRecord _newRecord(
    ModelManifest manifest,
    String localPath, {
    int downloadedBytes = 0,
  }) {
    return ModelDownloadRecord(
      id: manifest.recordId,
      modelVersion: manifest.version,
      sourceUrl: manifest.sourceUri.toString(),
      expectedChecksum: manifest.expectedSha256,
      expectedBytes: manifest.expectedBytes,
      downloadedBytes: downloadedBytes,
      retryCount: 0,
      state: ModelDownloadState.notStarted,
      updatedAtUtc: _currentUtc(),
      localPath: localPath,
    );
  }

  Future<bool> _isValidModelFile(File file, ModelManifest manifest) async {
    if (!await file.exists() || await file.length() != manifest.expectedBytes) {
      return false;
    }
    final digest = await file.openRead().transform(sha256).single;
    if (digest.toString() != manifest.expectedSha256) {
      return false;
    }
    try {
      await verifier.verify(file.path, manifest);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isPreviouslyVerifiedArtifact(
    ModelDownloadRecord? record,
    ModelManifest manifest,
    File finalFile,
  ) {
    if (record == null ||
        (record.state != ModelDownloadState.active &&
            record.state != ModelDownloadState.ready)) {
      return false;
    }
    return record.id == manifest.recordId &&
        record.modelVersion == manifest.version &&
        record.expectedChecksum == manifest.expectedSha256 &&
        record.expectedBytes == manifest.expectedBytes &&
        record.downloadedBytes == manifest.expectedBytes &&
        record.localPath == finalFile.path;
  }

  Future<void> _recordVerifiedActivation(
    ModelManifest manifest,
    ModelDownloadRecord record, {
    required bool allowLegacy,
    bool cachedArtifact = false,
  }) async {
    try {
      final recorder = cachedArtifact
          ? onCachedArtifactVerified ?? onVerifiedActivation
          : onVerifiedActivation;
      if (recorder != null) {
        await recorder(
          modelVersion: manifest.version,
          completionId: _verifiedCompletionId(manifest, record),
        );
      } else if (allowLegacy) {
        await onDownloadCompleted?.call(manifest.version);
      }
    } catch (_) {
      // Diagnostics must not turn an already activated, verified local model
      // into a user-visible failure. A later validated open retries the stable
      // idempotency marker through [onVerifiedActivation].
    }
  }

  String _verifiedCompletionId(
    ModelManifest manifest,
    ModelDownloadRecord record,
  ) {
    final identity = utf8.encode(
      '${manifest.recordId}\n${manifest.version}\n${manifest.expectedSha256}'
      '\n${record.updatedAtUtc.millisecondsSinceEpoch}',
    );
    return 'verified-${sha256.convert(identity)}';
  }

  DateTime _currentUtc() {
    final current = nowUtc();
    if (!current.isUtc) {
      throw ArgumentError.value(current, 'nowUtc', 'must return UTC');
    }
    return current;
  }

  DateTime _nextUpdatedAt(DateTime previous) {
    final current = _currentUtc();
    if (current.isAfter(previous)) return current;
    return previous.add(const Duration(milliseconds: 1));
  }

  Future<ModelDownloadRecord> _failAndThrow(
    ModelDownloadRecord record,
    int downloaded,
    String partialPath,
    ModelFailureCode code,
  ) async {
    await repository.save(
      record.copyWith(
        state: ModelDownloadState.failed,
        downloadedBytes: downloaded,
        retryCount: record.retryCount + 1,
        updatedAtUtc: _nextUpdatedAt(record.updatedAtUtc),
        localPath: partialPath,
        failureCode: code,
      ),
    );
    throw ModelLifecycleException(code);
  }
}
