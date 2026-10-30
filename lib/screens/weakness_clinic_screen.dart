import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'mastery_dashboard_screen.dart';
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
  Future<ProgressSnapshot>? _load;
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _owners;
  String? _ownerId;
  int _generation = 0;
  int _ownerBinding = 0;
  bool _bound = false;
  bool _redrawScheduled = false;
  bool _openingReview = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_owners?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _generation++;
  }

  void _bindOwners({bool force = false}) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!force && _bound && identical(_dependencies, dependencies)) return;
    _bound = true;
    _generation++;
    _ownerId = null;
    _dependencies = dependencies;
    unawaited(_owners?.cancel());
    final binding = ++_ownerBinding;
    final source =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    void changed(String? owner) {
      if (!mounted ||
          !identical(_dependencies, dependencies) ||
          binding != _ownerBinding) {
        return;
      }
      _generation++;
      _ownerId = owner;
      if (_redrawScheduled) return;
      _redrawScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redrawScheduled = false;
        if (mounted) setState(() {});
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    _owners = source?.listen(
      changed,
      onError: (Object _, StackTrace _) => changed(null),
      onDone: () => changed(null),
    );
  }

  @override
  void didUpdateWidget(covariant WeaknessClinicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _bindOwners(force: true);
    }
    if (!identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _generation++;
    }
  }

  ProgressLoader? get _loader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _loader;
    return loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : Future<ProgressSnapshot>.sync(loader);
  }

  void _retry() {
    if (!mounted) return;
    final next = _loadProgress();
    setState(() {
      _load = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (_visible && !visible && !_openingReview) _generation++;
    _visible = visible;
    _bindOwners();
    if (_load != null) return;
    _load = _loadProgress();
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
        child: FutureBuilder<ProgressSnapshot>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _WeaknessMessage(
                'อ่านข้อมูลจุดอ่อนไม่สำเร็จ',
                liveRegion: true,
                onRetry: _retry,
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังวิเคราะห์คำที่ควรฝึก',
                ),
              );
            }
            final progress = snapshot.data!;
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
              learning: widget.learning,
              canQuiz: features.isVisible(FieldFeature.quiz),
              canReview: features.isVisible(FieldFeature.srs),
              onReview: _reviewAction(features),
              onReturn: () {
                if (!mounted) return;
                _retry();
              },
            );
          },
        ),
      ),
    );
  }

  VoidCallback? _reviewAction(FieldFeatureRegistry features) {
    final generation = _generation;
    final ownerId = _ownerId;
    final dependencies = _dependencies;
    final learning = widget.learning ?? dependencies?.learning;
    if (ownerId == null || learning == null) return null;
    bool current() =>
        mounted &&
        generation == _generation &&
        ownerId == _ownerId &&
        identical(dependencies, _dependencies) &&
        identical(learning, widget.learning ?? _dependencies?.learning) &&
        features.isVisible(FieldFeature.srs) &&
        Visibility.of(context) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    return () async {
      if (_openingReview ||
          !current() ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (owners == null) return;
      _openingReview = true;
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'learning/weakness-srs',
            builder: (_) => current()
                ? SrsFlashcardsScreen(
                    expectedOwnerId: ownerId,
                    ownerChanges: owners,
                    learning: learning,
                    voice: dependencies?.voice,
                  )
                : const Scaffold(
                    body: Center(child: Text('การทบทวนไม่พร้อมใช้งาน')),
                  ),
          ),
        );
      } finally {
        _openingReview = false;
        if (mounted) _retry();
      }
    };
  }
}

class _WeaknessBody extends StatelessWidget {
  const _WeaknessBody(
    this.progress, {
    this.learning,
    required this.canQuiz,
    required this.canReview,
    required this.onReturn,
    required this.onReview,
  });

  final ProgressSnapshot progress;
  final LearningUseCases? learning;
  final bool canQuiz;
  final bool canReview;
  final VoidCallback onReturn;
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
                  onPressed: () async {
                    await AppNavigator.pushPage<void>(
                      context,
                      AppPage<void>(
                        name: 'learning/weakness-practice',
                        builder: (_) => QuizScreen(
                          wordIds: practiceWords
                              .map((item) => item.wordId)
                              .toList(),
                          learning: learning,
                        ),
                      ),
                    );
                    onReturn();
                  },
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
