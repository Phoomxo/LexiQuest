import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_import_file_parser.dart';
import 'package:vocab_learning_app/features/vocabulary/data/file_selector_vocabulary_import_file_picker.dart';

void main() {
  test('selects CSV or JSON and returns platform-neutral bytes', () async {
    List<XTypeGroup>? acceptedTypes;
    final picker = FileSelectorVocabularyImportFilePicker(
      openFile: ({required acceptedTypeGroups}) async {
        acceptedTypes = acceptedTypeGroups;
        return XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: 'travel.csv',
          mimeType: 'text/csv',
        );
      },
    );

    final selected = await picker.pick();

    expect(acceptedTypes, hasLength(1));
    expect(acceptedTypes!.single.extensions, ['csv', 'json']);
    expect(acceptedTypes!.single.mimeTypes, ['text/csv', 'application/json']);
    expect(selected?.name, 'travel.csv');
    expect(selected?.mimeType, 'text/csv');
    expect(selected?.bytes, [1, 2, 3]);
  });

  test('returns null when the native picker is cancelled', () async {
    final picker = FileSelectorVocabularyImportFilePicker(
      openFile: ({required acceptedTypeGroups}) async => null,
    );

    expect(await picker.pick(), isNull);
  });

  test('rejects an oversized file before reading bytes', () {
    final picker = FileSelectorVocabularyImportFilePicker(
      openFile: ({required acceptedTypeGroups}) async => XFile.fromData(
        Uint8List(maxVocabularyImportBytes + 1),
        length: maxVocabularyImportBytes + 1,
        path: 'large.csv',
      ),
    );

    expect(
      picker.pick,
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'fileTooLarge',
        ),
      ),
    );
  });

  test('rejects actual bytes that grow beyond the preflight length', () {
    final picker = FileSelectorVocabularyImportFilePicker(
      openFile: ({required acceptedTypeGroups}) async => XFile.fromData(
        Uint8List(maxVocabularyImportBytes + 1),
        length: 1,
        path: 'changed.csv',
      ),
    );

    expect(
      picker.pick,
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'fileTooLarge',
        ),
      ),
    );
  });
}
