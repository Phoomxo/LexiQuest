import '../features/ai_tutor/presentation/menu_action_binding.dart';
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
  const ProfileSettingsScreen({
    super.key,
    this.loader,
    this.onOpenMastery,
    this.secondaryActions = const [],
  });

  final ProfileSettingsProfileLoader? loader;
  final VoidCallback? onOpenMastery;
  final List<Widget> secondaryActions;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen>
    with WidgetsBindingObserver {
  final _details = ExpansibleController();
  Future<_ProfileView>? _load;
  AppDependencies? _dependencies;
  ProfileSettingsProfileLoader? _loader;
  StreamSubscription<_ProfileOwner?>? _ownerSubscription;
  _ProfileOwner? _profileOwner;
  var _ownerReady = false;
  var _active = false;
  var _pending = false;
  var _exited = false;
  var _foreground = true;
  var _epoch = 0;
  var _generation = 0;

  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _bind();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(ProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    // Standalone profile loaders do not borrow another authority's identity.
    final dependencies = widget.loader == null
        ? AppDependenciesScope.maybeOf(context)
        : null;
    final changed =
        !identical(dependencies, _dependencies) ||
        !identical(widget.loader, _loader);
    final active = _visible;
    _dependencies = dependencies;
    _loader = widget.loader;
    if (changed || active != _active) {
      _active = active;
      _retire();
      _observeOwner();
      if (active) _reload();
    }
  }

  void _retire() {
    _generation++;
    _load = null;
    _pending = false;
  }

  bool _current(int generation) =>
      mounted && !_exited && generation == _generation;

  void _observeOwner() {
    final epoch = ++_epoch;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _profileOwner = null;
    _ownerReady = false;
    final progress = _dependencies?.progress;
    if (!_active || progress == null) return;
    _pending = true;
    _ownerSubscription = progress.watchProfileOwner().listen(
      (owner) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _profileOwner = owner;
          _ownerReady = true;
          if (_active) _reload();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _profileOwner = null;
          _ownerReady = false;
          _load = Future<_ProfileView>.error(error, stack);
          _load!.ignore();
        });
      },
    );
  }

  void _reload() {
    final dependencies = _dependencies;
    final progress = dependencies?.progress;
    final loader = _loader;
    if (progress != null && !_ownerReady) return;
    _retire();
    final generation = _generation;
    final owner = _profileOwner;
    _pending = true;
    _load = Future<_ProfileView>.sync(() async {
      if (loader != null) return (profile: await loader(), account: null);
      if (progress == null || owner == null) {
        throw StateError(
          'personal learning profile dependency or owner unavailable',
        );
      }
      final profile = await progress.loadPersonalLearningProfile();
      final current = await progress.owners.getOrCreateActiveOwner();
      final session = dependencies?.account?.currentSession;
      if (profile.ownerId != owner.ownerId ||
          current.id != owner.ownerId ||
          current.firebaseUid != owner.firebaseUid ||
          (owner.firebaseUid != null &&
              session != null &&
              owner.firebaseUid != session.uid)) {
        throw StateError('personal learning profile owner changed');
      }
      return (
        profile: profile,
        account: owner.firebaseUid != null ? session : null,
      );
    });
    // Observe immediate failures even if another generation retires this future.
    _load!.then<void>(
      (_) {
        if (_current(generation)) _pending = false;
      },
      onError: (Object _, StackTrace __) {
        if (_current(generation)) _pending = false;
      },
    );
  }

  void _retry(int generation) {
    if (!_current(generation) || !_active || !_visible || _pending) return;
    setState(() {
      if (_dependencies?.progress != null && !_ownerReady) {
        _retire();
        _observeOwner();
      } else {
        _reload();
      }
    });
  }

  void _exit() {
    _exited = true;
    _epoch++;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _retire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exit();
    _details.dispose();
    super.dispose();
  }

  Widget _masteryAction() {
    final generation = _generation;
    final callback = widget.onOpenMastery;
    void invoke() {
      if (!_current(generation) ||
          !_active ||
          !_visible ||
          !identical(callback, widget.onOpenMastery))
        return;
      callback?.call();
    }

    return MenuActionBinding(
      id: 'home/mastery',
      label: 'ดูภาพรวมการเรียน',
      onInvoke: invoke,
      child: MenuActionBinding(
        id: 'profile-open-mastery',
        label: 'ดูภาพรวมการเรียน',
        onInvoke: invoke,
        child: FilledButton.icon(
          key: const ValueKey('profile-open-mastery'),
          onPressed: invoke,
          icon: const Icon(Icons.insights_outlined),
          label: const Text('ดูภาพรวมการเรียน'),
        ),
      ),
    );
  }

  Widget _pendingProfile(Widget status) => MenuActionListView(
    padding: const EdgeInsets.all(16),
    children: [
      Padding(padding: const EdgeInsets.all(16), child: status),
      if (widget.onOpenMastery != null) _masteryAction(),
      ...widget.secondaryActions,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_exited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('โปรไฟล์')),
        body: !_active || _exited
            ? const SizedBox.shrink()
            : FutureBuilder<_ProfileView>(
                key: ValueKey(generation),
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _pendingProfile(
                      const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _pendingProfile(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ไม่สามารถอ่านข้อมูลในเครื่องได้'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _retry(generation),
                            icon: const Icon(Icons.refresh),
                            label: const Text('ลองอีกครั้ง'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return _pendingProfile(
                      const Center(child: CircularProgressIndicator()),
                    );
                  }
                  final profile = snapshot.data!.profile;
                  final account = snapshot.data!.account;
                  return MenuActionListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...widget.secondaryActions,
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
                        ownerId: profile.ownerId,
                        entry: NavigationGlossary.require('profile/mastery'),
                        value: _available(
                          profile.mastery.availability,
                          '${profile.mastery.masteredWordCount} คำที่ชำนาญ',
                        ),
                      ),
                      _AxisCard(
                        ownerId: profile.ownerId,
                        entry: NavigationGlossary.require('profile/srs'),
                        value: _available(
                          profile.srs.availability,
                          '${profile.srs.dueReviewCount} คำถึงกำหนด จาก '
                          '${profile.srs.trackedWordCount} คำ',
                        ),
                      ),
                      _AxisCard(
                        ownerId: profile.ownerId,
                        entry: NavigationGlossary.require('profile/effort'),
                        value: _available(
                          profile.effort.availability,
                          _duration(profile.effort.activeDuration),
                        ),
                      ),
                      if (widget.onOpenMastery != null) _masteryAction(),
                      SizedBox(height: widget.onOpenMastery != null ? 24 : 12),
                      MenuActionBinding(
                        id: 'profile/show-learning-details',
                        label: 'รายละเอียดการเรียน',
                        ownerId: profile.ownerId,
                        onInvoke: () {
                          if (_current(generation) && _active && _visible)
                            _details.expand();
                        },
                        child: ExpansionTile(
                          controller: _details,
                          tilePadding: EdgeInsets.zero,
                          title: const Text('รายละเอียดการเรียน'),
                          key: const ValueKey('profile-learning-details'),
                          children: [
                            _AxisCard(
                              ownerId: profile.ownerId,
                              entry: NavigationGlossary.require(
                                'profile/accuracy',
                              ),
                              value: profile.accuracy.value == null
                                  ? 'ยังไม่มีหลักฐาน'
                                  : '${(profile.accuracy.value! * 100).toStringAsFixed(0)}% '
                                        'จาก ${profile.accuracy.sampleSize} คำตอบ',
                            ),
                            _AxisCard(
                              ownerId: profile.ownerId,
                              entry: NavigationGlossary.require(
                                'profile/weakness',
                              ),
                              value: _available(
                                profile.weakness.availability,
                                profile.weakness.items.isEmpty
                                    ? 'ไม่พบจุดอ่อนในหลักฐานปัจจุบัน'
                                    : '${profile.weakness.items.length} คำที่ควรทบทวน',
                              ),
                            ),
                            _AxisCard(
                              ownerId: profile.ownerId,
                              entry: NavigationGlossary.require(
                                'profile/engagement',
                              ),
                              value: _available(
                                profile.engagement.availability,
                                '${profile.engagement.totalXp} XP · '
                                'ต่อเนื่อง ${profile.engagement.currentStreakDays} วัน',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _AxisCard extends StatelessWidget {
  const _AxisCard({
    required this.entry,
    required this.value,
    required this.ownerId,
  });

  final String ownerId;

  final NavigationGlossaryEntry entry;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MenuActionBinding(
      ownerId: ownerId,
      id: entry.id,
      label: entry.fullThaiLabel,
      onInvoke: null,
      readValue: value,
      child: Tooltip(
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
              subtitle: Text(
                value,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
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
