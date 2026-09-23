import 'dart:convert';

import 'package:flutter/material.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/ai_tutor/presentation/menu_action_binding.dart';

import '../features/goals/application/learning_goal_use_cases.dart';
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

final class _LearningGoalsScreenState extends State<LearningGoalsScreen> {
  Future<List<LearningGoal>>? _goals;
  ReviewOwnerIdentityReader? _loadedOwnerReader;
  String? _assistanceOwnerId;
  int _readGeneration = 0;
  LearningGoalUseCases? _loadedUseCases;
  Future<bool>? _reminderEntryAvailable;
  Listenable? _registryChanges;
  final Set<String> _deleting = {};
  bool _openingGoal = false;

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
    if (!identical(useCases, _loadedUseCases) ||
        !identical(owners, _loadedOwnerReader) ||
        _goals == null) {
      _loadedUseCases = useCases;
      _loadedOwnerReader = owners;
      _assistanceOwnerId = null;
      _goals = useCases == null ? null : _readGoals(useCases, owners);
    }
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
  ) async {
    final generation = ++_readGeneration;
    _assistanceOwnerId = null;
    final before = await _optionalOwner(owners);
    final goals = await useCases.list();
    final after = before == null ? null : await _optionalOwner(owners);
    if (mounted &&
        generation == _readGeneration &&
        identical(useCases, _loadedUseCases) &&
        before != null &&
        before == after) {
      _assistanceOwnerId = before;
    }
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
    setState(() {
      _goals = _readGoals(useCases, _loadedOwnerReader);
    });
  }

  Future<void> _openReminder(
    LearningGoal goal,
    StudyReminderUseCases reminders,
    StudyReminderMutationGuard mutationAllowed,
  ) async {
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'goals/study-reminder-settings',
        builder: (_) => StudyReminderSettingsScreen(
          useCases: reminders,
          source: StudyReminderSource.goalDeadline(goal.id),
          sourceLabel: goal.title,
          mutationAllowed: mutationAllowed,
        ),
      ),
    );
  }

  Future<void> _createGoal(
    LearningGoalUseCases useCases,
    FeatureRegistry? registry,
    LearningGoalMutationGuard mutationAllowed, {
    LearningGoal? goal,
  }) async {
    if (_openingGoal || !mounted || !mutationAllowed()) return;
    _openingGoal = true;
    try {
      final openingOwnerId = await useCases.activeOwnerId();
      if (!mounted || !mutationAllowed()) return;
      if (openingOwnerId != await useCases.activeOwnerId()) {
        throw const LearningGoalOwnerChanged();
      }
      if (!mounted || !mutationAllowed()) return;
      final created = await showDialog<LearningGoal>(
        context: context,
        builder: (_) => _CreateLearningGoalDialog(
          useCases: useCases,
          registry: registry,
          mutationAllowed: mutationAllowed,
          openingOwnerId: openingOwnerId,
          initialGoal: goal,
        ),
      );
      if (created != null && mounted && mutationAllowed()) _reload(useCases);
    } catch (_) {
      if (mounted && mutationAllowed()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยังเปิดเป้าหมายไม่ได้ กรุณาลองอีกครั้ง'),
          ),
        );
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
      final owner = await useCases.activeOwnerId();
      if (!mutationAllowed()) return;
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
          const SnackBar(content: Text('ยังลบเป้าหมายไม่ได้ กรุณาลองอีกครั้ง')),
        );
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
    bool mutationAllowed() =>
        mounted &&
        identical(useCases, _resolveUseCases()) &&
        (registry?.isEnabled(Feature.studyPlanning) ?? allowWithoutRegistry);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NavigationGlossary.require('study-planning/goals').fullThaiLabel,
        ),
      ),
      floatingActionButton: useCases == null
          ? null
          : compactAddButton
          ? FloatingActionButton(
              key: const ValueKey<String>('learning-goals/add'),
              tooltip: 'เพิ่มเป้าหมาย',
              onPressed: () => _createGoal(useCases, registry, mutationAllowed),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              key: const ValueKey<String>('learning-goals/add'),
              onPressed: () => _createGoal(useCases, registry, mutationAllowed),
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
                    const Center(child: Text('โหลดเป้าหมายการเรียนไม่ได้')),
                  );
                }
                final goals = snapshot.data ?? const <LearningGoal>[];
                if (goals.isEmpty) {
                  return _guidance(
                    'ready',
                    const Center(child: Text('ยังไม่ได้กำหนดเป้าหมายการเรียน')),
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
                                  style: Theme.of(context).textTheme.bodySmall,
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
                                      tooltip: 'ลบเป้าหมายและการเตือนที่ผูกไว้',
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
                                                onPressed: () => _openReminder(
                                                  goal,
                                                  reminders,
                                                  mutationAllowed,
                                                ),
                                                icon: const Icon(
                                                  Icons.notifications_outlined,
                                                ),
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    _LearningGoalStatusMenu(
                                      goal: goal,
                                      useCases: useCases,
                                      registry: registry,
                                      mutationAllowed: mutationAllowed,
                                      onChanged: () => _reload(useCases),
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
    );
  }

  @override
  void dispose() {
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
    this.initialGoal,
  });

  final LearningGoalUseCases useCases;
  final FeatureRegistry? registry;
  final LearningGoalMutationGuard mutationAllowed;
  final String openingOwnerId;
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

  Listenable? get _registryChanges =>
      widget.registry is Listenable ? widget.registry as Listenable : null;

  @override
  void initState() {
    super.initState();
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
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!widget.mutationAllowed()) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _submitting = true;
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
        _pendingCommand = command;
      }
      if (!widget.mutationAllowed()) {
        throw const LearningGoalMutationUnavailable();
      }
      final goal = await widget.useCases.executeCreate(
        command,
        mutationAllowed: widget.mutationAllowed,
      );
      if (mounted) Navigator.of(context).pop(goal);
    } on LearningGoalOwnerChanged {
      _pendingCommand = null;
      if (mounted) Navigator.of(context).pop();
    } on LearningGoalMutationUnavailable {
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationMessage = _pendingCommand == null
            ? 'กรุณาระบุชื่อเป้าหมาย เลือกวันที่ เวลา และเขตเวลาให้ครบ'
            : 'ยังยืนยันการสร้างเป้าหมายไม่ได้ การลองอีกครั้งจะใช้รายละเอียดเดิม';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = _pendingCommand == null && !_submitting;
    return AlertDialog(
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
            decoration: const InputDecoration(labelText: 'ประเภทเป้าหมาย'),
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
                    if (value != null) _kind = value;
                  }
                : null,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey<String>('learning-goals/title'),
            controller: _title,
            enabled: fieldsEnabled,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'ชื่อเป้าหมาย'),
          ),
          const SizedBox(height: 12),
          LocalStudyDateTimeField(
            fieldKey: 'learning-goals/deadline',
            referenceUtc: widget.useCases.nowUtc(),
            enabled: fieldsEnabled,
            initialUtc: widget.initialGoal?.deadlineAtUtc,
            initialTimezoneId:
                widget.initialGoal?.timezone.timezoneId ?? 'Asia/Bangkok',
            onChanged: (instant, zone) {
              _deadlineUtc = instant;
              _timezoneId = zone;
            },
          ),
          if (_validationMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _validationMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          key: ValueKey<String>(
            widget.initialGoal == null
                ? 'learning-goals/create'
                : 'learning-goals/save',
          ),
          onPressed: _submitting ? null : _submit,
          child: Text(
            _pendingCommand != null
                ? 'ลองอีกครั้ง'
                : widget.initialGoal == null
                ? 'สร้างเป้าหมาย'
                : 'บันทึกเป้าหมาย',
          ),
        ),
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
  });

  final LearningGoal goal;
  final LearningGoalUseCases useCases;
  final FeatureRegistry? registry;
  final LearningGoalMutationGuard mutationAllowed;
  final VoidCallback onChanged;

  @override
  State<_LearningGoalStatusMenu> createState() =>
      _LearningGoalStatusMenuState();
}

final class _LearningGoalStatusMenuState
    extends State<_LearningGoalStatusMenu> {
  bool _menuOpen = false;

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
    if (status == widget.goal.status || !widget.mutationAllowed()) return;
    try {
      await widget.useCases.updateStatus(
        widget.goal,
        status,
        mutationAllowed: widget.mutationAllowed,
      );
      if (mounted) widget.onChanged();
    } on LearningGoalMutationUnavailable {
      // A live emergency-off is an expected fail-closed outcome.
    } on Object {
      // The popup closes; a later retry reuses durable semantic idempotency.
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
      onOpened: () => _menuOpen = true,
      onCanceled: () => _menuOpen = false,
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
