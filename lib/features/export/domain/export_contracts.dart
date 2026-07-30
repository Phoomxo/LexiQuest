import 'dart:typed_data';

enum ExportFormat { csv, pdf, anki, researchJson }

final class ExportSelection {
  const ExportSelection({
    required this.includeVocabulary,
    required this.includeAttempts,
    required this.includeReading,
  });

  final bool includeVocabulary;
  final bool includeAttempts;
  final bool includeReading;

  bool get isEmpty => !includeVocabulary && !includeAttempts && !includeReading;
}

final class ExportArtifact {
  const ExportArtifact({
    required this.format,
    required this.suggestedFileName,
    required this.mimeType,
    required this.bytes,
    required this.recordCount,
    required this.schemaVersion,
    required this.algorithmVersion,
    required this.generatedAtUtc,
    required this.timeZone,
    required this.exclusions,
  });

  final ExportFormat format;
  final String suggestedFileName;
  final String mimeType;
  final Uint8List bytes;
  final int recordCount;
  final int schemaVersion;
  final int algorithmVersion;
  final DateTime generatedAtUtc;
  final String timeZone;
  final List<String> exclusions;
}

final class ExportSaveResult {
  const ExportSaveResult({required this.path, required this.bytesWritten});

  final String path;
  final int bytesWritten;
}

enum ExportFailureCode {
  noSelection,
  noData,
  consentRequired,
  cancelled,
  permissionDenied,
  insufficientSpace,
  writeFailed,
  unavailable,
}

final class ExportException implements Exception {
  const ExportException(this.code, [this.cause]);

  final ExportFailureCode code;
  final Object? cause;
}

final class ExportCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ExportException(ExportFailureCode.cancelled);
  }
}

abstract interface class ExportArtifactStore {
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  });
}
