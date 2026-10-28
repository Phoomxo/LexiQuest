import 'package:flutter/material.dart';

import '../../rewards/domain/reward_models.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import '../domain/adventure_reaction.dart';
import 'adventure_mission_sheet.dart';
import 'widgets/adventure_companion_panel.dart';
import 'widgets/adventure_map.dart';
import 'widgets/adventure_map_list.dart';
import 'widgets/adventure_status_panel.dart';
import 'widgets/adventure_standard_switch.dart';

final class AdventureHubScreen extends StatelessWidget {
  const AdventureHubScreen({
    super.key,
    required this.snapshot,
    required this.reaction,
    required this.rewardOwnership,
    required this.onStartMission,
    required this.onPresentationChanged,
    required this.onRefresh,
    this.reactionLanguage,
    this.onStartDialogue,
  });

  final AdventureJourneySnapshot snapshot;
  final AdventureReaction? reaction;
  final RewardAccount rewardOwnership;
  final Future<void> Function(AdventureMissionRef mission) onStartMission;
  final ValueChanged<TodayExperiencePresentation> onPresentationChanged;
  final VoidCallback onRefresh;
  final AdventureReactionLanguage? reactionLanguage;
  final Future<void> Function(AdventureMissionRef mission)? onStartDialogue;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ภารกิจวันนี้'),
      actions: <Widget>[
        IconButton(
          key: const ValueKey('adventure-refresh'),
          onPressed: onRefresh,
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
              onChanged: onPresentationChanged,
            ),
          ),
          const SizedBox(height: 12),
          AdventureStatusPanel(freshness: snapshot.freshness),
          const SizedBox(height: 12),
          AdventureMissionSheet(
            mission: snapshot.primaryMission,
            onStart: onStartMission,
            onStartDialogue: onStartDialogue,
          ),
          const SizedBox(height: 24),
          AdventureCompanionPanel(
            reaction: reaction,
            rewardOwnership: rewardOwnership,
            language: reactionLanguage,
          ),
          if (reaction != null) const SizedBox(height: 12),
          _AdventureJourneyPresentation(nodes: snapshot.nodes),
        ],
      ),
    ),
  );
}

// Keep presentation changes local: the companion, status and mission do not
// need to rebuild when the learner switches between the same journey's views.
final class _AdventureJourneyPresentation extends StatefulWidget {
  const _AdventureJourneyPresentation({required this.nodes});

  final List<AdventureNodeSnapshot> nodes;

  @override
  State<_AdventureJourneyPresentation> createState() =>
      _AdventureJourneyPresentationState();
}

final class _AdventureJourneyPresentationState
    extends State<_AdventureJourneyPresentation>
    with AutomaticKeepAliveClientMixin {
  var _showList = false;
  late Widget _map;
  late Widget _list;

  void _updateViews() {
    _map = AdventureMap(nodes: widget.nodes);
    _list = AdventureMapList(nodes: widget.nodes);
  }

  @override
  void initState() {
    super.initState();
    _updateViews();
  }

  @override
  void didUpdateWidget(covariant _AdventureJourneyPresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateViews();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // Preserve the learner's choice when this section scrolls out of view.
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<bool>(
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
        ),
        const SizedBox(height: 12),
        // Keep the rendered views for the current snapshot. Hidden content
        // contributes neither layout space nor accessibility nodes.
        Visibility(visible: !_showList, maintainState: true, child: _map),
        Visibility(visible: _showList, maintainState: true, child: _list),
      ],
    );
  }
}
