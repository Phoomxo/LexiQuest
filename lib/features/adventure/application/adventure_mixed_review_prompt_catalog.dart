import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning/application/cloze_mode_adapter.dart';
import '../../learning/application/definition_quiz_mode_adapter.dart';
import '../../learning/application/flashcard_mode_adapter.dart';
import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/application/meaning_quiz_mode_adapter.dart';
import '../../learning/application/typed_recall_mode_adapter.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../vocabulary/domain/vocabulary_word.dart';

/// Immutable presentation and capture inputs for one exact mixed-review item.
///
/// Adapter-specific questions are retained so scoring and evidence capture can
/// continue through the canonical Learning adapter instead of being copied
/// into Adventure.
final class AdventureMixedReviewPrompt {
  AdventureMixedReviewPrompt._({
    required this.identity,
    required this.mode,
    required this.promptVariant,
    required this.promptText,
    required this.answer,
    required Iterable<String> options,
    required this.word,
    this.meaningQuizQuestion,
    this.clozeQuestion,
    this.definitionQuizQuestion,
    this.typedRecallPrompt,
  }) : options = List<String>.unmodifiable(options);

  final ContentIdentity identity;
  final LessonMode mode;
  final String promptVariant;
  final String promptText;
  final String? answer;
  final List<String> options;
  final QuizWord word;
  final MeaningQuizQuestion? meaningQuizQuestion;
  final ClozeQuestion? clozeQuestion;
  final DefinitionQuizQuestion? definitionQuizQuestion;
  final TypedRecallPrompt? typedRecallPrompt;

  String get prompt => promptText;
  String? get correctAnswer => answer;
  QuizWord get quizWord => word;
}

/// Bounded, integrity-checked presentation artifacts persisted with an
/// accepted mixed-review checkpoint. Core lexical fields remain owned by the
/// canonical [QuizSession]; this snapshot retains only verified metadata that
/// cannot be reconstructed from that session after a restart.
final class AdventureMixedReviewCatalogSnapshot {
  factory AdventureMixedReviewCatalogSnapshot.fromLexicalWords({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
  }) {
    final frozenSession = _freezeCanonicalSession(session);
    final lexicalById = _indexLexicalWords(lexicalWords);
    final artifacts = <_AdventureLexicalArtifactSnapshot>[];
    for (final question in frozenSession.questions) {
      final word = question.word;
      final lexical = lexicalById[word.id];
      final rich = lexical?.richMetadata;
      if (lexical == null ||
          !_isExactLexicalWord(word, lexical) ||
          !lexical.isGlobal ||
          lexical.contentProvenance != ContentProvenance.packaged ||
          lexical.contentReviewState != ContentReviewState.approved ||
          lexical.contentPublicationState !=
              ContentPublicationState.published ||
          rich == null ||
          rich.verifiedContentRevision != lexical.contentRevision ||
          !_isCanonicalSha256(rich.verifiedArtifactChecksumSha256)) {
        continue;
      }
      artifacts.add(
        _AdventureLexicalArtifactSnapshot.validated(
          wordId: word.id,
          coreRevision: word.contentRevision!,
          coreChecksumSha256: word.contentChecksumSha256!,
          verifiedArtifactRevision: rich.verifiedContentRevision!,
          verifiedArtifactChecksumSha256: rich.verifiedArtifactChecksumSha256!,
          englishDefinition: rich.englishDefinition,
          examples: rich.examples,
        ),
      );
    }
    return AdventureMixedReviewCatalogSnapshot._(artifacts);
  }

