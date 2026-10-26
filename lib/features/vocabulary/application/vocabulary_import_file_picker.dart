import 'dart:typed_data';

final class VocabularyImportFile {
  const VocabularyImportFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String? mimeType;
  final Uint8List bytes;
}

typedef VocabularyImportFilePicker = Future<VocabularyImportFile?> Function();
