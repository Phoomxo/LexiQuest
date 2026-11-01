import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../ai/ai_models.dart';
import '../../../product/feature_contract/feature_contract_digest.dart';
import 'cloze_content.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'learning_models.dart';
import 'sentence_scramble_content.dart';

enum NativeExerciseUnavailableReason {
  notFound,
  legacy,
  corrupt,
  unsupportedPolicy,
  ownerChanged,
  contentChanged,
  revisionChanged,
}

final class NativeExerciseUnavailable extends StateError {
  NativeExerciseUnavailable(this.reason)
    : super('Native exercise unavailable: ${reason.name}');
  final NativeExerciseUnavailableReason reason;
  @override
  String toString() => 'NativeExerciseUnavailable(${reason.name})';
}

final class AcceptedNativePlan {
  AcceptedNativePlan(this.exercise) {
    final session = exercise.session;
    _identifier(session.id);
    _identifier(session.ownerId);
    _text(session.appVersion, 128);
    _text(session.buildId, 512);
    _utc(session.startedAtUtc?.millisecondsSinceEpoch);
    if (session.startedAtUtc!.microsecondsSinceEpoch % 1000 != 0) {
      throw const FormatException(
        'Native start requires millisecond UTC precision',
      );
    }
    _wordJson(exercise.word);
    if (utf8.encode(stableSerialization).length > maxSerializedBytes) {
      throw const FormatException('Native plan exceeds its byte budget');
    }
  }

  static const idPrefix = 'native-plan-v1:';
  static const maxSerializedBytes = 131072;
  final AcceptedNativeExercise exercise;

  Map<String, Object?> toJson() {
    final session = exercise.session;
    final content = switch (exercise) {
      SentenceScrambleSession(:final content) => _contentJson(
        content.sentence,
        content.kind,
        content.cefr,
        content.language,
        content.modelVersion,
        content.cached,
      ),
      ClozeSession(:final content) => _contentJson(
        content.sentence,
        content.kind,
        content.cefr,
        content.language,
        content.modelVersion,
        content.cached,
      ),
      _ => null,
    };
    return {
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
      'mode': switch (exercise) {
        DictationSession() => 'dictation',
        WordScrambleSession() => 'wordScramble',
        SentenceScrambleSession() => 'sentenceScramble',
        TypedClozeSession() => 'clozeTyped',
        ChoiceClozeSession() => 'clozeChoice',
      },
      'word': _wordJson(exercise.word),
      'content': content,
      'choices': [
        if (exercise case ChoiceClozeSession(:final choices))
          for (final choice in choices) _wordJson(choice),
      ],
      'presentation': switch (exercise) {
        WordScrambleSession(:final letters) => letters,
        SentenceScrambleSession(:final content) => [
          content.tokens,
          content.tokenOrder,
        ],
        ClozeSession(:final content) => [content.gapStart, content.gapEnd],
        _ => null,
      },
      'contentRevision': exercise.evidenceContentRevision,
    };
  }

  late final String stableSerialization = jsonEncode(toJson());
  late final String id =
      '$idPrefix${sha256.convert(utf8.encode(stableSerialization))}';

  factory AcceptedNativePlan.parse({required String id, required String json}) {
    final body = _decode(json, maxSerializedBytes);
    if (body['schemaVersion'] != 1) {
      throw NativeExerciseUnavailable(
        NativeExerciseUnavailableReason.unsupportedPolicy,
      );
    }
    if (body['policyVersion'] != EvidenceContext.currentPolicyVersion ||
        body['featureContractRevision'] !=
            currentFeatureContractIdentity.revision ||
        body['featureContractHash'] !=
            currentFeatureContractIdentity.semanticHash) {
      throw NativeExerciseUnavailable(
        NativeExerciseUnavailableReason.unsupportedPolicy,
      );
    }
    final stored = _map(body['session']);
    final session = LearningSessionDraft(
      id: _string(stored['id']),
      ownerId: _string(stored['ownerId']),
      activityType: _string(stored['activityType']),
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        _utc(stored['startedAtUtcMs']),
        isUtc: true,
      ),
      appVersion: _string(stored['appVersion']),
      buildId: _string(stored['buildId']),
    );
    final word = _word(body['word']);
    ContentResponse response() {
      final content = _map(body['content']);
      final kind = ContentKind.fromWire(_string(content['kind']));
      final cefr = CefrLevel.values
          .where((value) => value.wire == content['cefr'])
          .firstOrNull;
      if (kind == null || cefr == null || content['cached'] is! bool) {
        throw const FormatException('Invalid native content metadata');
      }
      return ContentResponse(
        text: _string(content['sentence']),
        kind: kind,
        cefr: cefr,
        language: _string(content['language']),
        modelVersion: _string(content['modelVersion']),
        cached: content['cached']! as bool,
      );
    }

