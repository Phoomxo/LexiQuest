import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/goals/application/learning_goal_use_cases.dart';
import '../features/goals/data/drift_learning_goal_repository.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/goals/domain/learning_goal.dart';
import '../features/goals/domain/learning_goal_repository.dart';
import '../features/reminders/application/study_reminder_use_cases.dart';
import '../features/reminders/domain/study_reminder.dart';
import '../features/reminders/domain/study_reminder_repository.dart';
import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/local_study_datetime_field.dart';
import 'study_reminder_settings_screen.dart';

String _goalKindLabel(LearningGoalKind kind) => switch (kind) {
  LearningGoalKind.languageTest => 'สอบภาษา',
  LearningGoalKind.course => 'รายวิชา',
  LearningGoalKind.personal => 'เป้าหมายส่วนตัว',
};

String _goalStatusLabel(LearningGoalStatus status) => switch (status) {
  LearningGoalStatus.active => 'กำลังทำ',
  LearningGoalStatus.completed => 'สำเร็จแล้ว',
  LearningGoalStatus.cancelled => 'ยกเลิกแล้ว',
};

final class LearningGoalsScreen extends StatefulWidget {
  const LearningGoalsScreen({
    super.key,
    this.useCases,
    this.reminderUseCases,
    this.reminderRuntimeEnabled,
    this.ownerIdentities,
  });

  final LearningGoalUseCases? useCases;
  final StudyReminderUseCases? reminderUseCases;
  final bool? reminderRuntimeEnabled;
  final ReviewOwnerIdentityReader? ownerIdentities;

  @override
  State<LearningGoalsScreen> createState() => _LearningGoalsScreenState();
}

