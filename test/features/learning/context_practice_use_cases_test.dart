import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/context_practice.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';

void main() {
  const inventory = ContextPracticeInventory();
  final bytes = File(
    'assets/content/lexical_metadata/starter-book/r1.json',
  ).readAsBytesSync();
  final sentence =
      (jsonDecode(utf8.decode(bytes)) as Map)['examples'][0] as String;
  final hash = sha256.convert(bytes).toString();
  test('reviewed exact book context admits only its explicit options', () {
    expect(
      inventory.admits(
        wordId: 'word:starter-book',
        artifactHash: hash,
        sentence: sentence,
        options: ['book', 'pencil'],
      ),
      isTrue,
    );
  });
  test('CONTEXT-AMBIGUOUS rejects unreviewed broad string keys', () {
    expect(
      inventory.admits(
        wordId: 'take',
        artifactHash: hash,
        sentence: 'Please ___ a photo.',
        options: ['take', 'make'],
      ),
      isFalse,
    );
  });
  test(
    'container confusables require the narrow-neck clue; handle alone is ambiguous',
    () {
      final bottle = File(
        'assets/content/lexical_metadata/starter-bottle/r1.json',
      ).readAsBytesSync();
      expect(
        inventory.admits(
          wordId: 'word:starter-bottle',
          artifactHash: sha256.convert(bottle).toString(),
          sentence:
              (jsonDecode(utf8.decode(bottle)) as Map)['examples'][0] as String,
          options: ['bottle', 'cup'],
        ),
        isTrue,
      );
      final cup = File(
        'assets/content/lexical_metadata/starter-cup/r1.json',
      ).readAsBytesSync();
      expect(
        inventory.admits(
          wordId: 'word:starter-cup',
          artifactHash: sha256.convert(cup).toString(),
          sentence:
              (jsonDecode(utf8.decode(cup)) as Map)['examples'][0] as String,
          options: ['cup', 'bottle'],
        ),
        isFalse,
      );
    },
  );
  test('rejects a changed context, hash, extra or equivalent distractor', () {
    for (final options in [
      ['book', 'pencil', 'bag'],
      ['book', 'BOOK'],
      ['book'],
    ]) {
      expect(
        inventory.admits(
          wordId: 'word:starter-book',
          artifactHash: hash,
          sentence: sentence,
          options: options,
        ),
        isFalse,
      );
    }
    expect(
      inventory.admits(
        wordId: 'word:starter-book',
        artifactHash: '0' * 64,
        sentence: sentence,
        options: ['book', 'pencil'],
      ),
      isFalse,
    );
    expect(
      inventory.admits(
        wordId: 'word:starter-book',
        artifactHash: hash,
        sentence: 'I have a book.',
        options: ['book', 'pencil'],
      ),
      isFalse,
    );
  });
  test(
    'context pinning uses reviewed alternatives, not session distractors',
    () {
      final word = VocabularyWord(
        id: 'word:starter-book',
        categoryId: 'c',
        ownerId: 'o',
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: DateTime.utc(2026),
        updatedAtUtc: DateTime.utc(2026),
        spelling: 'book',
        normalizedSpelling: 'book',
        meaning: 'หนังสือ',
        normalizedMeaning: 'หนังสือ',
        partOfSpeech: 'noun',
        source: 'packaged',
        isGlobal: true,
        contentRevision: 1,
        contentChecksumSha256: 'a' * 64,
        contentProvenance: ContentProvenance.packaged,
        contentReviewState: ContentReviewState.approved,
        contentPublicationState: ContentPublicationState.published,
        richMetadata: RichLexicalMetadata.fromVerifiedArtifact(
          bytes: bytes,
          wordId: 'word:starter-book',
          contentRevision: 1,
          verifiedArtifactChecksumSha256: hash,
        ),
      );
      final session = QuizSession(
        id: 's',
        ownerId: 'o',
        startedAtUtc: DateTime.utc(2026),
        questions: [
          QuizQuestion(
            word: QuizWord(
              id: word.id,
              categoryId: 'c',
              spelling: 'book',
              meaning: 'หนังสือ',
              partOfSpeech: 'noun',
              contentRevision: 1,
              contentChecksumSha256: 'a' * 64,
            ),
            options: ['หนังสือ'],
          ),
        ],
      );
      final items = const ClozeModeAdapter().pinItems(
        session: session,
        lexicalWords: [word],
        contextPractice: true,
      );
      expect(items.single.question!.options.toSet(), {'book', 'pencil'});
      expect(
        items.single.question!.optionIdentity('pencil'),
        'word:starter-pencil',
      );
    },
  );
}
