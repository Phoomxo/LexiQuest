import 'package:flutter/material.dart';

import '../../today_hub/application/today_hub_use_cases.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../../screens/today_hub_view.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../application/adventure_entry_use_cases.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import '../domain/adventure_world_catalog.dart';
import 'adventure_hub_screen.dart';
import 'widgets/adventure_standard_switch.dart';

typedef AdventureUtcNow = DateTime Function();
typedef AdventurePresentationPreferenceSaver =
    Future<void> Function(TodayExperiencePresentation presentation);

final class AdventureMissionLaunchContext {
  const AdventureMissionLaunchContext({
    required this.mission,
    required this.today,
    required this.entryDecision,
  });

  final AdventureMissionRef mission;
  final TodayHubSnapshot today;
  final AdventureProductEntryDecision entryDecision;
}

final class TodayExperienceHost extends StatefulWidget {
  const TodayExperienceHost({
    super.key,
    required this.ownerId,
    required this.entry,
    required this.activePermits,
    required this.todayHub,
    required this.catalog,
    required this.journey,
    required this.createEntryAttemptId,
    required this.nowUtc,
    required this.actions,
    required this.features,
    required this.assessmentAvailable,
    required this.onStartMission,
    this.onPresentationPreferenceChanged,
  });

  final String ownerId;
  final AdventureEntryUseCases entry;
  final ActivePresentationPermitReader activePermits;
  final TodayHubSnapshotLoader todayHub;
  final AdventureWorldCatalog catalog;
  final AdventureJourneyReader journey;
  final AdventureEntryAttemptIdFactory createEntryAttemptId;
  final AdventureUtcNow nowUtc;
  final TodayHubActionDelegate actions;
  final FeatureRegistry features;
  final bool assessmentAvailable;
  final Future<void> Function(AdventureMissionLaunchContext launch)
  onStartMission;
  final AdventurePresentationPreferenceSaver? onPresentationPreferenceChanged;

  @override
  State<TodayExperienceHost> createState() => _TodayExperienceHostState();
}

final class _TodayExperienceModel {
  const _TodayExperienceModel({required this.result, this.journey});

  final AdventureEntryHostResult? result;
  final AdventureJourneySnapshot? journey;
}

final class _TodayExperienceHostState extends State<TodayExperienceHost> {
  late AdventureEntryHost _entryHost;
  late Future<_TodayExperienceModel> _loadFuture;
  TodayExperiencePresentation? _sessionChoice;
  late DateTime _occurredAtUtc;
  var _refreshGeneration = 0;
  var _permitControlsPresentation = false;

  @override
  void initState() {
    super.initState();
    _startNewOpening();
  }

  @override
  void didUpdateWidget(TodayExperienceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        !identical(oldWidget.entry, widget.entry) ||
        !identical(oldWidget.todayHub, widget.todayHub) ||
        !identical(oldWidget.activePermits, widget.activePermits) ||
        !identical(oldWidget.catalog, widget.catalog) ||
        !identical(oldWidget.journey, widget.journey)) {
      _sessionChoice = null;
      _startNewOpening();
    }
  }

  void _startNewOpening() {
    _refreshGeneration += 1;
    _occurredAtUtc = widget.nowUtc();
    _entryHost = AdventureEntryHost(
      entry: widget.entry,
      activePermits: widget.activePermits,
      todayHub: widget.todayHub,
      createEntryAttemptId: widget.createEntryAttemptId,
    );
    _loadFuture = _load(_refreshGeneration, _entryHost);
  }

  Future<_TodayExperienceModel> _load(
    int generation,
    AdventureEntryHost host,
  ) async {
    final result = await host.open(
      ownerId: widget.ownerId,
      occurredAtUtc: _occurredAtUtc,
      sessionChoice: _sessionChoice,
    );
    if (generation != _refreshGeneration || result?.today == null) {
      return _TodayExperienceModel(result: result);
    }
    _permitControlsPresentation = result!.decision.permitId != null;
    final decision = result.decision;
    if (decision.destination != AdventureEntryDestination.adventure) {
      return _TodayExperienceModel(result: result);
    }
    final journeyNow = widget.nowUtc();
    final evaluatedAt = journeyNow.isBefore(result.today!.evaluatedAtUtc)
        ? result.today!.evaluatedAtUtc
        : journeyNow;
    final projected = await widget.journey.compose(
      AdventureJourneyRequest(
        ownerId: widget.ownerId,
        evaluatedAtUtc: evaluatedAt,
        catalog: widget.catalog,
        today: result.today!,
      ),
    );
    if (generation != _refreshGeneration) {
      return const _TodayExperienceModel(result: null);
    }
    return _TodayExperienceModel(result: result, journey: projected);
  }

  void _switch(TodayExperiencePresentation choice) {
    if (_sessionChoice == choice) return;
    setState(() {
      _sessionChoice = choice;
      _loadFuture = _load(_refreshGeneration, _entryHost);
    });
    if (!_permitControlsPresentation) {
      widget.onPresentationPreferenceChanged?.call(choice).catchError((_) {});
    }
  }

  void _refresh() {
    setState(_startNewOpening);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TodayExperienceModel>(
    future: _loadFuture,
    builder: (context, state) {
      if (state.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: const TodayHubLoading(),
        );
      }
      if (state.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: TodayHubLoadFailure(onRetry: _refresh),
        );
      }
      final model = state.data;
      final result = model?.result;
      final today = result?.today;
      if (result == null || today == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: _UnavailableState(onRefresh: _refresh),
        );
      }
      final journey = model?.journey;
      if (result.decision.destination == AdventureEntryDestination.adventure &&
          journey != null) {
        return AdventureHubScreen(
          snapshot: journey,
          onStartMission: (mission) => widget.onStartMission(
            AdventureMissionLaunchContext(
              mission: mission,
              today: today,
              entryDecision: result.decision,
            ),
          ),
          onPresentationChanged: _switch,
          onRefresh: _refresh,
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('กิจกรรมวันนี้'),
          actions: <Widget>[
            IconButton(
              key: const ValueKey('adventure-refresh'),
              onPressed: _refresh,
              tooltip: 'รีเฟรชกิจกรรมวันนี้',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AdventureStandardSwitch(
                  value: TodayExperiencePresentation.standard,
                  onChanged: _switch,
                ),
              ),
            ),
            Expanded(
              child: TodayHubView(
                snapshot: today,
                actions: widget.actions,
                features: widget.features,
                assessmentAvailable: widget.assessmentAvailable,
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.explore_off_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'กิจกรรมแบบผจญภัยยังไม่พร้อม รายการเรียนเดิมของคุณไม่เปลี่ยนแปลง',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('adventure-refresh'),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('รีเฟรช'),
          ),
        ],
      ),
    ),
  );
}
