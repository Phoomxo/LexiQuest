import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../product/feature_contract/feature_contract_digest.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'learning_models.dart';

enum QuizSelectionKind { category, wordIds, weakness }

final class QuizConfiguration {
  QuizConfiguration.category({String? categoryId, int limit = 10})
    : this._(
        selectionKind: QuizSelectionKind.category,
        categoryId: categoryId,
        wordIds: const [],
        requestedItemCount: limit,
      );

  QuizConfiguration.sourcePractice({
    required Iterable<String> wordIds,
    int limit = 20,
  }) : this._(
         selectionKind: QuizSelectionKind.wordIds,
         categoryId: null,
         wordIds: wordIds,
         requestedItemCount: limit,
       );

  QuizConfiguration.weaknessPractice({
    required Iterable<String> wordIds,
    int limit = 20,
  }) : this._(
         selectionKind: QuizSelectionKind.weakness,
         categoryId: null,
         wordIds: wordIds,
         requestedItemCount: limit,
       );

  QuizConfiguration._({
    required this.selectionKind,
    required this.categoryId,
    required Iterable<String> wordIds,
    required this.requestedItemCount,
  }) : wordIds = List.unmodifiable(wordIds.toSet().toList()..sort()) {
    if (requestedItemCount < 1 || requestedItemCount > 100) {
      throw const FormatException('Quiz item count must be 1..100.');
    }
    if (categoryId != null) _identifier(categoryId!, 'categoryId');
    for (final id in this.wordIds) {
      _identifier(id, 'wordId');
    }
    if (selectionKind == QuizSelectionKind.category) {
      if (this.wordIds.isNotEmpty) {
        throw const FormatException(
          'Category selection cannot contain word IDs.',
        );
      }
    } else if (categoryId != null || this.wordIds.isEmpty) {
      throw const FormatException('Target selection requires word IDs only.');
    }
    if (utf8.encode(stableSerialization).length > maxSerializedBytes) {
      throw const FormatException(
        'Quiz configuration exceeds its byte budget.',
      );
    }
  }

  static const maxSerializedBytes = 1024 * 1024;
  static const policyVersion = 'meaning-quiz-configuration-v1';
  static const hintPolicy = 'current-optional-meaning-hint-v1';
  static const revealPolicy = 'current-reveal-counts-wrong-v1';

  final QuizSelectionKind selectionKind;
  final String? categoryId;
  final List<String> wordIds;
  final int requestedItemCount;

  String get activityType => switch (selectionKind) {
    QuizSelectionKind.category => 'quiz',
    QuizSelectionKind.wordIds => 'sourcePractice',
    QuizSelectionKind.weakness => 'weaknessPractice',
  };

  Map<String, Object?> toJson({int? acceptedItemCount}) => {
    'policyVersion': policyVersion,
    'requestedItemCount': requestedItemCount,
    'acceptedItemCount': ?acceptedItemCount,
    'direction': 'forward',
    'inputMode': 'meaningChoice',
    'hintPolicy': hintPolicy,
    'revealPolicy': revealPolicy,
    'selection': {
      'kind': selectionKind.name,
      'categoryId': categoryId,
      'requestedWordIds': wordIds,
    },
  };

  late final String stableSerialization = jsonEncode(toJson());

  static QuizConfiguration _fromJson(Map<String, Object?> body) {
    _keys(body, {
      'policyVersion',
      'requestedItemCount',
      'acceptedItemCount',
      'direction',
      'inputMode',
      'hintPolicy',
      'revealPolicy',
      'selection',
    });
    if (body['policyVersion'] != policyVersion ||
        body['direction'] != 'forward' ||
        body['inputMode'] != 'meaningChoice' ||
        body['hintPolicy'] != hintPolicy ||
        body['revealPolicy'] != revealPolicy) {
      throw const FormatException('Unsupported quiz configuration.');
    }
    final selection = _map(body['selection'], 'selection');
    _keys(selection, {'kind', 'categoryId', 'requestedWordIds'});
    final kind = switch (selection['kind']) {
      'category' => QuizSelectionKind.category,
      'wordIds' => QuizSelectionKind.wordIds,
      'weakness' => QuizSelectionKind.weakness,
      _ => throw const FormatException('Unsupported quiz selection.'),
    };
    return QuizConfiguration._(
      selectionKind: kind,
      categoryId: _nullableString(selection['categoryId'], 'categoryId'),
      wordIds: _list(
        selection['requestedWordIds'],
        'requestedWordIds',
      ).map((id) => _string(id, 'wordId')),
      requestedItemCount: _int(
        body['requestedItemCount'],
        'requestedItemCount',
      ),
    );
  }
}

