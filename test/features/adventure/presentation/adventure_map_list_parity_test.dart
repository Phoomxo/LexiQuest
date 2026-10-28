import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/presentation/widgets/adventure_map.dart';
import 'package:vocab_learning_app/features/adventure/presentation/widgets/adventure_map_list.dart';

void main() {
  testWidgets('Map and List expose every node identity, label and state', (
    tester,
  ) async {
    final nodes = <AdventureNodeSnapshot>[
      for (final state in AdventureNodeState.values)
        AdventureNodeSnapshot(
          nodeId: 'node-${state.name}',
          kind: AdventureNodeKind.mission,
          state: state,
          label: 'Node ${state.name}',
          accessibilityLabel: 'Accessible ${state.name}',
          reasonCode: state.name,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AdventureMap(nodes: nodes)),
        ),
      ),
    );
    for (final node in nodes) {
      expect(
        find.byKey(ValueKey('adventure-map-node:${node.nodeId}')),
        findsOneWidget,
      );
      expect(find.text(node.label), findsOneWidget);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AdventureMapList(nodes: nodes)),
        ),
      ),
    );
    for (final node in nodes) {
      expect(
        find.byKey(ValueKey('adventure-list-node:${node.nodeId}')),
        findsOneWidget,
      );
      expect(find.text(node.label), findsOneWidget);
    }
  });
}