  factory AdventureMixedReviewCatalogSnapshot.fromJson(
    Map<String, Object?> json,
  ) {
    const keys = <String>{'schemaVersion', 'artifacts'};
    final rawArtifacts = json['artifacts'];
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['schemaVersion'] != currentSchemaVersion ||
        rawArtifacts is! List<Object?> ||
        rawArtifacts.length > _maximumArtifacts) {
      throw const FormatException(
        'invalid Adventure mixed-review catalog snapshot',
      );
    }
    final artifacts = <_AdventureLexicalArtifactSnapshot>[];
    final ids = <String>{};
    for (final raw in rawArtifacts) {
      if (raw is! Map<Object?, Object?> ||
          raw.keys.any((key) => key is! String)) {
        throw const FormatException(
          'invalid Adventure mixed-review catalog artifact',
        );
      }
      final artifact = _AdventureLexicalArtifactSnapshot.fromJson(
        raw.cast<String, Object?>(),
      );
      if (!ids.add(artifact.wordId)) {
        throw const FormatException(
          'duplicate Adventure mixed-review catalog artifact',
        );
      }
      artifacts.add(artifact);
    }
    return AdventureMixedReviewCatalogSnapshot._(artifacts);
  }

  AdventureMixedReviewCatalogSnapshot._(
    Iterable<_AdventureLexicalArtifactSnapshot> artifacts,
  ) : _artifacts = List<_AdventureLexicalArtifactSnapshot>.unmodifiable(
        artifacts,
      );

  static const int currentSchemaVersion = 1;
  static const int _maximumArtifacts = 32;

  final List<_AdventureLexicalArtifactSnapshot> _artifacts;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'artifacts': <Object?>[
      for (final artifact in _artifacts) artifact.toJson(),
    ],
  };

  List<VocabularyWord> restoreLexicalWords(QuizSession session) {
    final frozenSession = _freezeCanonicalSession(session);
    final wordsById = <String, QuizWord>{
      for (final question in frozenSession.questions)
        question.word.id: question.word,
    };
    final restored = <VocabularyWord>[];
    for (final artifact in _artifacts) {
      final word = wordsById[artifact.wordId];
      if (word == null ||
          word.contentRevision != artifact.coreRevision ||
          word.contentChecksumSha256 != artifact.coreChecksumSha256) {
        throw const FormatException(
          'Adventure mixed-review catalog core identity changed',
        );
      }
      final timestamp =
          frozenSession.startedAtUtc ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      restored.add(
        VocabularyWord(
          id: word.id,
          ownerId: frozenSession.ownerId ?? 'recovered:local',
          categoryId: word.categoryId,
          spelling: word.spelling,
          normalizedSpelling: word.normalizedSpelling ?? word.spelling,
          meaning: word.meaning,
          normalizedMeaning: word.normalizedMeaning ?? word.meaning,
          partOfSpeech: word.partOfSpeech,
          source: 'adventure-checkpoint',
          isGlobal: true,
          localRevision: 1,
          isDeleted: false,
          createdAtUtc: timestamp,
          updatedAtUtc: timestamp,
          cefrLevel: word.cefrLevel,
          contentRevision: artifact.coreRevision,
          contentChecksumSha256: artifact.coreChecksumSha256,
          contentProvenance: ContentProvenance.packaged,
          contentReviewState: ContentReviewState.approved,
          contentPublicationState: ContentPublicationState.published,
          richMetadata: RichLexicalMetadata(
            englishDefinition: artifact.englishDefinition,
            verifiedContentRevision: artifact.verifiedArtifactRevision,
            verifiedArtifactChecksumSha256:
                artifact.verifiedArtifactChecksumSha256,
            examples: artifact.examples,
          ),
        ),
      );
    }
    return List<VocabularyWord>.unmodifiable(restored);
  }
}

final class _AdventureLexicalArtifactSnapshot {
  factory _AdventureLexicalArtifactSnapshot.validated({
    required String wordId,
    required int coreRevision,
    required String coreChecksumSha256,
    required int verifiedArtifactRevision,
    required String verifiedArtifactChecksumSha256,
    required String? englishDefinition,
    required Iterable<String> examples,
  }) {
    final frozenExamples = List<String>.unmodifiable(examples);
    final payload = _validatedPayload(
      wordId: wordId,
      coreRevision: coreRevision,
      coreChecksumSha256: coreChecksumSha256,
      verifiedArtifactRevision: verifiedArtifactRevision,
      verifiedArtifactChecksumSha256: verifiedArtifactChecksumSha256,
      englishDefinition: englishDefinition,
      examples: frozenExamples,
    );
    return _AdventureLexicalArtifactSnapshot._(
      wordId: wordId,
      coreRevision: coreRevision,
      coreChecksumSha256: coreChecksumSha256,
      verifiedArtifactRevision: verifiedArtifactRevision,
      verifiedArtifactChecksumSha256: verifiedArtifactChecksumSha256,
      englishDefinition: englishDefinition,
      examples: frozenExamples,
      snapshotChecksumSha256: _checksum(payload),
    );
  }

