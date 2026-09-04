import 'package:flutter/material.dart';

import '../../domain/adventure_journey.dart';

final class AdventureMap extends StatelessWidget {
  const AdventureMap({super.key, required this.nodes});

  final List<AdventureNodeSnapshot> nodes;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'แผนที่ภารกิจ ${nodes.length} จุด',
    child: Column(
      key: const ValueKey('adventure-map'),
      children: <Widget>[
        for (final (index, node) in nodes.indexed) ...<Widget>[
          _MapNode(node: node),
          if (index != nodes.length - 1)
            const Icon(Icons.more_vert, semanticLabel: 'เส้นทางไปจุดถัดไป'),
        ],
      ],
    ),
  );
}

final class _MapNode extends StatelessWidget {
  const _MapNode({required this.node});

  final AdventureNodeSnapshot node;

  @override
  Widget build(BuildContext context) {
    final (icon, stateLabel) = _nodePresentation(node.state);
    return Semantics(
      container: true,
      label: '${node.accessibilityLabel}, $stateLabel',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Card(
          key: ValueKey<String>('adventure-map-node:${node.nodeId}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(child: Text(node.label)),
                Text(stateLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

(IconData, String) _nodePresentation(AdventureNodeState state) =>
    switch (state) {
      AdventureNodeState.hidden => (Icons.visibility_off_outlined, 'ซ่อนอยู่'),
      AdventureNodeState.locked => (Icons.lock_outline, 'ยังล็อก'),
      AdventureNodeState.available => (Icons.flag_outlined, 'พร้อม'),
      AdventureNodeState.current => (Icons.play_circle_outline, 'กำลังทำ'),
      AdventureNodeState.completed => (Icons.check_circle, 'เสร็จแล้ว'),
      AdventureNodeState.unavailable => (Icons.block_outlined, 'ไม่พร้อม'),
    };
