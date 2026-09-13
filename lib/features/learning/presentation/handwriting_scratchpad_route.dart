import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../runtime/production_feature_gate.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../domain/lesson_mode.dart';
import 'handwriting_scratchpad.dart';

/// Unscored local tool: observes identity, but never opens a learning session.
final class HandwritingScratchpadRoute extends StatefulWidget {
  const HandwritingScratchpadRoute({super.key, required this.ownerId});

  final String ownerId;

  @override
  State<HandwritingScratchpadRoute> createState() =>
      _HandwritingScratchpadRouteState();
}

final class _HandwritingScratchpadRouteState
    extends State<HandwritingScratchpadRoute> {
  final _controller = HandwritingScratchpadController();
  AppDependencies? _dependencies;
  StreamSubscription<List<String>>? _owners;
  Listenable? _featureChanges;
  bool _ready = false;
  bool _retired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (identical(dependencies, _dependencies) && _owners != null) return;
    if (_dependencies != null) _retire();
    _dependencies = dependencies;
    _featureChanges?.removeListener(_onFeatureChanged);
    final features = dependencies?.features;
    _featureChanges = features is Listenable ? features as Listenable : null;
    _featureChanges?.addListener(_onFeatureChanged);
    final database = dependencies?.database;
    if (_retired || database == null || !_deliverable ||
        features?.isEnabled(Feature.quiz) != true) {
      _retire();
      return;
    }
    _owners = (database.select(database.localOwners)
          ..where((row) => row.isActive.equals(true)))
        .watch()
        .map((rows) => rows.map((row) => row.id).toList())
        .listen((ids) {
          if (!mounted || _retired) return;
          if (ids.length != 1 || ids.single != widget.ownerId) {
            setState(_retire);
          } else {
            setState(() => _ready = true);
          }
        }, onError: (Object _, StackTrace __) {
          if (mounted) setState(_retire);
        });
  }

  bool get _deliverable =>
      _dependencies?.lessonModes?.resolve(LessonMode.handwritingScratchpad) !=
      null;

  void _onFeatureChanged() {
    if (!_retired && _dependencies?.features.isEnabled(Feature.quiz) != true) {
      setState(_retire);
    }
  }

  void _retire() {
    _retired = true;
    _ready = false;
    _controller.clear(notify: false);
  }

  @override
  void didUpdateWidget(HandwritingScratchpadRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) _retire();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired || !_deliverable) {
      return const ProductionFeatureUnavailable(
        feature: Feature.quiz,
        reason: ProductionFeatureUnavailableReason.missingDependency,
      );
    }
    return ProductionFeatureGate(
      feature: Feature.quiz,
      registry: _dependencies?.features,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('กระดานฝึกเขียน')),
        body: _ready
            ? HandwritingScratchpad(controller: _controller)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    unawaited(_owners?.cancel());
    _controller.clear(notify: false);
    _controller.dispose();
    super.dispose();
  }
}
