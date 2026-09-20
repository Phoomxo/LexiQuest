import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../learning/domain/written_rubric.dart';

enum SpeakingIntent { practice, assessment }

enum SpeakingInput { speech, textFallback }

/// Supplemental lexical feedback about the displayed transcript only.
final class SpeakingRubricResult {
  SpeakingRubricResult._(
    this.target,
    this.response,
    this.input,
    this.confirmed,
    this.isFinal,
    this.status,
    List<int>? scores,
    this.explanation,
  ) : scores = scores == null ? null : List.unmodifiable(scores);
  final String target, response, explanation;
  final SpeakingInput input;
  final bool confirmed, isFinal;
  final RubricStatus status;
  final List<int>? scores;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'rubricRevision': SpeakingRubric.revision,
    'inventoryHash': SpeakingRubric.fingerprint,
    'target': target,
    'response': response,
    'input': input.name,
    'confirmed': confirmed,
    'isFinal': isFinal,
    'status': status.name,
    'scores': scores,
    'explanation': explanation,
  };
  factory SpeakingRubricResult.fromJson(Map<String, Object?> json) {
    if (json['target'] is! String ||
        json['response'] is! String ||
        json['confirmed'] is! bool ||
        json['isFinal'] is! bool ||
        !SpeakingInput.values.any((v) => v.name == json['input'])) {
      throw const FormatException('Invalid speaking result');
    }
    final expected = const SpeakingRubric().assess(
      json['target'] as String,
      json['response'] as String,
      input: SpeakingInput.values.byName(json['input'] as String),
      confirmed: json['confirmed'] as bool,
      isFinal: json['isFinal'] as bool,
    );
    if (jsonEncode(expected.toJson()) != jsonEncode(json)) {
      throw const FormatException('Invalid pinned speaking rubric');
    }
    return expected;
  }
}

final class SpeakingRubric {
  const SpeakingRubric();
  static const revision = 1;
  static const prompts = {
    'book':
        'At the library, tell a friend about reading a book (the object with pages).',
    'pencil':
        'In class, tell a friend about writing with a pencil (the erasable tool).',
    'bottle':
        'At lunch, tell a friend about drinking water from a bottle (the container).',
  };
  // Frozen written-v1 exact catalog supplies semantic/grammatical oracles only.
  // This policy never calls its capitalization/punctuation form evaluator.
  static String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'revision': revision,
            'prompts': prompts,
            'catalog': WrittenRubric.catalog,
            'content': WrittenRubric.fingerprint,
            'policy':
                'confirmed-final-transcript; ignore-case-terminal-punctuation-whitespace; no-acoustic-score-v1',
          }),
        ),
      )
      .toString();

  SpeakingRubricResult assess(
    String target,
    String response, {
    SpeakingInput input = SpeakingInput.speech,
    bool confirmed = false,
    bool isFinal = true,
  }) {
    SpeakingRubricResult result(
      RubricStatus status,
      List<int>? scores,
      String message,
    ) => SpeakingRubricResult._(
      target,
      response,
      input,
      confirmed,
      isFinal,
      status,
      scores,
      message,
    );
    if (!prompts.containsKey(target) ||
        response.trim().isEmpty ||
        response.length > 1000 ||
        RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(response)) {
      return result(
        RubricStatus.unassessable,
        null,
        'No usable response. Repeat or choose the separate text fallback. No lexical penalty.',
      );
    }
    if (input == SpeakingInput.speech && (!confirmed || !isFinal)) {
      return result(
        RubricStatus.uncertain,
        null,
        'Recognition is unconfirmed or incomplete. Repeat, or confirm the final transcript. No lexical penalty.',
      );
    }
    final key = response
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'[.!?]+$'), '')
        .trim();
    final scores = WrittenRubric.catalog[target]?[key];
    if (scores == null) {
      return result(
        RubricStatus.uncertain,
        null,
        'This sentence may be valid but is outside the finite local catalog. No score is assigned.',
      );
    }
    final message = scores[0] == 0
        ? 'The displayed words do not demonstrate the requested object meaning. Try using the object in the scenario.'
        : scores[1] == 0
        ? 'Object meaning is demonstrated. Describe the requested activity too.'
        : scores[2] == 1
        ? 'Meaning and use are demonstrated. Check articles or subject–verb agreement in the displayed words.'
        : 'Object meaning, contextual use and grammatical pattern are demonstrated in the displayed words.';
    return result(
      RubricStatus.assessed,
      scores,
      '$message Capitalization and punctuation are ignored. This is not a pronunciation or proficiency score.',
    );
  }
}
