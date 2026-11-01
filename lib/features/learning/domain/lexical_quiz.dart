part of 'accepted_quiz_plan.dart';

final class LexicalQuizSettings {
  const LexicalQuizSettings({
    this.advisoryMinutes,
    this.manualAudio = false,
    this.accessibleInput = false,
    this.reduceMotion = false,
  });
  final int? advisoryMinutes;
  final bool manualAudio;
  final bool accessibleInput;
  final bool reduceMotion;

  void validate() {
    final minutes = advisoryMinutes;
    if (minutes != null && (minutes < 1 || minutes > 180)) {
      throw const FormatException('Advisory time goal must be 1..180 minutes.');
    }
  }

  Map<String, Object?> toJson() => {
    'advisoryMinutes': advisoryMinutes,
    'manualAudio': manualAudio,
    'accessibleInput': accessibleInput,
    'reduceMotion': reduceMotion,
  };

  factory LexicalQuizSettings.fromJson(Map<String, Object?> body) {
    _keys(body, {
      'advisoryMinutes',
      'manualAudio',
      'accessibleInput',
      'reduceMotion',
    });
    final settings = LexicalQuizSettings(
      advisoryMinutes: _nullableInt(body['advisoryMinutes'], 'advisoryMinutes'),
      manualAudio: _bool(body['manualAudio'], 'manualAudio'),
      accessibleInput: _bool(body['accessibleInput'], 'accessibleInput'),
      reduceMotion: _bool(body['reduceMotion'], 'reduceMotion'),
    );
    settings.validate();
    return settings;
  }
}

final class LexicalQuizConfiguration {
  LexicalQuizConfiguration({
    required this.packVersionId,
    required Iterable<String> entryCodes,
    required this.input,
    required this.limit,
    this.settings = const LexicalQuizSettings(),
  }) : entryCodes = List.unmodifiable(entryCodes) {
    _identifier(packVersionId, 'packVersionId');
    if (limit < 1 ||
        limit > 100 ||
        this.entryCodes.isEmpty ||
        this.entryCodes.length > 100 ||
        this.entryCodes.toSet().length != this.entryCodes.length) {
      throw const FormatException('Invalid authored definition selection.');
    }
    for (final code in this.entryCodes) {
      if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,79}$').hasMatch(code)) {
        throw const FormatException('Invalid authored entry code.');
      }
    }
    settings.validate();
  }
  final String packVersionId;
  final List<String> entryCodes;
  final LexicalQuizInput input;
  final int limit;
  final LexicalQuizSettings settings;

  Map<String, Object?> configurationJson(List<String> words, int? accepted) => {
    'policyVersion': 'definition-quiz-configuration-v1',
    'requestedItemCount': limit,
    'acceptedItemCount': ?accepted,
    'direction': 'definition-to-word',
    'inputMode': input.name,
    'hintPolicy': 'authored-optional-definition-assistance-v1',
    'revealPolicy': QuizConfiguration.revealPolicy,
    'selection': {
      'kind': 'authoredPack',
      'packVersionId': packVersionId,
      'entryCodes': entryCodes,
      'requestedWordIds': words,
    },
    'settings': settings.toJson(),
  };
}