final class AcceptedQuizPlan {
  AcceptedQuizPlan._({
    required this.configuration,
    required Iterable<QuizQuestion> questions,
    required this.evidencePolicyVersion,
    required this.featureContractRevision,
    required this.featureContractHash,
  }) : questions = List.unmodifiable(
         questions.map(
           (question) => QuizQuestion(
             word: question.word,
             options: List.unmodifiable(question.options),
           ),
         ),
       ) {
    _identifier(evidencePolicyVersion, 'evidencePolicyVersion');
    _identifier(featureContractRevision, 'featureContractRevision');
    _sha(featureContractHash, 'featureContractHash');
    if (this.questions.isEmpty ||
        this.questions.length > configuration.requestedItemCount) {
      throw const FormatException('Invalid accepted quiz item count.');
    }
    final seen = <String>{};
    for (final question in this.questions) {
      _validateQuestion(question);
      final word = question.word;
      if (!seen.add(word.id)) {
        throw const FormatException('A quiz word can occur only once.');
      }
      if (configuration.selectionKind == QuizSelectionKind.category) {
        if (configuration.categoryId != null &&
            configuration.categoryId != word.categoryId) {
          throw const FormatException(
            'Question is outside the selected category.',
          );
        }
      } else if (!configuration.wordIds.contains(word.id)) {
        throw const FormatException(
          'Question is outside the selected word IDs.',
        );
      }
    }
  }

  factory AcceptedQuizPlan.create({
    required QuizConfiguration configuration,
    required Iterable<QuizQuestion> questions,
  }) => AcceptedQuizPlan._(
    configuration: configuration,
    questions: questions,
    evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
    featureContractRevision: currentFeatureContractIdentity.revision,
    featureContractHash: currentFeatureContractIdentity.semanticHash,
  );

  factory AcceptedQuizPlan.parse({required String id, required String json}) {
    if (json.length > maxSerializedBytes ||
        utf8.encode(json).length > maxSerializedBytes) {
      throw const FormatException(
        'Accepted quiz plan exceeds its byte budget.',
      );
    }
    final body = _map(jsonDecode(json), 'accepted quiz plan');
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
    if (body['schemaVersion'] != 1 ||
        body['mode'] != 'meaning-quiz' ||
        body['questionBuilderVersion'] != 'current-meaning-options-v1') {
      throw const FormatException('Unsupported accepted quiz plan.');
    }
    final configurationBody = _map(body['configuration'], 'configuration');
    final configuration = QuizConfiguration._fromJson(configurationBody);
    final values = _list(body['questions'], 'questions');
    if (values.length > 100) {
      throw const FormatException('Too many accepted quiz questions.');
    }
    final questions = <QuizQuestion>[];
    for (var ordinal = 0; ordinal < values.length; ordinal++) {
      final value = _map(values[ordinal], 'question');
      _keys(value, {
        'ordinal',
        'wordId',
        'categoryId',
        'spelling',
        'meaning',
        'partOfSpeech',
        'contentRevision',
        'contentChecksumSha256',
        'options',
        'correctOptionOrdinal',
      });
      final word = QuizWord(
        id: _string(value['wordId'], 'wordId'),
        categoryId: _string(value['categoryId'], 'categoryId'),
        spelling: _string(value['spelling'], 'spelling'),
        meaning: _string(value['meaning'], 'meaning'),
        partOfSpeech: _string(value['partOfSpeech'], 'partOfSpeech'),
        contentRevision: _string(value['contentRevision'], 'contentRevision'),
      );
      final options = _list(
        value['options'],
        'options',
      ).map((option) => _string(option, 'option')).toList(growable: false);
      if (value['ordinal'] != ordinal ||
          value['contentChecksumSha256'] != quizWordChecksum(word) ||
          value['correctOptionOrdinal'] != options.indexOf(word.meaning)) {
        throw const FormatException('Question pins do not match its content.');
      }
      questions.add(QuizQuestion(word: word, options: options));
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
        configurationBody['acceptedItemCount'] != plan.questions.length ||
        plan.stableSerialization != json ||
        plan.id != id) {
      throw const FormatException(
        'Accepted quiz plan identity is inconsistent.',
      );
    }
    return plan;
  }

