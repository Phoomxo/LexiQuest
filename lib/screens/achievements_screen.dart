import 'dart:async';

import 'package:flutter/material.dart';

import '../features/export/domain/export_contracts.dart';
import '../features/motivation/presentation/achievement_share_composer.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import '../features/rewards/data/drift_achievement_share_reader.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

typedef AchievementProgressLoader = Future<ProgressSnapshot> Function();

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({
    super.key,
    this.loader,
    this.ownerChanges,
    this.saveImage,
    this.shareImage,
    this.onExternalOperation,
  });
  final AchievementProgressLoader? loader;
  final Stream<String?>? ownerChanges;
  final AchievementImageSaver? saveImage;
  final AchievementImageSharer? shareImage;
  final ValueChanged<bool>? onExternalOperation;
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with WidgetsBindingObserver {
  ProgressHostBinding? _binding;
  AppDependencies? _dependencies;
  ModalRoute<dynamic>? _route;
  var _configured = false;
  var _foreground = true;
  var _ownsComposer = false;
  var _external = false;
  String? _previewStatus;
  bool get _visible =>
      mounted &&
      _foreground &&
      (_route?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    ModalRoute.isCurrentOf(context);
    _configure();
    _binding?.syncVisibility(ownedCover: _ownsComposer);
  }

  void _configure() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (_configured && identical(_dependencies, dependencies)) return;
    _configured = true;
    _binding?.removeListener(_changed);
    _binding?.dispose();
    _dependencies = dependencies;
    final progress = dependencies?.progress;
    _binding = ProgressHostBinding(
      progress: progress,
      loader: widget.loader,
      ownerChanges:
          widget.ownerChanges ??
          progress?.watchActiveOwnerId() ??
          Stream<String?>.multi((events) {
            events.add(widget.loader != null ? 'local-preview' : null);
          }, isBroadcast: true),
      visible: () => _visible,
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.loader, oldWidget.loader) ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges) ||
        !identical(widget.saveImage, oldWidget.saveImage) ||
        !identical(widget.shareImage, oldWidget.shareImage)) {
      _configured = false;
      _configure();
      _binding?.syncVisibility(ownedCover: _ownsComposer);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && !_external) _binding?.invalidateLaunch();
    _binding?.syncVisibility(ownedCover: _ownsComposer || _external);
  }

  Future<void> _preview(
    AchievementEvidence achievement,
    int epoch,
    ProgressHostBinding expectedBinding,
  ) async {
    final binding = _binding;
    final owner = binding?.ownerId;
    if (binding == null ||
        !identical(binding, expectedBinding) ||
        owner == null ||
        !_visible ||
        shareableAchievementTitle(achievement) == null) {
      return;
    }
    bool readCurrent() =>
        mounted &&
        identical(binding, _binding) &&
        binding.isReadCurrent(epoch) &&
        _visible;
    if (!readCurrent()) return;
    try {
      await _requireSource(owner, achievement, readCurrent);
      if (!readCurrent()) return;
    } on Object {
      if (readCurrent()) {
        setState(
          () => _previewStatus =
              'ยังสร้างการ์ดจากหลักฐานนี้ไม่ได้ ลองอ่านความสำเร็จใหม่',
        );
      }
      return;
    }
    final generation = binding.beginLaunch(epoch);
    if (generation == null) return;
    _previewStatus = null;
    bool current() =>
        mounted &&
        identical(binding, _binding) &&
        binding.isLaunchCurrent(generation, owner);
    Future<void> revalidate() async {
      if (!current()) throw const ExportException(ExportFailureCode.cancelled);
      await _requireSource(owner, achievement, current);
      final snapshot = widget.loader != null
          ? await widget.loader!()
          : await _dependencies!.progress!.loadForOwner(
              expectedOwnerId: owner,
              stillCurrent: current,
            );
      if (!current() ||
          !snapshot.achievements.any(
            (row) =>
                row.id == achievement.id &&
                row.definitionVersion == achievement.definitionVersion &&
                row.sourceEventId == achievement.sourceEventId &&
                row.unlockedAtUtc == achievement.unlockedAtUtc &&
                shareableAchievementTitle(row) != null,
          )) {
        throw const ExportException(ExportFailureCode.cancelled);
      }
      await _requireSource(owner, achievement, current);
    }

    if (!mounted || !current()) return;
    _ownsComposer = true;
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: '/progress/achievement-card',
          builder: (_) => AchievementShareComposer(
            achievement: achievement,
            stillCurrent: current,
            revalidate: revalidate,
            scopeChanges: binding,
            onExternalOperation: (value) {
              if (mounted) {
                _external = value;
                widget.onExternalOperation?.call(value);
              }
            },
            saveImage: widget.saveImage,
            shareImage: widget.shareImage,
          ),
        ),
      );
    } finally {
      _ownsComposer = false;
      _external = false;
      widget.onExternalOperation?.call(false);
      if (mounted && identical(binding, _binding)) {
        binding.syncVisibility(ownedCover: false);
      }
    }
  }

  Future<void> _requireSource(
    String owner,
    AchievementEvidence evidence,
    bool Function() current,
  ) async {
    final database = _dependencies?.database;
    if (database == null && widget.loader != null) return;
    final runtime = _dependencies?.motivation;
    if (database == null ||
        runtime == null ||
        !identical(database, runtime.database)) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    await DriftAchievementShareReader(
      database,
      runtime.ownerWrites,
    ).requireEvidence(
      ownerId: owner,
      achievement: evidence,
      stillCurrent: current,
    );
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding;
    final progress = binding?.snapshot;
    final epoch = binding?.readEpoch;
    return Scaffold(
      appBar: AppBar(title: const Text('ความสำเร็จ')),
      body: AdaptiveContentPane(
        child:
            binding?.readFailed == true ||
                (binding?.ownerObserved == true && binding?.ownerId == null)
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: binding?.refresh,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              )
            : progress == null
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านประวัติความสำเร็จ',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_previewStatus != null)
                    Semantics(
                      key: const ValueKey('achievement-preview-status'),
                      liveRegion: true,
                      child: Text(_previewStatus!),
                    ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.toll_outlined),
                      title: const Text('คะแนนประสบการณ์'),
                      trailing: Text('${progress.totalXp}'),
                      subtitle: Text(
                        'คำนวณจาก ${progress.sampleSize} คำตอบที่บันทึกไว้',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (progress.achievements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'ยังไม่มีความสำเร็จที่ปลดล็อก\nยังไม่มีคำตอบที่บันทึกไว้',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final achievement in progress.achievements)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.workspace_premium_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _title(achievement.id),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('ปลดล็อกจากคำตอบที่บันทึกไว้'),
                              Text(
                                achievementCardDate(achievement.unlockedAtUtc),
                              ),
                              if (shareableAchievementTitle(achievement) !=
                                  null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    key: ValueKey(
                                      'achievement-preview-${achievement.id}',
                                    ),
                                    onPressed: () => unawaited(
                                      _preview(achievement, epoch!, binding!),
                                    ),
                                    icon: const Icon(Icons.image_outlined),
                                    label: const Text('สร้างการ์ดส่วนตัว'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }

  String _title(String id) => switch (id) {
    'first_answer' => 'บันทึกคำตอบครั้งแรก',
    'first_correct' => 'ตอบถูกครั้งแรก',
    'ten_correct' => 'ตอบถูกครบ 10 ครั้ง',
    'first_session' => 'เรียนจบรอบแรก',
    'perfect_session' => 'ตอบถูกครบทั้งรอบ',
    _ => 'ความสำเร็จจากการเรียน',
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _binding?.removeListener(_changed);
    _binding?.dispose();
    super.dispose();
  }
}
