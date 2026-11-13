import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/source_practice.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  final station = _word('word-station', 'station');
  final trainStation = _word('word-train-station', 'train station');
  final nation = _word('word-nation', 'nation');

  test('TXT preview matches whole words in first-occurrence order', () {
    final preview = parseSourcePracticeFile(
      fileName: 'travel.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(
        utf8.encode(
          'The station is quiet, and this train station is ready today.',
        ),
      ),
      words: [nation, trainStation, station],
    );

    expect(preview.passageText, contains('The station is quiet'));
    expect(preview.matchedWords.map((word) => word.id), [
      'word-station',
      'word-train-station',
    ]);
    expect(preview.unknownWords, containsAll(['the', 'quiet', 'ready']));
    expect(preview.unknownWords, isNot(contains('nation')));
    expect(preview.documentId, startsWith('local-source:'));
    expect(preview.documentId, isNot(contains('travel')));
    expect(preview.documentRevision, greaterThan(0));
  });

  test('Markdown extraction keeps visible prose and drops link destinations', () {
    final preview = parseSourcePracticeFile(
      fileName: 'lesson.md',
      mimeType: 'text/markdown',
      bytes: Uint8List.fromList(
        utf8.encode(
          '# Travel\n\nThe **station** is [near the river](https://example.test).',
        ),
      ),
      words: [station],
    );

    expect(preview.passageText, contains('Travel'));
    expect(preview.passageText, contains('near the river'));
    expect(preview.passageText, isNot(contains('https://')));
    expect(preview.matchedWords.single.id, 'word-station');
  });

  test('same logical source is stable and edited text advances revision', () {
    final first = reviewSourcePracticeText(
      sourceName: 'lesson.txt',
      text: 'The station is open and ready for every learner today.',
      words: [station],
    );
    final replay = reviewSourcePracticeText(
      sourceName: 'lesson.txt',
      text: 'The station is open and ready for every learner today.',
      words: [station],
    );
    final edited = reviewSourcePracticeText(
      sourceName: 'lesson.txt',
      text: 'The station is closed but ready for every learner today.',
      words: [station],
    );

    expect(replay.documentId, first.documentId);
    expect(replay.documentRevision, first.documentRevision);
    expect(edited.documentId, first.documentId);
    expect(edited.documentRevision, isNot(first.documentRevision));
  });

  test('English gate rejects short and predominantly non-English content', () {
    expect(
      () => reviewSourcePracticeText(
        sourceName: 'short.txt',
        text: 'station open',
        words: [station],
      ),
      throwsA(_failure('notEnglish')),
    );
    expect(
      () => reviewSourcePracticeText(
        sourceName: 'mixed.txt',
        text: 'นี่ คือ บทเรียน ภาษาไทย station open ready today learner',
        words: [station],
      ),
      throwsA(_failure('notEnglish')),
    );
    expect(
      () => reviewSourcePracticeText(
        sourceName: 'thai-run.txt',
        text:
            'นี่คือบทเรียนภาษาไทยที่มีเนื้อหายาวกว่าคำอังกฤษอย่างชัดเจน'
            ' station open ready today learner',
        words: [station],
      ),
      throwsA(_failure('notEnglish')),
    );
  });

  test('file boundary rejects type, encoding, empty, and oversized input', () {
    expect(
      () => parseSourcePracticeFile(
        fileName: 'lesson.json',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode('valid words are here today')),
        words: [station],
      ),
      throwsA(_failure('unsupportedType')),
    );
    expect(
      () => parseSourcePracticeFile(
        fileName: 'lesson.txt',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode('valid words are here today')),
        words: [station],
      ),
      throwsA(_failure('unsupportedType')),
    );
    expect(
      () => parseSourcePracticeFile(
        fileName: 'lesson.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList([0xC3, 0x28]),
        words: [station],
      ),
      throwsA(_failure('invalidEncoding')),
    );
    expect(
      () => parseSourcePracticeFile(
        fileName: 'lesson.txt',
        mimeType: 'text/plain',
        bytes: Uint8List(0),
        words: [station],
      ),
      throwsA(_failure('emptyFile')),
    );
    expect(
      () => parseSourcePracticeFile(
        fileName: 'lesson.txt',
        mimeType: 'text/plain',
        bytes: Uint8List(maxSourcePracticeBytes + 1),
        words: [station],
      ),
      throwsA(_failure('fileTooLarge')),
    );
    expect(
      () => reviewSourcePracticeText(
        sourceName: 'edited.txt',
        text: 'a' * (maxSourcePracticeBytes + 1),
        words: [station],
      ),
      throwsA(_failure('fileTooLarge')),
    );
  });

  test(
    'reselecting the same source resumes opaque progress after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-source-practice-',
      );
      final databaseFile = File('${directory.path}/restart.sqlite');
      AppDatabase? first;
      AppDatabase? reopened;
      try {
        final preview = reviewSourcePracticeText(
          sourceName: 'private-lesson.txt',
          text: 'The station is open and ready for every learner today.',
          words: [station],
        );
        first = AppDatabase(NativeDatabase(databaseFile));
        final firstOwners = DriftLocalOwnerRepository(
          first,
          generateId: () => 'restart-owner',
          nowUtc: () => DateTime.utc(2026, 10, 21),
        );
        await firstOwners.getOrCreateActiveOwner();
        final firstLearning = _learning(first, firstOwners);
        await firstLearning.saveReadingProgress(
          documentId: preview.documentId,
          documentRevision: preview.documentRevision,
          position: 3,
          isCompleted: false,
        );
        await first.close();
        first = null;

        reopened = AppDatabase(NativeDatabase(databaseFile));
        final reopenedOwners = DriftLocalOwnerRepository(
          reopened,
          generateId: () => 'unused-owner',
          nowUtc: () => DateTime.utc(2026, 10, 21),
        );
        final replay = reviewSourcePracticeText(
          sourceName: 'private-lesson.txt',
          text: 'The station is open and ready for every learner today.',
          words: [station],
        );
        final restored = await _learning(reopened, reopenedOwners)
            .loadReadingProgress(
              documentId: replay.documentId,
              documentRevision: replay.documentRevision,
            );
        expect(restored?.lastPosition, 3);
        final event = await reopened.select(reopened.readingEvents).getSingle();
        expect(event.documentId, startsWith('local-source:'));
        expect(event.documentId, isNot(contains('private-lesson')));
        expect(event.documentId, isNot(contains('station')));

        final revised = reviewSourcePracticeText(
          sourceName: 'private-lesson.txt',
          text: 'The station is closed but ready for every learner today.',
          words: [station],
        );
        expect(revised.documentId, replay.documentId);
        expect(revised.documentRevision, isNot(replay.documentRevision));
        expect(
          await _learning(reopened, reopenedOwners).loadReadingProgress(
            documentId: revised.documentId,
            documentRevision: revised.documentRevision,
          ),
          isNull,
        );
      } finally {
        await first?.close();
        await reopened?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );
}

Matcher _failure(String code) => isA<SourcePracticeFailure>().having(
  (failure) => failure.code,
  'code',
  code,
);

VocabularyWord _word(String id, String spelling) => VocabularyWord(
  id: id,
  ownerId: 'owner-1',
  categoryId: 'category-1',
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: 'meaning of $spelling',
  normalizedMeaning: 'meaning of $spelling',
  partOfSpeech: 'noun',
  source: 'manual',
  isGlobal: false,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: DateTime.utc(2026),
  updatedAtUtc: DateTime.utc(2026),
);

LearningUseCases _learning(
  AppDatabase database,
  DriftLocalOwnerRepository owners,
) => LearningUseCases(
  owners: owners,
  repository: DriftLearningRepository(database),
  generateId: () => 'restart-id',
  nowUtc: () => DateTime.utc(2026, 10, 21, 1),
  buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
);