  final QuizConfiguration configuration;
  final List<QuizQuestion> questions;
  final String evidencePolicyVersion;
  final String featureContractRevision;
  final String featureContractHash;

  static const maxSerializedBytes =
      QuizConfiguration.maxSerializedBytes +
      100 * (6 * (256 + 256 + 120 + 500 + 60 + 256 + 4 * 500) + 1024) +
      16384;

  String get activityType => configuration.activityType;
  String get mode => 'meaning-quiz';
  bool get supportsCurrentPolicy =>
      evidencePolicyVersion == EvidenceContext.currentPolicyVersion &&
      featureContractRevision == currentFeatureContractIdentity.revision &&
      featureContractHash == currentFeatureContractIdentity.semanticHash;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'mode': mode,
    'activityType': activityType,
    'configuration': configuration.toJson(acceptedItemCount: questions.length),
    'questionBuilderVersion': 'current-meaning-options-v1',
    'evidencePolicyVersion': evidencePolicyVersion,
    'featureContractRevision': featureContractRevision,
    'featureContractHash': featureContractHash,
    'questions': [
      for (var ordinal = 0; ordinal < questions.length; ordinal++)
        {
          'ordinal': ordinal,
          'wordId': questions[ordinal].word.id,
          'categoryId': questions[ordinal].word.categoryId,
          'spelling': questions[ordinal].word.spelling,
          'meaning': questions[ordinal].word.meaning,
          'partOfSpeech': questions[ordinal].word.partOfSpeech,
          'contentRevision': questions[ordinal].word.contentRevision,
          'contentChecksumSha256': quizWordChecksum(questions[ordinal].word),
          'options': questions[ordinal].options,
          'correctOptionOrdinal': questions[ordinal].options.indexOf(
            questions[ordinal].word.meaning,
          ),
        },
    ],
  };

  late final String stableSerialization = jsonEncode(toJson());
  late final String id =
      'quiz-plan:${sha256.convert(utf8.encode(stableSerialization))}';
}

String quizWordChecksum(QuizWord word) {
  _validateWord(word);
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            word.id,
            word.categoryId,
            word.spelling,
            word.meaning,
            word.partOfSpeech,
            word.contentRevision,
          ]),
        ),
      )
      .toString();
}

final class QuizAssistance {
  QuizAssistance({
    this.hintVisible = false,
    this.hintFirstShownAtUtcMs,
    this.revealRequestedAtUtcMs,
  }) {
    _nullableTime(hintFirstShownAtUtcMs, 'hintFirstShownAtUtcMs');
    _nullableTime(revealRequestedAtUtcMs, 'revealRequestedAtUtcMs');
    if (hintVisible && hintFirstShownAtUtcMs == null) {
      throw const FormatException('Visible hint requires a durable receipt.');
    }
    if (hintFirstShownAtUtcMs != null &&
        revealRequestedAtUtcMs != null &&
        revealRequestedAtUtcMs! < hintFirstShownAtUtcMs!) {
      throw const FormatException('Reveal cannot precede the first hint.');
    }
  }

  final bool hintVisible;
  final int? hintFirstShownAtUtcMs;
  final int? revealRequestedAtUtcMs;

