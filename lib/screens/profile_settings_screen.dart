import 'package:flutter/material.dart';

import '../features/progress/domain/personal_learning_profile.dart';
import '../runtime/app_dependencies.dart';

typedef ProfileSettingsProfileLoader =
    Future<PersonalLearningProfile> Function();

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key, this.loader});

  final ProfileSettingsProfileLoader? loader;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  Future<PersonalLearningProfile>? _load;
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
        widget.loader ??
        AppDependenciesScope.maybeOf(
          context,
        )?.progress?.loadPersonalLearningProfile;
    _load = loader == null
        ? Future<PersonalLearningProfile>.error(
            StateError('personal learning profile dependency unavailable'),
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
      body: FutureBuilder<PersonalLearningProfile>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('ไม่สามารถอ่านข้อมูลในเครื่องได้'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!;
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
              if (profile.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้',
                    textAlign: TextAlign.center,
                  ),
                ),
              _AxisCard(
                label: 'Mastery',
                value: _available(
                  profile.mastery.availability,
                  '${profile.mastery.masteredWordCount} คำที่ชำนาญ',
                ),
              ),
              _AxisCard(
                label: 'SRS',
                value: _available(
                  profile.srs.availability,
                  '${profile.srs.dueReviewCount} คำถึงกำหนด จาก '
                  '${profile.srs.trackedWordCount} คำ',
                ),
              ),
              _AxisCard(
                label: 'Effort',
                value: _available(
                  profile.effort.availability,
                  _duration(profile.effort.activeDuration),
                ),
              ),
              _AxisCard(
                label: 'Accuracy',
                value: profile.accuracy.value == null
                    ? 'ยังไม่มีหลักฐาน'
                    : '${(profile.accuracy.value! * 100).toStringAsFixed(0)}% '
                          'จาก ${profile.accuracy.sampleSize} คำตอบ',
              ),
              _AxisCard(
                label: 'Weakness',
                value: _available(
                  profile.weakness.availability,
                  profile.weakness.items.isEmpty
                      ? 'ไม่พบจุดอ่อนในหลักฐานปัจจุบัน'
                      : '${profile.weakness.items.length} คำที่ควรทบทวน',
                ),
              ),
              _AxisCard(
                label: 'Engagement',
                value: _available(
                  profile.engagement.availability,
                  '${profile.engagement.totalXp} XP · '
                  'Streak ${profile.engagement.currentStreakDays} วัน',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AxisCard extends StatelessWidget {
  const _AxisCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(title: Text(label), subtitle: Text(value)),
    );
  }
}

String _available(ProfileAxisAvailability availability, String value) =>
    availability == ProfileAxisAvailability.available
    ? value
    : 'ยังไม่มีหลักฐาน';

String _duration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '$seconds วินาที' : '$minutes นาที $seconds วินาที';
}
