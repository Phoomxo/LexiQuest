import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  group('AdventureMixedReviewPromptCatalog', () {
    test('supports only the exact adapter-backed prompt matrix', () {
      final words = _quizWords();
      final catalog = _catalog(words: words, direction: SessionDirection.mixed);
      final first = _identity(words[0]);
      final second = _identity(words[1]);

      expect(
        <(LessonMode, String), bool>{
          (LessonMode.typedRecall, 'typedRecall'): catalog.supports(
            first,
            LessonMode.typedRecall,
            'typedRecall',
          ),
          (LessonMode.meaningQuiz, 'meaningChoice'): catalog.supports(
            first,
            LessonMode.meaningQuiz,
            'meaningChoice',
          ),
          (LessonMode.meaningQuiz, 'wordChoice'): catalog.supports(
            first,
            LessonMode.meaningQuiz,
            'wordChoice',
          ),
          (LessonMode.cloze, 'clozeSelected'): catalog.supports(
            first,
            LessonMode.cloze,
            'clozeSelected',
          ),
          (LessonMode.definitionQuiz, 'definitionChoice'): catalog.supports(
            first,
            LessonMode.definitionQuiz,
            'definitionChoice',
          ),
          (LessonMode.flashcard, 'flashcardExposure'): catalog.supports(
            first,
            LessonMode.flashcard,
            'flashcardExposure',
          ),
          (LessonMode.cloze, 'clozeTyped'): catalog.supports(
            first,
            LessonMode.cloze,
            'clozeTyped',
          ),
          (LessonMode.flashcard, 'srsRecall'): catalog.supports(
            first,
            LessonMode.flashcard,
            'srsRecall',
          ),
          (LessonMode.matching, 'matchingPair'): catalog.supports(
            first,
            LessonMode.matching,
            'matchingPair',
          ),
        },
        <(LessonMode, String), bool>{
          (LessonMode.typedRecall, 'typedRecall'): true,
          (LessonMode.meaningQuiz, 'meaningChoice'): true,
          (LessonMode.meaningQuiz, 'wordChoice'): false,
          (LessonMode.cloze, 'clozeSelected'): true,
          (LessonMode.definitionQuiz, 'definitionChoice'): true,
          (LessonMode.flashcard, 'flashcardExposure'): true,
          (LessonMode.cloze, 'clozeTyped'): false,
          (LessonMode.flashcard, 'srsRecall'): false,
          (LessonMode.matching, 'matchingPair'): false,
        },
      );
      expect(
        catalog.supports(second, LessonMode.meaningQuiz, 'wordChoice'),
        isTrue,
      );
      expect(
        catalog.supports(second, LessonMode.meaningQuiz, 'meaningChoice'),
        isFalse,
      );

      final typed = catalog.resolve(
        identity: first,
        mode: LessonMode.typedRecall,
        promptVariant: 'typedRecall',
      );
      expect(typed.identity, first);
      expect(typed.mode, LessonMode.typedRecall);
      expect(typed.promptVariant, 'typedRecall');
      expect(typed.promptText, words[0].meaning);
      expect(typed.answer, words[0].normalizedSpelling);
      expect(typed.options, isEmpty);
      expect(typed.word.contentRevision, words[0].contentRevision);
      expect(typed.word.contentChecksumSha256, words[0].contentChecksumSha256);
      expect(typed.typedRecallPrompt!.wordId, words[0].id);

      final meaning = catalog.resolve(
        identity: first,
        mode: LessonMode.meaningQuiz,
        promptVariant: 'meaningChoice',
      );
      expect(
        meaning.meaningQuizQuestion!.direction,
        MeaningQuizDirection.wordToMeaning,
      );
      expect(meaning.promptText, meaning.meaningQuizQuestion!.prompt);
      expect(meaning.answer, meaning.meaningQuizQuestion!.correctOption);
      expect(meaning.options, meaning.meaningQuizQuestion!.options);

      final cloze = catalog.resolve(
        identity: first,
        mode: LessonMode.cloze,
        promptVariant: 'clozeSelected',
      );
      expect(cloze.clozeQuestion, isA<ClozeQuestion>());
      expect(cloze.promptText, cloze.clozeQuestion!.prompt);
      expect(cloze.answer, cloze.clozeQuestion!.correctAnswer);

      final definition = catalog.resolve(
        identity: first,
        mode: LessonMode.definitionQuiz,
        promptVariant: 'definitionChoice',
      );
      expect(definition.definitionQuizQuestion, isA<DefinitionQuizQuestion>());
      expect(
        definition.promptText,
        definition.definitionQuizQuestion!.definition,
      );
      expect(
        definition.answer,
        definition.definitionQuizQuestion!.correctOption,
      );

      final flashcard = catalog.resolve(
        identity: first,
        mode: LessonMode.flashcard,
        promptVariant: 'flashcardExposure',
      );
      expect(flashcard.promptText, words[0].spelling);
      expect(flashcard.answer, words[0].meaning);
      expect(flashcard.options, isEmpty);
      expect(flashcard.typedRecallPrompt, isNull);
      expect(flashcard.meaningQuizQuestion, isNull);
      expect(flashcard.clozeQuestion, isNull);
      expect(flashcard.definitionQuizQuestion, isNull);
    });

    test('requires a deliverable adapter of the exact expected type', () {
      final words = _quizWords();
      final identity = _identity(words.first);
      final wrongRegistry = LessonModeRegistry(<LessonModeRegistration>[
        LessonModeRegistration(
          adapter: const _UnexpectedModeAdapter(LessonMode.meaningQuiz),
          feature: Feature.quiz,
          productionEntryId: 'test:unexpected-meaning',
          routeName: 'test/unexpected-meaning',
        ),
      ]);
      final catalog = _catalog(words: words, registry: wrongRegistry);

      expect(
        catalog.supports(identity, LessonMode.meaningQuiz, 'meaningChoice'),
        isFalse,
      );
      expect(
        () => catalog.resolve(
          identity: identity,
          mode: LessonMode.meaningQuiz,
          promptVariant: 'meaningChoice',
        ),
        throwsStateError,
      );
    });

    test(
      'Matching stays unsupported even when its registration is enabled',
      () {
        final words = _quizWords();
        final identity = _identity(words.first);

        for (final registry in <LessonModeRegistry>[
          buildLessonModeRegistry(),
          buildLessonModeRegistry(
            matchingDeliveryState: LessonModeDeliveryState.enabled,
          ),
        ]) {
          final catalog = _catalog(words: words, registry: registry);
          expect(
            catalog.supports(identity, LessonMode.matching, 'matchingPair'),
            isFalse,
          );
        }
      },
    );

    test('stale, unreviewed, and missing rich artifacts fail closed', () {
      final words = _quizWords();
      final lexical = <VocabularyWord>[
        _lexicalWord(words[0], revision: words[0].contentRevision! + 1),
        _lexicalWord(words[1], reviewState: ContentReviewState.unreviewed),
        _lexicalWord(words[3]),
      ];
      final catalog = _catalog(
        words: words,
        lexicalWords: lexical,
        direction: SessionDirection.forward,
      );

      for (final word in words.take(3)) {
        final identity = _identity(word);
        for (final modeAndPrompt in <(LessonMode, String)>[
          (LessonMode.meaningQuiz, 'meaningChoice'),
          (LessonMode.cloze, 'clozeSelected'),
          (LessonMode.definitionQuiz, 'definitionChoice'),
        ]) {
          expect(
            catalog.supports(identity, modeAndPrompt.$1, modeAndPrompt.$2),
            isFalse,
          );
        }
        expect(
          catalog.supports(identity, LessonMode.typedRecall, 'typedRecall'),
          isTrue,
        );
        expect(
          catalog.supports(identity, LessonMode.flashcard, 'flashcardExposure'),
          isTrue,
        );
      }

      expect(
        catalog.supports(
          ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: words.first.id,
            revision: words.first.contentRevision! + 1,
          ),
          LessonMode.typedRecall,
          'typedRecall',
        ),
        isFalse,
      );
    });

    test('rejects duplicate canonical IDs instead of choosing one', () {
      final words = _quizWords();

      expect(
        () => _catalog(words: <QuizWord>[words.first, words.first]),
        throwsArgumentError,
      );
      expect(
        () => _catalog(
          words: words,
          lexicalWords: <VocabularyWord>[
            _lexicalWord(words.first),
            _lexicalWord(words.first),
          ],
        ),
        throwsArgumentError,
      );
    });

    test(
      'reconstructs prompts deterministically in original session order',
      () {
        final words = _quizWords();
        final lexical = words.map(_lexicalWord).toList(growable: false);
        final first = _catalog(words: words, lexicalWords: lexical);
        final replay = _catalog(words: words, lexicalWords: lexical.reversed);

        expect(first.orderedIdentities, words.map(_identity));
        expect(replay.orderedIdentities, first.orderedIdentities);
        for (final identity in first.orderedIdentities) {
          for (final modeAndPrompt in <(LessonMode, String)>[
            (LessonMode.typedRecall, 'typedRecall'),
            (LessonMode.meaningQuiz, 'meaningChoice'),
            (LessonMode.meaningQuiz, 'wordChoice'),
            (LessonMode.cloze, 'clozeSelected'),
            (LessonMode.definitionQuiz, 'definitionChoice'),
            (LessonMode.flashcard, 'flashcardExposure'),
          ]) {
            if (!first.supports(identity, modeAndPrompt.$1, modeAndPrompt.$2)) {
              continue;
            }
            expect(
              _promptSnapshot(
                replay.resolve(
                  identity: identity,
                  mode: modeAndPrompt.$1,
                  promptVariant: modeAndPrompt.$2,
                ),
              ),
              _promptSnapshot(
                first.resolve(
                  identity: identity,
                  mode: modeAndPrompt.$1,
                  promptVariant: modeAndPrompt.$2,
                ),
              ),
            );
          }
        }

        final prompt = first.resolve(
          identity: first.orderedIdentities.first,
          mode: LessonMode.cloze,
          promptVariant: 'clozeSelected',
        );
        expect(() => prompt.options.add('mutable'), throwsUnsupportedError);
        expect(
          () => prompt.clozeQuestion!.optionIdentities['mutable'] = 'word:new',
          throwsUnsupportedError,
        );
      },
    );

    test(
      'durable snapshot reconstructs every prompt without vocabulary access',
      () {
        final words = _quizWords();
        final session = _session(words);
        final original = AdventureMixedReviewPromptCatalog(
          session: session,
          lexicalWords: words.map(_lexicalWord),
          registry: buildLessonModeRegistry(),
          direction: SessionDirection.mixed,
        );
        final encoded = original.snapshot.toJson();
        final restored = AdventureMixedReviewPromptCatalog.fromSnapshot(
          session: session,
          snapshot: AdventureMixedReviewCatalogSnapshot.fromJson(encoded),
          registry: buildLessonModeRegistry(),
          direction: SessionDirection.mixed,
        );

        for (final identity in original.orderedIdentities) {
          for (final modeAndPrompt in <(LessonMode, String)>[
            (LessonMode.typedRecall, 'typedRecall'),
            (LessonMode.meaningQuiz, 'meaningChoice'),
            (LessonMode.meaningQuiz, 'wordChoice'),
            (LessonMode.cloze, 'clozeSelected'),
            (LessonMode.definitionQuiz, 'definitionChoice'),
            (LessonMode.flashcard, 'flashcardExposure'),
          ]) {
            if (!original.supports(
              identity,
              modeAndPrompt.$1,
              modeAndPrompt.$2,
            )) {
              continue;
            }
            expect(
              _promptSnapshot(
                restored.resolve(
                  identity: identity,
                  mode: modeAndPrompt.$1,
                  promptVariant: modeAndPrompt.$2,
                ),
              ),
              _promptSnapshot(
                original.resolve(
                  identity: identity,
                  mode: modeAndPrompt.$1,
                  promptVariant: modeAndPrompt.$2,
                ),
              ),
            );
          }
        }
        expect(restored.snapshot.toJson(), encoded);

        final corrupted = Map<String, Object?>.of(encoded);
        final artifacts = (encoded['artifacts']! as List<Object?>)
            .map(
              (artifact) => Map<String, Object?>.of(
                (artifact! as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
        artifacts.first['englishDefinition'] = 'corrupted definition';
        corrupted['artifacts'] = artifacts;
        expect(
          () => AdventureMixedReviewCatalogSnapshot.fromJson(corrupted),
          throwsFormatException,
        );
      },
    );

    test('decoded snapshot does not retain the caller examples list', () {
      final words = _quizWords();
      final session = _session(words);
      final original = AdventureMixedReviewPromptCatalog(
        session: session,
        lexicalWords: words.map(_lexicalWord),
        registry: buildLessonModeRegistry(),
        direction: SessionDirection.mixed,
      );
      final sourceJson =
          (jsonDecode(jsonEncode(original.snapshot.toJson()))! as Map)
              .cast<String, Object?>();
      final decoded = AdventureMixedReviewCatalogSnapshot.fromJson(sourceJson);
      final snapshotBeforeMutation = jsonEncode(decoded.toJson());
      final artifacts = sourceJson['artifacts']! as List<Object?>;
      final firstArtifact = (artifacts.first! as Map).cast<String, Object?>();
      final sourceExamples = firstArtifact['examples']! as List<Object?>;

      sourceExamples[0] = 'The caller mutated this example.';

      expect(jsonEncode(decoded.toJson()), snapshotBeforeMutation);
      final restored = AdventureMixedReviewPromptCatalog.fromSnapshot(
        session: session,
        snapshot: decoded,
        registry: buildLessonModeRegistry(),
        direction: SessionDirection.mixed,
      );
      final identity = original.orderedIdentities.first;
      expect(
        _promptSnapshot(
          restored.resolve(
            identity: identity,
            mode: LessonMode.cloze,
            promptVariant: 'clozeSelected',
          ),
        ),
        _promptSnapshot(
          original.resolve(
            identity: identity,
            mode: LessonMode.cloze,
            promptVariant: 'clozeSelected',
          ),
        ),
      );
    });
  });
}

AdventureMixedReviewPromptCatalog _catalog({
  required List<QuizWord> words,
  Iterable<VocabularyWord>? lexicalWords,
  LessonModeRegistry? registry,
  SessionDirection direction = SessionDirection.mixed,
}) => AdventureMixedReviewPromptCatalog(
  session: _session(words),
  lexicalWords: lexicalWords ?? words.map(_lexicalWord),
  registry: registry ?? buildLessonModeRegistry(),
  direction: direction,
);

QuizSession _session(List<QuizWord> words) => QuizSession(
  id: 'session:adventure-mixed-review',
  ownerId: 'owner:one',
  startedAtUtc: DateTime.utc(2026, 9, 5, 9),
  questions: words
      .map((word) => QuizQuestion(word: word, options: const <String>[]))
      .toList(growable: false),
);

List<QuizWord> _quizWords() => const <QuizWord>[
  QuizWord(
    id: 'word:station',
    categoryId: 'category:travel',
    spelling: 'station',
    normalizedSpelling: 'station',
    meaning: 'สถานี',
    normalizedMeaning: 'สถานี',
    partOfSpeech: 'noun',
    contentRevision: 1,
    contentChecksumSha256: _checksumA,
  ),
  QuizWord(
    id: 'word:airport',
    categoryId: 'category:travel',
    spelling: 'airport',
    normalizedSpelling: 'airport',
    meaning: 'สนามบิน',
    normalizedMeaning: 'สนามบิน',
    partOfSpeech: 'noun',
    contentRevision: 2,
    contentChecksumSha256: _checksumB,
  ),
  QuizWord(
    id: 'word:market',
    categoryId: 'category:travel',
    spelling: 'market',
    normalizedSpelling: 'market',
    meaning: 'ตลาด',
    normalizedMeaning: 'ตลาด',
    partOfSpeech: 'noun',
    contentRevision: 3,
    contentChecksumSha256: _checksumC,
  ),
  QuizWord(
    id: 'word:hotel',
    categoryId: 'category:travel',
    spelling: 'hotel',
    normalizedSpelling: 'hotel',
    meaning: 'โรงแรม',
    normalizedMeaning: 'โรงแรม',
    partOfSpeech: 'noun',
    contentRevision: 4,
    contentChecksumSha256: _checksumD,
  ),
];

VocabularyWord _lexicalWord(
  QuizWord word, {
  int? revision,
  String? checksum,
  ContentReviewState reviewState = ContentReviewState.approved,
}) {
  final effectiveRevision = revision ?? word.contentRevision!;
  final effectiveChecksum = checksum ?? word.contentChecksumSha256!;
  return VocabularyWord(
    id: word.id,
    ownerId: 'owner:packaged',
    categoryId: word.categoryId,
    spelling: word.spelling,
    normalizedSpelling: word.normalizedSpelling!,
    meaning: word.meaning,
    normalizedMeaning: word.normalizedMeaning!,
    partOfSpeech: word.partOfSpeech,
    source: 'pack',
    isGlobal: true,
    localRevision: 1,
    isDeleted: false,
    createdAtUtc: DateTime.utc(2026, 8, 1),
    updatedAtUtc: DateTime.utc(2026, 8, 2),
    contentRevision: effectiveRevision,
    contentChecksumSha256: effectiveChecksum,
    contentProvenance: ContentProvenance.packaged,
    contentReviewState: reviewState,
    contentPublicationState: ContentPublicationState.published,
    richMetadata: RichLexicalMetadata(
      englishDefinition: 'Definition of ${word.spelling}',
      verifiedContentRevision: effectiveRevision,
      verifiedArtifactChecksumSha256: _artifactChecksum(word.id),
      examples: <String>['The ${word.spelling} is nearby.'],
    ),
  );
}

ContentIdentity _identity(QuizWord word) => ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: word.id,
  revision: word.contentRevision!,
);

