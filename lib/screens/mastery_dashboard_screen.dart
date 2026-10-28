import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'achievements_screen.dart';
import 'learning_history_screen.dart';
import 'shop_page.dart';
import 'weakness_clinic_screen.dart';

typedef ProgressLoader = Future<ProgressSnapshot> Function();

class MasteryDashboardScreen extends StatefulWidget {
  const MasteryDashboardScreen({
    super.key,
    this.loader,
    this.featureRegistry,
    this.onOpenMenu,
  });

  final ProgressLoader? loader;
  final FieldFeatureRegistry? featureRegistry;
  final VoidCallback? onOpenMenu;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen> {
  Future<ProgressSnapshot>? _load;
  ProgressLoader? _loader;

  ProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

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
    if (oldWidget.loader != widget.loader) {
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

  @override
  Widget build(BuildContext context) {
    final features =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
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
                  if (progress.sampleSize == 0) {
                    return const _DashboardMessage(
                      'ยังไม่มีคำตอบที่บันทึกไว้\nคำนวณจาก 0 คำตอบ',
                    );
                  }
                  return _DashboardBody(progress);
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
          OutlinedButton.icon(
            onPressed: () => _push(
              context,
              'progress/history',
              const LearningHistoryScreen(),
            ),
            icon: const Icon(Icons.history),
            label: const Text('ประวัติการเรียน'),
          ),
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
  const _DashboardBody(this.progress);

  final ProgressSnapshot progress;

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
