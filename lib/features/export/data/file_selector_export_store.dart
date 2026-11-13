import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/export_contracts.dart';

typedef _AndroidExportDestination = ({
  String destination,
  String selectionToken,
});

final class FileSelectorExportStore implements ExportArtifactStore {
  const FileSelectorExportStore({this.isAndroid});

  static const _androidChannel = MethodChannel('com.lexiquest.app/export');

  final bool? isAndroid;

  bool get _usesAndroidDocumentPicker => isAndroid ?? Platform.isAndroid;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    cancellation.throwIfCancelled();
    if (_usesAndroidDocumentPicker) {
      return _saveOnAndroid(artifact, cancellation, revalidateBeforeWrite);
    }
    final location = await getSaveLocation(
      suggestedName: artifact.suggestedFileName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: artifact.format.name,
          extensions: [_extension(artifact.suggestedFileName)],
          mimeTypes: [artifact.mimeType],
        ),
      ],
    );
    if (location == null) {
      throw const ExportException(ExportFailureCode.cancelled);
    }
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    cancellation.throwIfCancelled();
    Directory? stagingDirectory;
    File? partial;
    try {
      stagingDirectory = await getTemporaryDirectory();
      partial = File(
        '${stagingDirectory.path}${Platform.pathSeparator}'
        '${artifact.suggestedFileName}.partial',
      );
      if (await partial.exists()) await partial.delete();
      await partial.writeAsBytes(artifact.bytes, flush: true);
      cancellation.throwIfCancelled();
      await revalidateBeforeWrite();
      cancellation.throwIfCancelled();
      await XFile(
        partial.path,
        mimeType: artifact.mimeType,
      ).saveTo(location.path);
      // shortcut: external writes cannot roll back; upgrade with transactional stores.
      return ExportSaveResult(
        path: location.path,
        bytesWritten: artifact.bytes.length,
      );
    } on ExportException {
      rethrow;
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 28 || code == 112) {
        throw ExportException(ExportFailureCode.insufficientSpace, error);
      }
      if (code == 5 || code == 13) {
        throw ExportException(ExportFailureCode.permissionDenied, error);
      }
      throw ExportException(ExportFailureCode.writeFailed, error);
    } catch (error) {
      throw ExportException(ExportFailureCode.writeFailed, error);
    } finally {
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<ExportSaveResult> _saveOnAndroid(
    ExportArtifact artifact,
    ExportCancellation cancellation,
    ExportWriteRevalidator revalidateBeforeWrite,
  ) async {
    try {
      final location = await _selectAndroidDestination(artifact);
      if (location == null) {
        throw const ExportException(ExportFailureCode.cancelled);
      }
      try {
        cancellation.throwIfCancelled();
        await revalidateBeforeWrite();
        cancellation.throwIfCancelled();
      } catch (_) {
        await _discardAndroidDestination(location);
        rethrow;
      }
      await _writeAndroidDestination(location, artifact);
      // shortcut: external writes cannot roll back; upgrade with transactional stores.
      return ExportSaveResult(
        path: location.destination,
        bytesWritten: artifact.bytes.length,
      );
    } on ExportException {
      rethrow;
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'PERMISSION_DENIED' => ExportFailureCode.permissionDenied,
        'INSUFFICIENT_SPACE' => ExportFailureCode.insufficientSpace,
        'UNAVAILABLE' => ExportFailureCode.unavailable,
        _ => ExportFailureCode.writeFailed,
      };
      throw ExportException(code);
    } catch (error) {
      throw const ExportException(ExportFailureCode.writeFailed);
    }
  }

  Future<_AndroidExportDestination?> _selectAndroidDestination(
    ExportArtifact artifact,
  ) async {
    final response = await _androidChannel.invokeMethod<Object?>(
      'selectExportDestination',
      {
        'suggestedName': artifact.suggestedFileName,
        'mimeType': artifact.mimeType,
      },
    );
    if (response == null) return null;
    if (response is! Map) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    final destination = response['destination'];
    final selectionToken = response['selectionToken'];
    if (destination is! String ||
        destination.trim().isEmpty ||
        selectionToken is! String ||
        selectionToken.trim().isEmpty) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    return (
      destination: destination.trim(),
      selectionToken: selectionToken.trim(),
    );
  }

  Future<void> _writeAndroidDestination(
    _AndroidExportDestination location,
    ExportArtifact artifact,
  ) {
    return _androidChannel.invokeMethod<void>('writeExportFile', {
      'destination': location.destination,
      'selectionToken': location.selectionToken,
      'bytes': artifact.bytes,
    });
  }

  Future<void> _discardAndroidDestination(
    _AndroidExportDestination location,
  ) async {
    try {
      await _androidChannel.invokeMethod<void>('discardExportDestination', {
        'destination': location.destination,
        'selectionToken': location.selectionToken,
      });
    } on PlatformException {
      // The next picker invalidates any stale destination in native state.
    }
  }

  String _extension(String fileName) => fileName.split('.').last;
}
