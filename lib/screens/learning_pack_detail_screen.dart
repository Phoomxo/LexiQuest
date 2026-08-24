import 'package:flutter/material.dart';

import '../features/learning_packs/application/learning_pack_detail_use_cases.dart';
import '../features/learning_packs/domain/learning_pack_detail.dart';
import '../runtime/app_dependencies.dart';

/// Read-only child surface for one catalog-selected pack revision.
final class LearningPackDetailScreen extends StatefulWidget {
  const LearningPackDetailScreen({
    super.key,
    required this.packId,
    required this.revision,
    this.useCases,
  });

  final String packId;
  final int revision;
  final LearningPackDetailUseCases? useCases;

  @override
  State<LearningPackDetailScreen> createState() =>
      _LearningPackDetailScreenState();
}

final class _LearningPackDetailScreenState
    extends State<LearningPackDetailScreen> {
  late Future<LearningPackDetailView> _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final supplied = widget.useCases;
    if (supplied != null) {
      _detail = supplied.loadVersion(widget.packId, widget.revision);
      return;
    }
    final dependencies = AppDependenciesScope.maybeOf(context);
    final planning = dependencies?.studyPlanning;
    if (planning == null) {
      _detail = Future<LearningPackDetailView>.error(
        StateError('StudyPlanningUseCases is unavailable'),
      );
      return;
    }
    _detail = LearningPackDetailUseCases(
      packs: planning.packs,
      progress: planning.progress,
      lessonModes: dependencies?.lessonModes,
      features: dependencies?.features,
      hasComposedDependency: (feature) =>
          dependencies?.hasComposedDependencyFor(feature) ?? false,
    ).loadVersion(widget.packId, widget.revision);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LearningPackDetailView>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return LearningPackDetailUnavailable(
            packId: widget.packId,
            revision: widget.revision,
          );
        }
        return _DetailBody(view: snapshot.requireData);
      },
    );
  }
}

/// Typed fail-closed state for a missing, stale, unpublished, or corrupt
/// pinned revision. It does not attempt fallback content or mutate evidence.
final class LearningPackDetailUnavailable extends StatelessWidget {
  const LearningPackDetailUnavailable({
    super.key,
    required this.packId,
    required this.revision,
  });

  final String packId;
  final int revision;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning pack unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            label: 'Learning pack $packId revision $revision unavailable',
            child: const ExcludeSemantics(
              child: Text(
                'This learning pack revision is unavailable. Your saved '
                'learning data is unchanged.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.view});

  final LearningPackDetailView view;

  @override
  Widget build(BuildContext context) {
    final detail = view.detail;
    final summary = detail.summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Learning pack detail')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            label:
                '${summary.title}, ${summary.cefrLevel}, revision '
                '${summary.revision}',
            child: ExcludeSemantics(
              child: Text(
                summary.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Level: ${summary.cefrLevel}'),
          Text('Topic: ${summary.topic}'),
          Text('Skill: ${summary.skill}'),
          Text('Goal: ${summary.goal}'),
          const SizedBox(height: 24),
          const Text('Progress'),
          Text('Completed sessions: ${view.progress.completedSessions}'),
          Text('Practice attempts: ${view.progress.sampleSize}'),
          const SizedBox(height: 24),
          const Text('Pinned vocabulary references'),
          for (final wordId in detail.vocabularyWordIds)
            Semantics(
              container: true,
              label: 'Canonical vocabulary item: $wordId',
              child: ExcludeSemantics(child: ListTile(title: Text(wordId))),
            ),
          const SizedBox(height: 24),
          const Text('Activities'),
          for (final activity in view.activities)
            Semantics(
              container: true,
              label: '${activity.label}: ${activity.availability.label}',
              child: ExcludeSemantics(
                child: ListTile(
                  title: Text(activity.label),
                  subtitle: Text(activity.availability.label),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
