import 'dart:async';

import 'package:flutter/material.dart';

import '../../today_hub/application/today_hub_use_cases.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../../rewards/domain/reward_models.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../../screens/today_hub_view.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../application/adventure_entry_use_cases.dart';
import '../application/adventure_presentation_preferences.dart';
import '../application/adventure_reaction_selector.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import '../domain/adventure_reaction.dart';
import '../domain/adventure_world_catalog.dart';
import 'adventure_hub_screen.dart';
import 'widgets/adventure_standard_switch.dart';

typedef AdventureUtcNow = DateTime Function();

final class AdventureMissionLaunchContext {
  const AdventureMissionLaunchContext({
    required this.mission,
    required this.today,
    required this.entryDecision,
    required this.rewardOwnership,
  });

  final AdventureMissionRef mission;
  final TodayHubSnapshot today;
  final AdventureProductEntryDecision entryDecision;
  final RewardAccount rewardOwnership;
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
    required this.rewardAccounts,
    required this.createEntryAttemptId,
    required this.nowUtc,
    required this.actions,
    required this.features,
    required this.assessmentAvailable,
    required this.onStartMission,
    this.presentationPreferences,
  });

  final String ownerId;
  final AdventureEntryUseCases entry;
  final ActivePresentationPermitReader activePermits;
  final TodayHubSnapshotLoader todayHub;
  final AdventureWorldCatalog catalog;
  final AdventureJourneyReader journey;
  final RewardAccountReader rewardAccounts;
  final AdventureEntryAttemptIdFactory createEntryAttemptId;
  final AdventureUtcNow nowUtc;
  final TodayHubActionDelegate actions;
  final FeatureRegistry features;
  final bool assessmentAvailable;
  final Future<void> Function(AdventureMissionLaunchContext launch)
  onStartMission;
  final AdventurePresentationPreferenceWriter? presentationPreferences;

  @override
  State<TodayExperienceHost> createState() => _TodayExperienceHostState();
}

final class _TodayExperienceModel {
  const _TodayExperienceModel({
    required this.result,
    this.journey,
    this.rewardOwnership,
  });

  final AdventureEntryHostResult? result;
  final AdventureJourneySnapshot? journey;
  final RewardAccount? rewardOwnership;
}

final class _TodayExperienceHostState extends State<TodayExperienceHost> {
  late AdventureEntryHost _entryHost;
  late Future<_TodayExperienceModel> _loadFuture;
  TodayExperiencePresentation? _sessionChoice;
  late DateTime _occurredAtUtc;
  var _refreshGeneration = 0;
  var _presentationGeneration = 0;
  var _preferenceGeneration = 0;
  bool? _permitControlsPresentation;
  _PresentationSaveRun? _activePresentationSave;
  _QueuedPresentationSave? _queuedPresentationSave;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _presentationSaveFailure;

  @override
  void initState() {
    super.initState();
    _startNewOpening();
  }