    final AcceptedNativeExercise exercise = switch (body['mode']) {
      'dictation' => DictationSession(session: session, word: word),
      'wordScramble' => WordScrambleSession(session: session, word: word),
      'sentenceScramble' => SentenceScrambleSession(
        session: session,
        word: word,
        content: SentenceScrambleContent.parse(
          targetSpelling: word.spelling,
          response: response(),
        ),
      ),
      'clozeTyped' => TypedClozeSession(
        session: session,
        word: word,
        content: ClozeContent.parse(
          targetSpelling: word.spelling,
          response: response(),
        ),
      ),
      'clozeChoice' => ChoiceClozeSession(
        session: session,
        word: word,
        content: ClozeContent.parse(
          targetSpelling: word.spelling,
          response: response(),
        ),
        choices: _list(body['choices']).map(_word),
      ),
      _ => throw const FormatException('Unsupported native mode'),
    };
    final plan = AcceptedNativePlan(exercise);
    if (plan.id != id || plan.stableSerialization != json) {
      throw const FormatException('Native plan identity differs');
    }
    return plan;
  }
}

final class NativeExerciseDraft {
  NativeExerciseDraft({
    this.text = '',
    this.optionId,
    Iterable<int?>? tileSlots,
    this.responseTimeMs = 0,
    this.assisted = false,
  }) : tileSlots = tileSlots == null
           ? null
           : List<int?>.unmodifiable(tileSlots) {
    final indices = this.tileSlots?.whereType<int>().toList() ?? const <int>[];
    if (utf8.encode(text).length > 8192 ||
        text.length > 4096 ||
        responseTimeMs < 0 ||
        responseTimeMs > LearningEvidenceContract.maxResponseTimeMs ||
        (this.tileSlots?.length ?? 0) > 120 ||
        indices.any((value) => value < 0 || value >= 120) ||
        indices.toSet().length != indices.length) {
      throw const FormatException('Invalid native draft');
    }
    if (optionId != null) _identifier(optionId!);
  }
  final String text;
  final String? optionId;
  final List<int?>? tileSlots;
  final int responseTimeMs;
  final bool assisted;

  factory NativeExerciseDraft.fromInput(NativeAnswerInput input) {
    final draft = NativeExerciseDraft(
      text: switch (input) {
        DictationAnswerInput(:final response) => response,
        WordScrambleAnswerInput(:final response) => response,
        SentenceScrambleAnswerInput(:final response) => response,
        TypedClozeAnswerInput(:final response) => response,
        _ => '',
      },
      optionId: input is ChoiceClozeAnswerInput ? input.optionId : null,
      tileSlots: switch (input) {
        WordScrambleAnswerInput(:final tileSlots) => tileSlots,
        SentenceScrambleAnswerInput(:final tileSlots) => tileSlots,
        _ => null,
      },
      assisted: input is DictationAnswerInput && input.assisted,
      responseTimeMs: input.responseTime.inMilliseconds
          .clamp(0, LearningEvidenceContract.maxResponseTimeMs)
          .toInt(),
    );
    draft.validate(input.exercise);
    return draft;
  }

