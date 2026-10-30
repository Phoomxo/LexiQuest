import 'dart:async';

import 'package:flutter/material.dart';
import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/presentation/study_host.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../services/ai_reading_content_adapter.dart';

import 'associative_reading_session_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'review_center_screen.dart';
import 'dictation_quiz_screen.dart';
import 'fill_in_the_blanks_screen.dart';
import 'word_scramble_screen.dart';
import 'sentence_scramble_screen.dart';
import 'score_screen.dart';
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

enum _NativeMode { dictation, cloze, wordScramble, sentenceScramble }

class _ChooseModeScreenState extends State<ChooseModeScreen>
    with WidgetsBindingObserver {
  ProgressHostBinding? _progress;
  AppDependencies? _progressDependencies;
  Stream<String?>? _nativeOwnerSource;
  bool _openingProgressChild = false;
  bool _foreignProgressCover = false;
  AppDependencies? _studyDependencies;
  Stream<String?>? _studyOwners;
  bool _openingStudy = false;
  String? _studyOwnerId;
  int _studyEntryGeneration = 0;
  bool _studyRouteVisible = false;
  AppDependencies? _nativeDependencies;
  StreamSubscription<String?>? _nativeOwners;
  String? _nativeOwnerId;
  int _nativeGeneration = 0;
  int _nativeOwnerBinding = 0;
  final _nativeChanges = ValueNotifier<int>(0);
  bool _nativeNoticeScheduled = false;
  bool _nativeBound = false;
  bool _nativeRouteVisible = false;
  bool _openingNative = false;
  bool _choosingNativeOverlay = false;
  bool _openingSrs = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _studyEntryGeneration++;
    _nativeGeneration++;
    _progress?.dispose();
    _nativeChanges.dispose();
    _nativeOwners?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _studyEntryGeneration++;
    if (state != AppLifecycleState.resumed) {
      _invalidateNative();
      _progress?.invalidateLaunch();
    }
    _syncProgress();
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
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (_studyRouteVisible && !visible) _studyEntryGeneration++;
    _studyRouteVisible = visible;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _replaceStudyBinding(dependencies);
    if (_nativeRouteVisible &&
        !visible &&
        !_choosingNativeOverlay &&
        !_openingSrs) {
      _invalidateNative();
    }
    _nativeRouteVisible = visible;
    _replaceNativeBinding(dependencies);
    _bindProgress(dependencies);
    _syncProgress();
  }

  @override
  void didUpdateWidget(covariant ChooseModeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _replaceStudyBinding(AppDependenciesScope.maybeOf(context), force: true);
      _replaceNativeBinding(AppDependenciesScope.maybeOf(context), force: true);
    }
    if (!identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _invalidateNative();
    }
    if (!identical(oldWidget.loader, widget.loader) ||
        !identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _bindProgress(AppDependenciesScope.maybeOf(context), force: true);
    }
    _syncProgress();
  }

  void _replaceNativeBinding(
    AppDependencies? dependencies, {
    bool force = false,
  }) {
    if (!force &&
        _nativeBound &&
        identical(_nativeDependencies, dependencies)) {
      return;
    }
    _nativeBound = true;
    _invalidateNative();
    _nativeOwnerId = null;
    _nativeDependencies = dependencies;
    _nativeOwners?.cancel();
    final binding = ++_nativeOwnerBinding;
    final source =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    _nativeOwnerSource = source;
    _nativeOwners = source?.listen(
      (ownerId) {
        if (!mounted ||
            !identical(_nativeDependencies, dependencies) ||
            binding != _nativeOwnerBinding) {
          return;
        }
        if (_nativeOwnerId != ownerId) {
          _invalidateNative();
          _nativeOwnerId = ownerId;
        }
      },
      onError: (Object _, StackTrace _) {
        if (mounted &&
            identical(_nativeDependencies, dependencies) &&
            binding == _nativeOwnerBinding) {
          _invalidateNative();
          _nativeOwnerId = null;
        }
      },
      onDone: () {
        if (mounted &&
            identical(_nativeDependencies, dependencies) &&
            binding == _nativeOwnerBinding) {
          _invalidateNative();
          _nativeOwnerId = null;
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

  bool get _progressVisible =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _bindProgress(AppDependencies? dependencies, {bool force = false}) {
    if (!force &&
        _progress != null &&
        identical(_progressDependencies, dependencies) &&
        identical(_progress!.ownerChanges, _nativeOwnerSource)) {
      return;
    }
    _progress?.dispose();
    _progressDependencies = dependencies;
    _progress = ProgressHostBinding(
      progress: dependencies?.progress,
      loader: widget.loader,
      ownerChanges: _nativeOwnerSource,
      visible: () => _progressVisible,
    )..addListener(_progressChanged);
  }

  void _progressChanged() {
    if (mounted) setState(() {});
  }

  void _syncProgress() {
    _progress?.syncVisibility(
      ownedCover:
          Visibility.of(context) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ((_openingSrs || _openingProgressChild) && !_foreignProgressCover ||
              _choosingNativeOverlay ||
              _openingNative),
    );
  }

  void _refresh() => _progress?.refresh();

  VoidCallback? _readAction(VoidCallback action) {
    final binding = _progress;
    if (binding?.ownerId == null) return null;
    final epoch = binding!.readEpoch;
    return () {
      if (identical(binding, _progress) && binding.isReadCurrent(epoch)) {
        action();
      }
    };
  }

  Widget _trackProgressChild(Widget child, ProgressHostBinding binding) =>
      Builder(
        builder: (childContext) {
          final current = ModalRoute.isCurrentOf(childContext) == true;
          if (ModalRoute.of(childContext)?.isActive == true &&
              !current &&
              ModalRoute.of(context)?.isCurrent != true &&
              !_foreignProgressCover) {
            _foreignProgressCover = true;
            binding.invalidateLaunch();
            _invalidateNative();
          }
          return child;
        },
      );

  VoidCallback? _reviewCenterAction() {
    final binding = _progress;
    final owner = binding?.ownerId;
    final dependencies = _progressDependencies;
    final review = dependencies?.reviewCenter;
    final learning = _learning;
    final owners = _nativeOwnerSource;
    if (binding == null || owner == null || review == null || owners == null) {
      return null;
    }
    final epoch = binding.readEpoch;
    return () async {
      if (_openingProgressChild || !binding.isReadCurrent(epoch)) return;
      final launch = binding.beginLaunch(epoch, requireSnapshot: false);
      if (launch == null) return;
      bool current() =>
          mounted &&
          identical(binding, _progress) &&
          binding.isLaunchCurrent(launch, owner) &&
          identical(dependencies, _progressDependencies) &&
          identical(learning, _learning) &&
          Visibility.of(context) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      _openingProgressChild = true;
      _foreignProgressCover = false;
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'learning/review-center',
            builder: (_) => _trackProgressChild(
              current()
                  ? ReviewCenterScreen(
                      expectedOwnerId: owner,
                      reviewCenter: review,
                      ownerChanges: owners,
                      learning: learning,
                      savedWords: dependencies?.savedWords,
                      wordReports: dependencies?.wordReports,
                      voice: dependencies?.voice,
                      featureRegistry: _features,
                      languageCode: Localizations.localeOf(
                        context,
                      ).languageCode,
                    )
                  : const Scaffold(body: SizedBox.shrink()),
              binding,
            ),
          ),
        );
      } finally {
        _openingProgressChild = false;
        if (current() && _progressVisible) _syncProgress();
      }
    };
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
          Builder(
            builder: (context) {
              final binding = _progress;
              if (binding?.ownerId == null) return const SizedBox.shrink();
              if (binding!.loading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(
                    semanticsLabel: 'กำลังโหลดคำแนะนำการฝึก',
                  ),
                );
              }
              if (binding.readFailed || binding.snapshot == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text('โหลดคำแนะนำการฝึกไม่สำเร็จ'),
                    ),
                    TextButton.icon(
                      onPressed: _readAction(_refresh),
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ],
                );
              }
              final progress = binding.snapshot!;
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
                      onPressed: hasDue
                          ? _dueReviewAction()
                          : _readAction(
                              () => _push(
                                context,
                                hasWeakness
                                    ? WeaknessClinicScreen(
                                        loader: widget.loader,
                                        learning: _learning,
                                        featureRegistry: _features,
                                        ownerChanges: _nativeOwnerSource,
                                      )
                                    : QuizScreen(
                                        learning: _learning,
                                        expectedOwnerId: _progress?.ownerId,
                                        ownerChanges: _nativeOwnerSource,
                                      ),
                              ),
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
          const SizedBox(height: 16),
          _LearningTile(
            key: const ValueKey('review-center-entry'),
            icon: Icons.collections_bookmark_outlined,
            title: 'ศูนย์ทบทวน',
            subtitle: 'คำถึงกำหนด คำที่ผิด คำที่บันทึก และรายงานในเครื่อง',
            onTap: _reviewCenterAction(),
          ),
          const SizedBox(height: 24),
          Text('เลือกกิจกรรม', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (canQuiz) ...[
            _LearningTile(
              icon: Icons.quiz_outlined,
              title: 'ฝึกคำศัพท์',
              subtitle: 'ฝึกคำแปล แล้วดูคำที่ควรทบทวน',
              onTap: _readAction(
                () => _push(
                  context,
                  QuizScreen(
                    learning: _learning,
                    expectedOwnerId: _progress?.ownerId,
                    ownerChanges: _nativeOwnerSource,
                  ),
                ),
              ),
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
              onTap: _dueReviewAction(),
            ),
          if (canQuiz)
            _LearningTile(
              key: const ValueKey('dictation-entry'),
              icon: Icons.hearing_outlined,
              title: 'ฟังแล้วพิมพ์คำศัพท์',
              subtitle: 'เลือกหมวดหมู่ แล้วฝึกสะกดจากเสียงทีละคำ',
              onTap: _openDictation,
            ),
          if (canQuiz)
            _LearningTile(
              key: const ValueKey('cloze-entry'),
              icon: Icons.short_text_outlined,
              title: 'เติมคำในบริบท',
              subtitle: 'เลือกพิมพ์หรือเลือกคำจากประโยคที่สร้างด้วย AI',
              onTap: _openCloze,
            ),
          if (canQuiz)
            _LearningTile(
              key: const ValueKey('word-scramble-entry'),
              icon: Icons.sort_by_alpha_outlined,
              title: 'เกมเรียงตัวอักษร',
              subtitle: 'เลือกหมวดหมู่ แล้วเรียงตัวอักษรหรือพิมพ์คำตอบ',
              onTap: _openWordScramble,
            ),
          if (canQuiz)
            _LearningTile(
              key: const ValueKey('sentence-scramble-entry'),
              icon: Icons.reorder_outlined,
              title: 'เกมเรียงประโยค',
              subtitle:
                  'เลือกหมวดหมู่ แล้วเรียงคำหรือพิมพ์ประโยคที่สร้างด้วย AI',
              onTap: _openSentenceScramble,
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
              onTap: _readAction(
                () => _push(
                  context,
                  MasteryDashboardScreen(
                    loader: widget.loader,
                    featureRegistry: _features,
                    ownerChanges: _nativeOwnerSource,
                  ),
                ),
              ),
            ),
          if (canWeakness)
            _LearningTile(
              icon: Icons.healing_outlined,
              title: 'ฝึกจุดอ่อน',
              subtitle: 'ฝึกคำที่เคยตอบผิดได้โดยไม่ต้องรอวันทบทวน',
              onTap: _readAction(
                () => _push(
                  context,
                  WeaknessClinicScreen(
                    loader: widget.loader,
                    learning: _learning,
                    featureRegistry: _features,
                    ownerChanges: _nativeOwnerSource,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _invalidateNative() {
    _nativeGeneration++;
    if (_nativeNoticeScheduled) return;
    _nativeNoticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nativeNoticeScheduled = false;
      if (mounted) {
        _nativeChanges.value = _nativeGeneration;
        setState(() {});
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  VoidCallback? _dueReviewAction() {
    final generation = _nativeGeneration;
    final ownerId = _nativeOwnerId;
    final learning = _learning;
    final dependencies = _nativeDependencies;
    final binding = _progress;
    if (ownerId == null || learning == null || binding?.snapshot == null) {
      return null;
    }
    final epoch = binding!.readEpoch;
    int? launch;
    bool current() =>
        mounted &&
        (launch == null || binding.isLaunchCurrent(launch!, ownerId)) &&
        generation == _nativeGeneration &&
        ownerId == _nativeOwnerId &&
        identical(learning, _learning) &&
        identical(dependencies, _nativeDependencies) &&
        _features.isVisible(FieldFeature.srs) &&
        Visibility.of(context) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    return () async {
      if (_openingSrs ||
          !binding.isReadCurrent(epoch) ||
          !current() ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final owners = _nativeOwnerSource;
      if (owners == null) return;
      launch = binding.beginLaunch(epoch);
      if (launch == null) return;
      _foreignProgressCover = false;
      _openingSrs = true;
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'learning/due-srs',
            builder: (_) => _trackProgressChild(
              current()
                  ? SrsFlashcardsScreen(
                      expectedOwnerId: ownerId,
                      ownerChanges: owners,
                      learning: learning,
                      voice: dependencies?.voice,
                    )
                  : const Scaffold(
                      body: Center(child: Text('การทบทวนไม่พร้อมใช้งาน')),
                    ),
              binding,
            ),
          ),
        );
      } finally {
        _openingSrs = false;
        if (current() && _progressVisible) _syncProgress();
      }
    };
  }

  bool _nativeContextCurrent(
    int generation,
    String ownerId,
    LearningUseCases learning,
    AppDependencies dependencies,
  ) =>
      mounted &&
      generation == _nativeGeneration &&
      ownerId == _nativeOwnerId &&
      identical(_nativeDependencies, dependencies) &&
      identical(_learning, learning) &&
      _features.isVisible(FieldFeature.quiz) &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool _canOpenNative(
    int generation,
    String ownerId,
    LearningUseCases learning,
    AppDependencies dependencies,
  ) =>
      _nativeContextCurrent(generation, ownerId, learning, dependencies) &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> _openDictation() => _openNative(_NativeMode.dictation);

  Future<void> _openCloze() => _openNative(_NativeMode.cloze);

  Future<void> _openWordScramble() => _openNative(_NativeMode.wordScramble);

  Future<void> _openSentenceScramble() =>
      _openNative(_NativeMode.sentenceScramble);

  Widget _nativeOverlay(Widget child) => Builder(
    builder: (overlayContext) {
      final current = ModalRoute.isCurrentOf(overlayContext);
      if (ModalRoute.of(overlayContext)?.isActive == true && current != true) {
        _invalidateNative();
      }
      return child;
    },
  );

  Future<void> _openNative(_NativeMode mode) async {
    final cloze = mode == _NativeMode.cloze;
    if (_openingNative ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !Visibility.of(context) ||
        !_features.isVisible(FieldFeature.quiz)) {
      return;
    }
    final dependencies = _nativeDependencies;
    final learning = _learning;
    final ownerId = _nativeOwnerId;
    void unavailable({bool empty = false}) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            empty
                ? 'หมวดหมู่นี้ยังไม่มีคำที่พร้อมฝึก'
                : switch (mode) {
                    _NativeMode.cloze =>
                      'ยังเปิดกิจกรรมเติมคำไม่ได้ กรุณาลองใหม่ภายหลัง',
                    _NativeMode.wordScramble =>
                      'ยังเปิดเกมเรียงตัวอักษรไม่ได้ กรุณาลองใหม่ภายหลัง',
                    _NativeMode.sentenceScramble =>
                      'ยังเปิดเกมเรียงประโยคไม่ได้ กรุณาลองใหม่ภายหลัง',
                    _NativeMode.dictation =>
                      'ยังเปิดกิจกรรมฟังแล้วพิมพ์ไม่ได้ กรุณาลองใหม่ภายหลัง',
                  },
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
    final generation = _nativeGeneration;
    _openingNative = true;
    _choosingNativeOverlay = true;
    try {
      ClozeVariant? variant;
      if (cloze) {
        variant = await showDialog<ClozeVariant>(
          context: context,
          builder: (dialogContext) => _nativeOverlay(
            AlertDialog(
              scrollable: true,
              title: const Text('เลือกรูปแบบเติมคำ'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    key: const ValueKey('cloze-variant-typed'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(ClozeVariant.typed),
                    child: const Text('พิมพ์คำที่ขาดหายไป'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('cloze-variant-choice'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(ClozeVariant.choice),
                    child: const Text('เลือกจาก 3 คำ'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ยกเลิก'),
                ),
              ],
            ),
          ),
        );
        if (!_canOpenNative(generation, ownerId, learning, dependencies) ||
            variant == null) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
      final categoryId = await AppNavigator.pushPage<String>(
        context,
        AppPage<String>(
          name: switch (mode) {
            _NativeMode.cloze => 'learning/cloze-category',
            _NativeMode.wordScramble => 'learning/word-scramble-category',
            _NativeMode.sentenceScramble =>
              'learning/sentence-scramble-category',
            _NativeMode.dictation => 'learning/dictation-category',
          },
          builder: (_) => _nativeOverlay(
            SelectCategoryForQuiz(vocabulary: dependencies.vocabulary),
          ),
        ),
      );
      _choosingNativeOverlay = false;
      if (!_canOpenNative(generation, ownerId, learning, dependencies) ||
          categoryId == null) {
        return;
      }
      _nativeRouteVisible = true;
      final AcceptedNativeExercise? session = switch (mode) {
        _NativeMode.cloze => await learning.prepareCloze(
          categoryId: categoryId,
          variant: variant!,
          stillCurrent: () =>
              _canOpenNative(generation, ownerId, learning, dependencies),
        ),
        _NativeMode.wordScramble => await learning.prepareWordScramble(
          categoryId: categoryId,
          stillCurrent: () =>
              _canOpenNative(generation, ownerId, learning, dependencies),
        ),
        _NativeMode.sentenceScramble => await learning.prepareSentenceScramble(
          categoryId: categoryId,
          stillCurrent: () =>
              _canOpenNative(generation, ownerId, learning, dependencies),
        ),
        _NativeMode.dictation => await learning.prepareDictation(
          categoryId: categoryId,
          stillCurrent: () =>
              _canOpenNative(generation, ownerId, learning, dependencies),
        ),
      };
      if (!_canOpenNative(generation, ownerId, learning, dependencies)) {
        return;
      }
      if (session == null) {
        unavailable(empty: !cloze);
        return;
      }
      if (!mounted || session.ownerId != ownerId) {
        return;
      }
      final screenOwners = dependencies.progress!.watchActiveOwnerId();
      final summary = await AppNavigator.pushPage<LearningSessionSummary>(
        context,
        AppPage<LearningSessionSummary>(
          name: switch (mode) {
            _NativeMode.cloze => 'learning/cloze',
            _NativeMode.wordScramble => 'learning/word-scramble',
            _NativeMode.sentenceScramble => 'learning/sentence-scramble',
            _NativeMode.dictation => 'learning/dictation',
          },
          builder: (_) => switch (session) {
            final DictationSession exercise => DictationQuizScreen(
              session: exercise,
              learning: learning,
              voice: dependencies.voice,
              ownerChanges: screenOwners,
            ),
            final WordScrambleSession exercise => WordScrambleScreen(
              session: exercise,
              learning: learning,
              ownerChanges: screenOwners,
            ),
            final SentenceScrambleSession exercise => SentenceScrambleScreen(
              session: exercise,
              learning: learning,
              ownerChanges: screenOwners,
              voice: dependencies.voice,
            ),
            final ClozeSession exercise => FillInTheBlanksScreen(
              session: exercise,
              learning: learning,
              ownerChanges: screenOwners,
            ),
          },
        ),
      );
      if (mode == _NativeMode.sentenceScramble &&
          summary != null &&
          summary.id == session.id &&
          summary.state == 'completed' &&
          summary.correctCount >= 0 &&
          summary.wrongCount >= 0 &&
          summary.correctCount + summary.wrongCount == 1 &&
          summary.score == summary.correctCount * 100 &&
          _canOpenNative(generation, ownerId, learning, dependencies)) {
        await _showNativeSummary(
          summary,
          generation: generation,
          ownerId: ownerId,
          learning: learning,
          dependencies: dependencies,
        );
      }
      if (mounted) {
        _syncProgress();
      }
    } on Object {
      if (_canOpenNative(generation, ownerId, learning, dependencies)) {
        unavailable();
      }
    } finally {
      _choosingNativeOverlay = false;
      _openingNative = false;
    }
  }

  Future<void> _showNativeSummary(
    LearningSessionSummary summary, {
    required int generation,
    required String ownerId,
    required LearningUseCases learning,
    required AppDependencies dependencies,
  }) => AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: 'learning/sentence-scramble-result',
      builder: (scoreContext) => ValueListenableBuilder<int>(
        valueListenable: _nativeChanges,
        builder: (_, _, _) {
          final current = ModalRoute.isCurrentOf(scoreContext);
          final route = ModalRoute.of(scoreContext);
          if (route?.isActive == true &&
              current != true &&
              generation == _nativeGeneration) {
            _invalidateNative();
          }
          bool valid() => _nativeContextCurrent(
            generation,
            ownerId,
            learning,
            dependencies,
          );
          void close() {
            if (mounted &&
                route?.isCurrent == true &&
                route?.isActive == true) {
              Navigator.of(scoreContext).pop();
            }
          }

          if (!valid()) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('ผลการเรียน'),
                leading: BackButton(onPressed: close),
              ),
              body: const Center(
                child: Text('ข้อมูลเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม'),
              ),
            );
          }
          return ScoreScreen(
            correctAnswers: summary.correctCount,
            wrongAnswers: summary.wrongCount,
            score: summary.score,
            onBack: () {
              if (valid()) close();
            },
          );
        },
      ),
    ),
  );

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
    _syncProgress();
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
  final VoidCallback? onTap;

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
