import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'standard_voice_pack_manifest.dart';
import 'voice_models.dart';

final class StandardVoicePackByteResponse {
  const StandardVoicePackByteResponse({
    required this.statusCode,
    required this.bytes,
    this.contentRangeStart,
  });

  final int statusCode;
  final Stream<List<int>> bytes;
  final int? contentRangeStart;
}

abstract interface class StandardVoicePackByteSource {
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  });
}

final class StandardVoicePackCancellation {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class InstalledStandardVoicePack {
  const InstalledStandardVoicePack({
    required this.rootPath,
    required this.manifest,
    required this.activeMarkerPath,
  });

  final String rootPath;
  final StandardVoicePackManifest manifest;
  final String activeMarkerPath;

  String get manifestPath => '$rootPath${Platform.pathSeparator}manifest.json';

  String pathFor(String relativePath) {
    return '$rootPath${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}';
  }
}

const _storageFailure = VoiceFailure(
  category: VoiceFailureCategory.insufficientStorage,
  message: 'There is not enough storage for the voice pack.',
);
const _checksumFailure = VoiceFailure(
  category: VoiceFailureCategory.checksumMismatch,
  message: 'The voice pack failed integrity verification.',
);
const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'Voice pack installation was cancelled.',
);
const _networkFailure = VoiceFailure(
  category: VoiceFailureCategory.network,
  message: 'The voice pack could not be downloaded.',
);
const _timeoutFailure = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'The voice pack download timed out.',
);