  QuizAssistance showHint(int atUtcMs) {
    _time(atUtcMs, 'atUtcMs');
    return QuizAssistance(
      hintVisible: true,
      hintFirstShownAtUtcMs: hintFirstShownAtUtcMs ?? atUtcMs,
      revealRequestedAtUtcMs: revealRequestedAtUtcMs,
    );
  }

  QuizAssistance hideHint() => QuizAssistance(
    hintFirstShownAtUtcMs: hintFirstShownAtUtcMs,
    revealRequestedAtUtcMs: revealRequestedAtUtcMs,
  );

  QuizAssistance withReveal(int atUtcMs) {
    _time(atUtcMs, 'atUtcMs');
    return QuizAssistance(
      hintVisible: hintVisible,
      hintFirstShownAtUtcMs: hintFirstShownAtUtcMs,
      revealRequestedAtUtcMs: revealRequestedAtUtcMs ?? atUtcMs,
    );
  }

  Map<String, Object?> toJson() => {
    'hintVisible': hintVisible,
    'hintFirstShownAtUtcMs': hintFirstShownAtUtcMs,
    'revealRequestedAtUtcMs': revealRequestedAtUtcMs,
  };

  factory QuizAssistance.fromJson(Map<String, Object?> body) {
    _keys(body, {
      'hintVisible',
      'hintFirstShownAtUtcMs',
      'revealRequestedAtUtcMs',
    });
    return QuizAssistance(
      hintVisible: _bool(body['hintVisible'], 'hintVisible'),
      hintFirstShownAtUtcMs: _nullableInt(
        body['hintFirstShownAtUtcMs'],
        'hintFirstShownAtUtcMs',
      ),
      revealRequestedAtUtcMs: _nullableInt(
        body['revealRequestedAtUtcMs'],
        'revealRequestedAtUtcMs',
      ),
    );
  }
}

final class QuizAnswerReceipt {
  QuizAnswerReceipt({
    required this.capturedOwnerId,
    required this.attemptId,
    required this.questionOrdinal,
    required this.selectedOptionOrdinal,
    required this.revealed,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.attemptNumber,
    required this.occurredAtUtcMs,
    required this.responseTimeMs,
    required this.evidenceContext,
    this.providerProvenance,
  }) {
    _identifier(capturedOwnerId, 'capturedOwnerId');
    _identifier(attemptId, 'attemptId');
    _identifier(wordId, 'wordId');
    _time(occurredAtUtcMs, 'occurredAtUtcMs');
    if (questionOrdinal < 0 ||
        attemptNumber != questionOrdinal + 1 ||
        promptMode != 'meaningChoice' ||
        (responseTimeMs != null &&
            (responseTimeMs! < 0 ||
                responseTimeMs! >
                    LearningEvidenceContract.maxResponseTimeMs)) ||
        (providerProvenance != null &&
            !LearningEvidenceContract.validText(
              providerProvenance!,
              maxLength: LearningEvidenceContract.maxProviderProvenanceLength,
            )) ||
        !LearningEvidenceContract.isOrdinaryEvidence(evidenceContext)) {
      throw const FormatException('Invalid quiz answer receipt.');
    }
  }

