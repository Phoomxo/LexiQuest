import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../application/source_practice.dart';

typedef FileSelectorOpenSourcePracticeFile =
    Future<XFile?> Function({required List<XTypeGroup> acceptedTypeGroups});

final class FileSelectorSourcePracticeFilePicker {
  FileSelectorSourcePracticeFilePicker({
    FileSelectorOpenSourcePracticeFile? openFile,
  }) : _openFile = openFile ?? _openSourcePracticeFile;

  final FileSelectorOpenSourcePracticeFile _openFile;

  Future<SourcePracticeFile?> pick() async {
    final file = await _openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'TXT / Markdown',
          extensions: ['txt', 'md'],
          mimeTypes: ['text/plain', 'text/markdown', 'text/x-markdown'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxSourcePracticeBytes) {
      throw const SourcePracticeFailure('fileTooLarge');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      final remaining = maxSourcePracticeBytes + 1 - bytes.length;
      final take = chunk.length < remaining ? chunk.length : remaining;
      bytes.add(
        take == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, take),
      );
      if (bytes.length > maxSourcePracticeBytes) {
        throw const SourcePracticeFailure('fileTooLarge');
      }
    }
    final selectedBytes = bytes.takeBytes();
    if (selectedBytes.length > maxSourcePracticeBytes) {
      throw const SourcePracticeFailure('fileTooLarge');
    }
    return SourcePracticeFile(
      name: file.name,
      mimeType: file.mimeType,
      bytes: selectedBytes,
    );
  }
}

Future<XFile?> _openSourcePracticeFile({
  required List<XTypeGroup> acceptedTypeGroups,
}) => openFile(acceptedTypeGroups: acceptedTypeGroups);
