import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'learning_pack_catalog_screen.dart';
import 'learning_goals_screen.dart';
import 'learning_preference_quiz_screen.dart';
import 'personal_sets_screen.dart';
import 'study_plan_screen.dart';

/// The sole production study-planning parent. Future study-planning actions
/// remain children of this hub and do not receive their own feature delivery.
final class StudyPlanningHubScreen extends StatefulWidget {
  const StudyPlanningHubScreen({super.key});

  @override
  State<StudyPlanningHubScreen> createState() => _StudyPlanningHubScreenState();
}

final class _StudyPlanningHubScreenState extends State<StudyPlanningHubScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  int _generation = 0;
  bool _active = false;
  bool _opening = false;
  bool _exited = false;
  bool _foreground = true;

  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _generation++;
      _active = _visible;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final active = _visible;
    if (!identical(dependencies, _dependencies) || active != _active) {
      _generation++;
    }
    _dependencies = dependencies;
    _active = active;
  }

  Future<void> _open(int generation, String name, WidgetBuilder child) async {
    if (!mounted ||
        _exited ||
        generation != _generation ||
        _opening ||
        !_visible)
      return;
    _opening = true;
    // Retire every displayed action immediately, before Navigator rebuilds.
    _generation++;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'study-planning/$name',
          // The child resolves its own live scope; it never reads a retired parent.
          builder: (_) => ProductionFeatureGate(
            feature: Feature.studyPlanning,
            builder: child,
          ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted && !_exited) setState(() {});
    }
  }

  void _exit() {
    _exited = true;
    _generation++;
  }

  @override
  void dispose() {
    _exit();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
    final generation = _generation;
    void openCatalog() =>
        _open(generation, 'catalog', (_) => const LearningPackCatalogScreen());
    void openGoals() =>
        _open(generation, 'goals', (_) => const LearningGoalsScreen());
    void openPreferences() => _open(
      generation,
      'learning-preferences',
      (_) => const LearningPreferenceQuizScreen(),
    );
    void openPlan() =>
        _open(generation, 'plan', (_) => const StudyPlanScreen());
    void openSets() =>
        _open(generation, 'personal-sets', (_) => const PersonalSetsScreen());

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(hubEntry.fullThaiLabel)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MenuActionBinding(
                  id: 'study-planning/open-plan',
                  label: 'แผนการเรียนของฉัน',
                  onInvoke: () {
                    openPlan();
                  },
                  child: OutlinedButton.icon(
                    onPressed: () => openPlan(),
                    icon: const Icon(Icons.schedule),
                    label: const Text('แผนการเรียนของฉัน'),
                  ),
                ),
                MenuActionBinding(
                  id: 'study-planning/open-personal-sets',
                  label: 'ชุดคำส่วนตัว',
                  onInvoke: () {
                    openSets();
                  },
                  child: OutlinedButton.icon(
                    onPressed: () => openSets(),
                    icon: const Icon(Icons.collections_bookmark_outlined),
                    label: const Text('ชุดคำส่วนตัว'),
                  ),
                ),
                const Text(
                  'เลือกชุดเนื้อหาที่ตรวจสอบแล้วเพื่อวางแผนการฝึกครั้งถัดไป',
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
  child: MenuActionBinding(
    id: entry.id,
    label: entry.fullThaiLabel,
    onInvoke: onTap,
    child: Semantics(
      button: true,
      label: entry.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: child,
    ),
  ),
);
