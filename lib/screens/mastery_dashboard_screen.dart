import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'achievements_screen.dart';
import 'learning_history_screen.dart';
import 'review_center_screen.dart';
import 'shop_page.dart';
import 'weakness_clinic_screen.dart';

export '../features/progress/presentation/progress_host_binding.dart'
    show ProgressLoader;

class MasteryDashboardScreen extends StatefulWidget {
  const MasteryDashboardScreen({
    super.key,
    this.loader,
    this.featureRegistry,
    this.onOpenMenu,
    this.ownerChanges,
  });

  final ProgressLoader? loader;
  final FieldFeatureRegistry? featureRegistry;
  final VoidCallback? onOpenMenu;
  final Stream<String?>? ownerChanges;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  ProgressLoader? _loader;
  Stream<String?>? _ownerSource;
  Stream<String?>? _owners;
  ProgressHostBinding? _binding;
  ModalRoute<dynamic>? _route;
  Object? _childToken;
  ProgressHostBinding? _childBinding;
  String? _childOwner;
  int? _childGeneration;
  bool _childCovered = false;
  bool _bound = false;
  bool _paneVisible = false;
  bool _foreground = false;

  bool get _visible =>
      mounted && _foreground && _paneVisible && _route?.isCurrent == true;

  FieldFeatureRegistry get _features =>
      widget.featureRegistry ??
      _dependencies?.fieldFeatures ??
      const BuildFieldFeatureRegistry.allEnabled();

