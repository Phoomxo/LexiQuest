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
  }) => saveFile(
    suggestedName: artifact.suggestedFileName,
    mimeType: artifact.mimeType,
    typeLabel: artifact.format.name,
    bytes: artifact.bytes,
    cancellation: cancellation,
    revalidateBeforeWrite: revalidateBeforeWrite,
  );

  Future<ExportSaveResult> saveFile({
    required String suggestedName,
    required String mimeType,
    required String typeLabel,
    required Uint8List bytes,
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    cancellation.throwIfCancelled();
    if (_usesAndroidDocumentPicker) {
      return _saveOnAndroid(
        suggestedName,
        mimeType,
        bytes,
        cancellation,
        revalidateBeforeWrite,
      );
    }
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: typeLabel,
          extensions: [_extension(suggestedName)],
          mimeTypes: [mimeType],
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
        '$suggestedName.partial',
      );
      if (await partial.exists()) await partial.delete();
      await partial.writeAsBytes(bytes, flush: true);
      cancellation.throwIfCancelled();
      await revalidateBeforeWrite();
      cancellation.throwIfCancelled();
      await XFile(partial.path, mimeType: mimeType).saveTo(location.path);
      // shortcut: external writes cannot roll back; upgrade with transactional stores.
      return ExportSaveResult(path: location.path, bytesWritten: bytes.length);
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
    String suggestedName,
    String mimeType,
    Uint8List bytes,
    ExportCancellation cancellation,
    ExportWriteRevalidator revalidateBeforeWrite,
  ) async {
    try {
      final location = await _selectAndroidDestination(suggestedName, mimeType);
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
      await _writeAndroidDestination(location, bytes);
      // shortcut: external writes cannot roll back; upgrade with transactional stores.
      return ExportSaveResult(
        path: location.destination,
        bytesWritten: bytes.length,
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
    String suggestedName,
    String mimeType,
  ) async {
    final response = await _androidChannel.invokeMethod<Object?>(
      'selectExportDestination',
      {'suggestedName': suggestedName, 'mimeType': mimeType},
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
    Uint8List bytes,
  ) {
    return _androidChannel.invokeMethod<void>('writeExportFile', {
      'destination': location.destination,
      'selectionToken': location.selectionToken,
      'bytes': bytes,
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