  void validate(AcceptedNativeExercise exercise) {
    if (exercise is ChoiceClozeSession) {
      if (text.isNotEmpty ||
          tileSlots != null ||
          assisted ||
          (optionId != null &&
              !exercise.choices.any((word) => word.id == optionId))) {
        throw const FormatException(
          'Draft differs from original Cloze choices',
        );
      }
    } else if (optionId != null ||
        (assisted && exercise is! DictationSession)) {
      throw const FormatException('Draft has unsupported assistance or option');
    }
    final slots = tileSlots;
    if (slots != null) {
      final (bank, separator) = switch (exercise) {
        WordScrambleSession(:final letters) => (letters, ''),
        SentenceScrambleSession(:final content, :final tokenOrder) => (
          [for (final index in tokenOrder) content.tokens[index]],
          ' ',
        ),
        _ => throw const FormatException('Draft has no tile bank'),
      };
      if (slots.length != bank.length ||
          slots.whereType<int>().any((value) => value >= bank.length) ||
          text !=
              slots
                  .whereType<int>()
                  .map((index) => bank[index])
                  .join(separator)) {
        throw const FormatException(
          'Draft tile slots differ from the displayed response',
        );
      }
    }
  }

  List<int> canonicalTokenIndices(AcceptedNativeExercise exercise) {
    validate(exercise);
    final selected = tileSlots?.whereType<int>() ?? const <int>[];
    return List<int>.unmodifiable(switch (exercise) {
      WordScrambleSession() => selected,
      SentenceScrambleSession(:final tokenOrder) => selected.map(
        (index) => tokenOrder[index],
      ),
      _ => const <int>[],
    });
  }

  bool isCorrect(AcceptedNativeExercise exercise) => switch (exercise) {
    ChoiceClozeSession() => optionId == exercise.word.id,
    SentenceScrambleSession() => exercise.content.matchesResponse(text),
    _ =>
      text.trim().toLowerCase() == exercise.word.spelling.trim().toLowerCase(),
  };

  Map<String, Object?> toJson() => {
    'text': text,
    'optionId': optionId,
    'tileSlots': tileSlots,
    'responseTimeMs': responseTimeMs,
    'assisted': assisted,
  };

  factory NativeExerciseDraft.fromJson(Object? value) {
    final body = _map(value);
    if (body['assisted'] is! bool || body['responseTimeMs'] is! int) {
      throw const FormatException('Invalid native draft metadata');
    }
    return NativeExerciseDraft(
      text: _string(body['text']),
      optionId: body['optionId'] == null ? null : _string(body['optionId']),
      tileSlots: body['tileSlots'] == null
          ? null
          : _list(body['tileSlots']).map((value) {
              if (value != null && value is! int) {
                throw const FormatException('Invalid tile index');
              }
              return value as int?;
            }),
      responseTimeMs: body['responseTimeMs']! as int,
      assisted: body['assisted']! as bool,
    );
  }
}