  @override
  void didUpdateWidget(TodayExperienceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        !identical(
          oldWidget.presentationPreferences,
          widget.presentationPreferences,
        )) {
      _preferenceGeneration += 1;
      _activePresentationSave = null;
      _queuedPresentationSave = null;
      _clearPresentationSaveFailure();
    }
    if (oldWidget.ownerId != widget.ownerId ||
        !identical(oldWidget.entry, widget.entry) ||
        !identical(oldWidget.todayHub, widget.todayHub) ||
        !identical(oldWidget.activePermits, widget.activePermits) ||
        !identical(oldWidget.catalog, widget.catalog) ||
        !identical(oldWidget.journey, widget.journey) ||
        !identical(oldWidget.rewardAccounts, widget.rewardAccounts)) {
      _sessionChoice = null;
      _startNewOpening();
    }
  }

  void _startNewOpening() {
    _sessionChoice = null;
    _permitControlsPresentation = null;
    _queuedPresentationSave = null;
    _clearPresentationSaveFailure();
    _refreshGeneration += 1;
    _presentationGeneration += 1;
    _occurredAtUtc = widget.nowUtc();
    _entryHost = AdventureEntryHost(
      entry: widget.entry,
      activePermits: widget.activePermits,
      todayHub: widget.todayHub,
      createEntryAttemptId: widget.createEntryAttemptId,
    );
    _loadFuture = _load(
      _refreshGeneration,
      _presentationGeneration,
      _entryHost,
      _sessionChoice,
    );
  }

  Future<_TodayExperienceModel> _load(
    int refreshGeneration,
    int presentationGeneration,
    AdventureEntryHost host,
    TodayExperiencePresentation? sessionChoice,
  ) async {
    final result = await host.open(
      ownerId: widget.ownerId,
      occurredAtUtc: _occurredAtUtc,
      sessionChoice: sessionChoice,
    );
    if (refreshGeneration != _refreshGeneration || result?.today == null) {
      return _TodayExperienceModel(result: result);
    }
    if (presentationGeneration != _presentationGeneration) {
      return _TodayExperienceModel(result: result);
    }
    _permitControlsPresentation = result!.decision.permitId != null;
    if (_permitControlsPresentation == false && sessionChoice != null) {
      _queuePresentationSave(
        sessionChoice,
        presentationGeneration: presentationGeneration,
      );
    }
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
    final rewardOwnership = await widget.rewardAccounts.loadForOwner(
      widget.ownerId,
    );
    if (refreshGeneration != _refreshGeneration ||
        presentationGeneration != _presentationGeneration) {
      return const _TodayExperienceModel(result: null);
    }
    return _TodayExperienceModel(
      result: result,
      journey: projected,
      rewardOwnership: rewardOwnership,
    );
  }

  void _switch(TodayExperiencePresentation choice) {
    if (_sessionChoice == choice) return;
    final presentationGeneration = _presentationGeneration + 1;
    setState(() {
      _sessionChoice = choice;
      _presentationGeneration = presentationGeneration;
      _permitControlsPresentation = null;
      _queuedPresentationSave = null;
      _loadFuture = _load(
        _refreshGeneration,
        presentationGeneration,
        _entryHost,
        choice,
      );
    });
    _clearPresentationSaveFailure();
  }

  void _queuePresentationSave(
    TodayExperiencePresentation choice, {
    int? presentationGeneration,
  }) {
    final queuedGeneration = presentationGeneration ?? _presentationGeneration;
    final saver = widget.presentationPreferences;
    if (saver == null ||
        _permitControlsPresentation != false ||
        queuedGeneration != _presentationGeneration) {
      return;
    }
    _queuedPresentationSave = _QueuedPresentationSave(
      presentationGeneration: queuedGeneration,
      choice: choice,
    );
    final current = _activePresentationSave;
    if (current != null && current.generation == _preferenceGeneration) return;
    final run = _PresentationSaveRun(
      generation: _preferenceGeneration,
      ownerId: widget.ownerId,
      saver: saver,
    );
    _activePresentationSave = run;
    unawaited(_drainPresentationSaves(run));
  }

  Future<void> _drainPresentationSaves(_PresentationSaveRun run) async {
    try {
      while (_isCurrentSaveRun(run)) {
        final queued = _queuedPresentationSave;
        if (queued == null) return;
        _queuedPresentationSave = null;
        if (!_isCurrentPresentationSave(queued)) continue;
        try {
          await run.saver.saveForOwner(run.ownerId, queued.choice);
          if (!_isCurrentSaveRun(run)) return;
          if (_queuedPresentationSave == null &&
              _isCurrentPresentationSave(queued)) {
            _clearPresentationSaveFailure();
          }
        } catch (_) {
          if (!_isCurrentSaveRun(run)) return;
          if (_queuedPresentationSave == null &&
              _isCurrentPresentationSave(queued)) {
            _showPresentationSaveFailure(queued.choice);
          }
        }
      }
    } finally {
      if (identical(_activePresentationSave, run)) {
        _activePresentationSave = null;
      }
    }
  }

  bool _isCurrentSaveRun(_PresentationSaveRun run) =>
      mounted &&
      identical(_activePresentationSave, run) &&
      run.generation == _preferenceGeneration &&
      run.ownerId == widget.ownerId;

  bool _isCurrentPresentationSave(_QueuedPresentationSave queued) =>
      queued.presentationGeneration == _presentationGeneration &&
      _permitControlsPresentation == false &&
      _sessionChoice == queued.choice;

  void _showPresentationSaveFailure(TodayExperiencePresentation choice) {
    final messenger = ScaffoldMessenger.of(context);
    _clearPresentationSaveFailure();
    _presentationSaveFailure = messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('today-presentation-save-failure'),
        content: const Text('บันทึกรูปแบบหน้าวันนี้ไม่สำเร็จ'),
        action: SnackBarAction(
          label: 'ลองอีกครั้ง',
          onPressed: () {
            if (_sessionChoice == choice) _queuePresentationSave(choice);
          },
        ),
      ),
    );
  }

  void _clearPresentationSaveFailure() {
    _presentationSaveFailure?.close();
    _presentationSaveFailure = null;
  }

  void _refresh() {
    setState(_startNewOpening);
  }

  @override
  void dispose() {
    _preferenceGeneration += 1;
    _activePresentationSave = null;
    _queuedPresentationSave = null;
    _clearPresentationSaveFailure();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TodayExperienceModel>(
    future: _loadFuture,
    builder: (context, state) {
      if (state.connectionState != ConnectionState.done) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: _standardEscapeBody(const TodayHubLoading()),
        );
      }
      if (state.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: _standardEscapeBody(TodayHubLoadFailure(onRetry: _refresh)),
        );
      }
      final model = state.data;
      final result = model?.result;
      final today = result?.today;
      if (result == null || today == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('กิจกรรมวันนี้')),
          body: _standardEscapeBody(_UnavailableState(onRefresh: _refresh)),
        );
      }
      final journey = model?.journey;
      final rewardOwnership = model?.rewardOwnership;
      if (result.decision.destination == AdventureEntryDestination.adventure &&
          journey != null &&
          rewardOwnership != null) {
        final reaction = journey.primaryMission == null
            ? null
            : const AdventureReactionSelector().select(
                catalogVersion: journey.catalogVersion,
                trigger: AdventureReactionTrigger.missionReady,
                variantSeed: 0,
              );
        return AdventureHubScreen(
          snapshot: journey,
          reaction: reaction,
          rewardOwnership: rewardOwnership,
          reactionLanguage: widget.catalog.locale == 'th'
              ? AdventureReactionLanguage.th
              : AdventureReactionLanguage.en,
          onStartMission: (mission) => widget.onStartMission(
            AdventureMissionLaunchContext(
              mission: mission,
              today: today,
              entryDecision: result.decision,
              rewardOwnership: rewardOwnership,
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
        body: _standardEscapeBody(
          TodayHubView(
            snapshot: today,
            actions: widget.actions,
            features: widget.features,
            assessmentAvailable: widget.assessmentAvailable,
          ),
          presentation: TodayExperiencePresentation.standard,
        ),
      );
    },
  );

  Widget _standardEscapeBody(
    Widget child, {
    TodayExperiencePresentation? presentation,
  }) => Column(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AdventureStandardSwitch(
            value:
                presentation ??
                _sessionChoice ??
                TodayExperiencePresentation.adventure,
            onChanged: _switch,
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );
}

final class _PresentationSaveRun {
  const _PresentationSaveRun({
    required this.generation,
    required this.ownerId,
    required this.saver,
  });

  final int generation;
  final String ownerId;
  final AdventurePresentationPreferenceWriter saver;
}

final class _QueuedPresentationSave {
  const _QueuedPresentationSave({
    required this.presentationGeneration,
    required this.choice,
  });

  final int presentationGeneration;
  final TodayExperiencePresentation choice;
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