  factory _AdventureLexicalArtifactSnapshot.fromJson(
    Map<String, Object?> json,
  ) {
    const keys = <String>{
      'wordId',
      'coreRevision',
      'coreChecksumSha256',
      'verifiedArtifactRevision',
      'verifiedArtifactChecksumSha256',
      'englishDefinition',
      'examples',
      'snapshotChecksumSha256',
    };
    final rawExamples = json['examples'];
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['wordId'] is! String ||
        json['coreRevision'] is! int ||
        json['coreChecksumSha256'] is! String ||
        json['verifiedArtifactRevision'] is! int ||
        json['verifiedArtifactChecksumSha256'] is! String ||
        json['englishDefinition'] != null &&
            json['englishDefinition'] is! String ||
        rawExamples is! List<Object?> ||
        rawExamples.any((example) => example is! String) ||
        json['snapshotChecksumSha256'] is! String) {
      throw const FormatException(
        'invalid Adventure mixed-review catalog artifact',
      );
    }
    final examples = List<String>.unmodifiable(rawExamples.cast<String>());
    final payload = _validatedPayload(
      wordId: json['wordId']! as String,
      coreRevision: json['coreRevision']! as int,
      coreChecksumSha256: json['coreChecksumSha256']! as String,
      verifiedArtifactRevision: json['verifiedArtifactRevision']! as int,
      verifiedArtifactChecksumSha256:
          json['verifiedArtifactChecksumSha256']! as String,
      englishDefinition: json['englishDefinition'] as String?,
      examples: examples,
    );
    final expectedChecksum = _checksum(payload);
    if (json['snapshotChecksumSha256'] != expectedChecksum) {
      throw const FormatException(
        'Adventure mixed-review catalog artifact checksum changed',
      );
    }
    return _AdventureLexicalArtifactSnapshot._(
      wordId: json['wordId']! as String,
      coreRevision: json['coreRevision']! as int,
      coreChecksumSha256: json['coreChecksumSha256']! as String,
      verifiedArtifactRevision: json['verifiedArtifactRevision']! as int,
      verifiedArtifactChecksumSha256:
          json['verifiedArtifactChecksumSha256']! as String,
      englishDefinition: json['englishDefinition'] as String?,
      examples: examples,
      snapshotChecksumSha256: expectedChecksum,
    );
  }

  const _AdventureLexicalArtifactSnapshot._({
    required this.wordId,
    required this.coreRevision,
    required this.coreChecksumSha256,
    required this.verifiedArtifactRevision,
    required this.verifiedArtifactChecksumSha256,
    required this.englishDefinition,
    required this.examples,
    required this.snapshotChecksumSha256,
  });

  final String wordId;
  final int coreRevision;
  final String coreChecksumSha256;
  final int verifiedArtifactRevision;
  final String verifiedArtifactChecksumSha256;
  final String? englishDefinition;
  final List<String> examples;
  final String snapshotChecksumSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    ..._payload,
    'snapshotChecksumSha256': snapshotChecksumSha256,
  };

  Map<String, Object?> get _payload => <String, Object?>{
    'wordId': wordId,
    'coreRevision': coreRevision,
    'coreChecksumSha256': coreChecksumSha256,
    'verifiedArtifactRevision': verifiedArtifactRevision,
    'verifiedArtifactChecksumSha256': verifiedArtifactChecksumSha256,
    'englishDefinition': englishDefinition,
    'examples': examples,
  };

  static Map<String, Object?> _validatedPayload({
    required String wordId,
    required int coreRevision,
    required String coreChecksumSha256,
    required int verifiedArtifactRevision,
    required String verifiedArtifactChecksumSha256,
    required String? englishDefinition,
    required List<String> examples,
  }) {
    final validDefinition =
        englishDefinition == null ||
        englishDefinition.isNotEmpty &&
            englishDefinition == englishDefinition.trim() &&
            englishDefinition.runes.length <= 600;
    final seenExamples = <String>{};
    final validExamples =
        examples.length <= 8 &&
        examples.every(
          (example) =>
              example.isNotEmpty &&
              example == example.trim() &&
              example.runes.length <= 400 &&
              seenExamples.add(example),
        );
    if (!_isCanonicalWordId(wordId) ||
        coreRevision <= 0 ||
        verifiedArtifactRevision != coreRevision ||
        !_isCanonicalSha256(coreChecksumSha256) ||
        !_isCanonicalSha256(verifiedArtifactChecksumSha256) ||
        !validDefinition ||
        !validExamples) {
      throw const FormatException(
        'invalid Adventure mixed-review catalog artifact fields',
      );
    }
    return <String, Object?>{
      'wordId': wordId,
      'coreRevision': coreRevision,
      'coreChecksumSha256': coreChecksumSha256,
      'verifiedArtifactRevision': verifiedArtifactRevision,
      'verifiedArtifactChecksumSha256': verifiedArtifactChecksumSha256,
      'englishDefinition': englishDefinition,
      'examples': List<String>.unmodifiable(examples),
    };
  }

  static String _checksum(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}

