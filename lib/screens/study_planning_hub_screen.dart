import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'learning_pack_catalog_screen.dart';

/// The sole production study-planning parent. Future study-planning actions
/// remain children of this hub and do not receive their own feature delivery.
final class StudyPlanningHubScreen extends StatelessWidget {
  const StudyPlanningHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study planning')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose a verified learning pack to plan your next practice.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: 'Browse verified learning packs',
                child: FilledButton.icon(
                  key: const ValueKey<String>('study-planning/open-catalog'),
                  onPressed: () => AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'study-planning/catalog',
                      builder: (_) => ProductionFeatureGate(
                        feature: Feature.studyPlanning,
                        registry: AppDependenciesScope.maybeOf(
                          context,
                        )?.features,
                        builder: (_) => const LearningPackCatalogScreen(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Browse learning packs'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
