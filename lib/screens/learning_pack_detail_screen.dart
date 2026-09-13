import 'package:flutter/material.dart';

import '../features/learning/domain/lesson_mode.dart';
import '../navigation/navigation_glossary.dart';

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
    _reload();
  }

  @override
  void didUpdateWidget(covariant LearningPackDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packId != widget.packId ||
        oldWidget.revision != widget.revision ||
        oldWidget.useCases != widget.useCases ||
        oldWidget.vocabulary != widget.vocabulary) {
      _reload();
    }
  }

  void _reload() {
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
        readPinnedVocabulary: vocabulary?.readPinnedByIds,
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
      appBar: AppBar(title: const Text('ชุดเนื้อหายังไม่พร้อมใช้งาน')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            label: 'ชุดเนื้อหา $packId รุ่น $revision ไม่พร้อมใช้งาน',
            child: const ExcludeSemantics(
              child: Text(
                'ชุดเนื้อหารุ่นนี้ไม่พร้อมใช้งาน '
                'ข้อมูลการเรียนที่บันทึกไว้ไม่เปลี่ยนแปลง',
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
      appBar: AppBar(title: const Text('รายละเอียดชุดเนื้อหาการเรียน')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            label:
                '${summary.title}, ${summary.cefrLevel}, รุ่น '
                '${summary.revision}',
            child: ExcludeSemantics(
              child: Text(
                summary.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('รุ่นเนื้อหา: ${summary.revision}'),
          Text('คำศัพท์ในชุด: ${words.length}'),
          Text('ระดับภาษา: ${summary.cefrLevel}'),
          Text('หัวข้อ: ${summary.topic}'),
          Text('ทักษะ: ${summary.skill}'),
          Text('เป้าหมาย: ${summary.goal}'),
          const SizedBox(height: 24),
          const Text('ความคืบหน้าของชุดและรุ่นนี้'),
          Text('กิจกรรมที่เรียนจบ: ${view.progress.completedSessions}'),
          Text('จำนวนครั้งที่ฝึก: ${view.progress.sampleSize}'),
          const SizedBox(height: 24),
          const Text('คำศัพท์อ้างอิงของชุดนี้'),
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
          const Text('กิจกรรม'),
          for (final activity in view.activities)
            Semantics(
              container: true,
              label:
                  '${_activityLabel(activity.mode)}: ${_availabilityLabel(activity.availability)}',
              child: ExcludeSemantics(
                child: ListTile(
                  title: Text(_activityLabel(activity.mode)),
                  subtitle: Text(_availabilityLabel(activity.availability)),
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

String _availabilityLabel(LearningPackActivityAvailability availability) =>
    switch (availability) {
      LearningPackActivityAvailability.available => 'พร้อมใช้งาน',
      LearningPackActivityAvailability.unavailable => 'ยังไม่พร้อมใช้งาน',
    };

String _activityLabel(LessonMode mode) {
  if (mode == LessonMode.handwritingScratchpad) return 'กระดานฝึกเขียน';
  final id = switch (mode) {
    LessonMode.associativeReading => 'home/learn/associative-reading',
    LessonMode.meaningQuiz => 'home/learn/quiz',
    LessonMode.typedRecall => 'home/learn/quiz/typed-recall',
    LessonMode.definitionQuiz => 'home/learn/quiz/definition',
    LessonMode.cloze => 'home/learn/quiz/cloze',
    LessonMode.matching => 'home/learn/quiz/matching',
    LessonMode.flashcard => 'home/learn/srs',
    LessonMode.dictation => 'home/learn/quiz/dictation',
    LessonMode.speaking => 'home/learn/speech/speaking',
    LessonMode.shadowing => 'home/learn/speech/shadowing',
    LessonMode.cefrReading => 'home/learn/reading/cefr',
    LessonMode.sentenceScramble => 'home/learn/quiz/sentence-scramble',
    LessonMode.wordScramble => 'home/learn/quiz/word-scramble',
    LessonMode.handwritingScratchpad => throw StateError('Handled above'),
  };
  return NavigationGlossary.require(id).fullThaiLabel;
}
