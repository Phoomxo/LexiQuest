import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/dialogue_mission.dart';

void main() {
  test(
    'GRAPH-EXIT every authored choice has an objective and bounded exit',
    () {
      for (final graph in DialogueMissionInventory.missions) {
        expect(graph.validate(), isEmpty);
        expect(graph.maximumTurns, lessThanOrEqualTo(6));
        expect(graph.nodes.every((n) => n.exitAllowed), isTrue);
        final answer = graph
            .node(graph.start)
            .choices
            .singleWhere((c) => c.correct)
            .text;
        expect(graph.title.toLowerCase().contains(answer), isFalse);
        expect(
          graph
              .node(graph.start)
              .choices
              .first
              .objective
              .toLowerCase()
              .contains(answer),
          isFalse,
        );
        for (final node in graph.nodes.where((n) => !n.terminal)) {
          expect(node.choices.length, greaterThanOrEqualTo(2));
          expect(
            node.choices.every(
              (c) =>
                  c.objective.trim().isNotEmpty &&
                  c.consequence.trim().isNotEmpty,
            ),
            isTrue,
          );
        }
        expect(
          DialogueMission.fromJson(graph.toJson()).fingerprint,
          graph.fingerprint,
        );
      }
    },
  );
  test(
    'GRAPH-CYCLE rejects cyclic, unreachable, missing and dead-end nodes',
    () {
      final original = DialogueMissionInventory.missions.first.toJson();
      for (final defect in [
        'cycle',
        'missing',
        'dead',
        'objective',
        'exit',
        'budget',
        'unreachable',
      ]) {
        final graph = DialogueMission.fromJson(original);
        final json = graph.toJson();
        final nodes = json['nodes'] as List;
        final first = nodes.first as Map;
        final choices = first['choices'] as List;
        if (defect == 'cycle') (choices.first as Map)['next'] = first['id'];
        if (defect == 'missing') (choices.first as Map)['next'] = 'missing';
        if (defect == 'dead') first['choices'] = [];
        if (defect == 'objective') (choices.first as Map)['objective'] = '';
        if (defect == 'exit') first['exitAllowed'] = false;
        if (defect == 'budget') json['maximumTurns'] = 1;
        if (defect == 'unreachable') {
          nodes.add({
            ...Map<String, Object?>.from(nodes.last as Map),
            'id': 'unreachable',
          });
        }
        expect(
          DialogueMission.fromJson(json).validate(),
          isNotEmpty,
          reason: defect,
        );
      }
    },
  );
  test('scenario changes cannot preserve the exact content pin', () {
    final graph = DialogueMissionInventory.missions.first;
    final changed = graph.toJson()..['revision'] = 2;
    expect(
      DialogueMission.fromJson(changed).fingerprint,
      isNot(graph.fingerprint),
    );
  });
}