final class LexicalPackPin {
  LexicalPackPin({
    required this.ownerId,
    required this.packVersionId,
    required this.packId,
    required this.version,
    required this.packageSha256,
    required this.manifestSha256,
  }) {
    _identifier(ownerId, 'ownerId');
    _identifier(packVersionId, 'packVersionId');
    _identifier(packId, 'packId');
    _identifier(version, 'version');
    _sha(packageSha256, 'packageSha256');
    _sha(manifestSha256, 'manifestSha256');
  }
  final String ownerId;
  final String packVersionId;
  final String packId;
  final String version;
  final String packageSha256;
  final String manifestSha256;
  Map<String, Object?> toJson() => {
    'ownerId': ownerId,
    'packVersionId': packVersionId,
    'packId': packId,
    'version': version,
    'packageSha256': packageSha256,
    'manifestSha256': manifestSha256,
  };
  factory LexicalPackPin.fromJson(Map<String, Object?> body) {
    _keys(body, {
      'ownerId',
      'packVersionId',
      'packId',
      'version',
      'packageSha256',
      'manifestSha256',
    });
    return LexicalPackPin(
      ownerId: _string(body['ownerId'], 'ownerId'),
      packVersionId: _string(body['packVersionId'], 'packVersionId'),
      packId: _string(body['packId'], 'packId'),
      version: _string(body['version'], 'version'),
      packageSha256: _string(body['packageSha256'], 'packageSha256'),
      manifestSha256: _string(body['manifestSha256'], 'manifestSha256'),
    );
  }
}

final class LexicalEntryPin {
  LexicalEntryPin({
    required this.snapshotId,
    required this.wordRevision,
    required this.word,
    required String entryJson,
  }) : entry = const LearningPackCodec().decodeEntry(entryJson) {
    _identifier(snapshotId, 'snapshotId');
    _validateWord(word);
    if (wordRevision < 1 ||
        entry.canonicalJson != entryJson ||
        word.contentRevision != 'local-vocabulary-v1:$wordRevision' ||
        word.spelling != entry.spelling ||
        word.meaning != entry.meaning ||
        word.partOfSpeech != entry.partOfSpeech) {
      throw const FormatException('Lexical snapshot contradicts its word.');
    }
  }
  final String snapshotId;
  final int wordRevision;
  final QuizWord word;
  final LearningPackEntry entry;
  Map<String, Object?> toJson() => {
    'snapshotId': snapshotId,
    'wordRevision': wordRevision,
    'word': _lexicalWordJson(word),
    'entryJson': entry.canonicalJson,
    'entrySha256': entry.contentSha256,
  };
  factory LexicalEntryPin.fromJson(Map<String, Object?> body) {
    _keys(body, {
      'snapshotId',
      'wordRevision',
      'word',
      'entryJson',
      'entrySha256',
    });
    final pin = LexicalEntryPin(
      snapshotId: _string(body['snapshotId'], 'snapshotId'),
      wordRevision: _int(body['wordRevision'], 'wordRevision'),
      word: _lexicalWordFromJson(_map(body['word'], 'word')),
      entryJson: _string(body['entryJson'], 'entryJson'),
    );
    if (pin.entry.contentSha256 != body['entrySha256']) {
      throw const FormatException('Lexical entry hash changed.');
    }
    return pin;
  }
}

sealed class LexicalQuestionContent {
  LexicalQuestionContent({required this.source, required this.target});
  final LexicalPackPin source;
  final LexicalEntryPin target;
  LexicalQuizInput get input;
  List<String> get optionLabels;
  Iterable<LexicalEntryPin> get pins;
  Map<String, Object?> toJson();
  String get contentRevision =>
      'lexical-definition-v1:${sha256.convert(utf8.encode(jsonEncode(toJson())))}';
  void validate() {
    final definition = target.entry.definition;
    if (definition == null || definition.trim().isEmpty) {
      throw const FormatException(
        'An authored English definition is required.',
      );
    }
  }

  static LexicalQuestionContent fromJson(Map<String, Object?> body) {
    final source = LexicalPackPin.fromJson(_map(body['source'], 'source'));
    final target = LexicalEntryPin.fromJson(_map(body['target'], 'target'));
    if (body['kind'] == 'definitionTyped') {
      _keys(body, {'kind', 'source', 'target'});
      return DefinitionTypedContent(source: source, target: target);
    }
    if (body['kind'] == 'definitionChoice') {
      _keys(body, {'kind', 'source', 'target', 'options'});
      return DefinitionChoiceContent(
        source: source,
        target: target,
        options: _list(body['options'], 'options').map(
          (value) => LexicalDefinitionOption.fromJson(_map(value, 'option')),
        ),
      );
    }
    throw const FormatException('Unknown lexical question variant.');
  }
}

