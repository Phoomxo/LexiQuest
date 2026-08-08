import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

final class StandardVoicePackDownloadManager {
  StandardVoicePackDownloadManager({
    required this.rootDirectory,
    required this.source,
    required this.availableBytes,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 250),
  }) : assert(maxAttempts > 0 && maxAttempts <= 3);

  final Future<Directory> Function() rootDirectory;
  final StandardVoicePackByteSource source;
  final Future<int> Function(Directory directory) availableBytes;
  final int maxAttempts;
  final Duration retryDelay;
  Future<InstalledStandardVoicePack>? _inFlight;

  Future<InstalledStandardVoicePack> install(
    StandardVoicePackManifest manifest, {
    StandardVoicePackCancellation? cancellation,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    final token = cancellation ?? StandardVoicePackCancellation();
    late final Future<InstalledStandardVoicePack> operation;
    operation = _install(manifest, token).whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<InstalledStandardVoicePack> _install(
    StandardVoicePackManifest manifest,
    StandardVoicePackCancellation cancellation,
  ) async {
    _throwIfCancelled(cancellation);
    final root = await rootDirectory();
    await root.create(recursive: true);
    if (await availableBytes(root) < manifest.totalBytes) {
      throw _storageFailure;
    }

    final separator = Platform.pathSeparator;
    final finalDirectory = Directory(
      '${root.path}$separator${manifest.recordId}',
    );
    final staging = Directory(
      '${root.path}$separator${manifest.recordId}.partial',
    );
    final marker = File('${root.path}$separator${manifest.packId}.active');
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
      await finalDirectory.delete(recursive: true);
    }
    await staging.create(recursive: true);

    try {
      for (final file in manifest.files) {
        _throwIfCancelled(cancellation);
        await _downloadFile(staging, file, cancellation);
      }
      final manifestFile = File('${staging.path}${separator}manifest.json');
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
    try {
      await for (final chunk in response.bytes) {
        _throwIfCancelled(cancellation);
        downloaded += chunk.length;
        if (downloaded > descriptor.byteSize) throw _checksumFailure;
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (downloaded != descriptor.byteSize) throw _checksumFailure;
    final digest = await partial.openRead().transform(sha256).single;
    if (digest.toString() != descriptor.sha256) throw _checksumFailure;
    if (await finalFile.exists()) await finalFile.delete();
    await partial.rename(finalFile.path);
  }

  Future<bool> _verifyDirectory(
    Directory directory,
    StandardVoicePackManifest manifest,
  ) async {
    for (final descriptor in manifest.files) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${descriptor.relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!await file.exists() || await file.length() != descriptor.byteSize) {
        return false;
      }
      final digest = await file.openRead().transform(sha256).single;
      if (digest.toString() != descriptor.sha256) return false;
    }
    return true;
  }

  Future<void> _activate(File marker, String version) async {
    final partial = File('${marker.path}.partial');
    await partial.writeAsString(version, flush: true);
    if (await marker.exists()) await marker.delete();
    await partial.rename(marker.path);
  }

  void _throwIfCancelled(StandardVoicePackCancellation cancellation) {
    if (cancellation.isCancelled) throw _cancelledFailure;
  }
}