sealed class NativeCheckpoint {
  const NativeCheckpoint(this.draft);
  final NativeExerciseDraft draft;
  NativeCheckpointPhase get phase;
  RecordAnswerCommand? get answer => null;
  DateTime? get endedAtUtc => null;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'phase': phase.name,
    'draft': draft.toJson(),
    'answer': answer == null ? null : nativeAnswerJson(answer!),
    'endedAtUtcMs': endedAtUtc?.millisecondsSinceEpoch,
  };
  String get stableSerialization => jsonEncode(toJson());

  void validate(AcceptedNativePlan plan) {
    final exercise = plan.exercise;
    draft.validate(exercise);
    final command = answer;
    if (command != null) {
      final expectedHint = switch (exercise) {
        DictationSession() => draft.assisted ? 1 : 0,
        TypedClozeSession() => 1,
        _ => 0,
      };
      if (command.ownerId != exercise.ownerId ||
          command.sessionId != exercise.id ||
          command.nativeDraft == null ||
          jsonEncode(command.nativeDraft!.toJson()) !=
              jsonEncode(draft.toJson()) ||
          command.wordId != exercise.word.id ||
          command.isCorrect != draft.isCorrect(exercise) ||
          command.responseTimeMs != draft.responseTimeMs ||
          command.evidenceContext.hintLevel != expectedHint ||
          command.evidenceContext.policyVersion !=
              EvidenceContext.currentPolicyVersion ||
          command.evidenceContext.featureContractRevision !=
              currentFeatureContractIdentity.revision ||
          command.evidenceContext.featureContractHash !=
              currentFeatureContractIdentity.semanticHash ||
          !LearningEvidenceContract.isOrdinaryEvidence(
            command.evidenceContext,
          ) ||
          command.occurredAtUtc.isBefore(exercise.startedAtUtc) ||
          command.occurredAtUtc.microsecondsSinceEpoch % 1000 != 0 ||
          (exercise is ChoiceClozeSession && draft.optionId == null)) {
        throw const FormatException(
          'Native answer differs from its original response',
        );
      }
    }
    final end = endedAtUtc;
    if (end != null &&
        (!end.isUtc ||
            end.microsecondsSinceEpoch % 1000 != 0 ||
            end.isBefore(command?.occurredAtUtc ?? exercise.startedAtUtc))) {
      throw const FormatException('Native close precedes its saved facts');
    }
    if (utf8.encode(stableSerialization).length > 32768) {
      throw const FormatException('Native checkpoint exceeds its byte budget');
    }
  }

  factory NativeCheckpoint.parse(
    String json, {
    required AcceptedNativePlan plan,
  }) {
    final body = _decode(json, 32768);
    if (body['schemaVersion'] != 1) {
      throw const FormatException('Unsupported native checkpoint');
    }
    final draft = NativeExerciseDraft.fromJson(body['draft']);
    RecordAnswerCommand answer() => _answer(body['answer'], draft);
    DateTime end() => DateTime.fromMillisecondsSinceEpoch(
      _utc(body['endedAtUtcMs']),
      isUtc: true,
    );
    final NativeCheckpoint checkpoint = switch (body['phase']) {
      'awaitingAnswer' => AwaitingNativeAnswer(draft),
      'pendingAnswer' => PendingNativeAnswer(draft, answer()),
      'answered' => AnsweredNativeExercise(draft, answer()),
      'closing' => ClosingNativeExercise(draft, answer(), end()),
      'completed' => CompletedNativeExercise(draft, answer(), end()),
      'abandoned' => AbandonedNativeExercise(draft, end()),
      _ => throw const FormatException('Unsupported native phase'),
    };
    checkpoint.validate(plan);
    if (checkpoint.stableSerialization != json) {
      throw const FormatException('Native checkpoint is not canonical');
    }
    return checkpoint;
  }
}

final class AwaitingNativeAnswer extends NativeCheckpoint {
  const AwaitingNativeAnswer(super.draft);
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.awaitingAnswer;
}

final class PendingNativeAnswer extends NativeCheckpoint {
  const PendingNativeAnswer(super.draft, this.answer);
  @override
  final RecordAnswerCommand answer;
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.pendingAnswer;
}

final class AnsweredNativeExercise extends NativeCheckpoint {
  const AnsweredNativeExercise(super.draft, this.answer);
  @override
  final RecordAnswerCommand answer;
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.answered;
}

final class ClosingNativeExercise extends NativeCheckpoint {
  const ClosingNativeExercise(super.draft, this.answer, this.endedAtUtc);
  @override
  final RecordAnswerCommand answer;
  @override
  final DateTime endedAtUtc;
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.closing;
}

final class CompletedNativeExercise extends NativeCheckpoint {
  const CompletedNativeExercise(super.draft, this.answer, this.endedAtUtc);
  @override
  final RecordAnswerCommand answer;
  @override
  final DateTime endedAtUtc;
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.completed;
}

final class AbandonedNativeExercise extends NativeCheckpoint {
  const AbandonedNativeExercise(super.draft, this.endedAtUtc);
  @override
  final DateTime endedAtUtc;
  @override
  NativeCheckpointPhase get phase => NativeCheckpointPhase.abandoned;
}

