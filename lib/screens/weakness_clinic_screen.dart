import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import '../runtime/app_dependencies.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'quiz_screen.dart';
import 'srs_flashcards_screen.dart';
import '../navigation/app_routes.dart';

class WeaknessClinicScreen extends StatefulWidget {
  const WeaknessClinicScreen({
    super.key,
    this.loader,
    this.learning,
    this.featureRegistry,
    this.ownerChanges,
  });

  final ProgressLoader? loader;
  final LearningUseCases? learning;
  final FieldFeatureRegistry? featureRegistry;
  final Stream<String?>? ownerChanges;

  @override
  State<WeaknessClinicScreen> createState() => _WeaknessClinicScreenState();
}

class _WeaknessClinicScreenState extends State<WeaknessClinicScreen>
    with WidgetsBindingObserver {
  ProgressHostBinding? _binding;
  AppDependencies? _dependencies;
  Stream<String?>? _ownerChanges;
  bool _opening = false;
  bool _foreignCover = false;
  Route<dynamic>? _scoreRoute;
  Route<dynamic>? _quizRoute;

  bool get _visible =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _binding?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _binding?.invalidateLaunch();
    _syncVisibility();
  }

  void _bind({bool force = false}) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!force && _binding != null && identical(_dependencies, dependencies)) {
      return;
    }
    _binding?.dispose();
    _dependencies = dependencies;
    _ownerChanges =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    _binding = ProgressHostBinding(
      progress: dependencies?.progress,
      loader: widget.loader,
      ownerChanges: _ownerChanges,
      visible: () => _visible,
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _syncVisibility() => _binding?.syncVisibility(
    ownedCover:
        _opening &&
        !_foreignCover &&
        Visibility.of(context) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
  );

  @override
  void didUpdateWidget(covariant WeaknessClinicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        !identical(oldWidget.loader, widget.loader) ||
        !identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _bind(force: true);
    }
    _syncVisibility();
  }

  VoidCallback? _retryAction() {
    final binding = _binding;
    if (binding?.ownerId == null) return null;
    final epoch = binding!.readEpoch;
    return () {
      if (identical(binding, _binding) && binding.isReadCurrent(epoch)) {
        binding.refresh();
      }
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    Visibility.of(context);
    _bind();
    _syncVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final features =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ฝึกจุดอ่อน'),
      ),
      body: AdaptiveContentPane(
        child: Builder(
          builder: (context) {
            final binding = _binding;
            if (binding == null ||
                binding.readFailed ||
                binding.ownerChanges == null ||
                (binding.ownerObserved && binding.ownerId == null)) {
              return _WeaknessMessage(
                'อ่านข้อมูลจุดอ่อนไม่สำเร็จ',
                liveRegion: true,
                onRetry: _retryAction(),
              );
            }
            if (!binding.ownerObserved ||
                binding.loading ||
                binding.snapshot == null) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังวิเคราะห์คำที่ควรฝึก',
                ),
              );
            }
            final progress = binding.snapshot!;
            if (progress.sampleSize == 0) {
              return const _WeaknessMessage(
                'ยังไม่มีคำตอบสำหรับวิเคราะห์\nคำนวณจาก 0 คำตอบ',
              );
            }
            if (progress.weaknesses.isEmpty) {
              return _WeaknessMessage(
                'ยังไม่พบคำที่ตอบผิด\nคำนวณจาก ${progress.sampleSize} คำตอบ',
              );
            }
            return _WeaknessBody(
              progress,
              canQuiz: features.isVisible(FieldFeature.quiz),
              canReview: features.isVisible(FieldFeature.srs),
              onReview: _practiceAction(progress, features, review: true),
              onPractice: _practiceAction(progress, features, review: false),
            );
          },
        ),
      ),
    );
  }

  VoidCallback? _practiceAction(
    ProgressSnapshot progress,
    FieldFeatureRegistry features, {
    required bool review,
  }) {
    final binding = _binding;
    final owner = binding?.ownerId;
    final dependencies = _dependencies;
    final learning = widget.learning ?? dependencies?.learning;
    final owners = _ownerChanges;
    if (binding == null ||
        owner == null ||
        learning == null ||
        owners == null ||
        (review && !features.isVisible(FieldFeature.srs)) ||
        (!review && !features.isVisible(FieldFeature.quiz))) {
      return null;
    }
    final epoch = binding.readEpoch;
    final ids = List<String>.unmodifiable(
      progress.weaknesses.take(20).map((item) => item.wordId),
    );
    return () async {
      if (_opening || !binding.isReadCurrent(epoch)) return;
      final launch = binding.beginLaunch(epoch);
      if (launch == null) return;
      bool current() =>
          mounted &&
          identical(binding, _binding) &&
          binding.isLaunchCurrent(launch, owner) &&
          identical(dependencies, _dependencies) &&
          identical(learning, widget.learning ?? _dependencies?.learning) &&
          Visibility.of(context) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      void foreignCover() {
        if (_foreignCover) return;
        _foreignCover = true;
        binding.invalidateLaunch();
      }

      void scoreChanged(Route<dynamic>? route, bool current) {
        _scoreRoute = route;
        if (route != null &&
            route.isActive &&
            !current &&
            _quizRoute?.isCurrent != true) {
          foreignCover();
        }
      }

      _opening = true;
      _foreignCover = false;
      _scoreRoute = null;
      _quizRoute = null;
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: review
                ? 'learning/weakness-srs'
                : 'learning/weakness-practice',
            builder: (_) => Builder(
              builder: (childContext) {
                final childCurrent =
                    ModalRoute.isCurrentOf(childContext) == true;
                if (ModalRoute.of(childContext)?.isActive == true &&
                    !childCurrent &&
                    _scoreRoute?.isCurrent != true &&
                    ModalRoute.of(context)?.isCurrent != true) {
                  foreignCover();
                }
                if (!current()) {
                  return const Scaffold(body: SizedBox.shrink());
                }
                return review
                    ? SrsFlashcardsScreen(
                        expectedOwnerId: owner,
                        ownerChanges: owners,
                        learning: learning,
                        voice: dependencies?.voice,
                      )
                    : QuizScreen(
                        wordIds: ids,
                        selectionMode: QuizWordSelectionMode.weakness,
                        expectedOwnerId: owner,
                        ownerChanges: owners,
                        learning: learning,
                        onScoreRouteChanged: scoreChanged,
                      );
              },
            ),
          ),
          onRouteCreated: (route) => _quizRoute = route,
        );
      } finally {
        _opening = false;
        _scoreRoute = null;
        _quizRoute = null;
        if (current() && _visible) _syncVisibility();
      }
    };
  }
}