/// Pure catalog that reconstructs only prompts pinned to a canonical session.
///
/// Construction and lookup are read-only. Unsupported delivery, stale rich
/// artifacts, and non-exact identities fail closed without invoking Learning
/// evidence or repository APIs.
final class AdventureMixedReviewPromptCatalog {
  factory AdventureMixedReviewPromptCatalog({
    required QuizSession session,
    required Iterable<VocabularyWord> lexicalWords,
    required LessonModeRegistry registry,
    required SessionDirection direction,
  }) {
    final frozenSession = _freezeCanonicalSession(session);
    final lexicalById = _indexLexicalWords(lexicalWords);
    final orderedIdentities = <ContentIdentity>[];
    final exactLexicalWords = <VocabularyWord>[];
    for (final question in frozenSession.questions) {
      final word = question.word;
      orderedIdentities.add(_identityFor(word));
      final lexical = lexicalById[word.id];
      if (lexical != null && _isExactLexicalWord(word, lexical)) {
        exactLexicalWords.add(lexical);
      }
    }

    final prompts = <_AdventurePromptKey, AdventureMixedReviewPrompt>{};
    void add(AdventureMixedReviewPrompt prompt) {
      final key = _AdventurePromptKey(
        prompt.identity,
        prompt.mode,
        prompt.promptVariant,
      );
      if (prompts.containsKey(key)) {
        throw StateError('Duplicate Adventure mixed-review prompt identity.');
      }
      prompts[key] = prompt;
    }

    _pinTypedRecallPrompts(
      session: frozenSession,
      registry: registry,
      add: add,
    );
    _pinMeaningPrompts(
      session: frozenSession,
      lexicalWords: exactLexicalWords,
      registry: registry,
      direction: direction,
      add: add,
    );
    _pinClozePrompts(
      session: frozenSession,
      lexicalWords: exactLexicalWords,
      registry: registry,
      add: add,
    );
    _pinDefinitionPrompts(
      session: frozenSession,
      lexicalWords: exactLexicalWords,
      registry: registry,
      add: add,
    );
    _pinFlashcardPrompts(session: frozenSession, registry: registry, add: add);

    return AdventureMixedReviewPromptCatalog._(
      registry: registry,
      orderedIdentities: orderedIdentities,
      prompts: prompts,
      snapshot: AdventureMixedReviewCatalogSnapshot.fromLexicalWords(
        session: frozenSession,
        lexicalWords: exactLexicalWords,
      ),
    );
  }

