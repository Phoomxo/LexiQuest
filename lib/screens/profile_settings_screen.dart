import 'package:flutter/material.dart';

import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';

typedef ProfileProgressLoader = Future<ProgressSnapshot> Function();

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key, this.loader});

  final ProfileProgressLoader? loader;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
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
    final account = AppDependenciesScope.maybeOf(
      context,
    )?.account?.currentSession;
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: FutureBuilder<ProgressSnapshot>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('ไม่สามารถอ่านข้อมูลในเครื่องได้'));
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
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(account?.email ?? 'ผู้เรียน Guest'),
                  subtitle: Text(
                    account == null
                        ? 'ข้อมูลอยู่ในเครื่อง'
                        : account.emailVerified
                        ? 'บัญชียืนยันแล้ว'
                        : 'รอยืนยันอีเมล',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _Metric(label: 'XP สะสม', value: '${progress.totalXp}'),
              _Metric(label: 'Streak', value: '${progress.streakDays} วัน'),
              _Metric(
                label: 'ระดับจากคะแนนจริง',
                value: '${progress.gameLevel}',
              ),
              _Metric(
                label: 'คำตอบที่ใช้คำนวณ',
                value: '${progress.sampleSize}',
              ),
              _Metric(
                label: 'ความสำเร็จที่ปลดล็อก',
                value: '${progress.achievementCount}',
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'อัลกอริทึม v${progress.algorithmVersion} · '
                  'ไม่มีคะแนนหรืออันดับตัวอย่าง',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