final class StandardVoicePackDownloadManager {
  StandardVoicePackDownloadManager({
    required this.rootDirectory,
    required this.source,
    required this.availableBytes,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 250),
    this.storageReserveBytes = 8 * 1024 * 1024,
    this.bodyInactivityTimeout = const Duration(seconds: 30),
    this.bodyTotalTimeout = const Duration(minutes: 2),
    this.cancellationDrainTimeout = const Duration(seconds: 2),
    this.disposeTimeout = const Duration(seconds: 5),
  }) : assert(maxAttempts > 0 && maxAttempts <= 3),
       assert(storageReserveBytes >= 0),
       assert(bodyInactivityTimeout > Duration.zero),
       assert(bodyTotalTimeout > Duration.zero),
       assert(cancellationDrainTimeout > Duration.zero),
       assert(disposeTimeout > Duration.zero);

  final Future<Directory> Function() rootDirectory;
  final StandardVoicePackByteSource source;
  final Future<int> Function(Directory directory) availableBytes;
  final int maxAttempts;
  final Duration retryDelay;
  final int storageReserveBytes;
  final Duration bodyInactivityTimeout;
  final Duration bodyTotalTimeout;
  final Duration cancellationDrainTimeout;
  final Duration disposeTimeout;
  final Map<String, Future<InstalledStandardVoicePack>> _installOperations =
      <String, Future<InstalledStandardVoicePack>>{};
  final Map<String, Future<void>> _packTails = <String, Future<void>>{};
  final Set<StandardVoicePackCancellation> _activeCancellations =
      <StandardVoicePackCancellation>{};
  final Set<Future<Object?>> _activeOperations = <Future<Object?>>{};
  bool _disposed = false;

  int requiredInstallationBytes(
    StandardVoicePackManifest manifest, {
    int receiptBytes = 0,
  }) {
    if (receiptBytes < 0) {
      throw ArgumentError.value(receiptBytes, 'receiptBytes');
    }
    final installedManifestBytes = utf8
        .encode('${jsonEncode(manifest.toJson())}\n')
        .length;
    final markerBytes = utf8.encode(manifest.version).length;
    return manifest.totalBytes +
        installedManifestBytes +
        markerBytes +
        receiptBytes +
        storageReserveBytes;
  }

  Future<InstalledStandardVoicePack> install(
    StandardVoicePackManifest manifest, {
    StandardVoicePackCancellation? cancellation,
    int receiptBytes = 0,
  }) {
    _requireOpen();
    final fingerprint = _manifestFingerprint(manifest);
    final running = _installOperations[fingerprint];
    if (running != null) return running;
    final token = cancellation ?? StandardVoicePackCancellation();
    final operation = _enqueuePackOperation<InstalledStandardVoicePack>(
      packId: manifest.packId,
      cancellation: token,
      operation: () => _install(manifest, token, receiptBytes),
    );
    _installOperations[fingerprint] = operation;
    operation.then<void>(
      (_) {
        if (identical(_installOperations[fingerprint], operation)) {
          _installOperations.remove(fingerprint);
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_installOperations[fingerprint], operation)) {
          _installOperations.remove(fingerprint);
        }
      },
    );
    return operation;
  }

  Future<T> _enqueuePackOperation<T>({
    required String packId,
    required StandardVoicePackCancellation cancellation,
    required Future<T> Function() operation,
  }) {
    _activeCancellations.add(cancellation);
    final previous = _packTails[packId] ?? Future<void>.value();
    Future<T> begin() async {
      _throwIfCancelled(cancellation);
      return operation();
    }

    late final Future<T> future;
    future = previous
        .then<T>((_) => begin(), onError: (Object _, StackTrace _) => begin())
        .whenComplete(() {
          _activeCancellations.remove(cancellation);
        });
    _activeOperations.add(future);
    future.then<void>(
      (_) => _activeOperations.remove(future),
      onError: (Object _, StackTrace _) => _activeOperations.remove(future),
    );
    final tail = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _packTails[packId] = tail;
    tail.then<void>((_) {
      if (identical(_packTails[packId], tail)) _packTails.remove(packId);
    });
    return future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final cancellation in _activeCancellations.toList(growable: false)) {
      cancellation.cancel();
    }
    final pending = _activeOperations.toList(growable: false);
    try {
      await Future.wait<void>([
        for (final operation in pending)
          operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]).timeout(disposeTimeout);
    } on TimeoutException {
      // Shutdown remains bounded after every active stream has been asked to
      // cancel. The stream cancellation path has its own bounded drain.
    }
  }

  /// Network-free inspection used by the unified offline-content adapter.
  /// It verifies every authoritative audio file and the active version marker.
  Future<InstalledStandardVoicePack?> findVerifiedInstalled(
    StandardVoicePackManifest manifest,
  ) async {
    _requireOpen();
    final root = await _safeRoot();
    final separator = Platform.pathSeparator;
    final directory = Directory('${root.path}$separator${manifest.recordId}');
    final marker = File('${root.path}$separator${manifest.packId}.active');
    if (!await _isSafeDirectory(directory, root) ||
        !await _isSafeRegularFile(marker, root) ||
        (await marker.readAsString()).trim() != manifest.version ||
        !await _verifyDirectory(directory, manifest)) {
      return null;
    }
    return InstalledStandardVoicePack(
      rootPath: directory.path,
      manifest: manifest,
      activeMarkerPath: marker.path,
    );
  }

  /// Exact bytes occupied by the verified authoritative install, including
  /// its installed manifest and active marker.
  Future<int> installedBytes(StandardVoicePackManifest manifest) async {
    final installed = await findVerifiedInstalled(manifest);
    if (installed == null) throw _checksumFailure;
    return _installedTreeBytes(
      Directory(installed.rootPath),
      File(installed.activeMarkerPath),
    );
  }

  /// Removes only the canonical verified install and returns exact bytes
  /// deleted. Linked/reparse descendants fail closed before any deletion.
  Future<int> removeInstalled(StandardVoicePackManifest manifest) async {
    _requireOpen();
    return _enqueuePackOperation<int>(
      packId: manifest.packId,
      cancellation: StandardVoicePackCancellation(),
      operation: () async {
        final installed = await findVerifiedInstalled(manifest);
        if (installed == null) throw _checksumFailure;
        final directory = Directory(installed.rootPath);
        final marker = File(installed.activeMarkerPath);
        final bytes = await _installedTreeBytes(directory, marker);
        await directory.delete(recursive: true);
        await marker.delete();
        return bytes;
      },
    );
  }

  Future<InstalledStandardVoicePack> _install(
    StandardVoicePackManifest manifest,
    StandardVoicePackCancellation cancellation,
    int receiptBytes,
  ) async {
    _throwIfCancelled(cancellation);
    final root = await _safeRoot();

    final separator = Platform.pathSeparator;
    final finalDirectory = Directory(
      '${root.path}$separator${manifest.recordId}',
    );
    final staging = Directory(
      '${root.path}$separator${manifest.recordId}.partial',
    );
    final marker = File('${root.path}$separator${manifest.packId}.active');
    await _requireDirectoryTarget(finalDirectory, root);
    await _requireDirectoryTarget(staging, root);
    await _requireFileTarget(marker, root);
    if (await finalDirectory.exists() &&
        await _verifyDirectory(finalDirectory, manifest)) {
      await _activate(marker, manifest.version);
      return InstalledStandardVoicePack(
        rootPath: finalDirectory.path,
        manifest: manifest,
        activeMarkerPath: marker.path,
      );
    }
    if (await finalDirectory.exists()) {
      final installedManifest = await _readInstalledManifest(finalDirectory);
      if (installedManifest != null &&
          installedManifest.recordId == manifest.recordId &&
          _manifestFingerprint(installedManifest) !=
              _manifestFingerprint(manifest)) {
        throw _checksumFailure;
      }
      await finalDirectory.delete(recursive: true);
    }
    int freeBytes;
    try {
      freeBytes = await availableBytes(root);
    } on Object {
      throw _storageFailure;
    }
    if (freeBytes <
        requiredInstallationBytes(manifest, receiptBytes: receiptBytes)) {
      throw _storageFailure;
    }
    await staging.create(recursive: true);

    try {
      for (final file in manifest.files) {
        _throwIfCancelled(cancellation);
        await _downloadFile(staging, file, cancellation);
      }
      final manifestFile = File('${staging.path}${separator}manifest.json');
      await _requireFileTarget(manifestFile, staging);
      await manifestFile.writeAsString(
        '${jsonEncode(manifest.toJson())}\n',
        flush: true,
      );
      _throwIfCancelled(cancellation);
      await staging.rename(finalDirectory.path);
      await _activate(marker, manifest.version);
      return InstalledStandardVoicePack(
        rootPath: finalDirectory.path,
        manifest: manifest,
        activeMarkerPath: marker.path,
      );
    } on VoiceFailure catch (failure) {
      if (failure.category == VoiceFailureCategory.checksumMismatch &&
          await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> _downloadFile(
    Directory staging,
    StandardVoicePackFile descriptor,
    StandardVoicePackCancellation cancellation,
  ) async {
    final path = descriptor.relativePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final finalFile = File('${staging.path}${Platform.pathSeparator}$path');
    final partial = File('${finalFile.path}.partial');
    await partial.parent.create(recursive: true);
    await _requireDescendantDirectory(partial.parent, staging);
    await _requireFileTarget(finalFile, staging);
    await _requireFileTarget(partial, staging);
    var downloaded = await partial.exists() ? await partial.length() : 0;
    if (downloaded > descriptor.byteSize) {
      await partial.delete();
      downloaded = 0;
    }

    StandardVoicePackByteResponse? response;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _throwIfCancelled(cancellation);
      try {
        response = await source.open(
          descriptor.uri,
          start: downloaded,
          cancellation: cancellation,
        );
        break;
      } on VoiceFailure catch (error) {
        if (error.category != VoiceFailureCategory.network &&
            error.category != VoiceFailureCategory.timeout) {
          rethrow;
        }
        lastError = error;
      } on IOException catch (error) {
        lastError = error;
      }
      if (attempt < maxAttempts) {
        await Future.any([
          Future<void>.delayed(retryDelay * attempt),
          cancellation.whenCancelled,
        ]);
      }
    }
    if (response == null) {
      if (lastError is VoiceFailure) throw lastError;
      throw _networkFailure;
    }

    final isResume =
        downloaded > 0 &&
        response.statusCode == 206 &&
        response.contentRangeStart == downloaded;
    final isRestart = response.statusCode == 200;
    if (!isResume && !isRestart) throw _networkFailure;
    if (isRestart) downloaded = 0;
    final sink = partial.openWrite(
      mode: isResume ? FileMode.append : FileMode.write,
    );
    final iterator = StreamIterator<List<int>>(response.bytes);
    final bodyElapsed = Stopwatch()..start();
    try {
      while (await _moveNext(iterator, cancellation, bodyElapsed)) {
        final chunk = iterator.current;
        _throwIfCancelled(cancellation);
        downloaded += chunk.length;
        if (downloaded > descriptor.byteSize) throw _checksumFailure;
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      try {
        await iterator.cancel().timeout(cancellationDrainTimeout);
      } on TimeoutException {
        // The caller-facing operation remains bounded even if a provider does
        // not finish its cancellation callback.
      } on Object {
        // Provider cancellation failures cannot replace the already-selected
        // integrity, timeout, or cancellation outcome.
      }
      await sink.close();
    }
    if (downloaded != descriptor.byteSize) throw _checksumFailure;
    final digest = await partial.openRead().transform(sha256).single;
    if (digest.toString() != descriptor.sha256) throw _checksumFailure;
    if (!descriptor.relativePath.toLowerCase().endsWith('.wav') ||
        !await _isValidPcmWav(partial)) {
      throw _checksumFailure;
    }
    if (await finalFile.exists()) await finalFile.delete();
    await partial.rename(finalFile.path);
  }

  Future<bool> _verifyDirectory(
    Directory directory,
    StandardVoicePackManifest manifest,
  ) async {
    final manifestFile = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    if (!await _isSafeRegularFile(manifestFile, directory)) return false;
    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final installed = StandardVoicePackManifest.fromJson(decoded);
      if (jsonEncode(installed.toJson()) != jsonEncode(manifest.toJson())) {
        return false;
      }
    } on Object {
      return false;
    }
    for (final descriptor in manifest.files) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${descriptor.relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!await _isSafeRegularFile(file, directory) ||
          await file.length() != descriptor.byteSize) {
        return false;
      }
      final digest = await file.openRead().transform(sha256).single;
      if (digest.toString() != descriptor.sha256 ||
          !descriptor.relativePath.toLowerCase().endsWith('.wav') ||
          !await _isValidPcmWav(file)) {
        return false;
      }
    }
    return true;
  }

  Future<StandardVoicePackManifest?> _readInstalledManifest(
    Directory directory,
  ) async {
    final manifestFile = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    if (!await _isSafeRegularFile(manifestFile, directory)) return null;
    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return StandardVoicePackManifest.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<Directory> _safeRoot() async {
    final configured = await rootDirectory();
    await configured.create(recursive: true);
    final absolute = configured.absolute;
    final resolved = await absolute.resolveSymbolicLinks();
    if (_normalizedPath(absolute.path) != _normalizedPath(resolved)) {
      throw _checksumFailure;
    }
    return Directory(resolved);
  }

  Future<bool> _isSafeDirectory(Directory value, Directory parent) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type != FileSystemEntityType.directory) return false;
    try {
      final resolved = await value.absolute.resolveSymbolicLinks();
      return _isDirectChild(resolved, parent.path) &&
          _normalizedPath(resolved) == _normalizedPath(value.absolute.path);
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _isSafeRegularFile(File value, Directory parent) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type != FileSystemEntityType.file) return false;
    try {
      final resolved = await value.absolute.resolveSymbolicLinks();
      return _isDescendant(resolved, parent.path) &&
          _normalizedPath(resolved) == _normalizedPath(value.absolute.path);
    } on FileSystemException {
      return false;
    }
  }

  Future<int> _installedTreeBytes(Directory directory, File marker) async {
    final root = await _safeRoot();
    if (!await _isSafeDirectory(directory, root) ||
        !await _isSafeRegularFile(marker, root)) {
      throw _checksumFailure;
    }
    var total = await marker.length();
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file ||
          !await _isSafeRegularFile(File(entity.path), directory)) {
        throw _checksumFailure;
      }
      total += await File(entity.path).length();
    }
    return total;
  }

  Future<void> _requireDirectoryTarget(
    Directory value,
    Directory parent,
  ) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        !await _isSafeDirectory(value, parent)) {
      throw _checksumFailure;
    }
  }

  Future<void> _requireDescendantDirectory(
    Directory value,
    Directory parent,
  ) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type != FileSystemEntityType.directory) throw _checksumFailure;
    final resolved = await value.absolute.resolveSymbolicLinks();
    if ((_normalizedPath(resolved) != _normalizedPath(parent.path) &&
            !_isDescendant(resolved, parent.path)) ||
        _normalizedPath(resolved) != _normalizedPath(value.absolute.path)) {
      throw _checksumFailure;
    }
  }

  Future<void> _requireFileTarget(File value, Directory parent) async {
    final type = await FileSystemEntity.type(value.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.file ||
        !await _isSafeRegularFile(value, parent)) {
      throw _checksumFailure;
    }
  }

  bool _isDirectChild(String value, String parent) =>
      _normalizedPath(File(value).parent.path) == _normalizedPath(parent);

  bool _isDescendant(String value, String parent) {
    final normalizedParent = _normalizedPath(parent);
    final normalizedValue = _normalizedPath(value);
    return normalizedValue.startsWith(
      '$normalizedParent${Platform.pathSeparator}'.replaceAll('\\', '/'),
    );
  }

  String _normalizedPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<void> _activate(File marker, String version) async {
    final partial = File('${marker.path}.partial');
    final root = marker.parent;
    await _requireFileTarget(marker, root);
    await _requireFileTarget(partial, root);
    await partial.writeAsString(version, flush: true);
    if (await marker.exists()) await marker.delete();
    await partial.rename(marker.path);
  }

  void _throwIfCancelled(StandardVoicePackCancellation cancellation) {
    if (cancellation.isCancelled) throw _cancelledFailure;
  }

  Future<bool> _moveNext(
    StreamIterator<List<int>> iterator,
    StandardVoicePackCancellation cancellation,
    Stopwatch bodyElapsed,
  ) async {
    final remaining = bodyTotalTimeout - bodyElapsed.elapsed;
    if (remaining <= Duration.zero) throw _timeoutFailure;
    final waitTimeout = remaining < bodyInactivityTimeout
        ? remaining
        : bodyInactivityTimeout;
    try {
      return await Future.any<bool>(<Future<bool>>[
        iterator.moveNext().timeout(waitTimeout),
        cancellation.whenCancelled.then<bool>((_) => false),
      ]).then((hasNext) {
        if (cancellation.isCancelled) throw _cancelledFailure;
        return hasNext;
      });
    } on TimeoutException {
      throw _timeoutFailure;
    }
  }

  Future<bool> _isValidPcmWav(File file) async {
    final length = await file.length();
    if (length < 44) return false;
    final handle = await file.open();
    try {
      final riff = await handle.read(12);
      if (riff.length != 12 ||
          !_asciiEquals(riff, 0, 'RIFF') ||
          !_asciiEquals(riff, 8, 'WAVE')) {
        return false;
      }
      final riffData = ByteData.sublistView(Uint8List.fromList(riff));
      if (riffData.getUint32(4, Endian.little) + 8 != length) return false;

      var offset = 12;
      int? blockAlign;
      var hasFormat = false;
      var hasAudio = false;
      while (offset + 8 <= length) {
        await handle.setPosition(offset);
        final header = await handle.read(8);
        if (header.length != 8) return false;
        final headerData = ByteData.sublistView(Uint8List.fromList(header));
        final chunkBytes = headerData.getUint32(4, Endian.little);
        final dataStart = offset + 8;
        final dataEnd = dataStart + chunkBytes;
        if (dataEnd > length) return false;
        if (_asciiEquals(header, 0, 'fmt ')) {
          if (chunkBytes < 16) return false;
          await handle.setPosition(dataStart);
          final format = await handle.read(16);
          if (format.length != 16) return false;
          final data = ByteData.sublistView(Uint8List.fromList(format));
          final encoding = data.getUint16(0, Endian.little);
          final channels = data.getUint16(2, Endian.little);
          final sampleRate = data.getUint32(4, Endian.little);
          final byteRate = data.getUint32(8, Endian.little);
          final align = data.getUint16(12, Endian.little);
          final bitsPerSample = data.getUint16(14, Endian.little);
          final expectedAlign = channels * bitsPerSample ~/ 8;
          if (encoding != 1 ||
              (channels != 1 && channels != 2) ||
              sampleRate < 8000 ||
              sampleRate > 192000 ||
              !const <int>{8, 16, 24, 32}.contains(bitsPerSample) ||
              align == 0 ||
              align != expectedAlign ||
              byteRate != sampleRate * align) {
            return false;
          }
          blockAlign = align;
          hasFormat = true;
        } else if (_asciiEquals(header, 0, 'data')) {
          if (chunkBytes == 0) return false;
          hasAudio = true;
          final align = blockAlign;
          if (align != null && chunkBytes % align != 0) return false;
        }
        offset = dataEnd + (chunkBytes.isOdd ? 1 : 0);
      }
      return hasFormat && hasAudio && offset == length;
    } on FileSystemException {
      return false;
    } finally {
      await handle.close();
    }
  }

  bool _asciiEquals(List<int> bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index += 1) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  String _manifestFingerprint(StandardVoicePackManifest manifest) =>
      sha256.convert(utf8.encode(jsonEncode(manifest.toJson()))).toString();

  void _requireOpen() {
    if (_disposed) {
      throw StateError('StandardVoicePackDownloadManager is disposed.');
    }
  }
}