final class _LearningGoalsScreenState extends State<LearningGoalsScreen>
    with RouteAware {
  Future<List<LearningGoal>>? _goals;
  ReviewOwnerIdentityReader? _loadedOwnerReader;
  String? _assistanceOwnerId;
  int _readGeneration = 0;
  LearningGoalUseCases? _loadedUseCases;
  Future<bool>? _reminderEntryAvailable;
  Listenable? _registryChanges;
  final Set<String> _deleting = {};
  bool _openingGoal = false;
  bool _active = false, _exited = false, _reading = false;
  bool _statusOpen = false;
  bool _covered = false;
  String? _displayedOwner;
  PageRoute<dynamic>? _route;
  Route<dynamic>? _editorRoute;
  final ValueNotifier<int> _lifetime = ValueNotifier<int>(0);
  void _signal() {
    scheduleMicrotask(() {
      if (mounted) _lifetime.value++;
    });
  }

  ProgressUseCases? _progress;
  StreamSubscription<({String ownerId, String? firebaseUid})?>?
  _ownerSubscription;
  int _ownerEpoch = 0;
  int _ownerVersion = 0;
  bool _openingReminder = false;

  void _observeOwner() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final repository = _loadedUseCases?.repository;
    final progress =
        repository is DriftLearningGoalRepository &&
            identical(repository.owners, dependencies?.progress?.owners)
        ? dependencies?.progress
        : null;
    if (identical(progress, _progress)) return;
    _progress = progress;
    final epoch = ++_ownerEpoch;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = progress?.watchProfileOwner().listen(
      (owner) {
        if (!mounted ||
            _exited ||
            epoch != _ownerEpoch ||
            owner?.ownerId == _displayedOwner ||
            (_displayedOwner == null && _reading))
          return;
        _ownerVersion++;
        final editor = _editorRoute;
        _editorRoute = null;
        setState(() {
          _retire();
        });
        if (editor?.isActive == true) editor!.navigator?.removeRoute(editor);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_exited && epoch == _ownerEpoch)
            setState(_refreshGoalSource);
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _ownerEpoch) return;
        _ownerVersion++;
        setState(() {
          _retire();
          _goals = Future<List<LearningGoal>>.error(error, stack);
          _goals!.ignore();
        });
      },
    );
  }

  bool get _visible =>
      !_exited &&
      !_covered &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent != false ||
          _editorRoute?.isActive == true ||
          _statusOpen);
  bool _current(int generation) =>
      mounted &&
      !_exited &&
      _active &&
      generation == _readGeneration &&
      _visible;
  void _retire() {
    _statusOpen = false;
    _signal();
    ++_readGeneration;
    _goals = null;
    _reading = false;
    _assistanceOwnerId = null;
    _displayedOwner = null;
    _deleting.clear();
  }

  @override
  void didPushNext() {
    _covered = true;
    if (mounted)
      setState(() {
        _active = false;
        _retire();
      });
  }

  @override
  void didPopNext() {
    _covered = false;
    if (mounted) setState(_refreshGoalSource);
  }

  void _exit() {
    _exited = true;
    _ownerEpoch++;
    _ownerSubscription?.cancel().ignore();
    _ownerSubscription = null;
    _active = false;
    _retire();
  }

  LearningGoalUseCases? _resolveUseCases() =>
      widget.useCases ?? AppDependenciesScope.maybeOf(context)?.learningGoals;

  FeatureRegistry? _resolveFeatureRegistry() =>
      AppDependenciesScope.maybeOf(context)?.features;

  StudyReminderUseCases? _resolveReminderUseCases() =>
      widget.reminderUseCases ??
      AppDependenciesScope.maybeOf(context)?.studyReminders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && !identical(route, _route)) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
    _refreshGoalSource();
    final registry = _resolveFeatureRegistry();
    final Listenable? changes = registry is Listenable
        ? registry as Listenable
        : null;
    if (!identical(changes, _registryChanges)) {
      _registryChanges?.removeListener(_onRegistryChanged);
      _registryChanges = changes;
      _registryChanges?.addListener(_onRegistryChanged);
    }
    _refreshReminderAvailability();
  }

  @override
  void didUpdateWidget(LearningGoalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshGoalSource();
    if (!identical(oldWidget.reminderUseCases, widget.reminderUseCases) ||
        oldWidget.reminderRuntimeEnabled != widget.reminderRuntimeEnabled) {
      _refreshReminderAvailability();
    }
  }

  void _refreshGoalSource() {
    final useCases = _resolveUseCases();
    final owners =
        widget.ownerIdentities ??
        AppDependenciesScope.maybeOf(context)?.activeOwnerIdentities;
    final active = _visible;
    if (identical(useCases, _loadedUseCases) &&
        identical(owners, _loadedOwnerReader) &&
        active == _active &&
        _goals != null)
      return;
    _retire();
    _loadedUseCases = useCases;
    _loadedOwnerReader = owners;
    _active = active;
    _observeOwner();
    if (active && useCases != null) _load(useCases);
  }

  void _load(LearningGoalUseCases useCases) {
    final generation = ++_readGeneration;
    _reading = true;
    _displayedOwner = null;
    final read = Future<List<LearningGoal>>.sync(
      () => _readGoals(useCases, _loadedOwnerReader, generation),
    );
    _goals = read;
    read.then<void>(
      (_) {
        if (_current(generation)) {
          setState(() => _reading = false);
          _signal();
        }
      },
      onError: (Object _, StackTrace __) {
        if (_current(generation)) {
          setState(() => _reading = false);
          _signal();
        }
      },
    );
  }

  Future<String?> _optionalOwner(ReviewOwnerIdentityReader? owners) async {
    try {
      return await owners?.requireSingleActiveOwnerId();
    } catch (_) {
      // Identity lookup is for optional context; native goals remain available.
      return null;
    }
  }

  Future<List<LearningGoal>> _readGoals(
    LearningGoalUseCases useCases,
    ReviewOwnerIdentityReader? owners,
    int generation,
  ) async {
    _assistanceOwnerId = null;
    final owner = await useCases.activeOwnerId();
    final before = await _optionalOwner(owners);
    final goals = await useCases.list();
    final after = await useCases.activeOwnerId();
    if (!_current(generation) || owner != after || owner.isEmpty) {
      throw const LearningGoalOwnerChanged();
    }
    final optionalAfter = before == null ? null : await _optionalOwner(owners);
    final finalOwner = await useCases.activeOwnerId();
    if (!_current(generation) || finalOwner != owner)
      throw const LearningGoalOwnerChanged();
    _displayedOwner = owner;
    if (before == owner && optionalAfter == owner) _assistanceOwnerId = owner;
    return goals;
  }

  Widget _guidance(
    String status,
    Widget child, {
    int? count,
  }) => MenuActionBinding(
    id: 'study-planning/goals/context',
    label: 'Learning goals currently displayed',
    ownerId: _assistanceOwnerId,
    onInvoke: null,
    readValue: status == 'ready' && _assistanceOwnerId == null
        ? null
        : jsonEncode({
            'screen': 'learning-goals',
            'status': status,
            'count': ?count,
            'purpose':
                'User planning goals; completion is not assessed language proficiency.',
            'manualChangesRequired': true,
          }),
    child: child,
  );

  void _onRegistryChanged() {
    if (!mounted) return;
    setState(_refreshReminderAvailability);
  }

  void _refreshReminderAvailability() {
    final reminders = _resolveReminderUseCases();
    final registry = _resolveFeatureRegistry();
    final runtimeEnabled =
        widget.reminderRuntimeEnabled ??
        registry?.isEnabled(Feature.studyPlanning) ??
        false;
    _reminderEntryAvailable = reminders == null || !runtimeEnabled
        ? Future<bool>.value(false)
        : reminders.canOpenSettings();
  }

  void _reload(LearningGoalUseCases useCases) {
    if (!mounted || !_visible || _reading) return;
    setState(() => _load(useCases));
  }

  Future<void> _openReminder(
    LearningGoal goal,
    StudyReminderUseCases reminders,
    StudyReminderMutationGuard mutationAllowed,
  ) async {
    if (_openingReminder || !mutationAllowed()) return;
    _openingReminder = true;
    final useCases = _loadedUseCases!;
    final owner = _displayedOwner;
    final ownerVersion = _ownerVersion;
    try {
      if (await useCases.activeOwnerId() != owner || !mutationAllowed()) return;
      late final MaterialPageRoute<void> route;
      bool childAllowed() =>
          mounted &&
          !_exited &&
          route.isActive &&
          route.isCurrent &&
          ownerVersion == _ownerVersion &&
          identical(useCases, _loadedUseCases) &&
          identical(reminders, _resolveReminderUseCases()) &&
          (_resolveFeatureRegistry()?.isEnabled(Feature.studyPlanning) ??
              widget.useCases != null) &&
          (widget.reminderRuntimeEnabled ??
              _resolveFeatureRegistry()?.isEnabled(Feature.studyPlanning) ??
              false);
      route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'goals/study-reminder-settings'),
        builder: (_) => StudyReminderSettingsScreen(
          useCases: reminders,
          source: StudyReminderSource.goalDeadline(goal.id),
          sourceLabel: goal.title,
          mutationAllowed: childAllowed,
        ),
      );
      await Navigator.of(context).push(route);
    } on Object {
      if (mounted && mutationAllowed())
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังเปิดการเตือนไม่ได้ กรุณาลองอีกครั้ง'),
          ),
        );
    } finally {
      _openingReminder = false;
    }
  }

  Future<void> _createGoal(
    LearningGoalUseCases useCases,
    FeatureRegistry? registry,
    LearningGoalMutationGuard mutationAllowed, {
    LearningGoal? goal,
  }) async {
    if (_openingGoal || !mounted || !mutationAllowed()) return;
    _openingGoal = true;
    final displayedOwner = _displayedOwner;
    try {
      final openingOwnerId = await useCases.activeOwnerId();
      if (!mounted || !mutationAllowed()) return;
      if (openingOwnerId != displayedOwner ||
          openingOwnerId != await useCases.activeOwnerId()) {
        throw const LearningGoalOwnerChanged();
      }
      if (!mounted || !mutationAllowed()) return;
      late final DialogRoute<LearningGoal> route;
      route = DialogRoute<LearningGoal>(
        context: context,
        builder: (_) => _CreateLearningGoalDialog(
          useCases: useCases,
          registry: registry,
          mutationAllowed: () =>
              mounted &&
              !_exited &&
              _visible &&
              identical(useCases, _loadedUseCases) &&
              _editorRoute == route &&
              route.isActive &&
              !_reading &&
              _displayedOwner == openingOwnerId &&
              (registry?.isEnabled(Feature.studyPlanning) ??
                  widget.useCases != null),
          lifetime: _lifetime,
          retryRead: () => _reload(useCases),
          openingOwnerId: openingOwnerId,
          initialGoal: goal,
        ),
      );
      _editorRoute = route;
      final created = await Navigator.of(context).push(route);
      _editorRoute = null;
      if (created != null && mounted && mutationAllowed()) _reload(useCases);
    } catch (error) {
      if (mounted && mutationAllowed()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังเปิดเป้าหมายไม่ได้ กรุณาลองอีกครั้ง'),
          ),
        );
        if (error is LearningGoalOwnerChanged) _reload(useCases);
      }
    } finally {
      _openingGoal = false;
    }
  }

  Future<void> _deleteGoal(
    LearningGoal goal,
    LearningGoalUseCases useCases,
    LearningGoalMutationGuard mutationAllowed,
  ) async {
    if (_deleting.contains(goal.id) || !mutationAllowed()) return;
    setState(() => _deleting.add(goal.id));
    try {
      final owner = _displayedOwner;
      if (owner == null ||
          await useCases.activeOwnerId() != owner ||
          !mutationAllowed())
        return;
      final command = await useCases.prepareUpdate(
        goal,
        expectedOwnerId: owner,
        kind: goal.kind,
        title: goal.title,
        deadlineAtUtc: goal.deadlineAtUtc,
        timezone: goal.timezone,
        isDeleted: true,
      );
      await useCases.executeCreate(command, mutationAllowed: mutationAllowed);
      if (mounted && mutationAllowed()) _reload(useCases);
    } on Object {
      if (mounted && mutationAllowed()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังยืนยันการลบไม่ได้ กำลังอ่านรายการล่าสุด'),
          ),
        );
        _reload(useCases);
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(goal.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final useCases = _resolveUseCases();
    final reminders = _resolveReminderUseCases();
    final registry = _resolveFeatureRegistry();
    final allowWithoutRegistry = widget.useCases != null;
    final compactAddButton =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(16) >= 24;
    final generation = _readGeneration;
    bool mutationAllowed() =>
        _current(generation) &&
        !_reading &&
        _displayedOwner != null &&
        identical(useCases, _resolveUseCases()) &&
        (registry?.isEnabled(Feature.studyPlanning) ?? allowWithoutRegistry);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_exited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            NavigationGlossary.require('study-planning/goals').fullThaiLabel,
          ),
        ),
        floatingActionButton: useCases == null || _displayedOwner == null
            ? null
            : compactAddButton
            ? FloatingActionButton(
                key: const ValueKey<String>('learning-goals/add'),
                tooltip: 'เพิ่มเป้าหมาย',
                onPressed: () =>
                    _createGoal(useCases, registry, mutationAllowed),
                child: const Icon(Icons.add),
              )
            : FloatingActionButton.extended(
                key: const ValueKey<String>('learning-goals/add'),
                onPressed: () =>
                    _createGoal(useCases, registry, mutationAllowed),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มเป้าหมาย'),
              ),
        body: useCases == null
            ? _guidance(
                'unavailable',
                const Center(child: Text('เป้าหมายการเรียนไม่พร้อมใช้งาน')),
              )
            : FutureBuilder<List<LearningGoal>>(
                future: _goals,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _guidance(
                      'loading',
                      const Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _guidance(
                      'unavailable',
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('โหลดเป้าหมายการเรียนไม่ได้'),
                              const SizedBox(height: 16),
                              FilledButton(
                                key: const ValueKey('learning-goals/retry'),
                                onPressed: () {
                                  if (_current(generation) && !_reading)
                                    _reload(useCases);
                                },
                                child: const Text('ลองอีกครั้ง'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  final goals = snapshot.data ?? const <LearningGoal>[];
                  if (goals.isEmpty) {
                    return _guidance(
                      'ready',
                      const Center(
                        child: Text('ยังไม่ได้กำหนดเป้าหมายการเรียน'),
                      ),
                      count: 0,
                    );
                  }
                  return _guidance(
                    'ready',
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: goals.length,
                      itemBuilder: (context, index) {
                        final goal = goals[index];
                        final countdown = useCases.countdown(goal);
                        final label = switch (countdown.state) {
                          LearningGoalDeadlineState.future =>
                            'เหลือ ${countdown.days} วัน',
                          LearningGoalDeadlineState.today => 'ครบกำหนดวันนี้',
                          LearningGoalDeadlineState.past =>
                            'เลยกำหนด ${countdown.days} วัน',
                        };
                        return MenuActionBinding(
                          id: 'study-planning/goals/item/${goal.id}',
                          label: 'Learning goal in the current list',
                          ownerId: _assistanceOwnerId,
                          onInvoke: null,
                          readValue: _assistanceOwnerId == null
                              ? null
                              : jsonEncode({
                                  'title': goal.title,
                                  'kind': goal.kind.name,
                                  'status': goal.status.name,
                                  'deadlineUtc': goal.deadlineAtUtc
                                      .toIso8601String(),
                                  'timezone': goal.timezone.timezoneId,
                                  'deadlineState': countdown.state.name,
                                  'days': countdown.days,
                                  'deleting': _deleting.contains(goal.id),
                                }),
                          child: Card(
                            key: ValueKey<String>('learning-goal/${goal.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    goal.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_goalKindLabel(goal.kind)} · $label',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      IconButton(
                                        key: ValueKey(
                                          'learning-goal/${goal.id}/edit',
                                        ),
                                        tooltip: 'แก้ไขเป้าหมาย',
                                        onPressed: _deleting.contains(goal.id)
                                            ? null
                                            : () => _createGoal(
                                                useCases,
                                                registry,
                                                mutationAllowed,
                                                goal: goal,
                                              ),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'learning-goal/${goal.id}/delete',
                                        ),
                                        tooltip:
                                            'ลบเป้าหมายและการเตือนที่ผูกไว้',
                                        onPressed: _deleting.contains(goal.id)
                                            ? null
                                            : () => _deleteGoal(
                                                goal,
                                                useCases,
                                                mutationAllowed,
                                              ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                      if (reminders != null)
                                        FutureBuilder<bool>(
                                          future: _reminderEntryAvailable,
                                          builder: (context, snapshot) =>
                                              snapshot.data == true
                                              ? IconButton(
                                                  key: ValueKey<String>(
                                                    'learning-goal/${goal.id}/reminder',
                                                  ),
                                                  tooltip: 'ตั้งเวลาเตือนเรียน',
                                                  onPressed: () =>
                                                      _openReminder(
                                                        goal,
                                                        reminders,
                                                        mutationAllowed,
                                                      ),
                                                  icon: const Icon(
                                                    Icons
                                                        .notifications_outlined,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      _LearningGoalStatusMenu(
                                        goal: goal,
                                        useCases: useCases,
                                        registry: registry,
                                        mutationAllowed: mutationAllowed,
                                        expectedOwnerId: _displayedOwner!,
                                        onMenuOpen: (open) =>
                                            _statusOpen = open,
                                        onChanged: () {
                                          if (mutationAllowed())
                                            _reload(useCases);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    count: goals.length,
                  );
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _exit();
    _lifetime.dispose();
    appRouteObserver.unsubscribe(this);
    _registryChanges?.removeListener(_onRegistryChanged);
    super.dispose();
  }
}

final class _CreateLearningGoalDialog extends StatefulWidget {
  const _CreateLearningGoalDialog({
    required this.useCases,
    required this.registry,
    required this.mutationAllowed,
    required this.openingOwnerId,
    required this.lifetime,
    required this.retryRead,
    this.initialGoal,
  });

  final LearningGoalUseCases useCases;
  final FeatureRegistry? registry;
  final LearningGoalMutationGuard mutationAllowed;
  final String openingOwnerId;
  final Listenable lifetime;
  final VoidCallback retryRead;
  final LearningGoal? initialGoal;

  @override
  State<_CreateLearningGoalDialog> createState() =>
      _CreateLearningGoalDialogState();
}

final class _CreateLearningGoalDialogState
    extends State<_CreateLearningGoalDialog> {
  final TextEditingController _title = TextEditingController();
  DateTime? _deadlineUtc;
  String _timezoneId = 'Asia/Bangkok';
  LearningGoalKind _kind = LearningGoalKind.languageTest;
  LearningGoalCreateCommand? _pendingCommand;
  bool _submitting = false;
  String? _validationMessage;
  String _assistanceStatus = 'draft';
  bool _exited = false;
  int _operationGeneration = 0;
  void _onLifetime() {
    if (!mounted) return;
    setState(() {
      _operationGeneration++;
      if (_submitting) {
        _submitting = false;
        _assistanceStatus = _pendingCommand == null
            ? 'draft'
            : 'confirmationUnknown';
      }
    });
  }

  bool _routeWasCurrent = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent != false;
    // A pending save belongs to the visible editor. Picking fields is disabled
    // during submission, so retiring pending work leaves owned pickers usable.
    if (_routeWasCurrent && !current && _submitting) {
      _operationGeneration++;
      _submitting = false;
      _assistanceStatus = _pendingCommand == null
          ? 'draft'
          : 'confirmationUnknown';
    }
    _routeWasCurrent = current;
  }

  bool _current() =>
      mounted &&
      !_exited &&
      widget.mutationAllowed() &&
      ModalRoute.of(context)?.isCurrent != false;

  void _edited() {
    _assistanceStatus = 'draft';
    _validationMessage = null;
  }

  String _editorContext() {
    final confirmed = widget.initialGoal;
    return jsonEncode({
      'screen': 'learning-goal-editor',
      'operation': confirmed == null ? 'create' : 'edit',
      'status': _assistanceStatus,
      'manualSaveRequired': true,
      'retryUsesSameDetails': _pendingCommand != null,
      'purpose':
          'Planning goal draft; not assessed proficiency. Submission outcome may be unconfirmed after an error.',
      'draft': {
        'title': _title.text,
        'kind': _kind.name,
        'deadlineUtc': _deadlineUtc?.toIso8601String(),
        'timezone': _timezoneId,
      },
      'lastConfirmed': confirmed == null
          ? null
          : {
              'title': confirmed.title,
              'kind': confirmed.kind.name,
              'deadlineUtc': confirmed.deadlineAtUtc.toIso8601String(),
              'timezone': confirmed.timezone.timezoneId,
              'status': confirmed.status.name,
            },
    });
  }

  Listenable? get _registryChanges =>
      widget.registry is Listenable ? widget.registry as Listenable : null;

  @override
  void initState() {
    super.initState();
    widget.lifetime.addListener(_onLifetime);
    final goal = widget.initialGoal;
    if (goal != null) {
      _title.text = goal.title;
      _deadlineUtc = goal.deadlineAtUtc;
      _timezoneId = goal.timezone.timezoneId;
      _kind = goal.kind;
    }
    _registryChanges?.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (mounted && !widget.mutationAllowed()) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _registryChanges?.removeListener(_onRegistryChanged);
    widget.lifetime.removeListener(_onLifetime);
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_current()) return;
    final generation = _operationGeneration;
    bool current() => _current() && generation == _operationGeneration;
    if (!widget.mutationAllowed()) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _submitting = true;
      _assistanceStatus = 'submitting';
      _validationMessage = null;
    });
    try {
      var command = _pendingCommand;
      if (command == null) {
        final deadline = _deadlineUtc;
        if (deadline == null) {
          throw const FormatException('Choose date and time');
        }
        final timezone = LearningGoalUseCases.timezoneContext(
          _timezoneId,
          deadline,
        );
        command = widget.initialGoal == null
            ? await widget.useCases.prepareCreate(
                expectedOwnerId: widget.openingOwnerId,
                kind: _kind,
                title: _title.text,
                deadlineAtUtc: deadline,
                timezone: timezone,
              )
            : await widget.useCases.prepareUpdate(
                widget.initialGoal!,
                expectedOwnerId: widget.openingOwnerId,
                kind: _kind,
                title: _title.text,
                deadlineAtUtc: deadline,
                timezone: timezone,
              );
        if (!current()) return;
        _pendingCommand = command;
      }
      if (!current()) {
        throw const LearningGoalMutationUnavailable();
      }
      final goal = await widget.useCases.executeCreate(
        command,
        mutationAllowed: current,
      );
      if (!current()) return;
      if (await widget.useCases.activeOwnerId() != widget.openingOwnerId) {
        throw const LearningGoalOwnerChanged();
      }
      if (current()) Navigator.of(context).pop(goal);
    } on LearningGoalOwnerChanged {
      _pendingCommand = null;
      if (current()) Navigator.of(context).pop();
    } on LearningGoalMutationUnavailable {
      if (current()) Navigator.of(context).maybePop();
    } on Object catch (error) {
      if (!current()) return;
      setState(() {
        _submitting = false;
        final invalid = error is FormatException || error is ArgumentError;
        _assistanceStatus = _pendingCommand != null
            ? 'confirmationUnknown'
            : invalid
            ? 'invalidDraft'
            : 'preparationFailed';
        _validationMessage = _pendingCommand == null
            ? invalid
                  ? 'กรุณาระบุชื่อเป้าหมาย เลือกวันที่ เวลา และเขตเวลาให้ครบ'
                  : 'ยังเตรียมการบันทึกเป้าหมายไม่ได้ กรุณาลองอีกครั้ง'
            : 'ยังยืนยันการสร้างเป้าหมายไม่ได้ การลองอีกครั้งจะใช้รายละเอียดเดิม';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.mutationAllowed();
    final recovery = AlertDialog(
      title: const Text('กำลังตรวจสอบเจ้าของเป้าหมาย'),
      content: const Text('ร่างยังอยู่ กรุณาลองอ่านข้อมูลอีกครั้ง'),
      actions: [
        TextButton(
          onPressed: () {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              _exited = true;
              Navigator.of(context).pop();
            }
          },
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: const ValueKey('learning-goals/editor-retry'),
          onPressed: widget.retryRead,
          child: const Text('ลองอีกครั้ง'),
        ),
      ],
    );
    final generation = _operationGeneration;
    bool editingAllowed() => _current() && generation == _operationGeneration;
    final fieldsEnabled = _pendingCommand == null && !_submitting;
    return Stack(
      children: [
        Offstage(
          offstage: !available,
          child: PopScope<LearningGoal>(
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) _exited = true;
            },
            child: MenuActionBinding(
              id: 'study-planning/goals/editor',
              label: 'Current learning goal draft and last confirmed values',
              ownerId: widget.openingOwnerId,
              onInvoke: null,
              readValue: widget.mutationAllowed() ? _editorContext() : null,
              child: AlertDialog(
                scrollable: true,
                insetPadding: const EdgeInsets.all(16),
                titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  widget.initialGoal == null
                      ? 'เพิ่มเป้าหมายการเรียน'
                      : 'แก้ไขเป้าหมายส่วนตัว',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<LearningGoalKind>(
                      key: const ValueKey<String>('learning-goals/kind'),
                      initialValue: _kind,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: const InputDecoration(
                        labelText: 'ประเภทเป้าหมาย',
                      ),
                      items: LearningGoalKind.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_goalKindLabel(value)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: fieldsEnabled
                          ? (value) {
                              if (value != null && editingAllowed()) {
                                setState(() {
                                  _kind = value;
                                  _edited();
                                });
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey<String>('learning-goals/title'),
                      controller: _title,
                      onChanged: (_) {
                        if (editingAllowed()) setState(_edited);
                      },
                      enabled: fieldsEnabled,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อเป้าหมาย',
                      ),
                    ),
                    const SizedBox(height: 12),
                    LocalStudyDateTimeField(
                      fieldKey: 'learning-goals/deadline',
                      referenceUtc: widget.useCases.nowUtc(),
                      enabled: fieldsEnabled,
                      initialUtc: _deadlineUtc,
                      initialTimezoneId: _timezoneId,
                      onChanged: (instant, zone) {
                        if (!editingAllowed()) return;
                        setState(() {
                          _deadlineUtc = instant;
                          _timezoneId = zone;
                          _edited();
                        });
                      },
                    ),
                    if (_validationMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _validationMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (editingAllowed()) {
                        _exited = true;
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('ยกเลิก'),
                  ),
                  FilledButton(
                    key: ValueKey<String>(
                      widget.initialGoal == null
                          ? 'learning-goals/create'
                          : 'learning-goals/save',
                    ),
                    onPressed: _submitting
                        ? null
                        : () {
                            if (editingAllowed()) _submit();
                          },
                    child: Text(
                      _pendingCommand != null
                          ? 'ลองอีกครั้ง'
                          : widget.initialGoal == null
                          ? 'สร้างเป้าหมาย'
                          : 'บันทึกเป้าหมาย',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!available) recovery,
      ],
    );
  }
}

final class _LearningGoalStatusMenu extends StatefulWidget {
  const _LearningGoalStatusMenu({
    required this.goal,
    required this.useCases,
    required this.registry,
    required this.mutationAllowed,
    required this.onChanged,
    required this.expectedOwnerId,
    required this.onMenuOpen,
  });

  final LearningGoal goal;
  final LearningGoalUseCases useCases;
  final FeatureRegistry? registry;
  final LearningGoalMutationGuard mutationAllowed;
  final VoidCallback onChanged;
  final String expectedOwnerId;
  final ValueChanged<bool> onMenuOpen;

  @override
  State<_LearningGoalStatusMenu> createState() =>
      _LearningGoalStatusMenuState();
}

final class _LearningGoalStatusMenuState
    extends State<_LearningGoalStatusMenu> {
  bool _menuOpen = false;
  bool _busy = false;

  Listenable? get _registryChanges =>
      widget.registry is Listenable ? widget.registry as Listenable : null;

  @override
  void initState() {
    super.initState();
    _registryChanges?.addListener(_onRegistryChanged);
  }

  @override
  void didUpdateWidget(_LearningGoalStatusMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registry, widget.registry)) {
      final oldChanges = oldWidget.registry is Listenable
          ? oldWidget.registry as Listenable
          : null;
      oldChanges?.removeListener(_onRegistryChanged);
      _registryChanges?.addListener(_onRegistryChanged);
    }
  }

  void _onRegistryChanged() {
    if (mounted && _menuOpen && !widget.mutationAllowed()) {
      _menuOpen = false;
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _update(LearningGoalStatus status) async {
    _menuOpen = false;
    widget.onMenuOpen(false);
    if (_busy ||
        !mounted ||
        status == widget.goal.status ||
        !widget.mutationAllowed())
      return;
    _busy = true;
    try {
      await widget.useCases.updateStatus(
        widget.goal,
        status,
        expectedOwnerId: widget.expectedOwnerId,
        mutationAllowed: widget.mutationAllowed,
      );
      if (mounted && widget.mutationAllowed()) widget.onChanged();
    } on LearningGoalMutationUnavailable {
      // A live emergency-off is an expected fail-closed outcome.
    } on Object {
      // Read-only reconciliation after an uncertain acknowledgement.
      if (mounted && widget.mutationAllowed()) widget.onChanged();
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _registryChanges?.removeListener(_onRegistryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LearningGoalStatus>(
      key: ValueKey<String>('learning-goal/${widget.goal.id}/status'),
      tooltip: 'เปลี่ยนสถานะเป้าหมาย',
      onOpened: () {
        _menuOpen = true;
        widget.onMenuOpen(true);
      },
      onCanceled: () {
        _menuOpen = false;
        widget.onMenuOpen(false);
      },
      onSelected: _update,
      itemBuilder: (_) => LearningGoalStatus.values
          .where((status) => status != widget.goal.status)
          .map(
            (status) => PopupMenuItem(
              value: status,
              child: Text(_goalStatusLabel(status)),
            ),
          )
          .toList(growable: false),
      child: Text(_goalStatusLabel(widget.goal.status)),
    );
  }
}