Map<String, Object?> _promptSnapshot(
  AdventureMixedReviewPrompt prompt,
) => <String, Object?>{
  'identity':
      '${prompt.identity.type.name}:${prompt.identity.id}@${prompt.identity.revision}',
  'mode': prompt.mode.name,
  'promptVariant': prompt.promptVariant,
  'promptText': prompt.promptText,
  'answer': prompt.answer,
  'options': prompt.options,
  'wordRevision': prompt.word.contentRevision,
  'wordChecksum': prompt.word.contentChecksumSha256,
  'meaningDirection': prompt.meaningQuizQuestion?.direction.name,
  'meaningEvidenceChecksum': prompt.meaningQuizQuestion?.evidenceChecksumSha256,
  'clozeChecksum': prompt.clozeQuestion?.checksumSha256,
  'definitionChecksum': prompt.definitionQuizQuestion?.checksumSha256,
  'typedRevision': prompt.typedRecallPrompt?.contentRevision,
  'typedChecksum': prompt.typedRecallPrompt?.contentChecksumSha256,
};

String _artifactChecksum(String id) {
  final unit = switch (id) {
    'word:station' => '1',
    'word:airport' => '2',
    'word:market' => '3',
    'word:hotel' => '4',
    _ => 'f',
  };
  return unit * 64;
}

final class _UnexpectedModeAdapter implements LessonModeAdapter {
  const _UnexpectedModeAdapter(this.mode);

  @override
  final LessonMode mode;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      const LessonItem(id: 'unexpected');
}

const String _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _checksumC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _checksumD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
