import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/application/source_practice.dart';
import 'package:vocab_learning_app/features/vocabulary/data/file_selector_source_practice_file_picker.dart';

void main() {
  test('selects TXT or Markdown and returns platform-neutral bytes', () async {
    List<XTypeGroup>? acceptedTypes;
    final picker = FileSelectorSourcePracticeFilePicker(
      openFile: ({required acceptedTypeGroups}) async {
        acceptedTypes = acceptedTypeGroups;
        return XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: 'lesson.md',
          mimeType: 'text/markdown',
        );
      },
    );

    final selected = await picker.pick();

    expect(acceptedTypes, hasLength(1));
    expect(acceptedTypes!.single.extensions, ['txt', 'md']);
    expect(acceptedTypes!.single.mimeTypes, [
      'text/plain',
      'text/markdown',
      'text/x-markdown',
    ]);
    expect(selected?.name, 'lesson.md');
    expect(selected?.mimeType, 'text/markdown');
    expect(selected?.bytes, [1, 2, 3]);
  });

  test('returns null when native selection is cancelled', () async {
    final picker = FileSelectorSourcePracticeFilePicker(
      openFile: ({required acceptedTypeGroups}) async => null,
    );

    expect(await picker.pick(), isNull);
  });

  test('rejects reported size before reading bytes', () {
    final picker = FileSelectorSourcePracticeFilePicker(
      openFile: ({required acceptedTypeGroups}) async => XFile.fromData(
        Uint8List(maxSourcePracticeBytes + 1),
        length: maxSourcePracticeBytes + 1,
        path: 'large.txt',
      ),
    );

    expect(picker.pick, throwsA(_tooLarge));
  });

  test('rejects actual bytes larger than an understated length', () {
    final picker = FileSelectorSourcePracticeFilePicker(
      openFile: ({required acceptedTypeGroups}) async => XFile.fromData(
        Uint8List(maxSourcePracticeBytes + 1),
        length: 1,
        path: 'changed.txt',
      ),
    );

    expect(picker.pick, throwsA(_tooLarge));
  });
}

final Matcher _tooLarge = isA<SourcePracticeFailure>().having(
  (failure) => failure.code,
  'code',
  'fileTooLarge',
);