Map<String, Object?> nativeAnswerJson(RecordAnswerCommand command) => {
  'id': command.id,
  'ownerId': command.ownerId,
  'sessionId': command.sessionId,
  'wordId': command.wordId,
  'promptMode': command.promptMode,
  'isCorrect': command.isCorrect,
  'responseTimeMs': command.responseTimeMs,
  'attemptNumber': command.attemptNumber,
  'occurredAtUtcMs': command.occurredAtUtc.millisecondsSinceEpoch,
  'providerProvenance': command.providerProvenance,
  'evidenceContext': command.evidenceContext.toJson(),
};

RecordAnswerCommand _answer(Object? value, NativeExerciseDraft draft) {
  final body = _map(value);
  if (body['isCorrect'] is! bool ||
      body['attemptNumber'] is! int ||
      body['responseTimeMs'] is! int) {
    throw const FormatException('Invalid native answer');
  }
  final command = RecordAnswerCommand(
    id: _string(body['id']),
    ownerId: _string(body['ownerId']),
    sessionId: _string(body['sessionId']),
    wordId: _string(body['wordId']),
    promptMode: _string(body['promptMode']),
    isCorrect: body['isCorrect']! as bool,
    responseTimeMs: body['responseTimeMs']! as int,
    attemptNumber: body['attemptNumber']! as int,
    occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
      _utc(body['occurredAtUtcMs']),
      isUtc: true,
    ),
    providerProvenance: body['providerProvenance'] == null
        ? null
        : _string(body['providerProvenance']),
    evidenceContext: EvidenceContext.fromJson(_map(body['evidenceContext'])),
    nativeDraft: draft,
  );
  if (jsonEncode(nativeAnswerJson(command)) != jsonEncode(body)) {
    throw const FormatException(
      'Native answer has unknown or noncanonical fields',
    );
  }
  return command;
}

Map<String, Object?> _contentJson(
  String sentence,
  ContentKind kind,
  CefrLevel cefr,
  String language,
  String modelVersion,
  bool cached,
) => {
  'sentence': sentence,
  'kind': kind.wire,
  'cefr': cefr.wire,
  'language': language,
  'modelVersion': modelVersion,
  'cached': cached,
};

List<Object?> _wordJson(QuizWord word) {
  _identifier(word.id);
  _identifier(word.categoryId);
  _identifier(word.contentRevision);
  _text(word.spelling, 120);
  _text(word.meaning, 4096);
  _text(word.partOfSpeech, 256, allowEmpty: true);
  return [
    word.id,
    word.categoryId,
    word.spelling,
    word.meaning,
    word.partOfSpeech,
    word.contentRevision,
  ];
}

QuizWord _word(Object? value) {
  final values = _list(value);
  if (values.length != 6) {
    throw const FormatException('Invalid native word snapshot');
  }
  return QuizWord(
    id: _string(values[0]),
    categoryId: _string(values[1]),
    spelling: _string(values[2]),
    meaning: _string(values[3]),
    partOfSpeech: _string(values[4]),
    contentRevision: _string(values[5]),
  );
}

Map<String, Object?> _decode(String json, int maximum) {
  if (utf8.encode(json).length > maximum) {
    throw const FormatException('Native JSON exceeds its byte budget');
  }
  return _map(jsonDecode(json));
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected native object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected native array');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected native text');
  return value;
}

int _utc(Object? value) {
  if (value is! int || value < 0 || value > 8640000000000000) {
    throw const FormatException('Invalid native UTC time');
  }
  return value;
}

void _identifier(String? value) {
  if (value == null || !LearningEvidenceContract.validIdentifier(value)) {
    throw const FormatException('Invalid native identifier');
  }
}

void _text(String value, int maximum, {bool allowEmpty = false}) {
  if ((!allowEmpty && value.trim().isEmpty) ||
      value.length > maximum ||
      utf8.encode(value).length > maximum * 4) {
    throw const FormatException('Invalid native text');
  }
}
