import 'package:flutter/material.dart';

import '../features/goals/application/learning_goal_use_cases.dart';
import '../features/goals/domain/learning_goal.dart';
import '../features/goals/domain/learning_goal_repository.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';

final class LearningGoalsScreen extends StatefulWidget {
  const LearningGoalsScreen({super.key, this.useCases});

  final LearningGoalUseCases? useCases;

  @override
  State<LearningGoalsScreen> createState() => _LearningGoalsScreenState();
}

final class _LearningGoalsScreenState extends State<LearningGoalsScreen> {
  Future<List<LearningGoal>>? _goals;

  LearningGoalUseCases? _resolveUseCases() =>
      widget.useCases ?? AppDependenciesScope.maybeOf(context)?.learningGoals;

  FeatureRegistry? _resolveFeatureRegistry() =>
      AppDependenciesScope.maybeOf(context)?.features;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _goals ??= _resolveUseCases()?.list();
  }

  void _reload(LearningGoalUseCases useCases) {
    setState(() {
      _goals = useCases.list();
    });
  }

  Future<void> _createGoal(
    LearningGoalUseCases useCases,
    FeatureRegistry? registry,
    LearningGoalMutationGuard mutationAllowed,
  ) async {
    final created = await showDialog<LearningGoal>(
      context: context,
      builder: (_) => _CreateLearningGoalDialog(
        useCases: useCases,
        registry: registry,
        mutationAllowed: mutationAllowed,
      ),
    );
    if (created != null && mounted) _reload(useCases);
  }

  @override
  Widget build(BuildContext context) {
    final useCases = _resolveUseCases();
    final registry = _resolveFeatureRegistry();
    final allowWithoutRegistry = widget.useCases != null;
    bool mutationAllowed() =>
        registry?.isEnabled(Feature.studyPlanning) ?? allowWithoutRegistry;
    return Scaffold(
      appBar: AppBar(title: const Text('Learning goals')),
      floatingActionButton: useCases == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey<String>('learning-goals/add'),
              onPressed: () => _createGoal(useCases, registry, mutationAllowed),
              icon: const Icon(Icons.add),
              label: const Text('Add goal'),
            ),
      body: useCases == null
          ? const Center(child: Text('Learning goals are unavailable.'))
          : FutureBuilder<List<LearningGoal>>(
              future: _goals,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Learning goals unavailable.'),
                  );
                }
                final goals = snapshot.data ?? const <LearningGoal>[];
                if (goals.isEmpty) {
                  return const Center(
                    child: Text('No language-learning deadlines yet.'),
                  );
                }
                return ListView.builder(
                  itemCount: goals.length,
                  itemBuilder: (context, index) {
                    final goal = goals[index];
                    final countdown = useCases.countdown(goal);
                    final label = switch (countdown.state) {
                      LearningGoalDeadlineState.future =>
                        '${countdown.days} days remaining',
                      LearningGoalDeadlineState.today => 'Due today',
                      LearningGoalDeadlineState.past =>
                        '${countdown.days} days past deadline',
                    };
                    return ListTile(
                      key: ValueKey<String>('learning-goal/${goal.id}'),
                      title: Text(goal.title),
                      subtitle: Text('${goal.kind.name} · $label'),
                      trailing: _LearningGoalStatusMenu(
                        goal: goal,
                        useCases: useCases,
                        registry: registry,
                        mutationAllowed: mutationAllowed,
                        onChanged: () => _reload(useCases),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

final class _CreateLearningGoalDialog extends StatefulWidget {
  const _CreateLearningGoalDialog({
    required this.useCases,
    required this.registry,
    required this.mutationAllowed,
  });

  final LearningGoalUseCases useCases;
  final FeatureRegistry? registry;
  final LearningGoalMutationGuard mutationAllowed;

  @override
  State<_CreateLearningGoalDialog> createState() =>
      _CreateLearningGoalDialogState();
}

final class _CreateLearningGoalDialogState
    extends State<_CreateLearningGoalDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _deadline = TextEditingController();
  final TextEditingController _timezone = TextEditingController();
  LearningGoalKind _kind = LearningGoalKind.languageTest;
  LearningGoalCreateCommand? _pendingCommand;
  bool _submitting = false;
  String? _validationMessage;

  Listenable? get _registryChanges =>
      widget.registry is Listenable ? widget.registry as Listenable : null;

  @override
  void initState() {
    super.initState();
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
    _deadline.dispose();
    _timezone.dispose();
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
        final deadline = DateTime.parse(_deadline.text);
        if (!deadline.isUtc || !_deadline.text.endsWith('Z')) {
          throw const FormatException(
            'Deadline must use an explicit UTC Z suffix.',
          );
        }
        final timezone = LearningGoalUseCases.timezoneContext(
          _timezone.text,
          deadline,
        );
        command = widget.useCases.prepareCreate(
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
    } on LearningGoalMutationUnavailable {
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationMessage = _pendingCommand == null
            ? 'Enter a canonical title, UTC deadline, and timezone.'
            : 'Creation was not confirmed. Retry uses the same details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = _pendingCommand == null && !_submitting;
    return AlertDialog(
      title: const Text('Add learning goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<LearningGoalKind>(
              key: const ValueKey<String>('learning-goals/kind'),
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Goal type'),
              items: LearningGoalKind.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(growable: false),
              onChanged: fieldsEnabled
                  ? (value) {
                      if (value != null) _kind = value;
                    }
                  : null,
            ),
            TextField(
              key: const ValueKey<String>('learning-goals/title'),
              controller: _title,
              enabled: fieldsEnabled,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              key: const ValueKey<String>('learning-goals/deadline'),
              controller: _deadline,
              enabled: fieldsEnabled,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Deadline (UTC)',
                hintText: '2026-09-01T05:00:00Z',
              ),
            ),
            TextField(
              key: const ValueKey<String>('learning-goals/timezone'),
              controller: _timezone,
              enabled: fieldsEnabled,
              decoration: const InputDecoration(
                labelText: 'Learning timezone',
                hintText: 'Asia/Bangkok',
              ),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('learning-goals/create'),
          onPressed: _submitting ? null : _submit,
          child: Text(_pendingCommand == null ? 'Create' : 'Retry'),
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
      tooltip: 'Update goal status',
      onOpened: () => _menuOpen = true,
      onCanceled: () => _menuOpen = false,
      onSelected: _update,
      itemBuilder: (_) => LearningGoalStatus.values
          .where((status) => status != widget.goal.status)
          .map(
            (status) => PopupMenuItem(value: status, child: Text(status.name)),
          )
          .toList(growable: false),
      child: Text(widget.goal.status.name),
    );
  }
}
