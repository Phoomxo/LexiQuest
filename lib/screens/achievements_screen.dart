import 'package:flutter/material.dart';

import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';

typedef AchievementProgressLoader = Future<ProgressSnapshot> Function();

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, this.loader});

  final AchievementProgressLoader? loader;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  Future<ProgressSnapshot>? _load;
  var _wasActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    if (!isActive || (_wasActive && _load != null)) {
      _wasActive = isActive;
      return;
    }
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    _load = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : loader();
    _wasActive = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ความสำเร็จ')),
      body: FutureBuilder<ProgressSnapshot>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final progress = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.toll_outlined),
                  title: const Text('คะแนนสะสม'),
                  trailing: Text('${progress.totalXp}'),
                  subtitle: Text(
                    'หลักฐานคำตอบ ${progress.sampleSize} รายการ · อัลกอริทึม v${progress.algorithmVersion}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (progress.achievements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'ยังไม่มีความสำเร็จที่ปลดล็อก\nจำนวนหลักฐาน: 0',
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
                      subtitle: Text(
                        'หลักฐาน ${achievement.sourceEventId} · นิยาม v${achievement.definitionVersion}',
                      ),
                      trailing: Text(_date(achievement.unlockedAtUtc)),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  String _title(String id) => switch (id) {
    'first_answer' => 'บันทึกคำตอบครั้งแรก',
    'first_correct' => 'ตอบถูกครั้งแรก',
    'first_session' => 'เรียนจบเซสชันแรก',
    'perfect_session' => 'ตอบถูกครบทั้งเซสชัน',
    'ten_correct' => 'ตอบถูกครบ 10 ครั้ง',
    _ => id,
  };

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}