  factory QuizAnswerReceipt.capture({
    required AcceptedQuizPlan plan,
    required String ownerId,
    required String attemptId,
    required int questionOrdinal,
    required int? selectedOptionOrdinal,
    required bool revealed,
    required QuizAssistance assistance,
    required int occurredAtUtcMs,
    required int? responseTimeMs,
  }) {
    if (!plan.supportsCurrentPolicy) {
      throw StateError('Accepted quiz policy is unavailable for new evidence.');
    }
    if (questionOrdinal < 0 || questionOrdinal >= plan.questions.length) {
      throw const FormatException('Invalid quiz question ordinal.');
    }
    final question = plan.questions[questionOrdinal];
    final hintLevel = revealed
        ? 2
        : assistance.hintFirstShownAtUtcMs == null
        ? 0
        : 1;
    final answer = QuizAnswerReceipt(
      capturedOwnerId: ownerId,
      attemptId: attemptId,
      questionOrdinal: questionOrdinal,
      selectedOptionOrdinal: selectedOptionOrdinal,
      revealed: revealed,
      wordId: question.word.id,
      promptMode: 'meaningChoice',
      isCorrect:
          !revealed &&
          selectedOptionOrdinal != null &&
          selectedOptionOrdinal >= 0 &&
          selectedOptionOrdinal < question.options.length &&
          question.options[selectedOptionOrdinal] == question.word.meaning,
      attemptNumber: questionOrdinal + 1,
      occurredAtUtcMs: occurredAtUtcMs,
      responseTimeMs: responseTimeMs,
      evidenceContext: EvidenceContext.forNewEvidence(
        evidenceClass: hintLevel == 0
            ? EvidenceClass.recognition
            : EvidenceClass.guidedPractice,
        skillId: 'meaning-recall',
        hintLevel: hintLevel,
        contentRevision: question.word.contentRevision!,
        rolloutMode: EvidencePolicyRolloutMode.legacy,
      ),
    );
    answer.validateFor(plan, assistance);
    return answer;
  }

  final String capturedOwnerId;
  final String attemptId;
  final int questionOrdinal;
  final int? selectedOptionOrdinal;
  final bool revealed;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int attemptNumber;
  final int occurredAtUtcMs;
  final int? responseTimeMs;
  final String? providerProvenance;
  final EvidenceContext evidenceContext;

  void validateFor(AcceptedQuizPlan plan, QuizAssistance assistance) {
    if (questionOrdinal < 0 || questionOrdinal >= plan.questions.length) {
      throw const FormatException(
        'Answer question is not in the accepted plan.',
      );
    }
    final question = plan.questions[questionOrdinal];
    final selected = selectedOptionOrdinal;
    if (wordId != question.word.id ||
        (revealed
            ? selected != null ||
                  assistance.revealRequestedAtUtcMs != occurredAtUtcMs
            : selected == null ||
                  selected < 0 ||
                  selected >= question.options.length ||
                  assistance.revealRequestedAtUtcMs != null)) {
      throw const FormatException('Answer does not match accepted input.');
    }
    final expectedCorrect =
        !revealed && question.options[selected!] == question.word.meaning;
    final hintLevel = revealed
        ? 2
        : assistance.hintFirstShownAtUtcMs == null
        ? 0
        : 1;
    final hintTime = assistance.hintFirstShownAtUtcMs;
    if (isCorrect != expectedCorrect ||
        (hintTime != null && hintTime > occurredAtUtcMs) ||
        evidenceContext.contentRevision != question.word.contentRevision ||
        evidenceContext.hintLevel != hintLevel ||
        evidenceContext.skillId != 'meaning-recall' ||
        evidenceContext.evidenceClass !=
            (hintLevel == 0
                ? EvidenceClass.recognition
                : EvidenceClass.guidedPractice) ||
        evidenceContext.policyVersion != plan.evidencePolicyVersion ||
        evidenceContext.featureContractRevision !=
            plan.featureContractRevision ||
        evidenceContext.featureContractHash != plan.featureContractHash ||
        evidenceContext.classificationSource !=
            EvidenceClassificationSource.declared ||
        evidenceContext.engagementAllowed) {
      throw const FormatException('Answer evidence contradicts durable input.');
    }
  }

