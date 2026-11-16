import 'dart:async';
import 'package:drift/drift.dart' show TableUpdateQuery;
import '../runtime/app_dependencies.dart';
import '../features/identity/data/drift_owner_generation.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/review/domain/review_queue_item.dart';
import 'package:flutter/material.dart';

import '../features/today_hub/application/today_hub_use_cases.dart';
import '../features/today_hub/domain/today_hub_models.dart';
import '../runtime/registries/feature_registry.dart';
import 'today_hub_view.dart';

export 'today_hub_view.dart' show TodayHubActionDelegate, TodayHubView;

/// Legacy loading shell retained for the existing Today destination.
final class TodayHubScreen extends StatefulWidget {
  const TodayHubScreen({
    super.key,
    required this.useCases,
    required this.actions,
    required this.features,
    required this.assessmentAvailable,
    this.ownerIdentities,
    this.bindActions,
    this.onOpenPractice,
    this.manualPracticeAvailable = true,
  });

  final TodayHubSnapshotLoader useCases;
  final TodayHubActionDelegate actions;

  /// Binds async navigation to this view's current load/owner generation.
  final TodayHubActionDelegate Function(bool Function() isCurrent)? bindActions;
  final FeatureRegistry features;
  final bool assessmentAvailable;
  final ReviewOwnerIdentityReader? ownerIdentities;
  final VoidCallback? onOpenPractice;
  final bool manualPracticeAvailable;

  @override
  State<TodayHubScreen> createState() => _TodayHubScreenState();
}

final class _TodayHubScreenState extends State<TodayHubScreen> {
  TodayHubSnapshot? _snapshot;
  Object? _loadFailure;
  var _loadGeneration = 0;

  StreamSubscription<Object?>? _ownerChanges;
  AppDependencies? _dependencies;
  bool _active = false;
  String? _durableStamp;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _active && identical(dependencies, _dependencies)) return;
    _active = active;
    _dependencies = dependencies;
    _ownerChanges?.cancel();
    _ownerChanges = null;
    ++_loadGeneration;
    _snapshot = null;
    _loadFailure = null;
    final database = dependencies?.database;
    if (_active) {
      if (database != null && widget.ownerIdentities != null) {
        _ownerChanges = database
            .tableUpdates(
              TableUpdateQuery.allOf([
                TableUpdateQuery.onTable(database.localOwners),
                TableUpdateQuery.onTable(database.runtimeFlags),
              ]),
            )
            .listen((_) => _load());
      }
      _load();
    }
  }

  @override
  void didUpdateWidget(TodayHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_active &&
        (!identical(oldWidget.useCases, widget.useCases) ||
            !identical(oldWidget.ownerIdentities, widget.ownerIdentities)))
      _load();
  }

  Future<String?> _stamp() async {
    final database = _dependencies?.database;
    return database == null ? null : DriftOwnerGeneration(database).read();
  }

  Future<bool> _current(int generation, TodayHubSnapshot snapshot) async {
    if (!mounted ||
        !_active ||
        generation != _loadGeneration ||
        ModalRoute.of(context)?.isCurrent == false ||
        !widget.features.isEnabled(Feature.dailyContinuity))
      return false;
    try {
      final owner = await widget.ownerIdentities?.requireSingleActiveOwnerId();
      final stamp = await _stamp();
      return mounted &&
          _active &&
          generation == _loadGeneration &&
          (widget.ownerIdentities == null || owner == snapshot.ownerId) &&
          stamp == _durableStamp &&
          widget.features.isEnabled(Feature.dailyContinuity) &&
          ModalRoute.of(context)?.isCurrent != false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    if (!mounted || !_active) return;
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _loadFailure = null;
      });
    }
    try {
      final stamp = await _stamp();
      if (!mounted || !_active || generation != _loadGeneration) return;
      final owner = await widget.ownerIdentities?.requireSingleActiveOwnerId();
      if (!mounted || !_active || generation != _loadGeneration) return;
      final snapshot = await widget.useCases.load();
      if (!mounted || !_active || generation != _loadGeneration) return;
      final currentOwner = await widget.ownerIdentities
          ?.requireSingleActiveOwnerId();
      final currentStamp = await _stamp();
      if (stamp != currentStamp ||
          (widget.ownerIdentities != null &&
              (owner != snapshot.ownerId ||
                  currentOwner != snapshot.ownerId))) {
        throw StateError('Today owner changed during load');
      }
      if (!mounted || generation != _loadGeneration) return;
      _durableStamp = stamp;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadFailure = error);
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _ownerChanges?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('วันนี้')),
    body: _body(),
  );

  Widget _body() {
    if (_loadFailure != null) return TodayHubLoadFailure(onRetry: _load);
    final snapshot = _snapshot;
    if (snapshot == null) return const TodayHubLoading();
    final generation = _loadGeneration;
    return TodayHubView(
      snapshot: snapshot,
      actions: _CurrentTodayActions(
        widget.bindActions?.call(
              () => mounted && _active && generation == _loadGeneration,
            ) ??
            widget.actions,
        () => _current(generation, snapshot),
      ),
      manualPracticeAvailable: widget.manualPracticeAvailable,
      onOpenPractice: widget.onOpenPractice == null
          ? null
          : () async {
              if (await _current(generation, snapshot))
                widget.onOpenPractice?.call();
            },
      features: widget.features,
      assessmentAvailable: widget.assessmentAvailable,
    );
  }
}

/// A retained action belongs to this loaded view, never to a later tab/owner.
final class _CurrentTodayActions implements TodayHubActionDelegate {
  const _CurrentTodayActions(this.delegate, this.current);
  final TodayHubActionDelegate delegate;
  final Future<bool> Function() current;
  Future<void> _run(Future<void> Function() action) async {
    if (await current()) await action();
  }

  @override
  Future<void> resume(LearningSessionSummary session) =>
      _run(() => delegate.resume(session));
  @override
  Future<void> startRecommendation(TodayHubRecommendation value) =>
      _run(() => delegate.startRecommendation(value));
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) =>
      _run(() => delegate.openReview(work));
  @override
  Future<void> openHistory() => _run(delegate.openHistory);
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment value) =>
      _run(() => delegate.startAssessment(value));
  @override
  Future<void> openPlanning({required String ownerId}) =>
      _run(() => delegate.openPlanning(ownerId: ownerId));
}