  factory AdventureMixedReviewPromptCatalog.fromSnapshot({
    required QuizSession session,
    required AdventureMixedReviewCatalogSnapshot snapshot,
    required LessonModeRegistry registry,
    required SessionDirection direction,
  }) => AdventureMixedReviewPromptCatalog(
    session: session,
    lexicalWords: snapshot.restoreLexicalWords(session),
    registry: registry,
    direction: direction,
  );

  AdventureMixedReviewPromptCatalog._({
    required this._registry,
    required Iterable<ContentIdentity> orderedIdentities,
    required Map<_AdventurePromptKey, AdventureMixedReviewPrompt> prompts,
    required this.snapshot,
  }) : orderedIdentities = List<ContentIdentity>.unmodifiable(
         orderedIdentities,
       ),
       _prompts =
           Map<_AdventurePromptKey, AdventureMixedReviewPrompt>.unmodifiable(
             prompts,
           );

  final LessonModeRegistry _registry;
  final Map<_AdventurePromptKey, AdventureMixedReviewPrompt> _prompts;

  final AdventureMixedReviewCatalogSnapshot snapshot;

  /// Canonical content identities in the original [QuizSession] order.
  final List<ContentIdentity> orderedIdentities;

  bool supports(
    ContentIdentity identity,
    LessonMode mode,
    String promptVariant,
  ) {
    if (!_hasExpectedDeliverableAdapter(_registry, mode)) return false;
    return _prompts.containsKey(
      _AdventurePromptKey(identity, mode, promptVariant),
    );
  }

  AdventureMixedReviewPrompt resolve({
    required ContentIdentity identity,
    required LessonMode mode,
    required String promptVariant,
  }) {
    if (!supports(identity, mode, promptVariant)) {
      throw StateError(
        'Adventure mixed-review prompt is unavailable for '
        '${identity.id}@${identity.revision}, ${mode.name}/$promptVariant.',
      );
    }
    return _prompts[_AdventurePromptKey(identity, mode, promptVariant)]!;
  }
}

typedef _AddPrompt = void Function(AdventureMixedReviewPrompt prompt);

void _pinTypedRecallPrompts({
  required QuizSession session,
  required LessonModeRegistry registry,
  required _AddPrompt add,
}) {
  final adapter = registry.resolve(LessonMode.typedRecall)?.adapter;
  if (adapter is! TypedRecallModeAdapter) return;
  for (final question in session.questions) {
    final word = question.word;
    try {
      final pinned = _freezeTypedRecallPrompt(adapter.pinQuizPrompt(word));
      if (pinned.wordId != word.id ||
          pinned.contentRevision != word.contentRevision ||
          pinned.contentChecksumSha256 != word.contentChecksumSha256 ||
          pinned.promptKind != TypedRecallPromptKind.meaning) {
        continue;
      }
      add(
        AdventureMixedReviewPrompt._(
          identity: _identityFor(word),
          mode: LessonMode.typedRecall,
          promptVariant: 'typedRecall',
          promptText: word.meaning,
          answer: pinned.canonicalAnswer,
          options: const <String>[],
          word: word,
          typedRecallPrompt: pinned,
        ),
      );
    } on ArgumentError {
      // A malformed answer-set artifact is unsupported for this exact item.
    } on StateError {
      // A missing/stale prompt identity is unsupported for this exact item.
    }
  }
}

void _pinMeaningPrompts({
  required QuizSession session,
  required Iterable<VocabularyWord> lexicalWords,
  required LessonModeRegistry registry,
  required SessionDirection direction,
  required _AddPrompt add,
}) {
  final adapter = registry.resolve(LessonMode.meaningQuiz)?.adapter;
  if (adapter is! MeaningQuizModeAdapter) return;
  final questions = adapter.pinQuestions(
    session,
    direction: direction,
    lexicalWords: lexicalWords,
  );
  if (questions.length != session.questions.length) return;
  for (var index = 0; index < questions.length; index += 1) {
    final word = session.questions[index].word;
    final identity = _identityFor(word);
    final question = questions[index];
    final variant = switch (question.direction) {
      MeaningQuizDirection.wordToMeaning => 'meaningChoice',
      MeaningQuizDirection.meaningToWord => 'wordChoice',
    };
    if (!_meaningQuestionIsExact(question, word, identity)) continue;
    final pinned = _freezeMeaningQuestion(question, word);
    add(
      AdventureMixedReviewPrompt._(
        identity: identity,
        mode: LessonMode.meaningQuiz,
        promptVariant: variant,
        promptText: pinned.prompt,
        answer: pinned.correctOption,
        options: pinned.options,
        word: word,
        meaningQuizQuestion: pinned,
      ),
    );
  }
}

