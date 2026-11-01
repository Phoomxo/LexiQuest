import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../product/feature_contract/feature_contract_digest.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'learning_models.dart';

enum MatchingPhase {
  selecting,
  pending,
  answered,
  closing,
  completed,
  abandoned,
}

final class MatchingPlan {
  MatchingPlan({required this.session, required Iterable<QuizWord> words})
    : words = List.unmodifiable(words) {
    if (!session.id.startsWith(sessionPrefix) ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != activityType ||
        session.startedAtUtc == null ||
        !_millisecondUtc(session.startedAtUtc!) ||
        session.appVersion.trim().isEmpty ||
        session.buildId.trim().isEmpty ||
        this.words.length < 2 ||
        this.words.length > 8) {
      throw const FormatException('Invalid matching plan');
    }
    final ids = <String>{};
    final spellings = <String>{};
    final meanings = <String>{};
    for (final word in this.words) {
      if (!LearningEvidenceContract.validIdentifier(word.id) ||
          !LearningEvidenceContract.validIdentifier(word.categoryId) ||
          word.contentRevision == null ||
          !LearningEvidenceContract.validIdentifier(word.contentRevision!) ||
          !LearningEvidenceContract.validText(word.spelling, maxLength: 240) ||
          !LearningEvidenceContract.validText(word.meaning, maxLength: 1000) ||
          !ids.add(word.id) ||
          !spellings.add(_label(word.spelling)) ||
          !meanings.add(_label(word.meaning))) {
        throw const FormatException('Matching requires distinct pinned pairs');
      }
    }
    if (utf8.encode(stableSerialization).length > maximumBytes) {
      throw const FormatException('Matching plan exceeds its byte budget');
    }
  }

  static const sessionPrefix = 'session:matching-v1:';
  static const idPrefix = 'matching-plan-v1:';
  static const activityType = 'matching';
  static const promptMode = 'matchingPair';
  static const maximumBytes = 65536;
  final LearningSessionDraft session;
  final List<QuizWord> words;

  // Rotating the displayed meanings avoids an already-solved initial board.
  List<int> get meaningOrder => [
    for (var index = 1; index < words.length; index++) index,
    0,
  ];

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'policyVersion': EvidenceContext.currentPolicyVersion,
    'featureContractRevision': currentFeatureContractIdentity.revision,
    'featureContractHash': currentFeatureContractIdentity.semanticHash,
    'session': {
      'id': session.id,
      'ownerId': session.ownerId,
      'activityType': session.activityType,
      'startedAtUtcMs': session.startedAtUtc!.millisecondsSinceEpoch,
      'appVersion': session.appVersion,
      'buildId': session.buildId,
    },
    'words': [for (final word in words) _wordJson(word)],
  };

  late final String stableSerialization = jsonEncode(toJson());
  late final String id =
      '$idPrefix${sha256.convert(utf8.encode(stableSerialization))}';

  factory MatchingPlan.parse({required String id, required String json}) {
    if (utf8.encode(json).length > maximumBytes) {
      throw const FormatException('Matching plan exceeds its byte budget');
    }
    final body = _object(jsonDecode(json));
    _keys(body, {
      'schemaVersion',
      'policyVersion',
      'featureContractRevision',
      'featureContractHash',
      'session',
      'words',
    });
    if (body['schemaVersion'] != 1 ||
        body['policyVersion'] != EvidenceContext.currentPolicyVersion ||
        body['featureContractRevision'] !=
            currentFeatureContractIdentity.revision ||
        body['featureContractHash'] !=
            currentFeatureContractIdentity.semanticHash) {
      throw const FormatException('Unsupported matching policy');
    }
    final rawSession = _object(body['session']);
    _keys(rawSession, {
      'id',
      'ownerId',
      'activityType',
      'startedAtUtcMs',
      'appVersion',
      'buildId',
    });
    final rawWords = body['words'];
    if (rawWords is! List || rawWords.length > 8) {
      throw const FormatException('Invalid matching words');
    }
    final plan = MatchingPlan(
      session: LearningSessionDraft(
        id: _string(rawSession['id']),
        ownerId: _string(rawSession['ownerId']),
        activityType: _string(rawSession['activityType']),
        startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          _integer(rawSession['startedAtUtcMs']),
          isUtc: true,
        ),
        appVersion: _string(rawSession['appVersion']),
        buildId: _string(rawSession['buildId']),
      ),
      words: rawWords.map((raw) {
        final word = _object(raw);
        _keys(word, {
          'id',
          'categoryId',
          'spelling',
          'meaning',
          'partOfSpeech',
          'contentRevision',
        });
        return QuizWord(
          id: _string(word['id']),
          categoryId: _string(word['categoryId']),
          spelling: _string(word['spelling']),
          meaning: _string(word['meaning']),
          partOfSpeech: _string(word['partOfSpeech']),
          contentRevision: _string(word['contentRevision']),
        );
      }),
    );
    if (plan.id != id || plan.stableSerialization != json) {
      throw const FormatException('Matching plan identity changed');
    }
    return plan;
  }

  RecordAnswerCommand command(MatchingPairIntent intent) {
    intent.validate(this);
    return RecordAnswerCommand(
      id: intent.id,
      ownerId: session.ownerId,
      sessionId: session.id,
      wordId: words[intent.wordIndex].id,
      promptMode: promptMode,
      isCorrect: intent.isCorrect,
      responseTimeMs: intent.responseTimeMs,
      attemptNumber: intent.ordinal,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
        intent.occurredAtUtcMs,
        isUtc: true,
      ),
      evidenceContext: evidence,
    );
  }

  EvidenceContext get evidence => EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.recognition,
    skillId: 'meaning-recognition',
    hintLevel: 0,
    contentRevision: id,
    rolloutMode: EvidencePolicyRolloutMode.legacy,
  );
}