  RecordAnswerCommand toCommand({required String sessionId}) {
    _identifier(sessionId, 'sessionId');
    return RecordAnswerCommand(
      id: attemptId,
      ownerId: capturedOwnerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
        occurredAtUtcMs,
        isUtc: true,
      ),
      providerProvenance: providerProvenance,
      evidenceContext: evidenceContext,
    );
  }

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'capturedOwnerId': capturedOwnerId,
    'questionOrdinal': questionOrdinal,
    'selectedOptionOrdinal': selectedOptionOrdinal,
    'revealed': revealed,
    'wordId': wordId,
    'promptMode': promptMode,
    'isCorrect': isCorrect,
    'attemptNumber': attemptNumber,
    'occurredAtUtcMs': occurredAtUtcMs,
    'responseTimeMs': responseTimeMs,
    'providerProvenance': providerProvenance,
    'evidenceContext': evidenceContext.toJson(),
  };

  factory QuizAnswerReceipt.fromJson(Map<String, Object?> body) {
    _keys(body, {
      'attemptId',
      'capturedOwnerId',
      'questionOrdinal',
      'selectedOptionOrdinal',
      'revealed',
      'wordId',
      'promptMode',
      'isCorrect',
      'attemptNumber',
      'occurredAtUtcMs',
      'responseTimeMs',
      'providerProvenance',
      'evidenceContext',
    });
    return QuizAnswerReceipt(
      capturedOwnerId: _string(body['capturedOwnerId'], 'capturedOwnerId'),
      attemptId: _string(body['attemptId'], 'attemptId'),
      questionOrdinal: _int(body['questionOrdinal'], 'questionOrdinal'),
      selectedOptionOrdinal: _nullableInt(
        body['selectedOptionOrdinal'],
        'selectedOptionOrdinal',
      ),
      revealed: _bool(body['revealed'], 'revealed'),
      wordId: _string(body['wordId'], 'wordId'),
      promptMode: _string(body['promptMode'], 'promptMode'),
      isCorrect: _bool(body['isCorrect'], 'isCorrect'),
      attemptNumber: _int(body['attemptNumber'], 'attemptNumber'),
      occurredAtUtcMs: _int(body['occurredAtUtcMs'], 'occurredAtUtcMs'),
      responseTimeMs: _nullableInt(body['responseTimeMs'], 'responseTimeMs'),
      providerProvenance: _nullableString(
        body['providerProvenance'],
        'providerProvenance',
      ),
      evidenceContext: EvidenceContext.fromJson(
        _map(body['evidenceContext'], 'evidenceContext'),
      ),
    );
  }
}

final class QuizCloseReceipt {
  QuizCloseReceipt({
    required this.capturedOwnerId,
    required this.endedAtUtcMs,
  }) {
    _identifier(capturedOwnerId, 'capturedOwnerId');
    _time(endedAtUtcMs, 'endedAtUtcMs');
  }

  final String capturedOwnerId;
  final int endedAtUtcMs;

  Map<String, Object?> toJson() => {
    'capturedOwnerId': capturedOwnerId,
    'endedAtUtcMs': endedAtUtcMs,
  };

  factory QuizCloseReceipt.fromJson(Map<String, Object?> body) {
    _keys(body, {'capturedOwnerId', 'endedAtUtcMs'});
    return QuizCloseReceipt(
      capturedOwnerId: _string(body['capturedOwnerId'], 'capturedOwnerId'),
      endedAtUtcMs: _int(body['endedAtUtcMs'], 'endedAtUtcMs'),
    );
  }
}

sealed class QuizCheckpoint {
  QuizCheckpoint({
    required this.planId,
    required this.questionOrdinal,
    required this.assistance,
  }) {
    if (!RegExp(r'^quiz-plan:[0-9a-f]{64}$').hasMatch(planId) ||
        questionOrdinal < 0 ||
        questionOrdinal >= 100) {
      throw const FormatException('Invalid quiz checkpoint identity.');
    }
  }

  factory QuizCheckpoint.initial(AcceptedQuizPlan plan) => AwaitingQuizAnswer(
    planId: plan.id,
    questionOrdinal: 0,
    assistance: QuizAssistance(),
  );

