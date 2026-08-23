import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'production_feature_contract.dart';
import 'registries/feature_registry.dart';

enum ProductionFeatureUnavailableReason {
  missingRegistry,
  unavailableState,
  missingDependency,
}

/// Shared fail-closed experience for stale or direct feature routes.
final class ProductionFeatureUnavailable extends StatelessWidget {
  const ProductionFeatureUnavailable({
    super.key,
    required this.feature,
    required this.reason,
    this.state,
  });

  final Feature feature;
  final ProductionFeatureUnavailableReason reason;
  final FeatureState? state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feature unavailable')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This feature is not available right now. Your saved learning '
            'data is unchanged.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Lazily constructs one production feature subtree only while its effective
/// V2 registry state is enabled or limited.
///
/// A missing dependency scope fails closed. Runtime registries are observed so
/// an already-mounted route switches to [ProductionFeatureUnavailable] as soon
/// as a persisted or emergency override changes.
final class ProductionFeatureGate extends StatefulWidget {
  const ProductionFeatureGate({
    super.key,
    required this.feature,
    required this.builder,
    this.registry,
  });

  final Feature feature;
  final WidgetBuilder builder;

  /// Explicit registry binding keeps pushed subtrees on their caller's live
  /// runtime authority. A missing value resolves from the dependency scope.
  final FeatureRegistry? registry;

  @override
  State<ProductionFeatureGate> createState() => _ProductionFeatureGateState();
}

final class _ProductionFeatureGateState extends State<ProductionFeatureGate> {
  FeatureRegistry? _registry;
  Listenable? _registryChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observe(
      widget.registry ?? AppDependenciesScope.maybeOf(context)?.features,
    );
  }

  @override
  void didUpdateWidget(ProductionFeatureGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registry, widget.registry)) {
      _observe(
        widget.registry ?? AppDependenciesScope.maybeOf(context)?.features,
      );
    }
  }

  void _observe(FeatureRegistry? registry) {
    if (identical(registry, _registry)) return;
    _registryChanges?.removeListener(_onRegistryChanged);
    _registry = registry;
    final changes = registry is Listenable ? registry as Listenable : null;
    _registryChanges = changes;
    changes?.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _registryChanges?.removeListener(_onRegistryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = _registry;
    if (registry == null) {
      return ProductionFeatureUnavailable(
        feature: widget.feature,
        reason: ProductionFeatureUnavailableReason.missingRegistry,
      );
    }
    final state = registry.stateOf(widget.feature);
    if (state != FeatureState.enabled && state != FeatureState.limited) {
      return ProductionFeatureUnavailable(
        feature: widget.feature,
        reason: ProductionFeatureUnavailableReason.unavailableState,
        state: state,
      );
    }
    final dependencies = AppDependenciesScope.maybeOf(context);
    final delivery = productionFeatureContract[widget.feature];
    if (dependencies == null ||
        delivery == null ||
        !delivery.durable ||
        delivery.productionEntryId.isEmpty ||
        delivery.dependencyId.isEmpty ||
        !dependencies.hasComposedDependencyFor(widget.feature)) {
      return ProductionFeatureUnavailable(
        feature: widget.feature,
        reason: ProductionFeatureUnavailableReason.missingDependency,
        state: state,
      );
    }
    return widget.builder(context);
  }
}