void _pinClozePrompts({
  required QuizSession session,
  required Iterable<VocabularyWord> lexicalWords,
  required LessonModeRegistry registry,
  required _AddPrompt add,
}) {
  final adapter = registry.resolve(LessonMode.cloze)?.adapter;
  if (adapter is! ClozeModeAdapter) return;
  final items = adapter.pinItems(session: session, lexicalWords: lexicalWords);
  if (items.length != session.questions.length) return;
  for (var index = 0; index < items.length; index += 1) {
    final word = session.questions[index].word;
    final identity = _identityFor(word);
    final question = items[index].question;
    if (question == null || !_clozeQuestionIsExact(question, identity)) {
      continue;
    }
    final pinned = _freezeClozeQuestion(question);
    add(
      AdventureMixedReviewPrompt._(
        identity: identity,
        mode: LessonMode.cloze,
        promptVariant: 'clozeSelected',
        promptText: pinned.prompt,
        answer: pinned.correctAnswer,
        options: pinned.options,
        word: word,
        clozeQuestion: pinned,
      ),
    );
  }
}

void _pinDefinitionPrompts({
  required QuizSession session,
  required Iterable<VocabularyWord> lexicalWords,
  required LessonModeRegistry registry,
  required _AddPrompt add,
}) {
  final adapter = registry.resolve(LessonMode.definitionQuiz)?.adapter;
  if (adapter is! DefinitionQuizModeAdapter) return;
  final items = adapter.pinItems(session: session, lexicalWords: lexicalWords);
  if (items.length != session.questions.length) return;
  for (var index = 0; index < items.length; index += 1) {
    final word = session.questions[index].word;
    final identity = _identityFor(word);
    final question = items[index].question;
    if (question == null || !_definitionQuestionIsExact(question, identity)) {
      continue;
    }
    final pinned = _freezeDefinitionQuestion(question);
    add(
      AdventureMixedReviewPrompt._(
        identity: identity,
        mode: LessonMode.definitionQuiz,
        promptVariant: 'definitionChoice',
        promptText: pinned.definition,
        answer: pinned.correctOption,
        options: pinned.options,
        word: word,
        definitionQuizQuestion: pinned,
      ),
    );
  }
}

void _pinFlashcardPrompts({
  required QuizSession session,
  required LessonModeRegistry registry,
  required _AddPrompt add,
}) {
  final adapter = registry.resolve(LessonMode.flashcard)?.adapter;
  if (adapter is! FlashcardModeAdapter) return;
  for (final question in session.questions) {
    final word = question.word;
    add(
      AdventureMixedReviewPrompt._(
        identity: _identityFor(word),
        mode: LessonMode.flashcard,
        promptVariant: 'flashcardExposure',
        promptText: word.spelling,
        answer: word.meaning,
        options: const <String>[],
        word: word,
      ),
    );
  }
}

bool _hasExpectedDeliverableAdapter(
  LessonModeRegistry registry,
  LessonMode mode,
) {
  final adapter = registry.resolve(mode)?.adapter;
  return switch (mode) {
    LessonMode.typedRecall => adapter is TypedRecallModeAdapter,
    LessonMode.meaningQuiz => adapter is MeaningQuizModeAdapter,
    LessonMode.cloze => adapter is ClozeModeAdapter,
    LessonMode.definitionQuiz => adapter is DefinitionQuizModeAdapter,
    LessonMode.flashcard => adapter is FlashcardModeAdapter,
    _ => false,
  };
}

