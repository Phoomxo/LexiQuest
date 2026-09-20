import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../learning/domain/context_practice.dart';

/// Original authored language content. Revision one remains readable when
/// entry is disabled. Pins describe content, never learner mastery.
final class DialogueChoice {
  const DialogueChoice({
    required this.id,
    required this.text,
    required this.next,
    required this.objective,
    required this.consequence,
    required this.correct,
  });
  final String id, text, next, objective, consequence;
  final bool correct;
  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'next': next,
    'objective': objective,
    'consequence': consequence,
    'correct': correct,
  };
  factory DialogueChoice.fromJson(Map<String, Object?> j) {
    _keys(j, {'id', 'text', 'next', 'objective', 'consequence', 'correct'});
    return DialogueChoice(
      id: j['id'] as String,
      text: j['text'] as String,
      next: j['next'] as String,
      objective: j['objective'] as String,
      consequence: j['consequence'] as String,
      correct: j['correct'] as bool,
    );
  }
}

final class DialogueNode {
  DialogueNode({
    required this.id,
    required this.scene,
    required this.prompt,
    required this.terminal,
    required this.assisted,
    required this.exitAllowed,
    required List<DialogueChoice> choices,
  }) : choices = List.unmodifiable(choices);
  final String id, scene, prompt;
  final bool terminal, assisted, exitAllowed;
  final List<DialogueChoice> choices;
  Map<String, Object?> toJson() => {
    'id': id,
    'scene': scene,
    'prompt': prompt,
    'terminal': terminal,
    'assisted': assisted,
    'exitAllowed': exitAllowed,
    'choices': [for (final c in choices) c.toJson()],
  };
  factory DialogueNode.fromJson(Map<String, Object?> j) {
    _keys(j, {
      'id',
      'scene',
      'prompt',
      'terminal',
      'assisted',
      'exitAllowed',
      'choices',
    });
    return DialogueNode(
      id: j['id'] as String,
      scene: j['scene'] as String,
      prompt: j['prompt'] as String,
      terminal: j['terminal'] as bool,
      assisted: j['assisted'] as bool,
      exitAllowed: j['exitAllowed'] as bool,
      choices: [
        for (final c in j['choices'] as List)
          DialogueChoice.fromJson(Map<String, Object?>.from(c as Map)),
      ],
    );
  }
}

final class DialogueMission {
  DialogueMission({
    required this.id,
    required this.revision,
    required this.title,
    required this.wordId,
    required this.contentRevision,
    required this.contentHash,
    required this.start,
    required this.maximumTurns,
    required List<DialogueNode> nodes,
  }) : nodes = List.unmodifiable(nodes);
  final String id, title, wordId, contentHash, start;
  final int revision, contentRevision, maximumTurns;
  final List<DialogueNode> nodes;
  DialogueNode node(String id) => nodes.singleWhere((n) => n.id == id);
  String get fingerprint =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'revision': revision,
    'title': title,
    'wordId': wordId,
    'contentRevision': contentRevision,
    'contentHash': contentHash,
    'start': start,
    'maximumTurns': maximumTurns,
    'nodes': [for (final n in nodes) n.toJson()],
  };
  factory DialogueMission.fromJson(Map<String, Object?> j) {
    _keys(j, {
      'schemaVersion',
      'id',
      'revision',
      'title',
      'wordId',
      'contentRevision',
      'contentHash',
      'start',
      'maximumTurns',
      'nodes',
    });
    if (j['schemaVersion'] != 1) {
      throw const FormatException('Unsupported dialogue schema');
    }
    return DialogueMission(
      id: j['id'] as String,
      revision: j['revision'] as int,
      title: j['title'] as String,
      wordId: j['wordId'] as String,
      contentRevision: j['contentRevision'] as int,
      contentHash: j['contentHash'] as String,
      start: j['start'] as String,
      maximumTurns: j['maximumTurns'] as int,
      nodes: [
        for (final n in j['nodes'] as List)
          DialogueNode.fromJson(Map<String, Object?>.from(n as Map)),
      ],
    );
  }
  List<String> validate() {
    final errors = <String>[];
    if (id.trim().isEmpty ||
        title.trim().isEmpty ||
        wordId.trim().isEmpty ||
        revision < 1 ||
        contentRevision < 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash) ||
        maximumTurns < 1 ||
        maximumTurns > 6 ||
        nodes.isEmpty ||
        nodes.length > 32) {
      errors.add('invalid mission bounds or identity');
      return errors;
    }
    final ids = nodes.map((n) => n.id).toSet();
    if (ids.length != nodes.length || !ids.contains(start)) {
      return [...errors, 'invalid node identities'];
    }
    for (final n in nodes) {
      if (n.id.trim().isEmpty ||
          n.scene.trim().isEmpty ||
          !n.exitAllowed ||
          (n.terminal
              ? n.choices.isNotEmpty
              : n.choices.length < 2 || n.prompt.trim().isEmpty) ||
          n.choices.length > 6 ||
          n.choices.map((c) => c.id).toSet().length != n.choices.length ||
          (!n.terminal && n.choices.where((c) => c.correct).length != 1)) {
        errors.add('invalid state ${n.id}');
      }
      for (final c in n.choices) {
        if (c.id.trim().isEmpty ||
            c.text.trim().isEmpty ||
            c.objective.trim().isEmpty ||
            c.consequence.trim().isEmpty ||
            !ids.contains(c.next)) {
          errors.add('invalid branch ${n.id}/${c.id}');
        }
      }
    }
    final reached = <String>{};
    final distances = <String, int>{};
    int visit(String id, Set<String> path) {
      if (path.contains(id)) {
        errors.add('unbounded cycle');
        return maximumTurns + 1;
      }
      if (!ids.contains(id)) return maximumTurns + 1;
      reached.add(id);
      if (distances.containsKey(id)) return distances[id]!;
      final n = node(id);
      if (n.terminal) return 0;
      if (n.choices.isEmpty) return maximumTurns + 1;
      var longest = 0;
      for (final c in n.choices) {
        final length = 1 + visit(c.next, {...path, id});
        if (length > longest) longest = length;
      }
      return distances[id] = longest;
    }

    if (visit(start, {}) > maximumTurns) errors.add('turn budget exceeded');
    if (reached.length != nodes.length) errors.add('unreachable states');
    return List.unmodifiable(errors);
  }
}

