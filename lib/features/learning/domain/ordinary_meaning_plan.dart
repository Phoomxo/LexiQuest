import 'dart:convert';

import '../../learning_packs/domain/content_manifest.dart';
import 'learning_models.dart';
import 'meaning_quiz_composition.dart';
import 'lexical_prompt_artifact_identity.dart';
import 'session_configuration.dart';

/// A bounded, immutable admission payload. Decoding never consults live content.
final class OrdinaryMeaningPlan {
  OrdinaryMeaningPlan._(this.session, this.content, this.questions);

  final QuizSession session;
  final List<QuizWord> content;
  final List<MeaningQuizQuestion> questions;
  static const kind = 'ordinaryMeaningQuiz';
  static const maxBytes = 65536;

  static OrdinaryMeaningPlan freeze({
    required QuizSession session,
    required Iterable<QuizWord> content,
    required List<MeaningQuizQuestion> questions,
  }) => decode(_encode(session, content, questions));

  Map<String, Object?> toJson() => _encode(session, content, questions);

  List<PinnedQuizContent> get pins => List.unmodifiable([
    for (final word in content)
      PinnedQuizContent(
        identity: ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: word.id,
          revision: word.contentRevision!,
        ),
        checksumSha256: word.contentChecksumSha256!,
      ),
  ]);

  static Map<String, Object?> _encode(
    QuizSession session,
    Iterable<QuizWord> content,
    List<MeaningQuizQuestion> questions,
  ) => {
    'kind': kind,
    'version': 1,
    'owner': session.ownerId,
    'session': session.id,
    'started': session.startedAtUtc?.millisecondsSinceEpoch,
    'configuration': session.sessionConfiguration?.stableSerialization,
    'content': [for (final word in content) _wordJson(word)],
    'questions': [
      for (final q in questions)
        {
          'word': q.word.id,
          'direction': q.direction.name,
          'prompt': q.prompt,
          'answer': q.word.id,
          'options': [
            for (final label in q.options)
              {'id': q.optionIdentity(label), 'label': label},
          ],
          'artifact': q.contrastiveChecksumSha256,
          'artifactRevision': q.contrastiveIdentity?.revision,
          'evidence': q.evidenceChecksumSha256,
        },
    ],
  };

  static Map<String, Object?> _wordJson(QuizWord w) => {
    'id': w.id,
    'category': w.categoryId,
    'spelling': w.spelling,
    'meaning': w.meaning,
    'partOfSpeech': w.partOfSpeech,
    'cefr': w.cefrLevel,
    'normalizedSpelling': w.normalizedSpelling,
    'normalizedMeaning': w.normalizedMeaning,
    'revision': w.contentRevision,
    'checksum': w.contentChecksumSha256,
  };

  static OrdinaryMeaningPlan decode(Map<String, Object?> value) {
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      throw const FormatException('Meaning plan exceeds byte budget');
    }
    final root = _map(value, {
      'kind',
      'version',
      'owner',
      'session',
      'started',
      'configuration',
      'content',
      'questions',
    });
    if (root['kind'] != kind ||
        root['version'] is! int ||
        root['version'] != 1) {
      throw const FormatException('Unknown meaning plan version');
    }
    final owner = _text(root['owner']);
    final id = _text(root['session']);
    final started = root['started'];
    if (started is! int || started < 0) {
      throw const FormatException('Invalid start');
    }
    final config = root['configuration'] == null
        ? null
        : SessionConfiguration.fromStableSerialization(
            _text(root['configuration']),
          );
    if (config != null &&
        (config.ownerId != owner || config.mode.name != 'meaningQuiz')) {
      throw const FormatException('Invalid meaning configuration');
    }
    final content = <QuizWord>[];
    final byId = <String, QuizWord>{};
    for (final raw in _list(root['content'], 100)) {
      final w = _map(raw, {
        'id',
        'category',
        'spelling',
        'meaning',
        'partOfSpeech',
        'cefr',
        'normalizedSpelling',
        'normalizedMeaning',
        'revision',
        'checksum',
      });
      final revision = w['revision'];
      if (revision is! int || revision <= 0 || !_digest(w['checksum'])) {
        throw const FormatException('Invalid content pin');
      }
      final word = QuizWord(
        id: _text(w['id']),
        categoryId: _text(w['category']),
        spelling: _text(w['spelling']),
        meaning: _text(w['meaning']),
        partOfSpeech: _text(w['partOfSpeech']),
        cefrLevel: _nullableText(w['cefr']),
        normalizedSpelling: _nullableText(w['normalizedSpelling']),
        normalizedMeaning: _nullableText(w['normalizedMeaning']),
        contentRevision: revision,
        contentChecksumSha256: w['checksum'] as String,
      );
      if (byId.containsKey(word.id)) {
        throw const FormatException('Duplicate content');
      }
      byId[word.id] = word;
      content.add(word);
    }
    final questions = <MeaningQuizQuestion>[];
    final questionIds = <String>{};
    for (final raw in _list(root['questions'], 100)) {
      final q = _map(raw, {
        'word',
        'direction',
        'prompt',
        'answer',
        'options',
        'artifact',
        'artifactRevision',
        'evidence',
      });
      final word = byId[q['word']];
      if (word == null || !questionIds.add(word.id) || q['answer'] != word.id) {
        throw const FormatException('Unknown or duplicate question/answer');
      }
      final direction = switch (q['direction']) {
        'wordToMeaning' => MeaningQuizDirection.wordToMeaning,
        'meaningToWord' => MeaningQuizDirection.meaningToWord,
        _ => throw const FormatException('Unknown direction'),
      };
      final expectedDirection = switch (config?.direction ??
          SessionDirection.mixed) {
        SessionDirection.forward => MeaningQuizDirection.wordToMeaning,
        SessionDirection.reverse => MeaningQuizDirection.meaningToWord,
        SessionDirection.mixed =>
          questions.length.isEven
              ? MeaningQuizDirection.wordToMeaning
              : MeaningQuizDirection.meaningToWord,
      };
      final forward = direction == MeaningQuizDirection.wordToMeaning;
      if (direction != expectedDirection ||
          q['prompt'] != (forward ? word.spelling : word.meaning)) {
        throw const FormatException('Prompt/configuration mismatch');
      }
      final options = <String>[];
      final identities = <String, String>{};
      final optionIds = <String>{};
      for (final rawOption in _list(q['options'], 4)) {
        final option = _map(rawOption, {'id', 'label'});
        final source = byId[option['id']];
        final label = _text(option['label']);
        if (source == null ||
            !optionIds.add(source.id) ||
            identities.containsKey(label) ||
            label != (forward ? source.meaning : source.spelling)) {
          throw const FormatException('Option content mismatch');
        }
        options.add(label);
        identities[label] = source.id;
      }
      if (options.length < 2 || !optionIds.contains(word.id)) {
        throw const FormatException('Missing answer or distractor');
      }
      final artifact = q['artifact'];
      final artifactRevision = q['artifactRevision'];
      final evidence = q['evidence'];
      if (artifact == null
          ? (artifactRevision != null || evidence != null)
          : (!_digest(artifact) ||
                artifactRevision != word.contentRevision ||
                evidence !=
                    LexicalPromptArtifactResolver.resolveForAdapter(
                      promptMode: forward ? 'meaningChoice' : 'wordChoice',
                      wordId: word.id,
                      coreRevision: word.contentRevision!,
                      coreChecksumSha256: word.contentChecksumSha256,
                      verifiedArtifactRevision: artifactRevision as int,
                      verifiedArtifactChecksumSha256: artifact as String,
                    )?.checksumSha256)) {
        throw const FormatException('Invalid lexical artifact identity');
      }
      questions.add(
        MeaningQuizQuestion(
          word: word,
          direction: direction,
          prompt: q['prompt'] as String,
          correctOption: forward ? word.meaning : word.spelling,
          options: List.unmodifiable(options),
          optionIdentities: Map.unmodifiable(identities),
          contrastiveIdentity: artifact == null
              ? null
              : ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: word.id,
                  revision: word.contentRevision!,
                ),
          contrastiveChecksumSha256: artifact as String?,
          evidenceChecksumSha256: evidence as String?,
        ),
      );
    }
    if (config != null && config.itemCount != questions.length) {
      throw const FormatException('Question count mismatch');
    }
    if (questions.indexed.any((q) => q.$2.word.id != content[q.$1].id)) {
      throw const FormatException('Question/content order mismatch');
    }
    final session = QuizSession(
      id: id,
      ownerId: owner,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(started, isUtc: true),
      sessionConfiguration: config,
      questions: canonicalQuizQuestions(questions.map((q) => q.word)),
    );
    return OrdinaryMeaningPlan._(
      session,
      List.unmodifiable(content),
      List.unmodifiable(questions),
    );
  }

  void validateBinding(
    LearningSessionDraft draft,
    List<PinnedQuizContent> pins,
  ) {
    if (draft.id != session.id ||
        draft.ownerId != session.ownerId ||
        draft.activityType != 'quiz' ||
        draft.startedAtUtc?.millisecondsSinceEpoch !=
            session.startedAtUtc?.millisecondsSinceEpoch ||
        draft.sessionConfiguration?.stableSerialization !=
            session.sessionConfiguration?.stableSerialization ||
        jsonEncode([
              for (final p in pins)
                [p.identity.id, p.identity.revision, p.checksumSha256],
            ]) !=
            jsonEncode([
              for (final p in this.pins)
                [p.identity.id, p.identity.revision, p.checksumSha256],
            ])) {
      throw const FormatException('Meaning admission binding mismatch');
    }
  }

  void validatePresentation(QuizSession presented) {
    if (presented.id != session.id ||
        presented.ownerId != session.ownerId ||
        presented.startedAtUtc != session.startedAtUtc ||
        presented.sessionConfiguration?.stableSerialization !=
            session.sessionConfiguration?.stableSerialization ||
        jsonEncode(
              presented.questions.map((q) => _wordJson(q.word)).toList(),
            ) !=
            jsonEncode(
              session.questions.map((q) => _wordJson(q.word)).toList(),
            )) {
      throw const FormatException('Meaning presentation binding mismatch');
    }
  }

  void validateCurrentContent(
    List<QuizWord> current,
    List<MeaningQuizQuestion> composed,
  ) {
    if (jsonEncode(current.map(_wordJson).toList()) !=
            jsonEncode(content.map(_wordJson).toList()) ||
        composed.length != questions.length) {
      throw const FormatException('Meaning content changed');
    }
    for (var i = 0; i < questions.length; i++) {
      if (composed[i].contrastiveChecksumSha256 !=
              questions[i].contrastiveChecksumSha256 ||
          composed[i].evidenceChecksumSha256 !=
              questions[i].evidenceChecksumSha256) {
        throw const FormatException('Meaning lexical artifact changed');
      }
    }
  }

  static Map<Object?, Object?> _map(Object? raw, Set<String> keys) {
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('Unknown/missing meaning plan fields');
    }
    return raw.cast<Object?, Object?>();
  }

  static List<Object?> _list(Object? raw, int max) {
    if (raw is! List || raw.isEmpty || raw.length > max) {
      throw const FormatException('Invalid list budget');
    }
    return raw.cast<Object?>();
  }

  static String _text(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw const FormatException('Invalid text');
    }
    return raw;
  }

  static String? _nullableText(Object? raw) => raw == null ? null : _text(raw);
  static bool _digest(Object? raw) =>
      raw is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(raw);
}