QuizSession _freezeCanonicalSession(QuizSession source) {
  if (source.questions.isEmpty) {
    throw ArgumentError.value(source, 'session', 'must contain content');
  }
  final seenIds = <String>{};
  final questions = <QuizQuestion>[];
  for (final sourceQuestion in source.questions) {
    final word = _freezeQuizWord(sourceQuestion.word);
    if (!_isCanonicalWordId(word.id) ||
        word.contentRevision == null ||
        word.contentRevision! <= 0 ||
        !_isCanonicalSha256(word.contentChecksumSha256)) {
      throw ArgumentError.value(
        sourceQuestion.word,
        'session.questions',
        'must have a canonical lexical identity',
      );
    }
    if (!seenIds.add(word.id)) {
      throw ArgumentError.value(
        word.id,
        'session.questions',
        'must not contain duplicate lexical IDs',
      );
    }
    questions.add(
      QuizQuestion(
        word: word,
        options: List<String>.unmodifiable(sourceQuestion.options),
      ),
    );
  }
  return QuizSession(
    id: source.id,
    questions: List<QuizQuestion>.unmodifiable(questions),
    startedAtUtc: source.startedAtUtc,
    ownerId: source.ownerId,
    sessionConfiguration: source.sessionConfiguration,
  );
}

Map<String, VocabularyWord> _indexLexicalWords(
  Iterable<VocabularyWord> source,
) {
  final result = <String, VocabularyWord>{};
  for (final word in source) {
    if (!_isCanonicalWordId(word.id)) {
      throw ArgumentError.value(
        word.id,
        'lexicalWords',
        'must contain canonical IDs',
      );
    }
    if (result.containsKey(word.id)) {
      throw ArgumentError.value(
        word.id,
        'lexicalWords',
        'must not contain duplicate lexical IDs',
      );
    }
    result[word.id] = word;
  }
  return Map<String, VocabularyWord>.unmodifiable(result);
}

bool _isExactLexicalWord(QuizWord pinned, VocabularyWord lexical) =>
    !lexical.isDeleted &&
    lexical.id == pinned.id &&
    lexical.categoryId == pinned.categoryId &&
    lexical.spelling == pinned.spelling &&
    lexical.normalizedSpelling ==
        (pinned.normalizedSpelling ?? pinned.spelling) &&
    lexical.meaning == pinned.meaning &&
    lexical.normalizedMeaning == (pinned.normalizedMeaning ?? pinned.meaning) &&
    lexical.partOfSpeech == pinned.partOfSpeech &&
    lexical.cefrLevel == pinned.cefrLevel &&
    lexical.contentRevision == pinned.contentRevision &&
    lexical.contentChecksumSha256 == pinned.contentChecksumSha256;

bool _meaningQuestionIsExact(
  MeaningQuizQuestion question,
  QuizWord word,
  ContentIdentity identity,
) =>
    question.word.id == word.id &&
    question.word.contentRevision == word.contentRevision &&
    question.word.contentChecksumSha256 == word.contentChecksumSha256 &&
    question.contrastiveIdentity == identity &&
    _isCanonicalSha256(question.contrastiveChecksumSha256) &&
    _isCanonicalSha256(question.evidenceChecksumSha256) &&
    question.prompt.isNotEmpty &&
    question.options.contains(question.correctOption) &&
    question.optionIdentity(question.correctOption) == word.id;

bool _clozeQuestionIsExact(ClozeQuestion question, ContentIdentity identity) =>
    question.wordId == identity.id &&
    question.identity == identity &&
    _isCanonicalSha256(question.checksumSha256) &&
    _isCanonicalSha256(question.manifestChecksumSha256) &&
    question.prompt.isNotEmpty &&
    question.options.contains(question.correctAnswer) &&
    question.optionIdentity(question.correctAnswer) == identity.id;

bool _definitionQuestionIsExact(
  DefinitionQuizQuestion question,
  ContentIdentity identity,
) =>
    question.wordId == identity.id &&
    question.identity == identity &&
    _isCanonicalSha256(question.checksumSha256) &&
    _isCanonicalSha256(question.manifestChecksumSha256) &&
    question.definition.isNotEmpty &&
    question.options.contains(question.correctOption) &&
    question.optionIdentity(question.correctOption) == identity.id;

