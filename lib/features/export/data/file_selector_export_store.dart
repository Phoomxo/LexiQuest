import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/export_contracts.dart';

final class FileSelectorExportStore implements ExportArtifactStore {
  const FileSelectorExportStore();

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
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
      await XFile(
        partial.path,
        mimeType: artifact.mimeType,
      ).saveTo(location.path);
      cancellation.throwIfCancelled();
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

  String _extension(String fileName) => fileName.split('.').last;
}
