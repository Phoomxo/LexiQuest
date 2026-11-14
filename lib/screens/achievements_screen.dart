import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

typedef AchievementProgressLoader = Future<ProgressSnapshot> Function();

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, this.loader});

  final AchievementProgressLoader? loader;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  Future<ProgressSnapshot>? _load;
  AchievementProgressLoader? _loader;
  AppDependencies? _dependencies;
  ValueListenable<int>? _progressUpdates;
  int _generation = 0;

  AchievementProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _loader = _currentLoader;
    final dependencies = _dependencies;
    final generation = ++_generation;
    bool current() =>
        mounted &&
        generation == _generation &&
        identical(dependencies, _dependencies);
    final next = Future<ProgressSnapshot>.sync(() async {
      if (loader == null) {
        throw StateError('progress dependency unavailable');
      }
      final progress = await loader();
      if (!current()) throw StateError('achievement context changed');
      final owners =
          dependencies?.localOwners ?? dependencies?.progress?.owners;
      if (owners != null && progress.ownerId != null) {
        final owner = await owners.getOrCreateActiveOwner();
        if (!current() || owner.id != progress.ownerId) {
          throw StateError('achievement owner changed');
        }
      }
      return progress;
    });
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final updates = dependencies?.progressUpdates;
    final scopeChanged = !identical(dependencies, _dependencies);
    final updatesChanged = !identical(updates, _progressUpdates);
    if (updatesChanged) {
      _progressUpdates?.removeListener(_refresh);
      _progressUpdates = updates;
      updates?.addListener(_refresh);
    }
    _dependencies = dependencies;
    if (_load == null ||
        scopeChanged ||
        updatesChanged ||
        _currentLoader != _loader) {
      _load = _loadProgress();
    }
  }

  @override
  void didUpdateWidget(AchievementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loader != oldWidget.loader) {
      _load = _loadProgress();
    }
  }

  @override
  void dispose() {
    _generation++;
    _progressUpdates?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ความสำเร็จ'),
      ),
      body: AdaptiveContentPane(
        child: FutureBuilder<ProgressSnapshot>(
          key: ValueKey(_generation),
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านประวัติความสำเร็จ',
                ),
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านประวัติความสำเร็จ',
                ),
              );
            }
            final progress = snapshot.data!;
            final unlocked = {
              for (final achievement in progress.achievements)
                if (achievement.definitionVersion == 1) achievement.id,
            };
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.toll_outlined),
                    title: const Text('คะแนนประสบการณ์'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${progress.totalXp}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const Text('รวม XP จากคำตอบและภารกิจที่บันทึกไว้'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (progress.achievements.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        progress.sampleSize == 0
                            ? 'ยังไม่มีความสำเร็จที่ปลดล็อก\nยังไม่มีคำตอบที่บันทึกไว้'
                            : 'ยังไม่มีความสำเร็จที่ปลดล็อก',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final achievement in progress.achievements)
                  _earned(achievement),
                if (achievementV1Metadata.keys.any(
                  (key) => !unlocked.contains(key),
                )) ...[
                  const SizedBox(height: 16),
                  Text(
                    'เงื่อนไขที่ยังไม่ปลดล็อก',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final entry in achievementV1Metadata.entries)
                    if (!unlocked.contains(entry.key))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(entry.value.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ยังไม่ปลดล็อก'),
                              Text(entry.value.condition),
                            ],
                          ),
                        ),
                      ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _earned(AchievementEvidence achievement) {
    final metadata = achievement.definitionVersion == 1
        ? achievementV1Metadata[achievement.id]
        : null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: Text(metadata?.title ?? 'ความสำเร็จจากการเรียน'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metadata != null) const Text('เงื่อนไขปัจจุบัน'),
            if (metadata != null) Text(metadata.condition),
            const Text('ปลดล็อกเมื่อ'),
            Text(_date(achievement.unlockedAtUtc.toUtc())),
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}
