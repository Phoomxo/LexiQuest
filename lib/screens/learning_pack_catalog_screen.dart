import 'package:flutter/material.dart';

import '../features/learning_packs/application/learning_pack_use_cases.dart';
import '../features/learning_packs/domain/learning_pack.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature.dart';
import 'learning_pack_detail_screen.dart';

/// Read-only catalog child of [StudyPlanningHubScreen].
final class LearningPackCatalogScreen extends StatefulWidget {
  const LearningPackCatalogScreen({super.key, this.useCases});

  final StudyPlanningUseCases? useCases;

  @override
  State<LearningPackCatalogScreen> createState() =>
      _LearningPackCatalogScreenState();
}

final class _LearningPackCatalogScreenState
    extends State<LearningPackCatalogScreen> {
  late Future<LearningPackCatalog> _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog =
        (widget.useCases ??
                AppDependenciesScope.of(context).studyPlanning ??
                (throw StateError('StudyPlanningUseCases is unavailable')))
            .listPacks(LearningPackFilter());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning packs')),
      body: FutureBuilder<LearningPackCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Verified learning packs are unavailable.'),
              ),
            );
          }
          final packs = snapshot.requireData.packs;
          if (packs.isEmpty) {
            return const Center(child: Text('No verified learning packs yet.'));
          }
          return ListView.builder(
            itemCount: packs.length,
            itemBuilder: (context, index) => _PackTile(pack: packs[index]),
          );
        },
      ),
    );
  }
}

final class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack});

  final LearningPackSummary pack;

  void _open(BuildContext context) {
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'study-planning/catalog/detail',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.studyPlanning,
          registry: AppDependenciesScope.maybeOf(context)?.features,
          builder: (_) => LearningPackDetailScreen(
            packId: pack.packId,
            revision: pack.revision,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${pack.title}, ${pack.cefrLevel}, ${pack.topic}, revision '
          '${pack.revision}',
      onTap: () => _open(context),
      child: ExcludeSemantics(
        child: ListTile(
          key: ValueKey<String>(
            'learning-pack/open/${pack.packId}/${pack.revision}',
          ),
          onTap: () => _open(context),
          title: Text(pack.title),
          subtitle: Text(
            '${pack.cefrLevel} · ${pack.topic} · ${pack.skill} · '
            '${pack.goal} · Revision ${pack.revision}',
          ),
        ),
      ),
    );
  }
}