final class MatchingPairIntent {
  MatchingPairIntent({
    required this.id,
    required this.ordinal,
    required this.wordIndex,
    required this.meaningIndex,
    required this.occurredAtUtcMs,
    required this.responseTimeMs,
  });
  final String id;
  final int ordinal;
  final int wordIndex;
  final int meaningIndex;
  final int occurredAtUtcMs;
  final int? responseTimeMs;
  bool get isCorrect => wordIndex == meaningIndex;

  void validate(MatchingPlan plan) {
    if (ordinal < 1 ||
        ordinal > LearningEvidenceContract.maxAttemptNumber ||
        id != 'attempt:matching:${plan.session.id}:$ordinal' ||
        wordIndex < 0 ||
        wordIndex >= plan.words.length ||
        meaningIndex < 0 ||
        meaningIndex >= plan.words.length ||
        occurredAtUtcMs < plan.session.startedAtUtc!.millisecondsSinceEpoch ||
        (responseTimeMs != null &&
            (responseTimeMs! < 0 ||
                responseTimeMs! >
                    LearningEvidenceContract.maxResponseTimeMs))) {
      throw const FormatException('Invalid original matching attempt');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'ordinal': ordinal,
    'wordIndex': wordIndex,
    'meaningIndex': meaningIndex,
    'occurredAtUtcMs': occurredAtUtcMs,
    'responseTimeMs': responseTimeMs,
  };
  factory MatchingPairIntent.fromJson(Object? raw) {
    final body = _object(raw);
    _keys(body, {
      'id',
      'ordinal',
      'wordIndex',
      'meaningIndex',
      'occurredAtUtcMs',
      'responseTimeMs',
    });
    return MatchingPairIntent(
      id: _string(body['id']),
      ordinal: _integer(body['ordinal']),
      wordIndex: _integer(body['wordIndex']),
      meaningIndex: _integer(body['meaningIndex']),
      occurredAtUtcMs: _integer(body['occurredAtUtcMs']),
      responseTimeMs: body['responseTimeMs'] == null
          ? null
          : _integer(body['responseTimeMs']),
    );
  }
}

final class MatchingCheckpoint {
  MatchingCheckpoint({
    required this.phase,
    required this.attemptCount,
    required Iterable<int> matched,
    this.selectedWord,
    this.selectedMeaning,
    this.answer,
    this.endedAtUtcMs,
  }) : matched = List.unmodifiable(matched);
  final MatchingPhase phase;
  final int attemptCount;
  final List<int> matched;
  final int? selectedWord;
  final int? selectedMeaning;
  final MatchingPairIntent? answer;
  final int? endedAtUtcMs;