final class DefinitionTypedContent extends LexicalQuestionContent {
  DefinitionTypedContent({required super.source, required super.target}) {
    validate();
  }
  @override
  LexicalQuizInput get input => LexicalQuizInput.definitionTyped;
  @override
  List<String> get optionLabels => const [];
  @override
  Iterable<LexicalEntryPin> get pins => [target];
  @override
  Map<String, Object?> toJson() => {
    'kind': input.name,
    'source': source.toJson(),
    'target': target.toJson(),
  };
}

final class LexicalDefinitionOption {
  const LexicalDefinitionOption({
    required this.code,
    required this.pin,
    this.contrastiveExplanation,
  });
  final String code;
  final LexicalEntryPin pin;
  final String? contrastiveExplanation;
  Map<String, Object?> toJson() => {
    'code': code,
    'pin': pin.toJson(),
    'contrastiveExplanation': contrastiveExplanation,
  };
  factory LexicalDefinitionOption.fromJson(Map<String, Object?> body) {
    _keys(body, {'code', 'pin', 'contrastiveExplanation'});
    return LexicalDefinitionOption(
      code: _string(body['code'], 'code'),
      pin: LexicalEntryPin.fromJson(_map(body['pin'], 'pin')),
      contrastiveExplanation: _nullableString(
        body['contrastiveExplanation'],
        'contrastiveExplanation',
      ),
    );
  }
}

