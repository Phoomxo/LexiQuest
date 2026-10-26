import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_import_file_parser.dart';

void main() {
  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

  test('CSV keeps quoted commas and escaped quotes', () {
    final preview = parseVocabularyImportFile(
      fileName: 'travel.csv',
      mimeType: 'text/csv',
      bytes: bytes(
        'word,meaning,partOfSpeech\n'
        'station,"rail, bus",noun\n'
        'quote,"say ""hello""",verb',
      ),
    );

    expect(preview.rows, hasLength(2));
    expect(preview.rows.first.meaning, 'rail, bus');
    expect(preview.rows.last.meaning, 'say "hello"');
    expect(
      preview.rows.map((row) => row.status),
      everyElement(VocabularyImportPreviewStatus.ready),
    );
  });

  test('JSON accepts the same three vocabulary fields', () {
    final preview = parseVocabularyImportFile(
      fileName: 'travel.json',
      mimeType: 'application/json',
      bytes: bytes(
        jsonEncode([
          {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
        ]),
      ),
    );

    expect(preview.rows.single.word, 'station');
    expect(preview.rows.single.status, VocabularyImportPreviewStatus.ready);
  });

  test('preview separates invalid and duplicate rows', () {
    final preview = parseVocabularyImportFile(
      fileName: 'travel.csv',
      bytes: bytes(
        'word,meaning,partOfSpeech\n'
        'station,สถานี,noun\n'
        'station,สถานี,noun\n'
        'travel,,verb',
      ),
      existingRows: const [
        {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
      ],
    );

    expect(preview.readyCount, 0);
    expect(preview.duplicateCount, 2);
    expect(preview.needsEditCount, 1);
    expect(preview.rows.map((row) => row.status), [
      VocabularyImportPreviewStatus.duplicate,
      VocabularyImportPreviewStatus.duplicate,
      VocabularyImportPreviewStatus.needsEdit,
    ]);
    expect(preview.rows.last.failureCode, 'missingMeaning');
  });

  test('editing a rejected row recomputes preview status', () {
    final rows = reviewVocabularyImportRows(const [
      {'word': 'travel', 'meaning': '', 'partOfSpeech': 'verb'},
    ]);

    final edited = reviewVocabularyImportRows([
      rows.single.toMap()..['meaning'] = 'เดินทาง',
    ]);

    expect(edited.single.status, VocabularyImportPreviewStatus.ready);
    expect(edited.single.failureCode, isNull);
  });

  test('malformed, empty, unsupported, and oversized files fail closed', () {
    expect(
      () => parseVocabularyImportFile(
        fileName: 'broken.csv',
        bytes: bytes('word,meaning,partOfSpeech\n"station,สถานี,noun'),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'malformedCsv',
        ),
      ),
    );
    expect(
      () => parseVocabularyImportFile(
        fileName: 'empty.json',
        bytes: Uint8List(0),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'emptyFile',
        ),
      ),
    );
    expect(
      () => parseVocabularyImportFile(
        fileName: 'travel.txt',
        bytes: bytes('station,สถานี,noun'),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'unsupportedType',
        ),
      ),
    );
    expect(
      () => parseVocabularyImportFile(
        fileName: 'large.csv',
        bytes: Uint8List(maxVocabularyImportBytes + 1),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'fileTooLarge',
        ),
      ),
    );
  });

  test('reliable MIME mismatch and excessive row count fail closed', () {
    expect(
      () => parseVocabularyImportFile(
        fileName: 'travel.csv',
        mimeType: 'image/png',
        bytes: bytes('station,สถานี,noun'),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'unsupportedType',
        ),
      ),
    );
    final rows = List.generate(
      maxVocabularyImportRows + 1,
      (index) => 'word$index,meaning$index,noun',
    ).join('\n');
    expect(
      () =>
          parseVocabularyImportFile(fileName: 'large.csv', bytes: bytes(rows)),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'tooManyRows',
        ),
      ),
    );
  });

  test('generic text MIME falls back to extension and parser validation', () {
    final preview = parseVocabularyImportFile(
      fileName: 'travel.csv',
      mimeType: 'text/plain',
      bytes: bytes('station,สถานี,noun'),
    );

    expect(preview.readyCount, 1);
  });

  test('CSV keeps an all-empty delimited row for correction', () {
    final preview = parseVocabularyImportFile(
      fileName: 'travel.csv',
      bytes: bytes(
        'word,meaning,partOfSpeech\n'
        ',,\n'
        'train,รถไฟ,noun',
      ),
    );

    expect(preview.rows, hasLength(2));
    expect(preview.rows.first.status, VocabularyImportPreviewStatus.needsEdit);
    expect(preview.rows.first.failureCode, 'missingWord');
    expect(preview.rows.last.status, VocabularyImportPreviewStatus.ready);
  });

  test('CSV rejects a quoted-empty one-column record', () {
    expect(
      () => parseVocabularyImportFile(
        fileName: 'travel.csv',
        bytes: bytes(
          'word,meaning,partOfSpeech\n'
          '""\n'
          'train,รถไฟ,noun',
        ),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'malformedCsv',
        ),
      ),
    );
  });

  test('CSV rejects a quoted-empty one-column record at EOF', () {
    expect(
      () => parseVocabularyImportFile(
        fileName: 'travel.csv',
        bytes: bytes(
          'word,meaning,partOfSpeech\n'
          'train,รถไฟ,noun\n'
          '""',
        ),
      ),
      throwsA(
        isA<VocabularyImportFileFailure>().having(
          (error) => error.code,
          'code',
          'malformedCsv',
        ),
      ),
    );
  });
}
