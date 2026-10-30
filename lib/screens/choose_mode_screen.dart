import 'dart:async';

import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/presentation/study_host.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../services/ai_reading_content_adapter.dart';

import 'associative_reading_session_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'dictation_quiz_screen.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';
import '../navigation/app_routes.dart';
import 'srs_flashcards_screen.dart';
import 'weakness_clinic_screen.dart';

class ChooseModeScreen extends StatefulWidget {
  const ChooseModeScreen({
    super.key,
    this.loader,
    this.learning,
    this.featureRegistry,
    this.onOpenMenu,
    this.ownerChanges,
  });

  final ProgressLoader? loader;
  final LearningUseCases? learning;
  final FieldFeatureRegistry? featureRegistry;
  final VoidCallback? onOpenMenu;
  final Stream<String?>? ownerChanges;

  @override
  State<ChooseModeScreen> createState() => _ChooseModeScreenState();
}

class _ChooseModeScreenState extends State<ChooseModeScreen>
    with WidgetsBindingObserver {
  Future<ProgressSnapshot>? _load;
  AppDependencies? _studyDependencies;
  Stream<String?>? _studyOwners;
  bool _openingStudy = false;
  String? _studyOwnerId;
  int _studyEntryGeneration = 0;
  bool _studyRouteVisible = false;
  AppDependencies? _dictationDependencies;
  StreamSubscription<String?>? _dictationOwners;
  String? _dictationOwnerId;
  int _dictationGeneration = 0;
  bool _dictationBound = false;
  bool _dictationRouteVisible = false;
  bool _openingDictation = false;
  bool _choosingDictationCategory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _studyEntryGeneration++;
    _dictationGeneration++;
    _dictationOwners?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _studyEntryGeneration++;
    if (state != AppLifecycleState.resumed) {
      _dictationGeneration++;
    }
  }

  LearningUseCases? get _learning =>
      widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= _loadProgress();
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (_studyRouteVisible && !visible) _studyEntryGeneration++;
    _studyRouteVisible = visible;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _replaceStudyBinding(dependencies);
    if (_dictationRouteVisible && !visible && !_choosingDictationCategory) {
      _dictationGeneration++;
    }
    _dictationRouteVisible = visible;
    _replaceDictationBinding(dependencies);
  }

  @override
  void didUpdateWidget(covariant ChooseModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _replaceStudyBinding(AppDependenciesScope.maybeOf(context), force: true);
    }
    if (!identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _dictationGeneration++;
    }
  }

  void _replaceDictationBinding(AppDependencies? dependencies) {
    if (_dictationBound && identical(_dictationDependencies, dependencies)) {
      return;
    }
    _dictationBound = true;
    _dictationGeneration++;
    _dictationOwnerId = null;
    _dictationDependencies = dependencies;
    _dictationOwners?.cancel();
    final source = dependencies?.progress?.watchActiveOwnerId();
    _dictationOwners = source?.listen(
      (ownerId) {
        if (!mounted || !identical(_dictationDependencies, dependencies)) {
          return;
        }
        if (_dictationOwnerId != ownerId) {
          _dictationGeneration++;
          _dictationOwnerId = ownerId;
        }
      },
      onError: (Object _, StackTrace _) {
        if (mounted && identical(_dictationDependencies, dependencies)) {
          _dictationGeneration++;
          _dictationOwnerId = null;
        }
      },
      onDone: () {
        if (mounted && identical(_dictationDependencies, dependencies)) {
          _dictationGeneration++;
          _dictationOwnerId = null;
        }
      },
    );
  }

  void _replaceStudyBinding(
    AppDependencies? dependencies, {
    bool force = false,
  }) {
    if (!force && identical(dependencies, _studyDependencies)) return;
    _studyEntryGeneration++;
    _studyOwnerId = null;
    _studyDependencies = dependencies;
    final source =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    _studyOwners = dependencies?.studyRuntime == null
        ? null
        : source?.transform(
            StreamTransformer<String?, String?>.fromHandlers(
              handleData: (ownerId, sink) {
                _bindStudyOwner(dependencies, ownerId);
                sink.add(ownerId);
              },
              handleError: (Object error, StackTrace stack, sink) {
                _bindStudyOwner(dependencies, null);
                sink.addError(error, stack);
              },
              handleDone: (sink) {
                _bindStudyOwner(dependencies, null);
                sink.add(null);
                sink.close();
              },
            ),
          );
  }

  void _bindStudyOwner(AppDependencies? dependencies, String? ownerId) {
    if (identical(_studyDependencies, dependencies) &&
        _studyOwnerId != ownerId) {
      _studyOwnerId = ownerId;
      _studyEntryGeneration++;
    }
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    return loader == null
        ? Future.error(StateError('progress dependency unavailable'))
        : Future<ProgressSnapshot>.sync(loader);
  }

  void _refresh() {
    if (mounted) {
      final next = _loadProgress();
      setState(() {
        _load = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canQuiz = _features.isVisible(FieldFeature.quiz);
    final canReview = _features.isVisible(FieldFeature.srs);
    final canWeakness = _features.isVisible(FieldFeature.weakness);
    final canReading = _features.isVisible(FieldFeature.reading);
    final canViewProgress = _features.isVisible(FieldFeature.mastery);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 16.0
        : width < 600
        ? 20.0
        : ((width - 720) / 2).clamp(24.0, double.infinity).toDouble();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'เลือกแบบฝึก'),
        actions: widget.onOpenMenu == null
            ? null
            : [
                IconButton(
                  key: const ValueKey<String>('shell-drawer-button'),
                  tooltip: 'เปิดเมนูเพิ่มเติม',
                  onPressed: widget.onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
              ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          16,
          horizontalPadding,
          24,
        ),
        children: [
          Text(
            'วันนี้อยากฝึกอะไร',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _studyEntry(),
          FutureBuilder<ProgressSnapshot>(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'กำลังโหลดคำแนะนำการฝึก',
                  ),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text('โหลดคำแนะนำการฝึกไม่สำเร็จ'),
                    ),
                    TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ],
                );
              }
              final progress = snapshot.requireData;
              final hasDue = canReview && progress.dueReviewCount > 0;
              final hasWeakness = canWeakness && progress.weaknesses.isNotEmpty;
              final hasRecommendation = hasDue || hasWeakness || canQuiz;
              final queueSummary = <String>[
                if (canReview && progress.dueReviewCount > 0)
                  'ถึงกำหนด ${progress.dueReviewCount} คำ',
                if (canWeakness && progress.weaknesses.isNotEmpty)
                  'คำที่ควรฝึก ${progress.weaknesses.length} คำ',
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (queueSummary.isNotEmpty) Text(queueSummary.join(' • ')),
                  if (queueSummary.isNotEmpty) const SizedBox(height: 12),
                  if (hasRecommendation)
                    FilledButton.icon(
                      onPressed: () => _push(
                        context,
                        hasDue
                            ? SrsFlashcardsScreen(learning: _learning)
                            : hasWeakness
                            ? WeaknessClinicScreen(
                                loader: widget.loader,
                                learning: _learning,
                                featureRegistry: _features,
                              )
                            : QuizScreen(learning: _learning),
                      ),
                      icon: Icon(
                        hasDue
                            ? Icons.event_repeat_outlined
                            : hasWeakness
                            ? Icons.healing_outlined
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        hasDue
                            ? 'ทบทวน ${progress.dueReviewCount} คำ'
                            : hasWeakness
                            ? 'ฝึกคำที่ผิด ${progress.weaknesses.length} คำ'
                            : 'เริ่มฝึกคำศัพท์',
                      ),
                    )
                  else if (canReading)
                    const Text('เลือกกิจกรรมอ่านด้านล่าง')
                  else
                    const Text('ยังไม่มีกิจกรรมที่เปิดใช้งานในหน้านี้'),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('เลือกกิจกรรม', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (canQuiz) ...[
            _LearningTile(
              icon: Icons.quiz_outlined,
              title: 'ฝึกคำศัพท์',
              subtitle: 'ฝึกคำแปล แล้วดูคำที่ควรทบทวน',
              onTap: () => _push(context, QuizScreen(learning: _learning)),
            ),
            _LearningTile(
              icon: Icons.category_outlined,
              title: 'ฝึกตามหมวดหมู่',
              subtitle: 'เลือกจากหมวดหมู่ที่บันทึกในเครื่อง',
              onTap: () => _openCategoryQuiz(context),
            ),
          ],
          if (canReview)
            _LearningTile(
              icon: Icons.event_repeat_outlined,
              title: 'ทบทวนคำศัพท์ที่ถึงกำหนด',
              subtitle: 'ทบทวนคำที่ถึงเวลาแล้วตามประวัติการเรียน',
              onTap: () =>
                  _push(context, SrsFlashcardsScreen(learning: _learning)),
            ),
          if (canQuiz)
            _LearningTile(
              key: const ValueKey('dictation-entry'),
              icon: Icons.hearing_outlined,
              title: 'ฟังแล้วพิมพ์คำศัพท์',
              subtitle: 'เลือกหมวดหมู่ แล้วฝึกสะกดจากเสียงทีละคำ',
              onTap: _openDictation,
            ),
          if (canReading)
            _LearningTile(
              icon: Icons.menu_book_outlined,
              title: 'อ่านเรื่องสั้นและจำคำศัพท์',
              subtitle: 'อ่าน ทบทวนจากความจำ และแต่งประโยคด้วยคำเป้าหมาย',
              onTap: () => _openReading(context),
            ),
          if (canViewProgress)
            _LearningTile(
              icon: Icons.analytics_outlined,
              title: 'ภาพรวมการเรียน',
              subtitle: 'ดูความก้าวหน้าจากคำตอบที่บันทึกไว้',
              onTap: () => _push(
                context,
                MasteryDashboardScreen(
                  loader: widget.loader,
                  featureRegistry: _features,
                ),
              ),
            ),
          if (canWeakness)
            _LearningTile(
              icon: Icons.healing_outlined,
              title: 'ฝึกจุดอ่อน',
              subtitle: 'ฝึกคำที่เคยตอบผิดได้โดยไม่ต้องรอวันทบทวน',
              onTap: () => _push(
                context,
                WeaknessClinicScreen(
                  loader: widget.loader,
                  learning: _learning,
                  featureRegistry: _features,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _canOpenDictation(
    int generation,
    String ownerId,
    LearningUseCases learning,
    AppDependencies dependencies,
  ) =>
      mounted &&
      generation == _dictationGeneration &&
      ownerId == _dictationOwnerId &&
      identical(_dictationDependencies, dependencies) &&
      identical(_learning, learning) &&
      _features.isVisible(FieldFeature.quiz) &&
      ModalRoute.of(context)?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _openDictation() async {
    if (_openingDictation ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !Visibility.of(context) ||
        !_features.isVisible(FieldFeature.quiz)) {
      return;
    }
    final dependencies = _dictationDependencies;
    final learning = _learning;
    final ownerId = _dictationOwnerId;
    void unavailable({bool empty = false}) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            empty
                ? 'หมวดหมู่นี้ยังไม่มีคำที่พร้อมฝึก'
                : 'ยังเปิดกิจกรรมฟังแล้วพิมพ์ไม่ได้ กรุณาลองใหม่ภายหลัง',
          ),
        ),
      );
    }

    if (dependencies == null ||
        learning == null ||
        ownerId == null ||
        dependencies.progress == null ||
        dependencies.vocabulary == null) {
      unavailable();
      return;
    }
    final generation = _dictationGeneration;
    _openingDictation = true;
    _choosingDictationCategory = true;
    try {
      final categoryId = await AppNavigator.pushPage<String>(
        context,
        AppPage<String>(
          name: 'learning/dictation-category',
          builder: (_) =>
              SelectCategoryForQuiz(vocabulary: dependencies.vocabulary),
        ),
      );
      _choosingDictationCategory = false;
      if (!_canOpenDictation(generation, ownerId, learning, dependencies) ||
          categoryId == null) {
        return;
      }
      _dictationRouteVisible = true;
      final session = await learning.prepareDictation(
        categoryId: categoryId,
        stillCurrent: () =>
            _canOpenDictation(generation, ownerId, learning, dependencies),
      );
      if (!_canOpenDictation(generation, ownerId, learning, dependencies)) {
        return;
      }
      if (session == null) {
        unavailable(empty: true);
        return;
      }
      if (!mounted || session.ownerId != ownerId) {
        return;
      }
      final screenOwners = dependencies.progress!.watchActiveOwnerId();
      await AppNavigator.pushPage<LearningSessionSummary>(
        context,
        AppPage<LearningSessionSummary>(
          name: 'learning/dictation',
          builder: (_) => DictationQuizScreen(
            session: session,
            learning: learning,
            voice: dependencies.voice,
            ownerChanges: screenOwners,
          ),
        ),
      );
      if (mounted) {
        _refresh();
      }
    } on Object {
      if (_canOpenDictation(generation, ownerId, learning, dependencies)) {
        unavailable();
      }
    } finally {
      _choosingDictationCategory = false;
      _openingDictation = false;
    }
  }

  Future<void> _openCategoryQuiz(BuildContext context) async {
    final categoryId = await AppNavigator.pushPage<String>(
      context,
      AppPage<String>(
        name: 'learning/category-selector',
        builder: (_) => const SelectCategoryForQuiz(),
      ),
    );
    if (categoryId != null && context.mounted) {
      await _push(
        context,
        QuizScreen(categoryId: categoryId, learning: _learning),
      );
    }
  }

  Widget _studyEntry() {
    final runtime = _studyDependencies?.studyRuntime;
    final owners = _studyOwners;
    if (runtime == null || owners == null) return const SizedBox.shrink();
    final language = Localizations.localeOf(context).languageCode;
    return StreamBuilder<String?>(
      stream: owners,
      builder: (context, ownerSnapshot) {
        final ownerId = ownerSnapshot.data;
        if (ownerSnapshot.hasError || ownerId == null) {
          return const SizedBox.shrink();
        }
        return FutureBuilder<StudyView>(
          key: ValueKey((runtime, ownerId)),
          future: runtime.load(ownerId),
          builder: (context, snapshot) {
            final view = snapshot.data;
            if (snapshot.connectionState != ConnectionState.done ||
                snapshot.hasError ||
                view == null ||
                view.ownerId != ownerId ||
                view.phase == StudyPhase.unavailable) {
              return const SizedBox.shrink();
            }
            return _LearningTile(
              icon: Icons.science_outlined,
              title: language == 'th'
                  ? 'กิจกรรมวิจัยที่เข้าร่วม'
                  : 'Your study activity',
              subtitle: view.catalog.title(language),
              onTap: () => _openStudy(runtime, ownerId, owners, language),
            );
          },
        );
      },
    );
  }

  Future<void> _openStudy(
    StudyRuntime runtime,
    String ownerId,
    Stream<String?> owners,
    String language,
  ) async {
    final generation = _studyEntryGeneration;
    if (_openingStudy || !_canOpenStudy(runtime, ownerId, generation)) return;
    _openingStudy = true;
    try {
      final view = await runtime.load(ownerId);
      if (!mounted ||
          !_canOpenStudy(runtime, ownerId, generation) ||
          view.ownerId != ownerId ||
          view.phase == StudyPhase.unavailable) {
        return;
      }
      await _push(
        context,
        StudyHost(
          runtime: runtime,
          ownerId: ownerId,
          languageCode: language,
          ownerChanges: owners,
        ),
      );
    } on Object {
      if (mounted && _canOpenStudy(runtime, ownerId, generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == 'th'
                  ? 'ยังเปิดกิจกรรมวิจัยไม่ได้ กรุณาลองใหม่ภายหลัง'
                  : 'The study activity is unavailable. Please try again later.',
            ),
          ),
        );
      }
    } finally {
      _openingStudy = false;
    }
  }

  bool _canOpenStudy(StudyRuntime runtime, String ownerId, int generation) =>
      mounted &&
      generation == _studyEntryGeneration &&
      ownerId == _studyOwnerId &&
      identical(_studyDependencies?.studyRuntime, runtime) &&
      ModalRoute.of(context)?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _openReading(BuildContext context) async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final learning = _learning;
    if (learning == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังเปิดกิจกรรมอ่านไม่ได้ในขณะนี้')),
      );
      return;
    }
    final words = await learning.prepareReading();
    if (!context.mounted) return;
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เพิ่มคำศัพท์อย่างน้อย 1 คำก่อนเริ่มอ่าน'),
        ),
      );
      return;
    }
    final targetWords = words
        .map((word) => word.spelling)
        .toList(growable: false);
    final passage = await AiReadingContentAdapter().generatePassage(
      cefrLevel: 'B1',
      targetWords: targetWords,
      forceOffline: true,
    );
    if (!context.mounted) return;
    final owner = await learning.owners.getOrCreateActiveOwner();
    if (!context.mounted) return;
    await _push(
      context,
      AssociativeReadingSessionScreen(
        cefrLevel: passage.cefrLevel,
        targetWords: passage.targetWords,
        passageText: passage.passageText,
        documentId:
            '${passage.contentId}:${DateTime.now().microsecondsSinceEpoch}',
        learning: learning,
        associativeLearning: dependencies?.associativeLearning,
        targetWordIds: {for (final word in words) word.spelling: word.id},
        targetWordContentRevisions: {
          for (final word in words)
            if (word.contentRevision != null)
              word.spelling: word.contentRevision!,
        },
        ownerId: owner.id,
      ),
    );
  }

  Future<void> _push(BuildContext context, Widget screen) async {
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: 'learning/activity', builder: (_) => screen),
    );
    _refresh();
  }
}

class _LearningTile extends StatelessWidget {
  const _LearningTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 16,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
