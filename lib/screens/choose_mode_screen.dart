import 'dart:async';

import 'package:flutter/material.dart';
import '../ai/ai_models.dart';
import '../features/billing/presentation/subscription_screen.dart';
import '../features/learning_profile/presentation/learning_profile_editor_screen.dart';
import '../features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/recall_ladder.dart';
import '../features/learning/presentation/recall_ladder_panel.dart';
import '../features/study_reminders/presentation/study_reminder_settings_screen.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/motivation/presentation/quest_screen.dart';
import '../features/motivation/presentation/today_motivation_panel.dart';
import '../features/motivation/presentation/contextual_companion_panel.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import '../features/progress/presentation/today_resume_panel.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/presentation/study_host.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/motivation_runtime.dart';
import '../runtime/registries/feature.dart';
import '../services/ai_reading_content_adapter.dart';

import 'associative_reading_session_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'learning_history_screen.dart';
import 'review_center_screen.dart';
import 'focus_timer_screen.dart';
import 'dictation_quiz_screen.dart';
import 'fill_in_the_blanks_screen.dart';
import 'word_scramble_screen.dart';
import 'sentence_scramble_screen.dart';
import 'score_screen.dart';
import 'quiz_screen.dart';
import 'matching_quiz_screen.dart';
import 'source_practice_screen.dart';
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
  bool _nativeChildActive = false;
  bool _choosingNativeOverlay = false;
  bool _openingSrs = false;
  bool _openingMotivation = false;
  bool _openingMatching = false;
  bool _openingLadder = false;
  bool _openingReminder = false;

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
      if (!(_openingReminder &&
          _nativeDependencies?.studyReminders?.isRequestingPermission ==
              true)) {
        _invalidateNative();
      }
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
        !_nativeChildActive &&
        !_openingSrs &&
        !_openingMatching &&
        !_openingLadder &&
        !_openingReminder &&
        !_openingMotivation) {
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
              _nativeChildActive),
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
    final dependencies = _progressDependencies;
    final review = dependencies?.reviewCenter;
    final learning = _learning;
    final features = _features;
    final languageCode = Localizations.localeOf(context).languageCode;
    return _independentToolAction(
      routeName: 'learning/review-center',
      available: review != null,
      destination: (owner, owners) => ReviewCenterScreen(
        expectedOwnerId: owner,
        reviewCenter: review,
        ownerChanges: owners,
        learning: learning,
        savedWords: dependencies?.savedWords,
        wordReports: dependencies?.wordReports,
        voice: dependencies?.voice,
        featureRegistry: features,
        languageCode: languageCode,
      ),
    );
  }

  VoidCallback? _focusTimerAction() {
    final languageCode = Localizations.localeOf(context).languageCode;
    return _independentToolAction(
      routeName: 'learning/focus-timer',
      available: true,
      destination: (owner, owners) => FocusTimerScreen(
        expectedOwnerId: owner,
        ownerChanges: owners,
        languageCode: languageCode,
      ),
    );
  }

  VoidCallback? _independentToolAction({
    required String routeName,
    required bool available,
    required Widget Function(String owner, Stream<String?> owners) destination,
  }) {
    final binding = _progress;
    final owner = binding?.ownerId;
    final dependencies = _progressDependencies;
    final learning = _learning;
    final features = _features;
    final owners = _nativeOwnerSource;
    if (!available || binding == null || owner == null || owners == null) {
      return null;
    }
    final epoch = binding.readEpoch;
    return () async {
      if (!mounted ||
          _openingProgressChild ||
          !identical(binding, _progress) ||
          !binding.isReadCurrent(epoch)) {
        return;
      }
      final parentRoute = ModalRoute.of(context);
      if (parentRoute?.isCurrent != true) return;
      StreamSubscription<String?>? ownerLease;
      var childLeaseCurrent = true;
      var opening = false;
      int? launchGeneration;
      Widget? mountedDestination;

      bool childContextCurrent() =>
          mounted &&
          childLeaseCurrent &&
          identical(binding, _progress) &&
          identical(dependencies, _progressDependencies) &&
          identical(owners, _nativeOwnerSource) &&
          identical(learning, _learning) &&
          identical(features, _features);

      bool returnCurrent() =>
          childContextCurrent() &&
          launchGeneration != null &&
          binding.isLaunchCurrent(launchGeneration, owner) &&
          Visibility.of(context) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

      void invalidateChildLease() {
        if (!childLeaseCurrent) return;
        childLeaseCurrent = false;
        if (mounted) _invalidateNative();
      }

      try {
        try {
          ownerLease = owners.listen(
            (activeOwner) {
              if (activeOwner != owner) invalidateChildLease();
            },
            onError: (Object _, StackTrace _) => invalidateChildLease(),
            onDone: invalidateChildLease,
          );
        } on Object {
          invalidateChildLease();
          return;
        }
        if (!childContextCurrent() || !binding.isReadCurrent(epoch)) return;
        final generation = binding.beginLaunch(epoch, requireSnapshot: false);
        if (generation == null) return;
        launchGeneration = generation;
        opening = true;
        _openingProgressChild = true;
        _foreignProgressCover = false;
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: routeName,
            builder: (_) => ValueListenableBuilder<int>(
              valueListenable: _nativeChanges,
              builder: (childContext, _, _) {
                if (!childContextCurrent() ||
                    (mountedDestination == null &&
                        !binding.isLaunchCurrent(generation, owner))) {
                  final route = ModalRoute.of(childContext);
                  return Scaffold(
                    appBar: AppBar(
                      leading: BackButton(
                        onPressed: () {
                          if (route?.isCurrent == true) {
                            route?.navigator?.pop();
                          }
                        },
                      ),
                    ),
                    body: const Center(child: Text('กิจกรรมไม่พร้อมใช้งาน')),
                  );
                }
                return _trackProgressChild(
                  mountedDestination ??= destination(owner, owners),
                  binding,
                );
              },
            ),
          ),
        );
      } finally {
        if (opening) {
          _openingProgressChild = false;
          if (mounted &&
              returnCurrent() &&
              identical(parentRoute, ModalRoute.of(context)) &&
              parentRoute?.isCurrent == true &&
              _progressVisible) {
            _syncProgress();
          }
        }
        await ownerLease?.cancel();
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
          _motivationEntry(),
          _todayResumeEntry(),
          _recallEntry(),
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
          if (canQuiz && _nativeDependencies?.matching != null)
            _LearningTile(
              key: const ValueKey('matching-entry'),
              icon: Icons.compare_arrows_outlined,
              title: 'จับคู่คำศัพท์',
              subtitle: 'เลือกคำและความหมายที่ตรงกัน แล้วตรวจคำตอบ',
              onTap: _openingMatching ? null : _openMatching,
            ),
          if (AppDependenciesScope.maybeOf(context)?.learningPacks
              case final packs?)
            _LearningTile(
              key: const ValueKey('learning-packs-entry'),
              icon: Icons.library_books_outlined,
              title: 'แพ็กบทเรียนและคำศัพท์',
              subtitle: 'ดูเนื้อหา นำเข้า และฝึกจากแพ็กออฟไลน์',
              onTap: () => _push(
                context,
                LearningPackCatalogScreen(
                  packs: packs,
                  downloads: AppDependenciesScope.maybeOf(
                    context,
                  )?.learningPackDownloads,
                ),
              ),
            ),
          if (AppDependenciesScope.maybeOf(context)?.learningProfile
              case final profile?)
            _LearningTile(
              key: const ValueKey('learning-goal-onboarding-entry'),
              icon: Icons.flag_outlined,
              title: 'เป้าหมายและแผนการเรียน',
              subtitle: 'เลือกตั้งเป้าหมายและความชอบ หรือข้ามได้',
              onTap: _readAction(
                () => _push(
                  context,
                  LearningProfileEditorScreen(
                    profile: profile,
                    onboarding: true,
                  ),
                ),
              ),
            ),
          _LearningTile(
            key: const ValueKey('focus-timer-entry'),
            icon: Icons.timer_outlined,
            title: Localizations.localeOf(context).languageCode == 'en'
                ? 'Focus Timer'
                : 'จับเวลาโฟกัส',
            subtitle: Localizations.localeOf(context).languageCode == 'en'
                ? 'An optional local interval. It does not record learning time.'
                : 'ช่วงเวลาในเครื่อง เลือกใช้ได้ ไม่ใช่เวลาเรียนที่บันทึก',
            onTap: _focusTimerAction(),
          ),
          if (_nativeDependencies?.studyReminders != null)
            _LearningTile(
              key: const ValueKey('study-reminder-entry'),
              icon: Icons.notifications_none_outlined,
              title: 'การเตือนเรียน',
              subtitle: 'ปิดไว้จนกว่าคุณจะเลือกเวลาและอนุญาตการแจ้งเตือน',
              onTap: _nativeOwnerId == null || _openingReminder
                  ? null
                  : _openReminder,
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

  Future<void> _openMatching() async {
    final dependencies = _nativeDependencies;
    final matching = dependencies?.matching;
    final learning = _learning;
    final ownerId = _nativeOwnerId;
    final owners = dependencies?.progress;
    if (_openingMatching ||
        dependencies == null ||
        matching == null ||
        learning == null ||
        ownerId == null ||
        owners == null ||
        !_nativeRouteVisible ||
        !_canOpenNative(_nativeGeneration, ownerId, learning, dependencies)) {
      return;
    }
    final generation = _nativeGeneration;
    _openingMatching = true;
    bool current() =>
        _openingMatching &&
        _nativeContextCurrent(generation, ownerId, learning, dependencies) &&
        identical(matching, dependencies.matching);
    try {
      final plan = await matching.prepare(
        expectedOwnerId: ownerId,
        stillCurrent: current,
      );
      if (!current() || !mounted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ต้องมีคำและความหมายที่ไม่ซ้ำกันอย่างน้อย 2 คู่'),
          ),
        );
        return;
      }
      final screenOwners = owners.watchActiveOwnerId();
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/matching',
          builder: (_) => ValueListenableBuilder<int>(
            valueListenable: _nativeChanges,
            builder: (_, _, _) => current()
                ? MatchingQuizScreen(
                    matching: matching,
                    expectedOwnerId: ownerId,
                    ownerChanges: screenOwners,
                    preparedPlan: plan,
                    learning: learning,
                    learningTime: dependencies.learningTime,
                  )
                : const Scaffold(
                    body: Center(child: Text('กิจกรรมไม่พร้อมใช้งาน')),
                  ),
          ),
        ),
      );
    } on Object {
      if (current() && mounted && ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดเกมจับคู่ไม่ได้ ลองใหม่อีกครั้ง')),
        );
      }
    } finally {
      _openingMatching = false;
      if (mounted) _syncProgress();
    }
  }

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
      _nativeChildActive = true;
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
              learningTimeCallerContext: LearningTimeCallerContext.ordinary,
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
              learningTimeCallerContext: LearningTimeCallerContext.ordinary,
              session: exercise,
              learning: learning,
              ownerChanges: screenOwners,
            ),
          },
        ),
      );
      if (summary != null &&
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
          mode: mode,
        );
      }
      if (mounted) {
        _syncProgress();
      }
    } on AiFailure catch (failure) {
      if (_canOpenNative(generation, ownerId, learning, dependencies)) {
        final message = switch (failure.category) {
          AiFailureCategory.paymentRequired =>
            'ตรวจสอบหรือกู้คืนสิทธิ์สมาชิกก่อนใช้ AI ในส่วนนี้',
          AiFailureCategory.quotaExhausted =>
            'ใช้โควตา AI ของรอบนี้ครบแล้ว ตรวจสอบแพ็กเกจสมาชิกได้',
          AiFailureCategory.operationUncertain =>
            'ยังยืนยันผลคำขอ AI เดิมไม่ได้ กรุณารอตรวจสอบก่อนเริ่มคำขอใหม่',
          AiFailureCategory.authentication =>
            'ยังยืนยันบัญชีสำหรับ AI ไม่ได้ โปรดตรวจสอบการเข้าสู่ระบบ',
          _ => null,
        };
        if (message == null) {
          unavailable();
        } else {
          final billing = dependencies.billing;
          final canReviewMembership =
              failure.category == AiFailureCategory.paymentRequired ||
              failure.category == AiFailureCategory.quotaExhausted;
          final openMembership = billing == null || !canReviewMembership
              ? null
              : _readAction(() {
                  if (mounted &&
                      _canOpenNative(
                        generation,
                        ownerId,
                        learning,
                        dependencies,
                      )) {
                    unawaited(
                      _push(context, SubscriptionScreen(billing: billing)),
                    );
                  }
                });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              action: openMembership == null
                  ? null
                  : SnackBarAction(
                      label: 'ตรวจสอบสมาชิก',
                      onPressed: openMembership,
                    ),
            ),
          );
        }
      }
    } on Object {
      if (_canOpenNative(generation, ownerId, learning, dependencies)) {
        unavailable();
      }
    } finally {
      _nativeChildActive = false;
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
    required _NativeMode mode,
  }) => AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: switch (mode) {
        _NativeMode.dictation => 'learning/dictation-result',
        _NativeMode.cloze => 'learning/cloze-result',
        _NativeMode.sentenceScramble => 'learning/sentence-scramble-result',
        _NativeMode.wordScramble => 'learning/word-scramble-result',
      },
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
            learningTime: switch (mode) {
              _NativeMode.dictation ||
              _NativeMode.cloze => dependencies.learningTime,
              _NativeMode.wordScramble || _NativeMode.sentenceScramble => null,
            },
            resultOwnerId: ownerId,
            resultSessionId: summary.id,
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

  Future<void> _openReminder() async {
    final dependencies = _nativeDependencies;
    final runtime = dependencies?.studyReminders;
    final owner = _nativeOwnerId;
    if (_openingReminder ||
        dependencies == null ||
        runtime == null ||
        owner == null ||
        !_nativeRouteVisible ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final generation = _nativeGeneration;
    bool current() =>
        mounted &&
        generation == _nativeGeneration &&
        owner == _nativeOwnerId &&
        identical(dependencies, _nativeDependencies) &&
        identical(runtime, dependencies.studyReminders) &&
        !runtime.isRetired &&
        runtime.currentOwnerId == owner &&
        Visibility.of(context) &&
        (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
            (_openingReminder && runtime.isRequestingPermission));
    if (!current()) return;
    _openingReminder = true;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/study-reminder',
          builder: (_) => ValueListenableBuilder<int>(
            valueListenable: _nativeChanges,
            builder: (_, _, _) => current()
                ? StudyReminderSettingsScreen(runtime: runtime, ownerId: owner)
                : const Scaffold(
                    body: Center(child: Text('การเตือนไม่พร้อมใช้งาน')),
                  ),
          ),
        ),
      );
    } finally {
      _openingReminder = false;
    }
  }

  Widget _todayResumeEntry() => ValueListenableBuilder<int>(
    valueListenable: _nativeChanges,
    builder: (context, _, _) {
      final dependencies = _nativeDependencies;
      final progress = dependencies?.progress;
      final owner = _nativeOwnerId;
      final owners = _nativeOwnerSource;
      if (dependencies == null ||
          progress == null ||
          owner == null ||
          owners == null ||
          !_features.isVisible(FieldFeature.mastery)) {
        return const SizedBox.shrink();
      }
      final generation = _nativeGeneration;
      return TodayResumePanel(
        key: ValueKey(('today-resume', owner, generation)),
        progress: progress,
        ownerId: owner,
        ownerChanges: owners,
        onOpenHistory: () async {
          if (!mounted ||
              !context.mounted ||
              generation != _nativeGeneration ||
              owner != _nativeOwnerId ||
              !identical(dependencies, _nativeDependencies) ||
              ModalRoute.of(context)?.isCurrent != true ||
              !Visibility.of(context) ||
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) {
            return;
          }
          await AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: 'learning/today-history',
              builder: (_) => LearningHistoryScreen(ownerChanges: owners),
            ),
          );
        },
      );
    },
  );

  Widget _recallEntry() => ValueListenableBuilder<int>(
    valueListenable: _nativeChanges,
    builder: (context, _, _) {
      final dependencies = _nativeDependencies;
      final reader = dependencies?.recallLadder;
      final owner = _nativeOwnerId;
      final owners = _nativeOwnerSource;
      if (dependencies == null ||
          reader == null ||
          owner == null ||
          owners == null ||
          !_features.isVisible(FieldFeature.quiz)) {
        return const SizedBox.shrink();
      }
      final generation = _nativeGeneration;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RecallLadderPanel(
          key: ValueKey(('ladder', reader, owner, generation)),
          reader: reader,
          ownerId: owner,
          ownerChanges: owners,
          canPractice: (stage, word) => switch (stage) {
            RecallLadderStage.exposure =>
              _learning != null && _features.isVisible(FieldFeature.srs),
            RecallLadderStage.recognition ||
            RecallLadderStage.cloze ||
            RecallLadderStage.dictation => _learning != null,
            RecallLadderStage.matching => dependencies.matching != null,
            RecallLadderStage.typedRecall => dependencies.learningPacks != null,
            RecallLadderStage.speaking =>
              dependencies.speechPractice != null &&
                  dependencies.vocabulary != null &&
                  dependencies.sourcePracticeFilePicker != null &&
                  _features.isVisible(FieldFeature.speechPractice),
          },
          onPractice: (stage, word) async {
            final learning = _learning;
            if (_openingLadder ||
                learning == null ||
                !_nativeRouteVisible ||
                !_canOpenNative(generation, owner, learning, dependencies)) {
              return;
            }
            _openingLadder = true;
            try {
              switch (stage) {
                case RecallLadderStage.matching:
                  await _openMatching();
                case RecallLadderStage.cloze:
                  await _openCloze();
                case RecallLadderStage.dictation:
                  await _openDictation();
                case RecallLadderStage.exposure:
                  await _push(
                    context,
                    SrsFlashcardsScreen(
                      sourceWordIds: [word.id],
                      expectedOwnerId: owner,
                      ownerChanges: owners,
                      learning: learning,
                      learningTime: dependencies.learningTime,
                      voice: dependencies.voice,
                    ),
                  );
                case RecallLadderStage.recognition:
                  await _push(
                    context,
                    QuizScreen(
                      wordIds: [word.id],
                      learning: learning,
                      expectedOwnerId: owner,
                      ownerChanges: owners,
                      voice: dependencies.voice,
                      learningTime: dependencies.learningTime,
                    ),
                  );
                case RecallLadderStage.typedRecall:
                  await _push(
                    context,
                    LearningPackCatalogScreen(
                      packs: dependencies.learningPacks,
                      downloads: dependencies.learningPackDownloads,
                    ),
                  );
                case RecallLadderStage.speaking:
                  if (dependencies.vocabulary == null ||
                      dependencies.sourcePracticeFilePicker == null) {
                    return;
                  }
                  await _push(
                    context,
                    SourcePracticeScreen(
                      categoryId: word.categoryId,
                      categoryName: 'เลือกชุดคำเพื่อฝึกออกเสียง',
                      vocabulary: dependencies.vocabulary!,
                      learning: learning,
                      filePicker: dependencies.sourcePracticeFilePicker!,
                      associativeLearning: dependencies.associativeLearning,
                      voice: dependencies.voice,
                    ),
                  );
              }
            } finally {
              _openingLadder = false;
              if (mounted) _syncProgress();
            }
          },
        ),
      );
    },
  );

  Widget _motivationEntry() => ValueListenableBuilder<int>(
    valueListenable: _nativeChanges,
    builder: (context, _, _) {
      final dependencies = _nativeDependencies;
      final runtime = dependencies?.motivation;
      final ownerId = _nativeOwnerId;
      if (dependencies == null ||
          runtime == null ||
          ownerId == null ||
          !dependencies.features.isVisible(Feature.questV2)) {
        return const SizedBox.shrink();
      }
      final generation = _nativeGeneration;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TodayMotivationPanel(
              key: ValueKey((runtime, ownerId, generation)),
              runtime: runtime,
              ownerId: ownerId,
              onOpenQuests: () => _openMotivation(
                runtime,
                dependencies,
                ownerId,
                generation,
                practice: false,
              ),
              onPractice:
                  _learning == null || !_features.isVisible(FieldFeature.quiz)
                  ? null
                  : () => _openMotivation(
                      runtime,
                      dependencies,
                      ownerId,
                      generation,
                      practice: true,
                    ),
            ),
            ContextualCompanionPanel(
              key: ValueKey(('companion', runtime, ownerId, generation)),
              runtime: runtime,
              ownerId: ownerId,
              progress: dependencies.progress,
              onOpenQuests: () => _openMotivation(
                runtime,
                dependencies,
                ownerId,
                generation,
                practice: false,
              ),
              onPractice:
                  _learning == null || !_features.isVisible(FieldFeature.quiz)
                  ? null
                  : () => _openMotivation(
                      runtime,
                      dependencies,
                      ownerId,
                      generation,
                      practice: true,
                    ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openMotivation(
    MotivationRuntime runtime,
    AppDependencies dependencies,
    String ownerId,
    int generation, {
    required bool practice,
  }) async {
    bool current() =>
        mounted &&
        generation == _nativeGeneration &&
        ownerId == _nativeOwnerId &&
        identical(dependencies, _nativeDependencies) &&
        identical(runtime, dependencies.motivation) &&
        runtime.currentOwnerId == ownerId &&
        !runtime.isRetired &&
        runtime.isForeground &&
        dependencies.features.isVisible(Feature.questV2) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_openingMotivation ||
        !current() ||
        !_nativeRouteVisible ||
        ModalRoute.isCurrentOf(context) != true ||
        !Visibility.of(context) ||
        (practice &&
            (_learning == null || !_features.isVisible(FieldFeature.quiz)))) {
      return;
    }
    _openingMotivation = true;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: practice ? 'learning/today-practice' : 'motivation/quests',
          builder: (_) => !current()
              ? const Scaffold(
                  body: Center(
                    child: Text('ข้อมูลเปลี่ยนแล้ว กรุณากลับไปหน้าเรียน'),
                  ),
                )
              : practice
              ? QuizScreen(
                  learning: _learning,
                  expectedOwnerId: ownerId,
                  ownerChanges: _nativeOwnerSource,
                )
              : QuestScreen(runtime: runtime, ownerId: ownerId),
        ),
      );
    } finally {
      _openingMotivation = false;
      if (mounted) _syncProgress();
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
