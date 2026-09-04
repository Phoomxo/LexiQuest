import 'package:flutter/material.dart';

import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import 'adventure_mission_sheet.dart';
import 'widgets/adventure_map.dart';
import 'widgets/adventure_map_list.dart';
import 'widgets/adventure_status_panel.dart';
import 'widgets/adventure_standard_switch.dart';

final class AdventureHubScreen extends StatefulWidget {
  const AdventureHubScreen({
    super.key,
    required this.snapshot,
    required this.onStartMission,
    required this.onPresentationChanged,
    required this.onRefresh,
  });

  final AdventureJourneySnapshot snapshot;
  final Future<void> Function(AdventureMissionRef mission) onStartMission;
  final ValueChanged<TodayExperiencePresentation> onPresentationChanged;
  final VoidCallback onRefresh;

  @override
  State<AdventureHubScreen> createState() => _AdventureHubScreenState();
}

final class _AdventureHubScreenState extends State<AdventureHubScreen> {
  var _showList = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ภารกิจวันนี้'),
      actions: <Widget>[
        IconButton(
          key: const ValueKey('adventure-refresh'),
          onPressed: widget.onRefresh,
          tooltip: 'รีเฟรชภารกิจ',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        key: const ValueKey('adventure-hub'),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AdventureStandardSwitch(
              value: TodayExperiencePresentation.adventure,
              onChanged: widget.onPresentationChanged,
            ),
          ),
          const SizedBox(height: 12),
          AdventureStatusPanel(freshness: widget.snapshot.freshness),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            key: const ValueKey('adventure-map-list-switch'),
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.route_outlined),
                label: Text('แผนที่'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.list_alt_outlined),
                label: Text('รายการ'),
              ),
            ],
            selected: <bool>{_showList},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                setState(() => _showList = selection.single);
              }
            },
          ),
          const SizedBox(height: 12),
          if (_showList)
            AdventureMapList(nodes: widget.snapshot.nodes)
          else
            AdventureMap(nodes: widget.snapshot.nodes),
          const SizedBox(height: 12),
          AdventureMissionSheet(
            mission: widget.snapshot.primaryMission,
            onStart: widget.onStartMission,
          ),
        ],
      ),
    ),
  );
}
