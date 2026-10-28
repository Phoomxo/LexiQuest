import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'context_practice.dart';

enum RubricStatus { assessed, uncertain, unassessable }

final class RubricSpan {
  const RubricSpan(this.start, this.end, this.explanation);
  final int start, end;
  final String explanation;
  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'explanation': explanation,
  };
}

/// Supplemental lexical evidence only. There is deliberately no aggregate,
/// canonical correctness adapter, CEFR, SRS or reward field.
final class WrittenRubricResult {
  WrittenRubricResult._(
    this.target,
    this.response,
    this.status,
    List<int>? scores,
    List<RubricSpan> spans,
    this.explanation,
  ) : scores = scores == null ? null : List.unmodifiable(scores),
      spans = List.unmodifiable(spans);
  final String target, response, explanation;
  final RubricStatus status;
  final List<int>? scores;
  final List<RubricSpan> spans;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'rubricRevision': WrittenRubric.revision,
    'inventoryHash': WrittenRubric.fingerprint,
    'provenance': 'local-reviewed-response-catalog/ai-assisted-engineering',
    'target': target,
    'response': response,
    'status': status.name,
    'scores': scores,
    'spans': spans.map((s) => s.toJson()).toList(),
    'explanation': explanation,
  };
  factory WrittenRubricResult.fromJson(Map<String, Object?> json) {
    // Replay the pinned local policy, rejecting invented scores or spans.
    // This decoder is retained for revision 1 when later policies are added.
    if (json['target'] is! String || json['response'] is! String) {
      throw const FormatException('Invalid rubric result');
    }
    final expected = const WrittenRubric().assess(
      json['target'] as String,
      json['response'] as String,
    );
    if (jsonEncode(expected.toJson()) != jsonEncode(json)) {
      throw const FormatException('Unauthenticated rubric result');
    }
    return expected;
  }
}

/// Deliberately finite calibration scope: exact reviewed responses, with only
/// outer whitespace, case and terminal period normalization. New answers are
/// uncertain, never inferred incorrect from absence in this catalog.
final class WrittenRubric {
  const WrittenRubric();
  static const revision = 1;
  static const prompts = {
    'book': 'Write one sentence about reading a book (the object with pages).',
    'pencil':
        'Write one sentence about writing with a pencil (the erasable writing tool).',
    'bottle':
        'Write one sentence about drinking water from a bottle (the container).',
  };
  // [meaning, contextual use, form]; 0 contradicts task, 1 needs repair,
  // 2 demonstrated in this sentence. No interpretation beyond this prompt.
  static const catalog = <String, Map<String, List<int>>>{
    'book': {
      'i read a book': [2, 2, 2],
      'she reads a book': [2, 2, 2],
      'she read a book every day': [2, 2, 2],
      'she reads book': [2, 2, 1],
      'i drink a book': [0, 0, 2],
      'i book a room': [0, 0, 2],
      'i have a book': [2, 0, 2],
    },
    'pencil': {
      'i write with a pencil': [2, 2, 2],
      'she writes with a pencil': [2, 2, 2],
      'she write with a pencil': [2, 2, 1],
      'i pencil in a date': [0, 0, 2],
    },
    'bottle': {
      'i drink water from a bottle': [2, 2, 2],
      'she drinks water from a bottle': [2, 2, 2],
      'she drink water from a bottle': [2, 2, 1],
      'i bottle water': [0, 0, 2],
    },
  };
  static String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'revision': revision,
            'prompts': prompts,
            'catalog': catalog,
            'content': ContextPracticeInventory.fingerprint,
            'normalization':
                'trim/case/one-terminal-period; form-repair-if-noncanonical',
          }),
        ),
      )
      .toString();

  WrittenRubricResult assess(String target, String response) {
    if (!catalog.containsKey(target) ||
        response.trim().isEmpty ||
        response.length > 1000 ||
        RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(response)) {
      return WrittenRubricResult._(
        target,
        response,
        RubricStatus.unassessable,
        null,
        [],
        'Cannot assess this response. Use a supported prompt and 1–1000 characters.',
      );
    }
    final trimmed = response.trim();
    final key = trimmed.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final reviewed = catalog[target]![key];
    if (reviewed == null) {
      return WrittenRubricResult._(
        target,
        response,
        RubricStatus.uncertain,
        null,
        [],
        'This response is outside the reviewed local rubric. It may be valid; no score is assigned.',
      );
    }
    final scores = reviewed.toList();
    if (trimmed != '${key[0].toUpperCase()}${key.substring(1)}.') scores[2] = 1;
    final explanation = scores[0] == 0
        ? 'The sentence does not demonstrate the target object in the requested activity. Its sentence form is assessed separately.'
        : scores[1] == 0
        ? 'The object meaning is demonstrated, but the requested activity is not. Describe the activity in the prompt.'
        : scores[2] == 1
        ? 'The target meaning and use are demonstrated. Check articles, subject–verb agreement, initial capital and final period.'
        : 'The target object, requested use and sentence form are demonstrated here.';
    final start = response.toLowerCase().indexOf(target);
    return WrittenRubricResult._(
      target,
      response,
      RubricStatus.assessed,
      scores,
      [
        RubricSpan(
          start,
          start + target.length,
          scores[0] == 2
              ? 'Target object meaning demonstrated.'
              : 'Does not demonstrate the requested object meaning.',
        ),
        RubricSpan(
          0,
          response.length,
          scores[2] == 2
              ? 'Sentence form follows a reviewed pattern.'
              : 'Sentence form needs revision.',
        ),
      ],
      explanation,
    );
  }
}
