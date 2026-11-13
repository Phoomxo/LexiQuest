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
  });

  final ProgressLoader? loader;
  final LearningUseCases? learning;
  final FieldFeatureRegistry? featureRegistry;

  @override
  State<WeaknessClinicScreen> createState() => _WeaknessClinicScreenState();
}

class _WeaknessClinicScreenState extends State<WeaknessClinicScreen> {
  Future<ProgressSnapshot>? _load;
  AppDependencies? _dependencies;
  ProgressLoader? _resolvedLoader;
  LearningUseCases? _learning;
  bool _hadScope = false;
  int _generation = 0;

  ProgressLoader? get _loader {
    final dependencies = AppDependenciesScope.maybeOf(context);
    return dependencies == null
        ? (_hadScope ? null : widget.loader)
        : dependencies.progress?.load;
  }

  LearningUseCases? get _currentLearning {
    final dependencies = AppDependenciesScope.maybeOf(context);
    return dependencies == null
        ? (_hadScope ? null : widget.learning)
        : dependencies.learning;
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _resolvedLoader;
    final next = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : Future<ProgressSnapshot>.sync(loader);
    next.ignore();
    return next;
  }

  void _retry() {
    if (!mounted) return;
    final next = _loadProgress();
    setState(() {
      _generation++;
      _load = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindSources();
  }

  @override
  void didUpdateWidget(covariant WeaknessClinicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindSources();
  }

  void _bindSources() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (dependencies != null) _hadScope = true;
    final loader = _loader;
    final learning = _currentLearning;
    if (_load != null &&
        identical(dependencies, _dependencies) &&
        loader == _resolvedLoader &&
        identical(learning, _learning)) {
      return;
    }
    _dependencies = dependencies;
    _resolvedLoader = loader;
    _learning = learning;
    _generation++;
    _load = _loadProgress();
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      identical(AppDependenciesScope.maybeOf(context), _dependencies) &&
      _loader == _resolvedLoader &&
      identical(_currentLearning, _learning);

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
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
          key: ValueKey(_generation),
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
              learning: _learning,
              features: features,
              isCurrent: () => _current(generation),
              onReturn: () {
                if (!_current(generation)) return;
                _retry();
              },
            );
          },
        ),
      ),
    );
  }
}

class _WeaknessBody extends StatelessWidget {
  const _WeaknessBody(
    this.progress, {
    this.learning,
    required this.features,
    required this.isCurrent,
    required this.onReturn,
  });

  final ProgressSnapshot progress;
  final LearningUseCases? learning;
  final FieldFeatureRegistry features;
  final bool Function() isCurrent;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final practiceWords = progress.weaknesses.take(20).toList(growable: false);
    final canQuiz = features.isVisible(FieldFeature.quiz);
    final canReview = features.isVisible(FieldFeature.srs);
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
                    if (!isCurrent()) return;
                    await AppNavigator.pushPage<void>(
                      context,
                      AppPage<void>(
                        name: 'learning/weakness-practice',
                        builder: (_) => QuizScreen(
                          wordIds: practiceWords
                              .map((item) => item.wordId)
                              .toList(),
                          learning: learning,
                          featureRegistry: features,
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
                  onPressed: progress.dueReviewCount == 0
                      ? null
                      : () async {
                          if (!isCurrent()) return;
                          await AppNavigator.pushPage<void>(
                            context,
                            AppPage<void>(
                              name: 'learning/weakness-srs',
                              builder: (_) =>
                                  SrsFlashcardsScreen(learning: learning),
                            ),
                          );
                          onReturn();
                        },
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
