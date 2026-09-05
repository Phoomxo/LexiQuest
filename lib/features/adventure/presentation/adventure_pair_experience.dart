import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../runtime/registries/feature_registry.dart';
import '../../../screens/today_hub_view.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/pair_matching/application/pair_matching_source_composer.dart';
import '../../learning/pair_matching/domain/pair_matching_launch.dart';
import '../../learning/pair_matching/presentation/pair_board_view.dart';
import '../../learning/pair_matching/presentation/pair_matching_experience_host.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../application/adventure_diagnostics.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import 'adventure_pair_renderer.dart';
import 'today_experience_host.dart';

/// Explicit internal opt-in only. Both contextual constructors capture the
/// same Today review source; presentation is never another source authority.
/// Mount a fresh route for a new action. Rebuilds retain its launch identity.
final class AdventurePairExperience extends StatefulWidget {
  const AdventurePairExperience({
    super.key,
    required AdventureMissionLaunchContext this.launchContext,
    required this.runtime,
    required this.allowlist,
    required this.preferences,
    required this.onExit,
    this.direction = PairDirection.enToTh,
    this.isCurrent,
    this.decorationHealth,
    this.decoration,
  }) : capturedToday = null,
       capturedDecision = null;

  const AdventurePairExperience.standard({
    super.key,
    required TodayHubSnapshot today,
    required AdventureProductEntryDecision entryDecision,
    required this.runtime,
    required this.allowlist,
    required this.preferences,
    required this.onExit,
    this.direction = PairDirection.enToTh,
    this.isCurrent,
    this.decorationHealth,
    this.decoration,
  }) : capturedToday = today,
       capturedDecision = entryDecision,
       launchContext = null;

  final AdventureMissionLaunchContext? launchContext;
  final TodayHubSnapshot? capturedToday;
  final AdventureProductEntryDecision? capturedDecision;
  final PairMatchingExperienceRuntime runtime;
  final PairCuratedAllowlist allowlist;
  final PairDensityPreferences preferences;
  final VoidCallback onExit;
  final PairDirection direction;
  final bool Function()? isCurrent;
  final AdventurePairDecorationHealth? decorationHealth;
  final PairBoardDecoration? decoration;

  TodayHubSnapshot get today => launchContext?.today ?? capturedToday!;
  AdventureProductEntryDecision get entryDecision =>
      launchContext?.entryDecision ?? capturedDecision!;

  @override
  State<AdventurePairExperience> createState() =>
      _AdventurePairExperienceState();
}

