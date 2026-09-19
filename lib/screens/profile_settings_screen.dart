import 'dart:async';

import 'package:flutter/material.dart';

import '../features/account/domain/account_contracts.dart';
import '../features/progress/domain/personal_learning_profile.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';

typedef ProfileSettingsProfileLoader =
    Future<PersonalLearningProfile> Function();

typedef _ProfileView = ({
  PersonalLearningProfile profile,
  AccountSession? account,
});
typedef _ProfileOwner = ({String ownerId, String? firebaseUid});

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key, this.loader, this.onOpenMastery});

  final ProfileSettingsProfileLoader? loader;
  final VoidCallback? onOpenMastery;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  Future<_ProfileView>? _load;
  AppDependencies? _dependencies;
  StreamSubscription<_ProfileOwner?>? _ownerSubscription;
  _ProfileOwner? _profileOwner;
  var _ownerReady = false;
  var _wasActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final changed = !identical(_dependencies, dependencies);
    _dependencies = dependencies;
    final active = TickerMode.valuesOf(context).enabled;
    if (changed || active != _wasActive) _observeOwner();
    if (active && (!_wasActive || changed || _load == null)) _reload();
    _wasActive = active;
  }

  @override
  void didUpdateWidget(ProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.loader, widget.loader)) {
      _observeOwner();
      _load = null;
      if (TickerMode.valuesOf(context).enabled) {
        _reload();
        _wasActive = true;
      }
    }
  }

  void _observeOwner() {
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _profileOwner = null;
    _ownerReady = false;
    _load = null;
    final dependencies = _dependencies;
    if (!TickerMode.valuesOf(context).enabled ||
        widget.loader != null ||
        dependencies?.progress == null) {
      return;
    }
    _ownerSubscription = dependencies!.progress!.watchProfileOwner().listen(
      (owner) {
        if (!mounted || !identical(dependencies, _dependencies)) return;
        setState(() {
          _profileOwner = owner;
          _ownerReady = true;
          _load = null;
          if (TickerMode.valuesOf(context).enabled) _reload();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || !identical(dependencies, _dependencies)) return;
        setState(() {
          _profileOwner = null;
          _ownerReady = false;
          _load = Future.error(error, stack);
          _load!.ignore();
        });
      },
    );
  }

  void _reload() {
    final dependencies = _dependencies;
    final loader =
        widget.loader ?? dependencies?.progress?.loadPersonalLearningProfile;
    if (widget.loader == null && dependencies?.progress != null && !_ownerReady) {
      return;
    }
    final owner = _profileOwner;
    _load = () async {
      if (loader == null || (widget.loader == null && owner == null)) {
        throw StateError(
          'personal learning profile dependency or owner unavailable',
        );
      }
      final profile = await loader();
      final session = dependencies?.account?.currentSession;
      if (widget.loader == null &&
          (profile.ownerId != owner!.ownerId ||
              (owner.firebaseUid != null &&
                  session != null &&
                  owner.firebaseUid != session.uid))) {
        throw StateError('personal learning profile owner changed');
      }
      return (
        profile: profile,
        account: widget.loader != null || owner?.firebaseUid != null
            ? session
            : null,
      );
    }();
    // Owner notifications can supersede a load before FutureBuilder subscribes.
    // Keep failures observed; the current future still renders its error state.
    _load!.ignore();
  }

  @override
  void dispose() {
    _ownerSubscription?.cancel().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: FutureBuilder<_ProfileView>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('ไม่สามารถอ่านข้อมูลในเครื่องได้'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!.profile;
          final account = snapshot.data!.account;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(
                    account?.email ?? 'ผู้เรียนในเครื่อง',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    account == null
                        ? 'ข้อมูลอยู่ในเครื่อง'
                        : account.emailVerified
                        ? 'บัญชียืนยันแล้ว'
                        : 'รอยืนยันอีเมล',
                    style: Theme.of(context).textTheme.bodySmall,
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
                entry: NavigationGlossary.require('profile/mastery'),
                value: _available(
                  profile.mastery.availability,
                  '${profile.mastery.masteredWordCount} คำที่ชำนาญ',
                ),
              ),
              _AxisCard(
                entry: NavigationGlossary.require('profile/srs'),
                value: _available(
                  profile.srs.availability,
                  '${profile.srs.dueReviewCount} คำถึงกำหนด จาก '
                  '${profile.srs.trackedWordCount} คำ',
                ),
              ),
              _AxisCard(
                entry: NavigationGlossary.require('profile/effort'),
                value: _available(
                  profile.effort.availability,
                  _duration(profile.effort.activeDuration),
                ),
              ),
              if (widget.onOpenMastery != null) ...[
                FilledButton.icon(
                  key: const ValueKey('profile-open-mastery'),
                  onPressed: widget.onOpenMastery,
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('ดูภาพรวมการเรียน'),
                ),
              ],
              SizedBox(height: widget.onOpenMastery != null ? 24 : 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('รายละเอียดการเรียน'),
                key: const ValueKey('profile-learning-details'),
                children: [
                  _AxisCard(
                    entry: NavigationGlossary.require('profile/accuracy'),
                    value: profile.accuracy.value == null
                        ? 'ยังไม่มีหลักฐาน'
                        : '${(profile.accuracy.value! * 100).toStringAsFixed(0)}% '
                              'จาก ${profile.accuracy.sampleSize} คำตอบ',
                  ),
                  _AxisCard(
                    entry: NavigationGlossary.require('profile/weakness'),
                    value: _available(
                      profile.weakness.availability,
                      profile.weakness.items.isEmpty
                          ? 'ไม่พบจุดอ่อนในหลักฐานปัจจุบัน'
                          : '${profile.weakness.items.length} คำที่ควรทบทวน',
                    ),
                  ),
                  _AxisCard(
                    entry: NavigationGlossary.require('profile/engagement'),
                    value: _available(
                      profile.engagement.availability,
                      '${profile.engagement.totalXp} XP · '
                      'ต่อเนื่อง ${profile.engagement.currentStreakDays} วัน',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AxisCard extends StatelessWidget {
  const _AxisCard({required this.entry, required this.value});

  final NavigationGlossaryEntry entry;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: entry.tooltip,
      child: Semantics(
        label: entry.semanticsLabel,
        value: value,
        readOnly: true,
        excludeSemantics: true,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Icon(entry.icon),
            title: Text(
              entry.fullThaiLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ),
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
