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
  });

  final TodayHubSnapshotLoader useCases;
  final TodayHubActionDelegate actions;
  final FeatureRegistry features;
  final bool assessmentAvailable;

  @override
  State<TodayHubScreen> createState() => _TodayHubScreenState();
}

final class _TodayHubScreenState extends State<TodayHubScreen> {
  TodayHubSnapshot? _snapshot;
  Object? _loadFailure;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TodayHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.useCases, widget.useCases)) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _loadFailure = null;
      });
    }
    try {
      final snapshot = await widget.useCases.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadFailure = error);
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
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
    return TodayHubView(
      snapshot: snapshot,
      actions: widget.actions,
      features: widget.features,
      assessmentAvailable: widget.assessmentAvailable,
    );
  }
}
