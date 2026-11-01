import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../domain/learning_pack.dart';
import '../domain/learning_pack_download.dart';
import '../domain/learning_pack_repository.dart';

final class HttpLearningPackSource {
  HttpLearningPackSource({
    required this.client,
    required List<LearningPackDownloadDescriptor> catalog,
    this.timeout = const Duration(seconds: 30),
  }) : catalog = List.unmodifiable(catalog) {
    if (timeout <= Duration.zero ||
        timeout > const Duration(minutes: 2) ||
        catalog.map((entry) => entry.catalogId).toSet().length !=
            catalog.length) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
  }

  final http.Client client;
  final List<LearningPackDownloadDescriptor> catalog;
  final Duration timeout;
  final _aborters = <Completer<void>>{};
  bool _disposed = false;

  Future<LearningPack> download(
    LearningPackDownloadDescriptor descriptor, {
    required bool Function() stillCurrent,
    void Function(int received, int expected)? onProgress,
  }) async {
    var finished = false;
    bool current() {
      try {
        return !_disposed && !finished && stillCurrent();
      } on Object {
        return false;
      }
    }

    void requireCurrent() {
      if (!current()) {
        throw const PackStorageException(PackStorageFailureCode.ownerChanged);
      }
    }

    requireCurrent();
    // Descriptors come from app-owned catalog configuration, never a URL form.
    if (!catalog.any((entry) => identical(entry, descriptor))) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
    final abort = Completer<void>();
    _aborters.add(abort);
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    final ownerWatch = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!current()) cancel();
    });

    Future<LearningPack> read() async {
      final request = http.AbortableRequest(
        'GET',
        descriptor.uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['accept'] = 'application/json, application/octet-stream';
      requireCurrent();
      final response = await client.send(request);
      requireCurrent();
      if (response.statusCode != 200) {
        throw const PackStorageException(PackStorageFailureCode.unavailable);
      }
      if (response.contentLength != null &&
          response.contentLength != descriptor.packageByteCount) {
        throw const LearningPackException(
          LearningPackFailureCode.integrityMismatch,
        );
      }
      final bytes = BytesBuilder();
      var received = 0;
      onProgress?.call(0, descriptor.packageByteCount);
      await for (final chunk in response.stream) {
        requireCurrent();
        received += chunk.length;
        if (received > descriptor.packageByteCount ||
            received > maxLearningPackBytes) {
          throw const LearningPackException(LearningPackFailureCode.tooLarge);
        }
        bytes.add(chunk);
        onProgress?.call(received, descriptor.packageByteCount);
      }
      requireCurrent();
      if (received != descriptor.packageByteCount) {
        throw const LearningPackException(
          LearningPackFailureCode.integrityMismatch,
        );
      }
      final pack = await compute(_decodePack, (
        bytes.takeBytes(),
        descriptor.packageSha256,
      ));
      requireCurrent();
      if (pack.manifest.canonicalJson != descriptor.manifest.canonicalJson) {
        throw const LearningPackException(
          LearningPackFailureCode.integrityMismatch,
        );
      }
      return pack;
    }

    try {
      return await Future.any<LearningPack>([
        read(),
        abort.future.then(
          (_) => throw const PackStorageException(
            PackStorageFailureCode.ownerChanged,
          ),
        ),
      ]).timeout(timeout);
    } on PackStorageException {
      rethrow;
    } on LearningPackException {
      rethrow;
    } on Object {
      requireCurrent();
      throw const PackStorageException(PackStorageFailureCode.unavailable);
    } finally {
      finished = true;
      ownerWatch.cancel();
      cancel();
      _aborters.remove(abort);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final abort in _aborters) {
      if (!abort.isCompleted) abort.complete();
    }
    client.close();
  }
}

LearningPack _decodePack((Uint8List, String) input) =>
    const LearningPackCodec().decode(input.$1, expectedPackageSha256: input.$2);
