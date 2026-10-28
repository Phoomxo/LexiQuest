import 'package:flutter/material.dart';

import '../../domain/adventure_journey.dart';

final class AdventureMapList extends StatelessWidget {
  const AdventureMapList({super.key, required this.nodes});

  final List<AdventureNodeSnapshot> nodes;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'รายการภารกิจ ${nodes.length} จุด',
    child: Column(
      key: const ValueKey('adventure-map-list'),
      children: <Widget>[
        for (final node in nodes)
          Semantics(
            label: '${node.accessibilityLabel}, ${_label(node.state)}',
            excludeSemantics: true,
            child: ListTile(
              key: ValueKey<String>('adventure-list-node:${node.nodeId}'),
              minTileHeight: 48,
              leading: Icon(_icon(node.state)),
              title: Text(node.label),
              subtitle: Text(_label(node.state)),
            ),
          ),
      ],
    ),
  );
}

IconData _icon(AdventureNodeState state) => switch (state) {
  AdventureNodeState.hidden => Icons.visibility_off_outlined,
  AdventureNodeState.locked => Icons.lock_outline,
  AdventureNodeState.available => Icons.flag_outlined,
  AdventureNodeState.current => Icons.play_circle_outline,
  AdventureNodeState.completed => Icons.check_circle,
  AdventureNodeState.unavailable => Icons.block_outlined,
};

String _label(AdventureNodeState state) => switch (state) {
  AdventureNodeState.hidden => 'ซ่อนอยู่',
  AdventureNodeState.locked => 'ยังล็อก',
  AdventureNodeState.available => 'พร้อม',
  AdventureNodeState.current => 'กำลังทำ',
  AdventureNodeState.completed => 'เสร็จแล้ว',
  AdventureNodeState.unavailable => 'ไม่พร้อม',
};
