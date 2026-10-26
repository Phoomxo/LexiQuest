import 'package:flutter/material.dart';

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

  AchievementProgressLoader? get _loader =>
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
    if (_load != null) return;
    _load = _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ความสำเร็จ')),
      body: AdaptiveContentPane(
        child: FutureBuilder<ProgressSnapshot>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
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
                      onPressed: _retry,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                      child: ListTile(
                        leading: const Icon(Icons.workspace_premium_outlined),
                        title: Text(_title(achievement.id)),
                        subtitle: Text('ปลดล็อกจากคำตอบที่บันทึกไว้'),
                        trailing: Text(_date(achievement.unlockedAtUtc)),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _title(String id) => switch (id) {
    'first_answer' => 'บันทึกคำตอบครั้งแรก',
    'first_session' => 'เรียนจบรอบแรก',
    'perfect_session' => 'ตอบถูกครบทั้งรอบ',
    _ => 'ความสำเร็จจากการเรียน',
  };

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}