final class DialogueMissionInventory {
  static final List<DialogueMission> missions = List.unmodifiable([
    for (final entry in ContextPracticeInventory.entries) _mission(entry),
  ]);
  static DialogueMission? find(String id, String hash) {
    for (final mission in missions) {
      if (mission.id == id && mission.fingerprint == hash) return mission;
    }
    return null;
  }

  static DialogueMission _mission(ContextPracticeEntry e) {
    final scene = switch (e.answer) {
      'book' => 'At the library, Mira asks: “What can I read while I wait?”',
      'pencil' =>
        'At the writing desk, Mira asks: “What can I use to write and erase a letter?”',
      _ =>
        'At the picnic, Mira asks: “Which narrow-neck container holds our water?”',
    };
    const objective =
        'Use the situation and sentence clues to choose the matching object.';
    List<DialogueChoice> choices(bool repair) => [
      DialogueChoice(
        id: 'target',
        text: e.answer,
        next: 'done',
        objective: objective,
        consequence: 'Mira: “That fits what I need.” ${e.correctRationale}',
        correct: true,
      ),
      DialogueChoice(
        id: 'alternative',
        text: e.distractor,
        next: repair ? 'review' : 'repair',
        objective: objective,
        consequence:
            'Mira: “That does not fit this situation.” ${e.distractorRationale}',
        correct: false,
      ),
    ];
    return DialogueMission(
      id: 'dialogue-${e.answer}',
      revision: 1,
      title: switch (e.answer) {
        'book' => 'A wait at the library',
        'pencil' => 'A letter at the writing desk',
        _ => 'Water for the picnic',
      },
      wordId: e.wordId,
      contentRevision: 1,
      contentHash: e.artifactHash,
      start: 'request',
      maximumTurns: 2,
      nodes: [
        DialogueNode(
          id: 'request',
          scene: scene,
          prompt: e.sentence.replaceFirst(e.answer, '___'),
          terminal: false,
          assisted: false,
          exitAllowed: true,
          choices: choices(false),
        ),
        DialogueNode(
          id: 'repair',
          scene:
              'Mira explains: ${e.correctRationale}\nTry the language choice again with this help.',
          prompt: e.sentence.replaceFirst(e.answer, '___'),
          terminal: false,
          assisted: true,
          exitAllowed: true,
          choices: choices(true),
        ),
        DialogueNode(
          id: 'done',
          scene:
              'Mira has the right object. Mission finished. Recognition practice is not independent recall.',
          prompt: '',
          terminal: true,
          assisted: false,
          exitAllowed: true,
          choices: [],
        ),
        DialogueNode(
          id: 'review',
          scene:
              'Mira shows the object: ${e.answer}. Review the explanation, then finish. The first choice remains unchanged.',
          prompt: '',
          terminal: true,
          assisted: true,
          exitAllowed: true,
          choices: [],
        ),
      ],
    );
  }
}

void _keys(Map<String, Object?> j, Set<String> expected) {
  if (j.length != expected.length || !j.keys.every(expected.contains)) {
    throw const FormatException('Invalid dialogue keys');
  }
}
