import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/learning/domain/lesson_mode.dart';
import '../navigation/navigation_glossary.dart';

import '../features/learning_packs/application/learning_pack_detail_use_cases.dart';
import '../features/learning_packs/domain/content_manifest.dart';
import '../features/learning_packs/domain/learning_pack_detail.dart';
import '../features/review/domain/learner_intent.dart';
import '../features/review/domain/learner_intent_repository.dart';
import '../features/review/domain/content_quality_report.dart';
import '../features/review/presentation/content_report_sheet.dart';
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
    extends State<LearningPackDetailScreen>
    with WidgetsBindingObserver {
  Future<_DetailScreenData>? _detail;
  LearningPackDetailUseCases? _useCases;
  LearningPackDetailUseCases? _suppliedCases;
  VocabularyUseCases? _vocabulary;
  AppDependencies? _dependencies;
  BookmarkLearningItemAction? _bookmark;
  ReportContentAction? _report;
  LearnerIntentRepository? _intentRepository;
  StreamSubscription<({String ownerId, String? firebaseUid})?>? _owners;
  int _epoch = 0;
  int _generation = 0;
  bool _active = false;
  bool _pending = false;
  bool _exited = false;
  bool _foreground = true;
  bool _ownerReady = false;
  String? _ownerId;
  String? _packId;
  int? _revision;
  ModalBottomSheetRoute<void>? _reportRoute;

  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent != false ||
          (_reportRoute?.isCurrent == true &&
              ModalRoute.of(context)?.isActive == true));

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
      _bind();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(LearningPackDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final scope = AppDependenciesScope.maybeOf(context);
    // Explicit readers own their data; absent explicit vocabulary must not
    // silently resolve through a different planning composition.
    final dependencies = widget.useCases == null ? scope : null;
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    final bookmark = scope?.bookmarkLearningItem;
    final report = scope?.reportContent;
    final changed =
        !identical(dependencies, _dependencies) ||
        !identical(widget.useCases, _suppliedCases) ||
        !identical(vocabulary, _vocabulary) ||
        !identical(bookmark, _bookmark) ||
        !identical(report, _report) ||
        !identical(scope?.learnerIntents, _intentRepository) ||
        _packId != widget.packId ||
        _revision != widget.revision;
    if (changed) {
      _suppliedCases = widget.useCases;
      _dependencies = dependencies;
      _vocabulary = vocabulary;
      _bookmark = bookmark;
      _report = report;
      _intentRepository = scope?.learnerIntents;
      _packId = widget.packId;
      _revision = widget.revision;
      final planning = dependencies?.studyPlanning;
      _useCases =
          widget.useCases ??
          (planning == null
              ? null
              : LearningPackDetailUseCases(
                  packs: planning.packs,
                  progress: planning.progress,
                  lessonModes: dependencies?.lessonModes,
                  features: dependencies?.features,
                  hasComposedDependency: (feature) =>
                      dependencies?.hasComposedDependencyFor(feature) ?? false,
                  readPinnedVocabulary: vocabulary?.readPinnedByIds,
                ));
    }
    final active = _visible;
    if (changed || active != _active) {
      _active = active;
      _retire();
      _observe();
      if (active && _useCases == null) _read();
    }
  }

  void _retire() {
    _generation++;
    _detail = null;
    _pending = false;
    final route = _reportRoute;
    _reportRoute = null;
    if (route != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
  }

  bool _current(int generation) =>
      mounted && !_exited && generation == _generation;
  bool _allowed(int generation, {bool ownedReport = false}) =>
      _current(generation) &&
      _active &&
      _visible &&
      (ownedReport ? _reportRoute?.isCurrent == true : _reportRoute == null);

  void _observe() {
    final epoch = ++_epoch;
    _owners?.cancel().ignore();
    _owners = null;
    _ownerReady = false;
    _ownerId = null;
    if (!_active || _useCases == null) return;
    _pending = true;
    _owners = _useCases!.progress.watchProfileOwner().listen(
      (owner) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = true;
          _ownerId = owner?.ownerId;
          if (_active) _read();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = false;
          _ownerId = null;
          _detail = Future<_DetailScreenData>.error(error, stack);
          _detail!.ignore();
        });
      },
    );
  }

  void _read() {
    _retire();
    final generation = _generation;
    final cases = _useCases;
    final vocabulary = _vocabulary;
    final owner = _ownerId;
    final packId = widget.packId;
    final revision = widget.revision;
    _pending = true;
    _detail = Future<_DetailScreenData>.sync(() async {
      if (cases == null ||
          vocabulary == null ||
          !_ownerReady ||
          owner == null) {
        throw StateError('Pinned detail dependencies unavailable');
      }
      final view = await cases.loadVersion(packId, revision);
      if (!_current(generation) ||
          view.progress.ownerId != owner ||
          (await cases.progress.owners.getOrCreateActiveOwner()).id != owner) {
        throw StateError('Detail owner changed');
      }
      final words = await vocabulary.readPinnedByIds(
        view.detail.vocabularyWordIds,
      );
      final current = await cases.progress.owners.getOrCreateActiveOwner();
      if (!_current(generation) || current.id != owner)
        throw StateError('Detail owner changed');
      final ids = view.detail.vocabularyWordIds.toSet();
      if (words.length != ids.length ||
          words.map((w) => w.id).toSet().length != ids.length ||
          !words.every((w) => ids.contains(w.id)))
        throw StateError('Pinned vocabulary mismatch');
      return _DetailScreenData(view: view, words: words);
    });
    _detail!.then<void>(
      (_) {
        if (_current(generation)) _pending = false;
      },
      onError: (Object _, StackTrace __) {
        if (_current(generation)) _pending = false;
      },
    );
  }

  void _retry(int generation) {
    if (!_allowed(generation) || _pending) return;
    setState(() {
      if (_useCases != null && !_ownerReady) {
        _retire();
        _observe();
      } else {
        _read();
      }
    });
  }

  Future<void> _validateAction(
    int generation, {
    bool ownedReport = false,
  }) async {
    if (!_allowed(generation, ownedReport: ownedReport))
      throw StateError('Detail action expired');
    final owner = _ownerId;
    final current = await _useCases!.progress.owners.getOrCreateActiveOwner();
    if (!_allowed(generation, ownedReport: ownedReport) ||
        owner == null ||
        current.id != owner) {
      throw StateError('Detail action owner changed');
    }
  }

  Future<void> _openReport(int generation, ContentIdentity identity) async {
    if (!_allowed(generation) || _report == null) return;
    final action = _report!;
    final expectedOwnerId = _ownerId;
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      builder: (_) => ContentReportSheet(
        identity: identity,
        expectedOwnerId: expectedOwnerId,
        canSubmit: () => _allowed(generation, ownedReport: true),
        onSubmit: ({required reason, comment}) async {
          await _validateAction(generation, ownedReport: true);
          await action(identity: identity, reason: reason, comment: comment);
          await _validateAction(generation, ownedReport: true);
        },
      ),
    );
    _reportRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      if (identical(_reportRoute, route)) _reportRoute = null;
      if (mounted && !_exited) setState(_bind);
    }
  }

  void _exit() {
    _exited = true;
    _epoch++;
    _owners?.cancel().ignore();
    _owners = null;
    _retire();
  }

  @override
  void dispose() {
    _exit();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) setState(_exit);
      },
      child: !_active || _exited
          ? const Scaffold(body: SizedBox.shrink())
          : FutureBuilder<_DetailScreenData>(
              key: ValueKey(generation),
              future: _detail,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                if (snapshot.hasError)
                  return LearningPackDetailUnavailable(
                    packId: widget.packId,
                    revision: widget.revision,
                    onRetry: () => _retry(generation),
                  );
                final data = snapshot.requireData;
                final progress = data.view.progress;
                final summary = data.view.detail.summary;
                return MenuActionBinding(
                  id: 'study-planning/pack-detail-summary',
                  label: 'รายละเอียดชุดบทเรียนและความคืบหน้ารุ่นนี้',
                  ownerId: progress.ownerId,
                  onInvoke: null,
                  readValue: progress.ownerId == null
                      ? null
                      : jsonEncode({
                          'title': String.fromCharCodes(
                            summary.title.runes.take(20),
                          ),
                          'titleTruncated': summary.title.runes.length > 20,
                          'revision': summary.revision,
                          'wordCount': data.words.length,
                          'sampleSize': progress.sampleSize,
                          'completedSessions': progress.completedSessions,
                          'interpretation':
                              'Pinned pack revision and recorded practice, not-learner-proficiency. '
                              'Zero samples mean no recorded practice for this revision, not inability. '
                              'Content availability does not imply enrollment or completion.',
                        }),
                  child: _DetailBody(
                    view: data.view,
                    words: data.words,
                    bookmarkLearningItem: _bookmark,
                    reportContent: _report,
                    canInteract: () => _allowed(generation),
                    validateAction: () => _validateAction(generation),
                    openReport: (identity) => _openReport(generation, identity),
                  ),
                );
              },
            ),
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
    this.onRetry,
  });

  final VoidCallback? onRetry;
  final String packId;
  final int revision;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ชุดเนื้อหายังไม่พร้อมใช้งาน')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'ชุดเนื้อหา $packId รุ่น $revision ไม่พร้อมใช้งาน',
                child: const ExcludeSemantics(
                  child: Text(
                    'ชุดเนื้อหารุ่นนี้ไม่พร้อมใช้งาน ข้อมูลการเรียนที่บันทึกไว้ไม่เปลี่ยนแปลง',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ],
            ],
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
    required this.canInteract,
    required this.validateAction,
    required this.openReport,
  });

  final LearningPackDetailView view;
  final List<VocabularyWord> words;
  final BookmarkLearningItemAction? bookmarkLearningItem;
  final ReportContentAction? reportContent;
  final bool Function() canInteract;
  final Future<void> Function() validateAction;
  final void Function(ContentIdentity) openReport;

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
              expectedOwnerId: view.progress.ownerId,
              reportIdentity: ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: word.id,
                revision: word.contentRevision,
              ),
              onReport: reportContent,
              canInteract: canInteract,
              validateAction: validateAction,
              onOpenReport: () => openReport(
                ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: word.id,
                  revision: word.contentRevision,
                ),
              ),
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