QuizWord _freezeQuizWord(QuizWord source) => QuizWord(
  id: source.id,
  categoryId: source.categoryId,
  spelling: source.spelling,
  meaning: source.meaning,
  partOfSpeech: source.partOfSpeech,
  cefrLevel: source.cefrLevel,
  normalizedSpelling: source.normalizedSpelling,
  normalizedMeaning: source.normalizedMeaning,
  contentRevision: source.contentRevision,
  contentChecksumSha256: source.contentChecksumSha256,
  acceptedSpellingVariants: List<String>.unmodifiable(
    source.acceptedSpellingVariants,
  ),
  acceptedSpellingVariantsRevision: source.acceptedSpellingVariantsRevision,
  acceptedSpellingVariantsChecksumSha256:
      source.acceptedSpellingVariantsChecksumSha256,
);

MeaningQuizQuestion _freezeMeaningQuestion(
  MeaningQuizQuestion source,
  QuizWord word,
) => MeaningQuizQuestion(
  word: word,
  direction: source.direction,
  prompt: source.prompt,
  correctOption: source.correctOption,
  options: List<String>.unmodifiable(source.options),
  optionIdentities: Map<String, String>.unmodifiable(source.optionIdentities),
  contrastiveIdentity: source.contrastiveIdentity,
  contrastiveChecksumSha256: source.contrastiveChecksumSha256,
  evidenceChecksumSha256: source.evidenceChecksumSha256,
);

ClozeQuestion _freezeClozeQuestion(ClozeQuestion source) => ClozeQuestion(
  wordId: source.wordId,
  identity: source.identity,
  checksumSha256: source.checksumSha256,
  manifestChecksumSha256: source.manifestChecksumSha256,
  prompt: source.prompt,
  correctAnswer: source.correctAnswer,
  options: List<String>.unmodifiable(source.options),
  optionIdentities: Map<String, String>.unmodifiable(source.optionIdentities),
);

DefinitionQuizQuestion _freezeDefinitionQuestion(
  DefinitionQuizQuestion source,
) => DefinitionQuizQuestion(
  wordId: source.wordId,
  identity: source.identity,
  checksumSha256: source.checksumSha256,
  manifestChecksumSha256: source.manifestChecksumSha256,
  definition: source.definition,
  correctOption: source.correctOption,
  options: List<String>.unmodifiable(source.options),
  partOfSpeech: source.partOfSpeech,
  optionIdentities: Map<String, String>.unmodifiable(source.optionIdentities),
);

TypedRecallPrompt _freezeTypedRecallPrompt(TypedRecallPrompt source) =>
    TypedRecallPrompt(
      wordId: source.wordId,
      canonicalAnswer: source.canonicalAnswer,
      acceptedVariants: source.acceptedVariants,
      acceptedVariantsRevision: source.acceptedVariantsRevision,
      acceptedVariantsChecksumSha256: source.acceptedVariantsChecksumSha256,
      promptKind: source.promptKind,
      normalizationRevision: source.normalizationRevision,
      contentRevision: source.contentRevision,
      contentChecksumSha256: source.contentChecksumSha256,
    );

ContentIdentity _identityFor(QuizWord word) => ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: word.id,
  revision: word.contentRevision!,
);

bool _isCanonicalWordId(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= 256 &&
    !value.contains('@') &&
    !_control.hasMatch(value);

bool _isCanonicalSha256(String? value) =>
    value != null && _sha256.hasMatch(value);

final class _AdventurePromptKey {
  const _AdventurePromptKey(this.identity, this.mode, this.promptVariant);

  final ContentIdentity identity;
  final LessonMode mode;
  final String promptVariant;

  @override
  bool operator ==(Object other) =>
      other is _AdventurePromptKey &&
      other.identity == identity &&
      other.mode == mode &&
      other.promptVariant == promptVariant;

  @override
  int get hashCode => Object.hash(identity, mode, promptVariant);
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _control = RegExp(r'[\u0000-\u001f\u007f-\u009f]', unicode: true);