final class DefinitionChoiceContent extends LexicalQuestionContent {
  DefinitionChoiceContent({
    required super.source,
    required super.target,
    required Iterable<LexicalDefinitionOption> options,
  }) : authoredOptions = List.unmodifiable(options) {
    validate();
  }
  final List<LexicalDefinitionOption> authoredOptions;
  @override
  LexicalQuizInput get input => LexicalQuizInput.definitionChoice;
  @override
  List<String> get optionLabels => List.unmodifiable([
    for (final option in authoredOptions) option.pin.word.spelling,
  ]);
  @override
  Iterable<LexicalEntryPin> get pins => [
    target,
    for (final option in authoredOptions) option.pin,
  ];
  @override
  void validate() {
    super.validate();
    final authored = target.entry.definitionQuestion;
    if (authored == null ||
        authoredOptions.length < 2 ||
        authoredOptions.length > 4 ||
        authored.options.length != authoredOptions.length ||
        optionLabels.map(normalizeLexicalResponse).toSet().length !=
            authoredOptions.length) {
      throw const FormatException(
        'Distinct authored definition options are required.',
      );
    }
    var correct = 0;
    for (var i = 0; i < authoredOptions.length; i++) {
      final option = authoredOptions[i];
      final expected = authored.options[i];
      if (option.code != expected.code ||
          option.pin.entry.code != expected.entryCode ||
          option.contrastiveExplanation != expected.contrastiveExplanation) {
        throw const FormatException('Authored definition option pins changed.');
      }
      if (option.code == authored.correctOptionCode) {
        correct++;
        if (jsonEncode(option.pin.toJson()) != jsonEncode(target.toJson())) {
          throw const FormatException(
            'Correct authored option is not the target.',
          );
        }
      }
    }
    if (correct != 1) {
      throw const FormatException(
        'Exactly one authored correct option is required.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': input.name,
    'source': source.toJson(),
    'target': target.toJson(),
    'options': [for (final option in authoredOptions) option.toJson()],
  };
}

String normalizeLexicalResponse(String value) => value.trim().toLowerCase();

sealed class LexicalQuizLocalData {
  const LexicalQuizLocalData();
  Map<String, Object?> toJson();
  LexicalQuizLocalData nextQuestion();
  static LexicalQuizLocalData initial(LexicalQuizInput input) =>
      switch (input) {
        LexicalQuizInput.definitionChoice => const LexicalChoiceLocalData(),
        LexicalQuizInput.definitionTyped => LexicalTypedLocalData(),
      };
  static LexicalQuizLocalData fromJson(Map<String, Object?> body) {
    if (body['kind'] == 'definitionChoice') {
      _keys(body, {'kind'});
      return const LexicalChoiceLocalData();
    }
    _keys(body, {'kind', 'draft', 'responses'});
    if (body['kind'] != 'definitionTyped') {
      throw const FormatException('Unknown local lexical state.');
    }
    final responses = <int, String?>{};
    for (final value in _list(body['responses'], 'responses')) {
      final response = _map(value, 'response');
      _keys(response, {'ordinal', 'text'});
      final ordinal = _int(response['ordinal'], 'ordinal');
      if (responses.containsKey(ordinal)) {
        throw const FormatException('Duplicate private response.');
      }
      responses[ordinal] = _nullableString(response['text'], 'text');
    }
    return LexicalTypedLocalData(
      draft: _string(body['draft'], 'draft'),
      responses: responses,
    );
  }
}

final class LexicalChoiceLocalData extends LexicalQuizLocalData {
  const LexicalChoiceLocalData();
  @override
  Map<String, Object?> toJson() => {'kind': 'definitionChoice'};
  @override
  LexicalChoiceLocalData nextQuestion() => this;
}

final class LexicalTypedLocalData extends LexicalQuizLocalData {
  LexicalTypedLocalData({
    this.draft = '',
    Map<int, String?> responses = const {},
  }) : responses = Map.unmodifiable(responses) {
    if (draft.length > 512 ||
        this.responses.length > 100 ||
        this.responses.entries.any(
          (entry) =>
              entry.key < 0 ||
              entry.key >= 100 ||
              (entry.value != null &&
                  (entry.value!.length > 512 || entry.value!.trim().isEmpty)),
        )) {
      throw const FormatException('Invalid private typed response.');
    }
  }
  final String draft;
  final Map<int, String?> responses;
  LexicalTypedLocalData withDraft(String text) =>
      LexicalTypedLocalData(draft: text, responses: responses);
  LexicalTypedLocalData withAnswer(int ordinal, String? text) =>
      LexicalTypedLocalData(
        draft: draft,
        responses: {...responses, ordinal: text},
      );
  @override
  LexicalTypedLocalData nextQuestion() =>
      LexicalTypedLocalData(responses: responses);
  @override
  Map<String, Object?> toJson() => {
    'kind': 'definitionTyped',
    'draft': draft,
    'responses': [
      for (final ordinal in responses.keys.toList()..sort())
        {'ordinal': ordinal, 'text': responses[ordinal]},
    ],
  };
}

Map<String, Object?> _lexicalWordJson(QuizWord word) => {
  'id': word.id,
  'categoryId': word.categoryId,
  'spelling': word.spelling,
  'meaning': word.meaning,
  'partOfSpeech': word.partOfSpeech,
  'contentRevision': word.contentRevision,
  'checksumSha256': quizWordChecksum(word),
};

QuizWord _lexicalWordFromJson(Map<String, Object?> body) {
  _keys(body, {
    'id',
    'categoryId',
    'spelling',
    'meaning',
    'partOfSpeech',
    'contentRevision',
    'checksumSha256',
  });
  final word = QuizWord(
    id: _string(body['id'], 'id'),
    categoryId: _string(body['categoryId'], 'categoryId'),
    spelling: _string(body['spelling'], 'spelling'),
    meaning: _string(body['meaning'], 'meaning'),
    partOfSpeech: _string(body['partOfSpeech'], 'partOfSpeech'),
    contentRevision: _string(body['contentRevision'], 'contentRevision'),
  );
  if (body['checksumSha256'] != quizWordChecksum(word)) {
    throw const FormatException('Pinned lexical word hash changed.');
  }
  return word;
}

Map<String, Object?> _lexicalPlanJson(AcceptedQuizPlan plan) => {
  'schemaVersion': 2,
  'mode': plan.mode,
  'activityType': plan.activityType,
  'configuration': plan.configuration.toJson(
    acceptedItemCount: plan.questions.length,
  ),
  'questionBuilderVersion': 'authored-definition-deck-v1',
  'evidencePolicyVersion': plan.evidencePolicyVersion,
  'featureContractRevision': plan.featureContractRevision,
  'featureContractHash': plan.featureContractHash,
  'questions': [
    for (var i = 0; i < plan.questions.length; i++)
      {'ordinal': i, 'content': plan.questions[i].lexical!.toJson()},
  ],
};

AcceptedQuizPlan _parseLexicalPlan(
  String id,
  String json,
  Map<String, Object?> body,
) {
  _keys(body, {
    'schemaVersion',
    'mode',
    'activityType',
    'configuration',
    'questionBuilderVersion',
    'evidencePolicyVersion',
    'featureContractRevision',
    'featureContractHash',
    'questions',
  });
  if (body['mode'] != 'definition-quiz' ||
      body['questionBuilderVersion'] != 'authored-definition-deck-v1') {
    throw const FormatException('Unsupported lexical plan.');
  }
  final config = _map(body['configuration'], 'configuration');
  _keys(config, {
    'policyVersion',
    'requestedItemCount',
    'acceptedItemCount',
    'direction',
    'inputMode',
    'hintPolicy',
    'revealPolicy',
    'selection',
    'settings',
  });
  final selection = _map(config['selection'], 'selection');
  _keys(selection, {'kind', 'packVersionId', 'entryCodes', 'requestedWordIds'});
  if (selection['kind'] != 'authoredPack') {
    throw const FormatException('Invalid lexical selection.');
  }
  final input = LexicalQuizInput.values.firstWhere(
    (input) => input.name == config['inputMode'],
    orElse: () => throw const FormatException('Unknown lexical input mode.'),
  );
  final configuration = QuizConfiguration.lexical(
    lexical: LexicalQuizConfiguration(
      packVersionId: _string(selection['packVersionId'], 'packVersionId'),
      entryCodes: _list(
        selection['entryCodes'],
        'entryCodes',
      ).map((e) => _string(e, 'entryCode')),
      input: input,
      limit: _int(config['requestedItemCount'], 'requestedItemCount'),
      settings: LexicalQuizSettings.fromJson(
        _map(config['settings'], 'settings'),
      ),
    ),
    wordIds: _list(
      selection['requestedWordIds'],
      'requestedWordIds',
    ).map((e) => _string(e, 'wordId')),
  );
  final values = _list(body['questions'], 'questions');
  if (values.length > 100) {
    throw const FormatException('Too many lexical questions.');
  }
  final questions = <QuizQuestion>[];
  for (var i = 0; i < values.length; i++) {
    final value = _map(values[i], 'question');
    _keys(value, {'ordinal', 'content'});
    if (value['ordinal'] != i) {
      throw const FormatException('Lexical question order changed.');
    }
    questions.add(
      QuizQuestion.lexical(
        LexicalQuestionContent.fromJson(_map(value['content'], 'content')),
      ),
    );
  }
  final plan = AcceptedQuizPlan._(
    configuration: configuration,
    questions: questions,
    evidencePolicyVersion: _string(
      body['evidencePolicyVersion'],
      'evidencePolicyVersion',
    ),
    featureContractRevision: _string(
      body['featureContractRevision'],
      'featureContractRevision',
    ),
    featureContractHash: _string(
      body['featureContractHash'],
      'featureContractHash',
    ),
  );
  if (body['activityType'] != plan.activityType ||
      config['acceptedItemCount'] != questions.length ||
      plan.stableSerialization != json ||
      plan.id != id) {
    throw const FormatException('Lexical plan identity changed.');
  }
  return plan;
}