  factory QuizCheckpoint.parse(String json, {required AcceptedQuizPlan plan}) {
    if (json.length > maxSerializedBytes ||
        utf8.encode(json).length > maxSerializedBytes) {
      throw const FormatException('Quiz checkpoint exceeds its byte budget.');
    }
    final body = _map(jsonDecode(json), 'quiz checkpoint');
    _keys(body, {
      'schemaVersion',
      'planId',
      'questionOrdinal',
      'phase',
      'assistance',
      'answer',
      'close',
    });
    if (body['schemaVersion'] != 1) {
      throw const FormatException('Unsupported quiz checkpoint.');
    }
    final planId = _string(body['planId'], 'planId');
    final ordinal = _int(body['questionOrdinal'], 'questionOrdinal');
    final assistance = QuizAssistance.fromJson(
      _map(body['assistance'], 'assistance'),
    );
    final phase = _string(body['phase'], 'phase');
    final QuizCheckpoint checkpoint;
    if (phase == 'awaitingAnswer') {
      if (body['answer'] != null || body['close'] != null) {
        throw const FormatException('Awaiting state cannot contain a command.');
      }
      checkpoint = AwaitingQuizAnswer(
        planId: planId,
        questionOrdinal: ordinal,
        assistance: assistance,
      );
    } else if (phase == 'pendingAnswer' || phase == 'answered') {
      if (body['close'] != null) {
        throw const FormatException(
          'Answer state cannot contain a close command.',
        );
      }
      final answer = QuizAnswerReceipt.fromJson(_map(body['answer'], 'answer'));
      checkpoint = phase == 'pendingAnswer'
          ? PendingQuizAnswer(
              planId: planId,
              questionOrdinal: ordinal,
              assistance: assistance,
              answer: answer,
            )
          : AnsweredQuizQuestion(
              planId: planId,
              questionOrdinal: ordinal,
              assistance: assistance,
              answer: answer,
            );
    } else {
      if (body['answer'] != null) {
        throw const FormatException('Terminal state cannot contain an answer.');
      }
      final close = QuizCloseReceipt.fromJson(_map(body['close'], 'close'));
      checkpoint = switch (phase) {
        'closing' => ClosingQuizSession(
          planId: planId,
          questionOrdinal: ordinal,
          assistance: assistance,
          close: close,
        ),
        'completed' => CompletedQuizSession(
          planId: planId,
          questionOrdinal: ordinal,
          assistance: assistance,
          close: close,
        ),
        'abandoned' => AbandonedQuizSession(
          planId: planId,
          questionOrdinal: ordinal,
          assistance: assistance,
          close: close,
        ),
        _ => throw const FormatException('Unsupported quiz checkpoint phase.'),
      };
    }
    checkpoint.validateFor(plan);
    if (checkpoint.stableSerialization != json) {
      throw const FormatException('Quiz checkpoint is not canonical.');
    }
    return checkpoint;
  }

  final String planId;
  static const maxSerializedBytes = 64 * 1024;
  final int questionOrdinal;
  final QuizAssistance assistance;
  String get phase;
  QuizAnswerReceipt? get answer => null;
  QuizCloseReceipt? get close => null;

