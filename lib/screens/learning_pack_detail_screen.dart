import 'package:flutter/material.dart';

import '../features/learning_packs/application/learning_pack_detail_use_cases.dart';
import '../features/learning_packs/domain/content_manifest.dart';
import '../features/learning_packs/domain/learning_pack_detail.dart';
import '../features/review/domain/learner_intent.dart';
import '../features/review/domain/content_quality_report.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/rich_lexical_card.dart';

/// Read-only child surface for one catalog-selected pack revision.
final class LearningPackDetailScreen extends StatefulWidget {
  const LearningPackDetailScreen({
    super.key,
    required this.packId,
    required this.revision,
    this.useCases,
    this.vocabulary,
  });

  final String packId;
  final int revision;
  final LearningPackDetailUseCases? useCases;
  final VocabularyUseCases? vocabulary;

  @override
  State<LearningPackDetailScreen> createState() =>
      _LearningPackDetailScreenState();
}

final class _LearningPackDetailScreenState
    extends State<LearningPackDetailScreen> {
  late Future<_DetailScreenData> _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    final supplied = widget.useCases;
    if (supplied != null) {
      _detail = _load(supplied, vocabulary);
      return;
    }
    final planning = dependencies?.studyPlanning;
    if (planning == null) {
      _detail = Future<_DetailScreenData>.error(
        StateError('StudyPlanningUseCases is unavailable'),
      );
      return;
    }
    _detail = _load(
      LearningPackDetailUseCases(
        packs: planning.packs,
        progress: planning.progress,
        lessonModes: dependencies?.lessonModes,
        features: dependencies?.features,
        hasComposedDependency: (feature) =>
            dependencies?.hasComposedDependencyFor(feature) ?? false,
      ),
      vocabulary,
    );
  }

  Future<_DetailScreenData> _load(
    LearningPackDetailUseCases useCases,
    VocabularyUseCases? vocabulary,
  ) async {
    final view = await useCases.loadVersion(widget.packId, widget.revision);
    if (vocabulary == null) {
      throw StateError('VocabularyUseCases is unavailable');
    }
    final words = await vocabulary.readPinnedByIds(
      view.detail.vocabularyWordIds,
    );
    return _DetailScreenData(view: view, words: words);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DetailScreenData>(
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
        final data = snapshot.requireData;
        final dependencies = AppDependenciesScope.maybeOf(context);
        return _DetailBody(
          view: data.view,
          words: data.words,
          bookmarkLearningItem: dependencies?.bookmarkLearningItem,
          reportContent: dependencies?.reportContent,
        );
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
  const _DetailBody({
    required this.view,
    required this.words,
    required this.bookmarkLearningItem,
    required this.reportContent,
  });

  final LearningPackDetailView view;
  final List<VocabularyWord> words;
  final BookmarkLearningItemAction? bookmarkLearningItem;
  final ReportContentAction? reportContent;

  @override
  Widget build(BuildContext context) {
    final summary = view.detail.summary;
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
          for (final word in words)
            RichLexicalCard(
              word: word,
              bookmarkIdentity: ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: word.id,
                revision: word.contentRevision,
              ),
              onBookmark: bookmarkLearningItem,
              reportIdentity: ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: word.id,
                revision: word.contentRevision,
              ),
              onReport: reportContent,
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

final class _DetailScreenData {
  const _DetailScreenData({required this.view, required this.words});

  final LearningPackDetailView view;
  final List<VocabularyWord> words;
}
