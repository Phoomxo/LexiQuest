import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';

Finder accessibilityRoleRegion(Finder scope, AccessibilitySemanticRole role) =>
    find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AccessibilitySemanticRegion && widget.role == role,
        description: '${role.name} accessibility region',
      ),
    );

Future<T> withAccessibilitySemantics<T>(
  WidgetTester tester,
  Future<T> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    return await body();
  } finally {
    handle.dispose();
  }
}

void expectInsideAccessibilityRole({
  required Finder scope,
  required Finder descendant,
  required AccessibilitySemanticRole role,
  String? reason,
}) {
  final region = accessibilityRoleRegion(scope, role);
  expect(region, findsAtLeastNWidgets(1), reason: reason);
  expect(
    find.ancestor(of: descendant, matching: region),
    findsOneWidget,
    reason: reason,
  );
}

SemanticsNode semanticsNodeForAccessibilityRole(
  WidgetTester tester, {
  required Finder scope,
  required AccessibilitySemanticRole role,
}) {
  final region = accessibilityRoleRegion(scope, role);
  expect(region, findsOneWidget);
  return tester.getSemantics(region);
}

void expectRenderedAccessibilityTraversal(
  WidgetTester tester, {
  required Finder scope,
  required List<AccessibilitySemanticRole> roles,
  String? reason,
}) {
  final nodesByRole = <List<SemanticsNode>>[
    for (final role in roles)
      _semanticsNodesForAccessibilityRole(tester, scope: scope, role: role),
  ];
  final nodes = nodesByRole.expand((nodes) => nodes).toList(growable: false);
  final commonAncestor = _nearestCommonAncestor(nodes);
  final traversal = _semanticTraversal(commonAncestor).toList(growable: false);
  final positionsByRole = <List<int>>[
    for (final roleNodes in nodesByRole)
      <int>[
        for (final node in roleNodes)
          traversal.indexWhere((entry) => entry.id == node.id),
      ],
  ];

  for (final positions in positionsByRole) {
    expect(positions, everyElement(greaterThanOrEqualTo(0)), reason: reason);
  }
  for (var index = 1; index < positionsByRole.length; index++) {
    expect(
      positionsByRole[index].reduce(
        (left, right) => left < right ? left : right,
      ),
      greaterThan(
        positionsByRole[index - 1].reduce(
          (left, right) => left > right ? left : right,
        ),
      ),
      reason: reason,
    );
  }
}

List<SemanticsNode> _semanticsNodesForAccessibilityRole(
  WidgetTester tester, {
  required Finder scope,
  required AccessibilitySemanticRole role,
}) {
  final region = accessibilityRoleRegion(scope, role);
  expect(region, findsAtLeastNWidgets(1));
  return <SemanticsNode>[
    for (final element in region.evaluate())
      tester.getSemantics(
        find.byElementPredicate((candidate) => identical(candidate, element)),
      ),
  ];
}

SemanticsNode _nearestCommonAncestor(List<SemanticsNode> nodes) {
  if (nodes.isEmpty) {
    throw ArgumentError.value(nodes, 'nodes', 'must not be empty');
  }
  final remainingAncestorIds = <Set<int>>[
    for (final node in nodes.skip(1))
      _semanticAncestors(node).map((ancestor) => ancestor.id).toSet(),
  ];
  return _semanticAncestors(nodes.first).firstWhere(
    (candidate) => remainingAncestorIds.every(
      (ancestorIds) => ancestorIds.contains(candidate.id),
    ),
    orElse: () => throw StateError('semantic roles do not share an ancestor'),
  );
}

Iterable<SemanticsNode> _semanticAncestors(SemanticsNode node) sync* {
  SemanticsNode? current = node;
  while (current != null) {
    yield current;
    current = current.parent;
  }
}

Iterable<SemanticsNode> _semanticTraversal(SemanticsNode node) sync* {
  yield node;
  for (final child in node.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  )) {
    yield* _semanticTraversal(child);
  }
}
