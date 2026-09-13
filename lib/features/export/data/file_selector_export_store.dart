import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/export_contracts.dart';

typedef AndroidExportSaver = Future<String?> Function(ExportArtifact artifact);
typedef AndroidExportDiscarder = Future<void> Function(String location);
typedef DesktopExportLocation =
    Future<String?> Function(ExportArtifact artifact);
typedef DesktopExportSaver =
    Future<void> Function(String source, String destination);

final class FileSelectorExportStore implements ExportArtifactStore {
  const FileSelectorExportStore({
    this.isAndroid,
    this.androidSaver,
    this.androidDiscarder,
    this.desktopLocation,
    this.desktopSaver,
    this.temporaryDirectory,
  });

  static const _androidChannel = MethodChannel('com.lexiquest.app/export');

  final bool? isAndroid;
  final AndroidExportSaver? androidSaver;
  final AndroidExportDiscarder? androidDiscarder;
  final DesktopExportLocation? desktopLocation;
  final DesktopExportSaver? desktopSaver;
  final Future<Directory> Function()? temporaryDirectory;
  static final Set<String> _activeDestinations = {};

  bool get _usesAndroidDocumentPicker => isAndroid ?? Platform.isAndroid;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (_usesAndroidDocumentPicker) {
      return _saveOnAndroid(artifact, cancellation);
    }
    final location = await (desktopLocation ?? _chooseDesktopLocation)(
      artifact,
    );
    if (location == null) {
      throw const ExportException(ExportFailureCode.cancelled);
    }
    cancellation.throwIfCancelled();
    final destination = File(location).absolute;
    if (!_activeDestinations.add(destination.path)) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    Directory? stagingDirectory;
    File? backup;
    var destinationTouched = false;
    var preserveBackup = false;
    try {
      final temporaryRoot =
          await (temporaryDirectory ?? getTemporaryDirectory)();
      stagingDirectory = await temporaryRoot.createTemp('lexiquest-export-');
      final partial = File(
        '${stagingDirectory.path}${Platform.pathSeparator}export.partial',
      );
      await partial.writeAsBytes(artifact.bytes, flush: true);
      cancellation.throwIfCancelled();
      if (await destination.exists()) {
        backup = await destination.copy(
          '${stagingDirectory.path}${Platform.pathSeparator}previous',
        );
      }
      cancellation.throwIfCancelled();
      destinationTouched = true;
      await (desktopSaver ?? _saveDesktop)(partial.path, destination.path);
      cancellation.throwIfCancelled();
      return ExportSaveResult(
        path: destination.path,
        bytesWritten: artifact.bytes.length,
      );
    } catch (error) {
      if (destinationTouched) {
        try {
          if (backup != null) {
            await backup.copy(destination.path);
          } else if (await destination.exists()) {
            await destination.delete();
          }
        } catch (_) {
          preserveBackup = backup != null;
          throw const ExportException(ExportFailureCode.cleanupFailed);
        }
      }
      if (error is ExportException) rethrow;
      if (error is FileSystemException) {
        final code = error.osError?.errorCode;
        if (code == 28 || code == 112) {
          throw const ExportException(ExportFailureCode.insufficientSpace);
        }
        if (code == 5 || code == 13) {
          throw const ExportException(ExportFailureCode.permissionDenied);
        }
      }
      throw const ExportException(ExportFailureCode.writeFailed);
    } finally {
      _activeDestinations.remove(destination.path);
      if (stagingDirectory != null) {
        try {
          if (preserveBackup) {
            // Keep the user's previous bytes when the destination cannot be
            // restored. Remove only this operation's new export payload.
            final partial = File(
              '${stagingDirectory.path}${Platform.pathSeparator}export.partial',
            );
            if (await partial.exists()) await partial.delete();
          } else {
            await stagingDirectory.delete(recursive: true);
          }
        } catch (_) {
          throw const ExportException(ExportFailureCode.cleanupFailed);
        }
      }
    }
  }

  Future<String?> _chooseDesktopLocation(ExportArtifact artifact) async {
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
    return location?.path;
  }

  Future<void> _saveDesktop(String source, String destination) =>
      XFile(source).saveTo(destination);

  Future<ExportSaveResult> _saveOnAndroid(
    ExportArtifact artifact,
    ExportCancellation cancellation,
  ) async {
    try {
      final location = await (androidSaver ?? _saveWithAndroidDocumentPicker)(
        artifact,
      );
      if (location == null) {
        throw const ExportException(ExportFailureCode.cancelled);
      }
      if (cancellation.isCancelled) {
        try {
          await (androidDiscarder ?? _discardAndroid)(location);
        } catch (_) {
          throw const ExportException(ExportFailureCode.cleanupFailed);
        }
        throw const ExportException(ExportFailureCode.cancelled);
      }
      if (androidSaver == null) {
        await _androidChannel.invokeMethod<void>('finishExportFile', {
          'location': location,
          'discard': false,
        });
      }
      return ExportSaveResult(
        path: location,
        bytesWritten: artifact.bytes.length,
      );
    } on ExportException {
      rethrow;
    } on PlatformException catch (error) {
      final code = switch (error.code) {
        'PERMISSION_DENIED' => ExportFailureCode.permissionDenied,
        'INSUFFICIENT_SPACE' => ExportFailureCode.insufficientSpace,
        'UNAVAILABLE' => ExportFailureCode.unavailable,
        'CLEANUP_FAILED' => ExportFailureCode.cleanupFailed,
        _ => ExportFailureCode.writeFailed,
      };
      throw ExportException(code);
    } catch (error) {
      throw const ExportException(ExportFailureCode.writeFailed);
    }
  }

  Future<void> _discardAndroid(String location) =>
      _androidChannel.invokeMethod<void>('finishExportFile', {
        'location': location,
        'discard': true,
      });

  Future<String?> _saveWithAndroidDocumentPicker(ExportArtifact artifact) {
    return _androidChannel.invokeMethod<String>('saveExportFile', {
      'suggestedName': artifact.suggestedFileName,
      'mimeType': artifact.mimeType,
      'bytes': artifact.bytes,
    });
  }

  String _extension(String fileName) => fileName.split('.').last;
}
