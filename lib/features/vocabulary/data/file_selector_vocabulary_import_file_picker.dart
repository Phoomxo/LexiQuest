import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../application/vocabulary_import_file_parser.dart';
import '../application/vocabulary_import_file_picker.dart';

typedef FileSelectorOpenImportFile =
    Future<XFile?> Function({required List<XTypeGroup> acceptedTypeGroups});

final class FileSelectorVocabularyImportFilePicker {
  FileSelectorVocabularyImportFilePicker({FileSelectorOpenImportFile? openFile})
    : _openFile = openFile ?? _openVocabularyImportFile;

  final FileSelectorOpenImportFile _openFile;

  Future<VocabularyImportFile?> pick() async {
    final file = await _openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'CSV / JSON',
          extensions: ['csv', 'json'],
          mimeTypes: ['text/csv', 'application/json'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxVocabularyImportBytes) {
      throw const VocabularyImportFileFailure('fileTooLarge');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      final remaining = maxVocabularyImportBytes + 1 - bytes.length;
      final take = chunk.length < remaining ? chunk.length : remaining;
      bytes.add(
        take == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, take),
      );
      if (bytes.length > maxVocabularyImportBytes) {
        throw const VocabularyImportFileFailure('fileTooLarge');
      }
    }
    final selectedBytes = bytes.takeBytes();
    if (selectedBytes.length > maxVocabularyImportBytes) {
      throw const VocabularyImportFileFailure('fileTooLarge');
    }
    return VocabularyImportFile(
      name: file.name,
      mimeType: file.mimeType,
      bytes: selectedBytes,
    );
  }
}

Future<XFile?> _openVocabularyImportFile({
  required List<XTypeGroup> acceptedTypeGroups,
}) => openFile(acceptedTypeGroups: acceptedTypeGroups);