  void validate(MatchingPlan plan) {
    if (attemptCount < 0 ||
        attemptCount > LearningEvidenceContract.maxAttemptNumber ||
        matched.length > plan.words.length ||
        matched.toSet().length != matched.length ||
        matched.any((index) => index < 0 || index >= plan.words.length) ||
        !matched.indexed.every(
          (entry) => entry.$1 == 0 || matched[entry.$1 - 1] < entry.$2,
        )) {
      throw const FormatException('Invalid matching checkpoint');
    }
    for (final selected in [selectedWord, selectedMeaning]) {
      if (selected != null &&
          (selected < 0 ||
              selected >= plan.words.length ||
              matched.contains(selected))) {
        throw const FormatException('Invalid matching selection');
      }
    }
    final hasAnswer =
        phase == MatchingPhase.pending || phase == MatchingPhase.answered;
    final hasEnd =
        phase == MatchingPhase.closing ||
        phase == MatchingPhase.completed ||
        phase == MatchingPhase.abandoned;
    if (hasAnswer != (answer != null) ||
        hasEnd != (endedAtUtcMs != null) ||
        (phase != MatchingPhase.selecting &&
            (selectedWord != null || selectedMeaning != null)) ||
        (endedAtUtcMs != null &&
            endedAtUtcMs! <
                plan.session.startedAtUtc!.millisecondsSinceEpoch) ||
        ((phase == MatchingPhase.closing || phase == MatchingPhase.completed) &&
            matched.length != plan.words.length)) {
      throw const FormatException('Matching phase contradicts its data');
    }
    if (answer != null) {
      answer!.validate(plan);
      if (answer!.ordinal !=
              attemptCount + (phase == MatchingPhase.pending ? 1 : 0) ||
          (phase == MatchingPhase.pending &&
              (matched.contains(answer!.wordIndex) ||
                  matched.contains(answer!.meaningIndex))) ||
          (phase == MatchingPhase.answered &&
              answer!.isCorrect != matched.contains(answer!.wordIndex))) {
        throw const FormatException('Matching answer contradicts the board');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'phase': phase.name,
    'attemptCount': attemptCount,
    'matched': matched,
    'selectedWord': selectedWord,
    'selectedMeaning': selectedMeaning,
    'answer': answer?.toJson(),
    'endedAtUtcMs': endedAtUtcMs,
  };
  String get stableSerialization => jsonEncode(toJson());
  factory MatchingCheckpoint.parse(String json, MatchingPlan plan) {
    if (utf8.encode(json).length > 16384) {
      throw const FormatException('Matching checkpoint is too large');
    }
    final body = _object(jsonDecode(json));
    _keys(body, {
      'schemaVersion',
      'phase',
      'attemptCount',
      'matched',
      'selectedWord',
      'selectedMeaning',
      'answer',
      'endedAtUtcMs',
    });
    final rawMatched = body['matched'];
    final phase = MatchingPhase.values
        .where((phase) => phase.name == body['phase'])
        .firstOrNull;
    if (body['schemaVersion'] != 1 || phase == null || rawMatched is! List) {
      throw const FormatException('Unsupported matching checkpoint');
    }
    final checkpoint = MatchingCheckpoint(
      phase: phase,
      attemptCount: _integer(body['attemptCount']),
      matched: rawMatched.map(_integer),
      selectedWord: body['selectedWord'] == null
          ? null
          : _integer(body['selectedWord']),
      selectedMeaning: body['selectedMeaning'] == null
          ? null
          : _integer(body['selectedMeaning']),
      answer: body['answer'] == null
          ? null
          : MatchingPairIntent.fromJson(body['answer']),
      endedAtUtcMs: body['endedAtUtcMs'] == null
          ? null
          : _integer(body['endedAtUtcMs']),
    );
    checkpoint.validate(plan);
    if (checkpoint.stableSerialization != json) {
      throw const FormatException('Matching checkpoint identity changed');
    }
    return checkpoint;
  }
}

abstract interface class MatchingState {
  MatchingPlan get plan;
  MatchingCheckpoint get checkpoint;
  int get revision;
  LearningSessionSummary? get completedSummary;
}

abstract interface class MatchingRepository {
  Future<MatchingPlan?> prepare({
    required LearningSessionDraft session,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
    required bool Function() stillCurrent,
  });
  Future<MatchingState> start(
    MatchingPlan plan, {
    required bool Function() stillCurrent,
  });
  Future<MatchingState> resume({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });
  Future<MatchingState> save(
    MatchingState state,
    MatchingCheckpoint next, {
    required bool Function() stillCurrent,
  });
  Future<MatchingState> commit(
    MatchingState state, {
    required bool Function() stillCurrent,
  });
  Future<MatchingState> finish(
    MatchingState state, {
    required bool Function() stillCurrent,
  });
}

Map<String, Object?> _wordJson(QuizWord word) => {
  'id': word.id,
  'categoryId': word.categoryId,
  'spelling': word.spelling,
  'meaning': word.meaning,
  'partOfSpeech': word.partOfSpeech,
  'contentRevision': word.contentRevision,
};
String _label(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
bool _millisecondUtc(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.microsecondsSinceEpoch % 1000 == 0;
Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a matching object');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    throw const FormatException('Unexpected matching fields');
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected matching text');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected a matching integer');
  return value;
}
