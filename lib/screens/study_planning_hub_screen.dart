import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'learning_pack_catalog_screen.dart';
import 'learning_goals_screen.dart';
import 'learning_preference_quiz_screen.dart';

/// The sole production study-planning parent. Future study-planning actions
/// remain children of this hub and do not receive their own feature delivery.
final class StudyPlanningHubScreen extends StatelessWidget {
  const StudyPlanningHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final hubEntry = NavigationGlossary.require('home/study-planning');
    final catalogEntry = NavigationGlossary.require(
      'study-planning/open-catalog',
    );
    final goalsEntry = NavigationGlossary.require('study-planning/open-goals');
    final preferencesEntry = NavigationGlossary.require(
      'study-planning/open-learning-preferences',
    );
    void openCatalog() {
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'study-planning/catalog',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: AppDependenciesScope.maybeOf(context)?.features,
            builder: (_) => const LearningPackCatalogScreen(),
          ),
        ),
      );
    }

    void openGoals() {
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'study-planning/goals',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: AppDependenciesScope.maybeOf(context)?.features,
            builder: (_) => const LearningGoalsScreen(),
          ),
        ),
      );
    }

    void openPreferences() {
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'study-planning/learning-preferences',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: dependencies?.features,
            builder: (_) => const LearningPreferenceQuizScreen(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(hubEntry.fullThaiLabel)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'เลือกชุดเนื้อหาที่ตรวจสอบแล้วเพื่อวางแผนการฝึกครั้งถัดไป',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _glossaryAction(
                entry: catalogEntry,
                onTap: openCatalog,
                child: FilledButton.icon(
                  key: const ValueKey<String>('study-planning/open-catalog'),
                  onPressed: openCatalog,
                  icon: Icon(catalogEntry.icon),
                  label: Text(catalogEntry.fullThaiLabel),
                ),
              ),
              const SizedBox(height: 12),
              _glossaryAction(
                entry: goalsEntry,
                onTap: openGoals,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('study-planning/open-goals'),
                  onPressed: openGoals,
                  icon: Icon(goalsEntry.icon),
                  label: Text(goalsEntry.fullThaiLabel),
                ),
              ),
              if (dependencies?.learnerPreferences != null) ...[
                const SizedBox(height: 12),
                _glossaryAction(
                  entry: preferencesEntry,
                  onTap: openPreferences,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'study-planning/open-learning-preferences',
                    ),
                    onPressed: openPreferences,
                    icon: Icon(preferencesEntry.icon),
                    label: Text(preferencesEntry.fullThaiLabel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _glossaryAction({
  required NavigationGlossaryEntry entry,
  required VoidCallback onTap,
  required Widget child,
}) => Tooltip(
  message: entry.tooltip,
  child: Semantics(
    button: true,
    label: entry.semanticsLabel,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  ),
);