  void validateFor(AcceptedQuizPlan plan) {
    if (planId != plan.id || questionOrdinal >= plan.questions.length) {
      throw const FormatException(
        'Checkpoint does not belong to accepted plan.',
      );
    }
    if (this is AwaitingQuizAnswer &&
        assistance.revealRequestedAtUtcMs != null) {
      throw const FormatException(
        'Awaiting state cannot forget a reveal command.',
      );
    }
    final answer = this.answer;
    if (answer != null) {
      if (answer.questionOrdinal != questionOrdinal) {
        throw const FormatException('Answer and cursor disagree.');
      }
      answer.validateFor(plan, assistance);
    }
    final close = this.close;
    if ((this is ClosingQuizSession || this is CompletedQuizSession) &&
        questionOrdinal != plan.questions.length - 1) {
      throw const FormatException('Quiz close must follow its final item.');
    }
    if (close != null) {
      final hintAt = assistance.hintFirstShownAtUtcMs;
      final revealAt = assistance.revealRequestedAtUtcMs;
      if ((hintAt != null && hintAt > close.endedAtUtcMs) ||
          (revealAt != null && revealAt > close.endedAtUtcMs)) {
        throw const FormatException('Quiz cannot close before assistance.');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'planId': planId,
    'questionOrdinal': questionOrdinal,
    'phase': phase,
    'assistance': assistance.toJson(),
    'answer': answer?.toJson(),
    'close': close?.toJson(),
  };

  String get stableSerialization => jsonEncode(toJson());
}

final class AwaitingQuizAnswer extends QuizCheckpoint {
  AwaitingQuizAnswer({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
  });
  @override
  String get phase => 'awaitingAnswer';
}

final class PendingQuizAnswer extends QuizCheckpoint {
  PendingQuizAnswer({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
    required this.answer,
  });
  @override
  final QuizAnswerReceipt answer;
  @override
  String get phase => 'pendingAnswer';
}

final class AnsweredQuizQuestion extends QuizCheckpoint {
  AnsweredQuizQuestion({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
    required this.answer,
  });
  @override
  final QuizAnswerReceipt answer;
  @override
  String get phase => 'answered';
}

final class ClosingQuizSession extends QuizCheckpoint {
  ClosingQuizSession({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
    required this.close,
  });
  @override
  final QuizCloseReceipt close;
  @override
  String get phase => 'closing';
}

final class CompletedQuizSession extends QuizCheckpoint {
  CompletedQuizSession({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
    required this.close,
  });
  @override
  final QuizCloseReceipt close;
  @override
  String get phase => 'completed';
}

final class AbandonedQuizSession extends QuizCheckpoint {
  AbandonedQuizSession({
    required super.planId,
    required super.questionOrdinal,
    required super.assistance,
    required this.close,
  });
  @override
  final QuizCloseReceipt close;
  @override
  String get phase => 'abandoned';
}

void _validateQuestion(QuizQuestion question) {
  _validateWord(question.word);
  if (question.options.isEmpty ||
      question.options.length > 4 ||
      question.options.toSet().length != question.options.length ||
      question.options
              .where((option) => option == question.word.meaning)
              .length !=
          1) {
    throw const FormatException(
      'Quiz requires one to four distinct pinned options.',
    );
  }
  for (final option in question.options) {
    _text(option, 'option', 500);
  }
}

void _validateWord(QuizWord word) {
  _identifier(word.id, 'wordId');
  _identifier(word.categoryId, 'categoryId');
  _identifier(word.contentRevision ?? '', 'contentRevision');
  _text(word.spelling, 'spelling', 120);
  _text(word.meaning, 'meaning', 500);
  _text(word.partOfSpeech, 'partOfSpeech', 60);
}

void _identifier(String value, String field) {
  if (value.trim() != value) throw FormatException('Invalid $field.');
  _text(value, field, 256);
}

void _text(String value, String field, int maximum) {
  if (value.trim().isEmpty || value.length > maximum) {
    throw FormatException('Invalid $field.');
  }
}

void _sha(String value, String field) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Invalid $field.');
  }
}

void _time(int value, String field) {
  if (value < 0 || value > 8640000000000000) {
    throw FormatException('Invalid $field.');
  }
}

void _nullableTime(int? value, String field) {
  if (value != null) _time(value, field);
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, dynamic>) throw FormatException('Invalid $field.');
  return value;
}

List<Object?> _list(Object? value, String field) {
  if (value is! List) throw FormatException('Invalid $field.');
  return value.cast<Object?>();
}

String _string(Object? value, String field) {
  if (value is! String) throw FormatException('Invalid $field.');
  return value;
}

String? _nullableString(Object? value, String field) =>
    value == null ? null : _string(value, field);

int _int(Object? value, String field) {
  if (value is! int) throw FormatException('Invalid $field.');
  return value;
}

int? _nullableInt(Object? value, String field) =>
    value == null ? null : _int(value, field);

bool _bool(Object? value, String field) {
  if (value is! bool) throw FormatException('Invalid $field.');
  return value;
}

void _keys(Map<String, Object?> body, Set<String> keys) {
  if (body.length != keys.length || !body.keys.toSet().containsAll(keys)) {
    throw const FormatException('Unexpected quiz JSON keys.');
  }
}
