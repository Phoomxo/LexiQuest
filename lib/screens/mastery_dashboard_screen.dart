import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'achievements_screen.dart';
import 'shop_page.dart';
import 'weakness_clinic_screen.dart';
import 'quiz_screen.dart';
import 'score_screen.dart';

typedef ProgressLoader = Future<ProgressSnapshot> Function();

class MasteryDashboardScreen extends StatefulWidget {
  const MasteryDashboardScreen({
    super.key,
    this.loader,
    this.featureRegistry,
    this.onOpenMenu,
    this.isActive = true,
  });

  final ProgressLoader? loader;
  final FieldFeatureRegistry? featureRegistry;
  final VoidCallback? onOpenMenu;
  final bool isActive;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen> {
  Future<ProgressSnapshot>? _load;
  ProgressLoader? _loader;
  String? _openingSessionId;
  bool _practicingHistory = false;

  ProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load == null || _currentLoader != _loader) {
      _load = _loadProgress();
    }
  }

  @override
  void didUpdateWidget(MasteryDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        (!oldWidget.isActive && widget.isActive)) {
      _load = _loadProgress();
    }
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _loader = _currentLoader;
    final next = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : Future<ProgressSnapshot>.sync(loader);
    // Route teardown can delay FutureBuilder's subscription until the next frame.
    next.ignore();
    return next;
  }

  void _refresh() {
    if (!mounted) return;
    final next = _loadProgress();
    setState(() {
      _load = next;
    });
  }

  Future<void> _openSession(String sessionId) async {
    if (_openingSessionId != null) return;
    final progress = AppDependenciesScope.maybeOf(context)?.progress;
    setState(() => _openingSessionId = sessionId);
    try {
      if (progress == null) throw StateError('progress unavailable');
      final entry = await progress.loadSession(sessionId);
      if (!mounted) return;
      if (entry == null ||
          progress != AppDependenciesScope.maybeOf(context)?.progress) {
        throw StateError('saved session unavailable');
      }
      final learning = AppDependenciesScope.maybeOf(context)?.learning;
      final features = _features;
      final canRepair =
          features.isVisible(FieldFeature.weakness) &&
          features.isVisible(FieldFeature.quiz);
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'progress/session/$sessionId',
          builder: (scoreContext) => ScoreScreen(
            correctAnswers: entry.summary.correctCount,
            wrongAnswers: entry.summary.wrongCount,
            score: entry.summary.score,
            sessionId: entry.summary.id,
            categoryName: entry.categoryName,
            returnLabel: 'กลับไปดูประวัติ',
            mistakes: entry.mistakes,
            onPracticeMistakes:
                !canRepair || learning == null || entry.mistakes.isEmpty
                ? null
                : () => _practiceHistoryMistakes(scoreContext, entry),
          ),
        ),
      );
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปิดผลรอบเดิมไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingSessionId = null);
    }
  }

  Future<void> _practiceHistoryMistakes(
    BuildContext scoreContext,
    SessionHistoryEntry entry,
  ) async {
    if (_practicingHistory) return;
    _practicingHistory = true;
    try {
      final features = _features;
      if (!features.isVisible(FieldFeature.weakness) ||
          !features.isVisible(FieldFeature.quiz)) {
        throw StateError('history repair unavailable');
      }
      final learning = AppDependenciesScope.maybeOf(scoreContext)?.learning;
      if (learning == null) throw StateError('learning unavailable');
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (!scoreContext.mounted) return;
      if (owner.id != entry.ownerId) throw StateError('learning owner changed');
      await AppNavigator.pushPage<void>(
        scoreContext,
        AppPage<void>(
          name: 'progress/session/${entry.summary.id}/practice',
          builder: (_) => QuizScreen(
            wordIds: entry.mistakes.map((word) => word.id).toList(),
            categoryName: entry.categoryName,
            learning: learning,
            featureRegistry: _features,
          ),
        ),
      );
    } catch (_) {
      if (scoreContext.mounted) {
        ScaffoldMessenger.of(scoreContext).showSnackBar(
          const SnackBar(
            content: Text('เริ่มฝึกคำที่ผิดไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      _practicingHistory = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _features;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ภาพรวมการเรียน'),
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
      body: AdaptiveContentPane(
        child: Column(
          children: [
            _ProgressActions(
              loader: widget.loader,
              features: features,
              onWeaknessReturn: _refresh,
            ),
            Expanded(
              child: FutureBuilder<ProgressSnapshot>(
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'กำลังอ่านประวัติการเรียน',
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _DashboardMessage(
                      'ไม่สามารถอ่านประวัติการเรียนในเครื่องได้',
                      onRetry: _refresh,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'กำลังอ่านประวัติการเรียน',
                      ),
                    );
                  }
                  final progress = snapshot.data!;
                  if (progress.sampleSize == 0 &&
                      progress.recentSessions.isEmpty) {
                    return const _DashboardMessage(
                      'ยังไม่มีคำตอบที่บันทึกไว้\nคำนวณจาก 0 คำตอบ',
                    );
                  }
                  return _DashboardBody(
                    progress,
                    onOpenSession: _openSession,
                    openingSessionId: _openingSessionId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressActions extends StatelessWidget {
  const _ProgressActions({
    required this.loader,
    required this.features,
    required this.onWeaknessReturn,
  });

  final ProgressLoader? loader;
  final FieldFeatureRegistry features;
  final VoidCallback onWeaknessReturn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (features.isVisible(FieldFeature.weakness))
            OutlinedButton.icon(
              onPressed: () async {
                await _push(
                  context,
                  'progress/weakness',
                  WeaknessClinicScreen(
                    loader: loader,
                    featureRegistry: features,
                  ),
                );
                onWeaknessReturn();
              },
              icon: const Icon(Icons.healing_outlined),
              label: const Text('คำที่ควรฝึกเพิ่ม'),
            ),
          if (features.isVisible(FieldFeature.achievements))
            OutlinedButton.icon(
              onPressed: () => _push(
                context,
                'progress/achievements',
                AchievementsScreen(loader: loader),
              ),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('ความสำเร็จ'),
            ),
          if (features.isVisible(FieldFeature.shop))
            OutlinedButton.icon(
              onPressed: () =>
                  _push(context, 'progress/theme-store', const ShopPage()),
              icon: const Icon(Icons.palette_outlined),
              label: const Text('ร้านค้ารางวัล'),
            ),
        ],
      ),
    );
  }

  Future<void> _push(
    BuildContext context,
    String name,
    Widget destination,
  ) async {
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: (_) => destination),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody(
    this.progress, {
    required this.onOpenSession,
    required this.openingSessionId,
  });

  final ProgressSnapshot progress;
  final ValueChanged<String> onOpenSession;
  final String? openingSessionId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricCard(
              label: 'ความแม่นยำ',
              value: '${((progress.accuracy ?? 0) * 100).toStringAsFixed(0)}%',
            ),
            _MetricCard(
              label: 'เรียนต่อเนื่อง',
              value: '${progress.streakDays} วัน',
            ),
            _MetricCard(label: 'คะแนนประสบการณ์', value: '${progress.totalXp}'),
            _MetricCard(
              label: 'รอบที่เรียนจบ',
              value: '${progress.completedSessions}',
            ),
            _MetricCard(
              label: 'ถึงกำหนดทบทวน',
              value: '${progress.dueReviewCount}',
            ),
            _MetricCard(
              label: 'ระดับจากคะแนนประสบการณ์',
              value: '${progress.gameLevel}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'ทักษะจากคำตอบที่บันทึกไว้',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...progress.skills.map((skill) => _SkillRow(skill)),
        const SizedBox(height: 12),
        Text(
          'คำนวณจาก ${progress.sampleSize} คำตอบที่บันทึกไว้',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Text('ประวัติการฝึก', style: Theme.of(context).textTheme.titleLarge),
        if (progress.recentSessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('ยังไม่มีรอบฝึกที่จบแล้ว'),
          ),
        for (final entry in progress.recentSessions)
          ListTile(
            key: ValueKey('history-session:${entry.summary.id}'),
            title: Text(switch (entry.activityType) {
              'quiz' => 'เลือกความหมาย',
              'srsReview' => 'ทบทวนด้วยบัตรคำ',
              'weaknessPractice' => 'ฝึกคำที่ผิด',
              'sourcePractice' => 'ฝึกจากเนื้อหา',
              'associativeReading' => 'อ่านและนึกคำ',
              _ => 'รอบฝึก',
            }),
            subtitle: Text(
              '${entry.categoryName == null ? '' : '${entry.categoryName} · '}'
              'ถูก ${entry.summary.correctCount} จาก ${entry.summary.correctCount + entry.summary.wrongCount} ข้อ · '
              '${MaterialLocalizations.of(context).formatShortDate(entry.completedAtUtc.toLocal())} '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.completedAtUtc.toLocal()))}',
            ),
            trailing: openingSessionId == entry.summary.id
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      semanticsLabel: 'กำลังเปิดผลรอบเดิม',
                    ),
                  )
                : Text('${entry.summary.score}%'),
            onTap: openingSessionId == null
                ? () => onOpenSession(entry.summary.id)
                : null,
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow(this.skill);

  final SkillEvidence skill;

  @override
  Widget build(BuildContext context) {
    final accuracy = skill.accuracy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(skill.label)),
                Text(
                  accuracy == null
                      ? 'ยังไม่มีข้อมูล'
                      : '${(accuracy * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: accuracy ?? 0,
              semanticsLabel: accuracy == null
                  ? '${skill.label} ยังไม่มีข้อมูลความแม่นยำ'
                  : '${skill.label} แม่นยำ ${(accuracy * 100).toStringAsFixed(0)} เปอร์เซ็นต์',
            ),
            const SizedBox(height: 6),
            Text('คำนวณจาก ${skill.sampleSize} คำตอบ'),
          ],
        ),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage(this.message, {this.onRetry});

  final String message;
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
              liveRegion: true,
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