class _WeaknessBody extends StatelessWidget {
  const _WeaknessBody(
    this.progress, {
    required this.canQuiz,
    required this.canReview,
    required this.onPractice,
    required this.onReview,
  });

  final ProgressSnapshot progress;
  final bool canQuiz;
  final bool canReview;
  final VoidCallback? onPractice;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final practiceWords = progress.weaknesses.take(20).toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'จัดอันดับจากสัดส่วนคำตอบผิด จาก '
            '${progress.sampleSize} คำตอบที่บันทึกไว้',
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: progress.weaknesses.length,
            itemBuilder: (context, index) {
              final item = progress.weaknesses[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(item.spelling),
                  subtitle: Text(
                    '${item.meaning}\nตอบผิด ${item.incorrectCount}/${item.sampleSize} ครั้ง '
                    '(${(item.errorRate * 100).toStringAsFixed(0)}%)',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canQuiz)
                FilledButton.icon(
                  onPressed: onPractice,
                  icon: const Icon(Icons.healing_outlined),
                  label: Text('ฝึกคำที่ผิด (${practiceWords.length})'),
                ),
              if (canQuiz && canReview) const SizedBox(height: 8),
              if (canReview)
                OutlinedButton.icon(
                  onPressed: progress.dueReviewCount == 0 ? null : onReview,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.event_repeat),
                  label: Text(
                    progress.dueReviewCount == 0
                        ? 'ยังไม่มีคำที่ถึงกำหนดทบทวน'
                        : 'ทบทวนคำที่ถึงกำหนด (${progress.dueReviewCount})',
                  ),
                ),
              if (!canQuiz && !canReview)
                const Text(
                  'เปิดแบบฝึกที่รองรับจากหน้าเรียน',
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeaknessMessage extends StatelessWidget {
  const _WeaknessMessage(this.message, {this.liveRegion = false, this.onRetry});

  final String message;
  final bool liveRegion;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: liveRegion,
              child: Text(message, textAlign: TextAlign.center),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
            ],
          ],
        ),
      ),
    );
  }
}