  bool get _ownsCover {
    final binding = _childBinding;
    final owner = _childOwner;
    final generation = _childGeneration;
    return _childToken != null &&
        !_childCovered &&
        _foreground &&
        _paneVisible &&
        binding != null &&
        identical(binding, _binding) &&
        owner != null &&
        generation != null &&
        binding.isLaunchCurrent(generation, owner);
  }

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _bind() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_bound &&
        identical(_dependencies, dependencies) &&
        identical(_loader, widget.loader) &&
        identical(_ownerSource, widget.ownerChanges)) {
      return;
    }
    _bound = true;
    _childCovered = true;
    final old = _binding;
    old?.removeListener(_changed);
    old?.dispose();
    _dependencies = dependencies;
    _loader = widget.loader;
    _ownerSource = widget.ownerChanges;
    _owners =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    _binding = ProgressHostBinding(
      progress: dependencies?.progress,
      loader: widget.loader,
      ownerChanges: _owners,
      visible: () => _visible,
    )..addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != null && !identical(_route, route)) {
      _binding?.invalidateLaunch();
    }
    _route = route;
    ModalRoute.isCurrentOf(context);
    _paneVisible = Visibility.of(context);
    _bind();
    _binding?.syncVisibility(ownedCover: _ownsCover);
  }

  @override
  void didUpdateWidget(covariant MasteryDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
    if (!identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      _binding?.invalidateLaunch();
    }
    _binding?.syncVisibility(ownedCover: _ownsCover);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _childCovered = true;
      _binding?.invalidateLaunch();
    }
    _binding?.syncVisibility(ownedCover: _ownsCover);
  }

  void _coveredChild(Object token, ProgressHostBinding binding) {
    if (!mounted ||
        !identical(_childToken, token) ||
        !identical(binding, _binding) ||
        _childCovered ||
        _route?.isCurrent == true) {
      return;
    }
    _childCovered = true;
    binding.invalidateLaunch();
  }

  VoidCallback? _action(
    String routeName,
    Widget Function(
      String owner,
      Stream<String?> owners,
      bool Function() current,
    )
    destination, {
    FieldFeature? feature,
  }) {
    final binding = _binding;
    final owner = binding?.ownerId;
    final owners = _owners;
    if (binding == null || owner == null || owners == null) {
      return null;
    }
    final epoch = binding.readEpoch;
    final dependencies = _dependencies;
    return () async {
      if (_childToken != null ||
          !identical(binding, _binding) ||
          !identical(dependencies, _dependencies) ||
          !binding.isReadCurrent(epoch) ||
          (feature != null && !_features.isVisible(feature))) {
        return;
      }
      final generation = binding.beginLaunch(epoch, requireSnapshot: false);
      if (generation == null) {
        return;
      }
      bool current() =>
          mounted &&
          identical(binding, _binding) &&
          identical(dependencies, _dependencies) &&
          binding.isLaunchCurrent(generation, owner) &&
          _foreground &&
          _paneVisible;
      final token = Object();
      _childToken = token;
      _childBinding = binding;
      _childOwner = owner;
      _childGeneration = generation;
      _childCovered = false;
      try {
        await AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: routeName,
            builder: (_) {
              if (!mounted ||
                  !identical(binding, _binding) ||
                  !identical(dependencies, _dependencies) ||
                  !binding.isLaunchCurrent(generation, owner) ||
                  !_foreground ||
                  !_paneVisible) {
                return const Scaffold(
                  body: _DashboardMessage('กิจกรรมไม่พร้อมใช้งาน'),
                );
              }
              return _MasteryChildVisibility(
                onCovered: () => _coveredChild(token, binding),
                child: destination(owner, owners, current),
              );
            },
          ),
        );
      } finally {
        if (mounted && identical(_childToken, token)) {
          _childToken = null;
          _childBinding = null;
          _childOwner = null;
          _childGeneration = null;
          if (identical(binding, _binding)) {
            binding.syncVisibility(ownedCover: false);
          }
        }
      }
    };
  }

  @override
  void dispose() {
    final binding = _binding;
    _binding = null;
    binding?.removeListener(_changed);
    binding?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('review-center-entry'),
                    onPressed: _action(
                      'learning/review-center',
                      (owner, owners, _) => ReviewCenterScreen(
                        expectedOwnerId: owner,
                        ownerChanges: owners,
                        reviewCenter: _dependencies?.reviewCenter,
                        learning: _dependencies?.learning,
                        savedWords: _dependencies?.savedWords,
                        wordReports: _dependencies?.wordReports,
                        voice: _dependencies?.voice,
                        featureRegistry: features,
                        languageCode: Localizations.localeOf(
                          context,
                        ).languageCode,
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('ศูนย์ทบทวน'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _action(
                      'progress/history',
                      (owner, owners, current) => LearningHistoryScreen(
                        ownerChanges: owners,
                        loader: ({before}) {
                          final progress = _dependencies?.progress;
                          if (progress == null) {
                            throw StateError('history dependency unavailable');
                          }
                          return progress.loadHistoryForOwner(
                            expectedOwnerId: owner,
                            stillCurrent: current,
                            before: before,
                          );
                        },
                      ),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('ประวัติการเรียน'),
                  ),
                  if (features.isVisible(FieldFeature.weakness))
                    OutlinedButton.icon(
                      onPressed: _action(
                        'progress/weakness',
                        (_, owners, _) => WeaknessClinicScreen(
                          loader: widget.loader,
                          learning: _dependencies?.learning,
                          ownerChanges: owners,
                          featureRegistry: features,
                        ),
                        feature: FieldFeature.weakness,
                      ),
                      icon: const Icon(Icons.healing_outlined),
                      label: const Text('คำที่ควรฝึกเพิ่ม'),
                    ),
                  if (features.isVisible(FieldFeature.achievements))
                    OutlinedButton.icon(
                      onPressed: _action(
                        'progress/achievements',
                        (_, _, _) => AchievementsScreen(loader: widget.loader),
                        feature: FieldFeature.achievements,
                      ),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('ความสำเร็จ'),
                    ),
                  if (features.isVisible(FieldFeature.shop))
                    OutlinedButton.icon(
                      onPressed: _action(
                        'progress/theme-store',
                        (_, _, _) => const ShopPage(),
                        feature: FieldFeature.shop,
                      ),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('ร้านค้ารางวัล'),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final binding = _binding;
    if (binding == null ||
        !_visible ||
        binding.ownerChanges == null ||
        (binding.ownerObserved && binding.ownerId == null)) {
      return const _DashboardMessage('บัญชีไม่พร้อมใช้งานสำหรับอ่านประวัติ');
    }
    if (binding.readFailed) {
      final epoch = binding.readEpoch;
      return _DashboardMessage(
        'ไม่สามารถอ่านประวัติการเรียนในเครื่องได้',
        onRetry: () {
          if (identical(binding, _binding) && binding.isReadCurrent(epoch)) {
            binding.refresh();
          }
        },
      );
    }
    final progress = binding.snapshot;
    if (progress == null) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'กำลังอ่านประวัติการเรียน',
        ),
      );
    }
    if (progress.sampleSize == 0) {
      return const _DashboardMessage(
        'ยังไม่มีคำตอบที่บันทึกไว้\nคำนวณจาก 0 คำตอบ',
      );
    }
    return _DashboardBody(progress);
  }
}

class _MasteryChildVisibility extends StatefulWidget {
  const _MasteryChildVisibility({required this.onCovered, required this.child});

  final VoidCallback onCovered;
  final Widget child;

  @override
  State<_MasteryChildVisibility> createState() =>
      _MasteryChildVisibilityState();
}

class _MasteryChildVisibilityState extends State<_MasteryChildVisibility> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context);
    if (current == false && ModalRoute.of(context)?.isActive == true) {
      widget.onCovered();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