final class _AdventurePairExperienceState
    extends State<AdventurePairExperience> {
  late final TodayHubSnapshot _today = widget.today;
  late final AdventureProductEntryDecision _decision = widget.entryDecision;
  late final PairMatchingExperienceRuntime _runtime = widget.runtime;
  late final PairDensityPreferences _preferences = widget.preferences;
  late final bool Function()? _capturedIsCurrent =
      widget.isCurrent ?? widget.launchContext?.isCurrent;
  late final bool _adventure = widget.launchContext != null;
  AdventureDiagnostics _diagnostics = AdventureDiagnostics();
  Listenable? _featureChanges;
  PairSourceSnapshot? _source;
  PairMatchingLaunchIntent? _launch;
  bool _unavailable = false;
  bool _ownerInvalidated = false;

  @override
  void initState() {
    super.initState();
    _observeFeatures();
    unawaited(_prepare());
  }

  bool _current() =>
      mounted &&
      identical(_runtime, widget.runtime) &&
      identical(_today, widget.today) &&
      _decision.entryAttemptId == widget.entryDecision.entryAttemptId &&
      (_capturedIsCurrent?.call() ?? true);

  Future<void> _prepare() async {
    try {
      if (!_current() || _today.ownerId != _preferences.ownerId) {
        return _deny(AdventureDiagnosticReasonCode.compositionOwnerMismatch);
      }
      if (_decision.destination !=
          (_adventure
              ? AdventureEntryDestination.adventure
              : AdventureEntryDestination.standardToday)) {
        return _deny(AdventureDiagnosticReasonCode.compositionUnavailableEntry);
      }
      final mission = widget.launchContext?.mission;
      if (mission != null && !_matchesMission(mission, _today)) {
        return _deny(AdventureDiagnosticReasonCode.compositionStaleSource);
      }
      final source = PairSourceSnapshot.today(
        snapshot: _today,
        allowlist: widget.allowlist,
      );
      if (!_supportedSource(_today, source)) {
        return _deny(
          AdventureDiagnosticReasonCode.compositionUnresolvedContent,
        );
      }
      if (await _runtime.requireOwner() != _today.ownerId || !_current()) {
        return _deny(AdventureDiagnosticReasonCode.compositionOwnerMismatch);
      }
      // Only route initialization following a real action creates identity.
      // Setup retry, parent rebuild and decoration fallback reuse these objects.
      final launch = PairMatchingLaunchIntent(
        ownerId: _today.ownerId,
        sourceSurface: PairSourceSurface.today,
        sourceSnapshotRef: source.reference,
        operationId: _runtime.learning.generateId(),
        createdAtUtc: _runtime.learning.nowUtc(),
        requestedDirection: widget.direction,
      );
      if (!mounted) return;
      setState(() {
        _source = source;
        _launch = launch;
      });
    } on Object {
      _deny(AdventureDiagnosticReasonCode.compositionUnavailableEntry);
    }
  }

  void _deny(AdventureDiagnosticReasonCode code) {
    _diagnostics.record(code);
    if (mounted) setState(() => _unavailable = true);
  }

  void _observeFeatures() {
    _featureChanges?.removeListener(_featuresChanged);
    final features = _runtime.features;
    _featureChanges = features is Listenable ? features as Listenable : null;
    _featureChanges?.addListener(_featuresChanged);
  }

  void _featuresChanged() {
    if (mounted) setState(() {});
  }

  Widget _decorate(
    BuildContext context,
    PairBoardModel model,
    Widget board,
    ValueChanged<PairDecorationFailure> reportFailure,
  ) {
    if (_ownerInvalidated || !mounted) return board;
    final custom = widget.decoration;
    if (custom != null) {
      try {
        return custom(context, model, board, reportFailure);
      } on Object {
        _diagnostics.record(
          AdventureDiagnosticReasonCode.entryFallbackDependencyUnavailable,
        );
        rethrow; // Existing Pair host owns synchronous construction fallback.
      }
    }
    return AdventurePairRenderer(
      model: model,
      standardBoard: board,
      reportFailure: reportFailure,
      diagnostics: _diagnostics,
      health: widget.decorationHealth,
    );
  }

  void _invalidateOwnerDecoration() {
    if (_ownerInvalidated) return;
    _ownerInvalidated = true;
    _diagnostics = AdventureDiagnostics();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_featuresChanged);
    // Counters are route-local and never retained in an owner store/outbox.
    _diagnostics = AdventureDiagnostics();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    if (_unavailable) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  english
                      ? 'This review is no longer available. Return to Today to choose again.'
                      : 'ชุดทบทวนนี้ไม่พร้อมแล้ว กลับไปเลือกจากกิจกรรมวันนี้อีกครั้ง',
                  key: const ValueKey('adventure-pair-unavailable'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.onExit,
                  child: Text(
                    english ? 'Return to Today' : 'กลับกิจกรรมวันนี้',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final launch = _launch;
    if (launch == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final decorated =
        !_ownerInvalidated &&
        _adventure &&
        (_runtime.features?.isEnabled(Feature.adventureMotivation) ?? false);
    return PairMatchingExperienceHost(
      key: const ValueKey('adventure-pair-host'),
      runtime: _runtime,
      launch: launch,
      source: _source!,
      preferences: _preferences,
      onExit: widget.onExit,
      canAdmitLaunch: _current,
      onOwnerInvalidated: _invalidateOwnerDecoration,
      decoration: decorated ? _decorate : null,
    );
  }
}

bool _matchesMission(AdventureMissionRef mission, TodayHubSnapshot today) {
  final identities = today.reviewWork.map((w) => w.identity).toSet();
  return mission.kind == AdventureMissionKind.review &&
      mission.ownerId == today.ownerId &&
      mission.sourceEvaluatedAtUtc == today.evaluatedAtUtc &&
      (mission.suggestedMode == null ||
          mission.suggestedMode == LessonMode.matching) &&
      mission.content.isNotEmpty &&
      mission.sourceId == mission.content.first.id &&
      mission.content.length == identities.length &&
      identities.length == today.reviewWork.length &&
      setEquals(mission.content.toSet(), identities);
}

bool _supportedSource(TodayHubSnapshot today, PairSourceSnapshot source) =>
    today.dependencyStates[TodayHubDependency.review] ==
        TodayHubDependencyState.ready &&
    source.items.length >= 4 &&
    source.items.length == today.reviewWork.length;

/// Stable per-router Standard opt-in. Keep this object in route/parent state;
/// the synchronous contextual factory only captures already-resolved inputs.
final class AdventurePairTodayActions {
  AdventurePairTodayActions({
    required this.runtime,
    required this.allowlist,
    required this.preferences,
    required this.openExperience,
    required this.onExit,
    this.direction = PairDirection.enToTh,
  });
  final PairMatchingExperienceRuntime runtime;
  final PairCuratedAllowlist allowlist;
  final PairDensityPreferences preferences;
  final Future<void> Function(Widget experience) openExperience;
  final VoidCallback onExit;
  final PairDirection direction;
  final _inFlight = <(String, String, TodayHubSnapshot), Future<void>>{};

  TodayHubActionDelegate contextualize({
    required TodayHubSnapshot today,
    required AdventureProductEntryDecision entryDecision,
    required TodayHubActionDelegate fallback,
    required bool Function() isCurrent,
  }) => _ContextualPairActions(this, today, entryDecision, fallback, isCurrent);

  Future<void> _open(
    _ContextualPairActions action,
    List<TodayHubReviewWorkItem> work,
  ) async {
    if (!action.isCurrent()) return;
    final source = PairSourceSnapshot.today(
      snapshot: action.today,
      allowlist: allowlist,
    );
    if (!listEquals(work, action.today.reviewWork) ||
        !_supportedSource(action.today, source)) {
      return action.fallback.openReview(work);
    }
    final key = (
      action.today.ownerId,
      action.decision.entryAttemptId,
      action.today,
    );
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final pending = _navigate(action);
    _inFlight[key] = pending;
    try {
      await pending;
    } finally {
      if (identical(_inFlight[key], pending)) _inFlight.remove(key);
    }
  }

  Future<void> _navigate(_ContextualPairActions action) async {
    String owner;
    try {
      owner = await runtime.requireOwner();
    } on Object {
      return;
    }
    if (!action.isCurrent() ||
        owner != action.today.ownerId ||
        owner != preferences.ownerId ||
        action.decision.destination !=
            AdventureEntryDestination.standardToday) {
      return;
    }
    return openExperience(
      AdventurePairExperience.standard(
        today: action.today,
        entryDecision: action.decision,
        runtime: runtime,
        allowlist: allowlist,
        preferences: preferences,
        direction: direction,
        onExit: onExit,
        isCurrent: action.isCurrent,
      ),
    );
  }
}

final class _ContextualPairActions implements TodayHubActionDelegate {
  const _ContextualPairActions(
    this.router,
    this.today,
    this.decision,
    this.fallback,
    this.isCurrent,
  );
  final AdventurePairTodayActions router;
  final TodayHubSnapshot today;
  final AdventureProductEntryDecision decision;
  final TodayHubActionDelegate fallback;
  final bool Function() isCurrent;
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) =>
      router._open(this, work);
  @override
  Future<void> resume(LearningSessionSummary session) =>
      fallback.resume(session);
  @override
  Future<void> startRecommendation(TodayHubRecommendation recommendation) =>
      fallback.startRecommendation(recommendation);
  @override
  Future<void> openHistory() => fallback.openHistory();
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) =>
      fallback.startAssessment(assessment);
}
