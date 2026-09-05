import 'dart:async';

import 'package:flutter/material.dart';

import '../../today_hub/application/today_hub_use_cases.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../../rewards/domain/reward_models.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../research/application/adventure_research_runtime.dart';
import '../../research/domain/measurement_opportunity.dart';
import '../../research/domain/motivation_measurement.dart';
import '../../research/domain/motivation_instrument.dart';
import '../../research/presentation/motivation_measurement_form.dart';
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
    this.research,
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
  final AdventureResearchRuntime? research;

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

final class _TodayExperienceHostState extends State<TodayExperienceHost>
    with WidgetsBindingObserver {
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
  MotivationMeasurementRun? _researchRun;
  MeasurementOpportunity? _researchOpportunity;
  StreamSubscription<void>? _researchChanges;
  Timer? _researchExpiry;
  Timer? _postPromptExpiry;
  bool _researchSuppressed = false;
  bool _researchRefreshing = false;
  bool _recordingResearchPresentation = false;
  int _recordedResearchGeneration = -1;
  final _pendingResearchPresentations = <_ResearchPresentationRecord>[];
  bool _researchCaptureFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startNewOpening();
    _observeResearch();
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
        !identical(oldWidget.rewardAccounts, widget.rewardAccounts) ||
        !identical(oldWidget.research, widget.research)) {
      _sessionChoice = null;
      _startNewOpening();
      _observeResearch();
    }
  }

  void _startNewOpening() {
    _researchRun = null;
    _researchOpportunity = null;
    _researchSuppressed = false;
    _recordedResearchGeneration = -1;
    _pendingResearchPresentations.clear();
    _researchCaptureFailed = false;
    _researchExpiry?.cancel();
    _postPromptExpiry?.cancel();
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
    if (widget.research != null &&
        !await widget.research!.isCurrentOwner(widget.ownerId)) {
      return const _TodayExperienceModel(result: null);
    }
    var result = await host.open(
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
    final research = widget.research;
    if (research != null && !await research.isCurrentOwner(widget.ownerId)) {
      return const _TodayExperienceModel(result: null);
    }
    if (research != null && result!.decision.permitId != null) {
      if (!_researchSuppressed) {
        try {
          final run = await research.useCases.prepare(
            ownerId: widget.ownerId,
            permitId: result.decision.permitId!,
          );
          if (refreshGeneration != _refreshGeneration ||
              presentationGeneration != _presentationGeneration) {
            return const _TodayExperienceModel(result: null);
          }
          _researchRun = run;
          _schedulePostPromptExpiry();
          if (run != null) {
            _researchOpportunity = await research.useCases.open(
              ownerId: widget.ownerId,
              runId: run.id,
              entryAttemptId: result.decision.entryAttemptId,
              presentation:
                  result.decision.destination ==
                      AdventureEntryDestination.adventure
                  ? TodayExperiencePresentation.adventure
                  : TodayExperiencePresentation.standard,
            );
            final permit = await research.currentPermit(widget.ownerId);
            _schedulePermitExpiry(permit);
          }
          if (run == null || _researchOpportunity == null) {
            _researchSuppressed = true;
          }
        } on Object {
          _researchSuppressed = true;
        }
      }
      if (refreshGeneration != _refreshGeneration ||
          presentationGeneration != _presentationGeneration) {
        return const _TodayExperienceModel(result: null);
      }
      if (_researchSuppressed) {
        _researchRun = null;
        _researchOpportunity = null;
        final ordinary = await widget.entry.resolve(
          AdventureEntryRequest(
            ownerId: widget.ownerId,
            entryAttemptId: result.decision.entryAttemptId,
            occurredAtUtc: widget.nowUtc(),
            sessionChoice:
                sessionChoice ?? TodayExperiencePresentation.standard,
          ),
        );
        result = AdventureEntryHostResult(
          decision: ordinary,
          today: result.today,
        );
      }
    }
    _permitControlsPresentation = result!.decision.permitId != null;
    if (_permitControlsPresentation == false && sessionChoice != null) {
      _queuePresentationSave(
        sessionChoice,
        presentationGeneration: presentationGeneration,
      );
    }
    final decision = result.decision;
    if (_researchPrompt != null) return _TodayExperienceModel(result: result);
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

  MotivationTimepoint? get _researchPrompt {
    final run = _researchRun;
    if (_researchSuppressed ||
        run == null ||
        run.state != MotivationMeasurementRunState.started) {
      return null;
    }
    if (run.score(MotivationTimepoint.baseline) == null) {
      return MotivationTimepoint.baseline;
    }
    final completion = run.indexCompletionAtUtc;
    final now = widget.nowUtc();
    if (completion != null &&
        !now.isBefore(completion) &&
        !now.isAfter(completion.add(const Duration(minutes: 30))) &&
        run.score(MotivationTimepoint.post) == null) {
      return MotivationTimepoint.post;
    }
    return null;
  }

  void _schedulePostPromptExpiry() {
    _postPromptExpiry?.cancel();
    final run = _researchRun;
    final completion = run?.indexCompletionAtUtc;
    if (run == null ||
        completion == null ||
        run.state != MotivationMeasurementRunState.started ||
        run.score(MotivationTimepoint.post) != null) {
      return;
    }
    // The response window includes its endpoint. Retire the optional form on
    // the first millisecond after it without loading another Today snapshot.
    final deadline = completion.add(
      const Duration(minutes: 30, milliseconds: 1),
    );
    final remaining = deadline.difference(widget.nowUtc());
    if (remaining.isNegative || remaining == Duration.zero) return;
    final generation = _refreshGeneration;
    _postPromptExpiry = Timer(remaining, () {
      if (mounted && generation == _refreshGeneration) setState(() {});
    });
  }

  void _schedulePermitExpiry(ResearchParticipationPermit? permit) {
    _researchExpiry?.cancel();
    if (permit == null) return;
    final remaining = permit.expiresAtUtc.difference(widget.nowUtc());
    if (remaining.isNegative || remaining == Duration.zero) return;
    final generation = _refreshGeneration;
    _researchExpiry = Timer(remaining, () {
      if (mounted && generation == _refreshGeneration) {
        unawaited(_refreshResearch());
      }
    });
  }

  void _observeResearch() {
    unawaited(_researchChanges?.cancel());
    _researchChanges = widget.research?.useCases
        .watch(widget.ownerId)
        .listen(
          (_) => _refreshResearch(),
          onError: (Object _, StackTrace _) {},
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshResearch();
  }

  Future<void> _refreshResearch() async {
    final research = widget.research;
    final run = _researchRun;
    if (!mounted || research == null || _researchRefreshing) return;
    _researchRefreshing = true;
    final generation = _refreshGeneration;
    final ownerId = widget.ownerId;
    try {
      final currentOwner = await research.isCurrentOwner(ownerId);
      if (!mounted ||
          generation != _refreshGeneration ||
          ownerId != widget.ownerId) {
        return;
      }
      if (!currentOwner) {
        setState(() {
          _refreshGeneration++;
          _researchRun = null;
          _researchOpportunity = null;
          _researchSuppressed = true;
          _loadFuture = Future.value(const _TodayExperienceModel(result: null));
        });
        return;
      }
      if (run == null) return;
      await research.useCases.reconcile(ownerId);
      final current = await research.measurements.load(ownerId, run.id);
      final permit = await research.currentPermit(ownerId);
      if (!mounted ||
          generation != _refreshGeneration ||
          ownerId != widget.ownerId) {
        return;
      }
      setState(() {
        _researchRun = current;
        _schedulePostPromptExpiry();
        _schedulePermitExpiry(permit);
        if (permit == null ||
            current?.state != MotivationMeasurementRunState.started) {
          _researchSuppressed = true;
          _loadFuture = _load(
            _refreshGeneration,
            _presentationGeneration,
            _entryHost,
            _sessionChoice,
          );
        }
      });
    } on Object {
      // Canonical learning remains available. No unbounded retry or raw errors.
    } finally {
      _researchRefreshing = false;
    }
  }

  Future<void> _finishResearchPrompt({
    bool skip = false,
    bool withdraw = false,
  }) async {
    final research = widget.research;
    final run = _researchRun;
    if (research == null || run == null) return;
    final ownerId = widget.ownerId;
    final generation = _refreshGeneration;
    if (withdraw) {
      await research.withdraw(ownerId);
    } else if (skip || _researchPrompt == MotivationTimepoint.post) {
      await research.useCases.close(
        MotivationMeasurementClose(
          ownerId: ownerId,
          runId: run.id,
          state: skip
              ? MotivationMeasurementRunState.skipped
              : MotivationMeasurementRunState.completed,
        ),
      );
    }
    if (!mounted ||
        generation != _refreshGeneration ||
        ownerId != widget.ownerId) {
      return;
    }
    setState(() {
      if (skip || withdraw) _researchSuppressed = true;
      _loadFuture = _load(
        _refreshGeneration,
        _presentationGeneration,
        _entryHost,
        _sessionChoice,
      );
    });
    // The form's acknowledgement includes the transition, not just the write.
    // Keep its callback alive until the new validated snapshot is available.
    await _loadFuture;
  }

  void _recordResearchPresentation(AdventureProductEntryDecision decision) {
    final research = widget.research;
    final opportunity = _researchOpportunity;
    final generation = _presentationGeneration;
    if (research == null ||
        opportunity == null ||
        _researchSuppressed ||
        _recordedResearchGeneration == generation) {
      return;
    }
    _recordedResearchGeneration = generation;
    final opening = _refreshGeneration;
    final ownerId = widget.ownerId;
    final presentation =
        decision.destination == AdventureEntryDestination.adventure
        ? TodayExperiencePresentation.adventure
        : TodayExperiencePresentation.standard;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          opening != _refreshGeneration ||
          generation != _presentationGeneration ||
          ownerId != widget.ownerId) {
        return;
      }
      // Queue every actually rendered transition. An earlier post-commit hook
      // must not discard switches or coalesce the first ten observable facts.
      _pendingResearchPresentations.add(
        _ResearchPresentationRecord(
          research: research,
          ownerId: ownerId,
          opportunityId: opportunity.id,
          opening: opening,
          presentation: presentation,
        ),
      );
      unawaited(_drainResearchPresentations());
    });
  }

  bool _isCurrentResearchRecord(_ResearchPresentationRecord record) =>
      mounted &&
      record.opening == _refreshGeneration &&
      record.ownerId == widget.ownerId &&
      identical(record.research, widget.research);

  Future<void> _drainResearchPresentations() async {
    if (_recordingResearchPresentation || _researchCaptureFailed) return;
    _recordingResearchPresentation = true;
    var changed = false;
    try {
      while (_pendingResearchPresentations.isNotEmpty) {
        final record = _pendingResearchPresentations.first;
        if (!_isCurrentResearchRecord(record)) {
          _pendingResearchPresentations.remove(record);
          continue;
        }
        try {
          var current = await record.research.useCases.recordPresented(
            record.ownerId,
            record.opportunityId,
          );
          if (!_isCurrentResearchRecord(record)) {
            _pendingResearchPresentations.remove(record);
            continue;
          }
          if (current.effectivePresentation != record.presentation) {
            current = await record.research.useCases.changePresentation(
              ownerId: record.ownerId,
              opportunityId: current.id,
              presentation: record.presentation,
              expectedRevision: current.localRevision,
            );
          }
          _pendingResearchPresentations.remove(record);
          if (_isCurrentResearchRecord(record)) {
            _researchOpportunity = current;
            changed = true;
          }
        } on ResearchCaptureDenied {
          _pendingResearchPresentations.remove(record);
          if (_isCurrentResearchRecord(record)) {
            _pendingResearchPresentations.clear();
            setState(() {
              _researchSuppressed = true;
              _loadFuture = _load(
                _refreshGeneration,
                _presentationGeneration,
                _entryHost,
                _sessionChoice,
              );
            });
          }
        } on Object {
          if (!_isCurrentResearchRecord(record)) {
            _pendingResearchPresentations.remove(record);
            continue;
          }
          // Preserve the exact pending identity until an explicit retry. Never
          // spin a build/error loop or let an old opening retry in a new owner.
          _researchCaptureFailed = true;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'บันทึกข้อมูลวิจัยยังไม่สำเร็จ คุณเรียนต่อได้ตามปกติ',
              ),
              action: SnackBarAction(
                label: 'ลองอีกครั้ง',
                onPressed: () {
                  if (_isCurrentResearchRecord(record)) {
                    _researchCaptureFailed = false;
                    unawaited(_drainResearchPresentations());
                  }
                },
              ),
            ),
          );
          break;
        }
      }
    } finally {
      _recordingResearchPresentation = false;
    }
    if (changed) await _refreshResearch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _researchExpiry?.cancel();
    _postPromptExpiry?.cancel();
    unawaited(_researchChanges?.cancel());
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
      final point = _researchPrompt;
      if (point != null) {
        final run = _researchRun!;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.catalog.locale == 'th'
                  ? 'แบบวัดแรงจูงใจ (สมัครใจ)'
                  : 'Optional motivation questionnaire',
            ),
          ),
          body: MotivationMeasurementForm(
            key: ValueKey('motivation-prompt-${run.id}-${point.name}'),
            run: run,
            timepoint: point,
            languageCode: widget.catalog.locale == 'th' ? 'th' : 'en',
            onAnswer: (item, code) => widget.research!.useCases.record(
              MotivationResponse(
                ownerId: run.ownerId,
                runId: run.id,
                itemId: item,
                responseCode: code,
              ),
            ),
            onComplete: () => _finishResearchPrompt(),
            onSkip: () => _finishResearchPrompt(skip: true),
            onWithdraw: () => _finishResearchPrompt(withdraw: true),
          ),
        );
      }
      _recordResearchPresentation(result.decision);
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

final class _ResearchPresentationRecord {
  const _ResearchPresentationRecord({
    required this.research,
    required this.ownerId,
    required this.opportunityId,
    required this.opening,
    required this.presentation,
  });
  final AdventureResearchRuntime research;
  final String ownerId;
  final String opportunityId;
  final int opening;
  final TodayExperiencePresentation presentation;
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
