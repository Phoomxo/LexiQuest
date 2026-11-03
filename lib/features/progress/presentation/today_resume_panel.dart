import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../application/progress_use_cases.dart';
import '../domain/learning_history_models.dart';
import 'resume_learning_history_entry.dart';

class TodayResumePanel extends StatefulWidget {
  const TodayResumePanel({
    super.key,
    required this.progress,
    required this.ownerId,
    required this.ownerChanges,
    required this.onOpenHistory,
    required this.onResume,
  });

  final ProgressUseCases progress;
  final String? ownerId;
  final Stream<String?> ownerChanges;
  final Future<void> Function() onOpenHistory;
  final Future<void> Function(
    LearningHistoryEntry entry,
    String ownerId,
    bool Function() stillCurrent,
  )
  onResume;

  @override
  State<TodayResumePanel> createState() => _TodayResumePanelState();
}

class _TodayResumePanelState extends State<TodayResumePanel>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _owners;
  AppDependencies? _dependencies;
  ModalRoute<Object?>? _route;
  LearningHistorySnapshot? _history;
  var _configured = false;
  var _ownerObserved = false;
  var _retired = false;
  var _foreground = true;
  var _covered = false;
  var _opening = false;
  var _failed = false;
  var _read = 0;

  bool get _visible =>
      mounted &&
      _configured &&
      _ownerObserved &&
      widget.ownerId != null &&
      !_retired &&
      _foreground &&
      (_route?.isCurrent ?? true) &&
      Visibility.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _owners = widget.ownerChanges.listen(
      (owner) {
        if (owner == null || owner != widget.ownerId) {
          _retire();
          return;
        }
        _ownerObserved = true;
        _invalidate();
        unawaited(_reload());
      },
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_configured && !identical(dependencies, _dependencies)) ||
        (dependencies?.progress != null &&
            !identical(dependencies!.progress, widget.progress))) {
      _retire();
      return;
    }
    _dependencies = dependencies;
    _route = ModalRoute.of(context);
    if (!_configured) {
      _configured = true;
      unawaited(_reload());
    }
    if (!_visible && !_covered) {
      _covered = true;
      _invalidate();
    } else if (_visible && _covered) {
      _covered = false;
      unawaited(_reload());
    }
  }

  @override
  void didUpdateWidget(TodayResumePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.progress, oldWidget.progress) ||
        widget.ownerId != oldWidget.ownerId ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges)) {
      _retire();
    }
  }

  void _invalidate() {
    _read++;
    if (mounted) {
      setState(() {
        _history = null;
        _failed = false;
      });
    }
  }

  void _retire() {
    _retired = true;
    _invalidate();
    unawaited(_owners?.cancel());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (_foreground) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    if (!_visible) {
      return;
    }
    final read = ++_read;
    bool current() => _visible && read == _read;
    setState(() {
      _history = null;
      _failed = false;
    });
    try {
      final history = await widget.progress.loadHistoryForOwner(
        expectedOwnerId: widget.ownerId!,
        stillCurrent: current,
      );
      if (current() && history.ownerId == widget.ownerId) {
        setState(() => _history = history);
      }
    } on Object {
      if (current()) {
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _resume(
    LearningHistoryEntry displayed,
    LearningHistorySnapshot history,
    int read,
  ) async {
    final dependencies = _dependencies;
    bool launchCurrent() =>
        _visible && read == _read && identical(history, _history);
    if (!launchCurrent() || _opening) return;
    bool activityCurrent() =>
        mounted &&
        !_retired &&
        _ownerObserved &&
        widget.ownerId == history.ownerId &&
        identical(dependencies, AppDependenciesScope.maybeOf(context));
    var failed = false;
    setState(() => _opening = true);
    try {
      final fresh = await widget.progress.loadHistoryForOwner(
        expectedOwnerId: history.ownerId,
        stillCurrent: launchCurrent,
      );
      if (!launchCurrent() || fresh.ownerId != history.ownerId) return;
      final matches = fresh.entries.where(
        (entry) =>
            entry.sessionId == displayed.sessionId &&
            entry.activityType == displayed.activityType &&
            entry.state == 'active' &&
            canOpenLearningHistoryEntry(entry),
      );
      if (matches.isEmpty) throw StateError('Session is unavailable');
      await widget.onResume(matches.first, history.ownerId, activityCurrent);
    } on Object {
      if (launchCurrent()) {
        failed = true;
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
      if (_visible && !failed) unawaited(_reload());
    }
  }

  Future<void> _openHistory() async {
    final history = _history;
    if (!_visible || _opening || history == null) {
      return;
    }
    final read = _read;
    bool current() => _visible && read == _read && identical(history, _history);
    setState(() => _opening = true);
    try {
      final fresh = await widget.progress.loadHistoryForOwner(
        expectedOwnerId: widget.ownerId!,
        stillCurrent: current,
      );
      if (!current() || fresh.ownerId != widget.ownerId) {
        return;
      }
      await widget.onOpenHistory();
    } on Object {
      if (current()) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
      if (_visible) {
        unawaited(_reload());
      }
    }
  }

  @override
  void dispose() {
    _retired = true;
    _read++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_owners?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired || widget.ownerId == null) {
      return const SizedBox.shrink();
    }
    final history = _history;
    final read = _read;
    final eligible = history?.entries.where(
      (entry) => entry.state == 'active' && canOpenLearningHistoryEntry(entry),
    );
    final entry = eligible == null || eligible.isEmpty ? null : eligible.first;
    if (history != null && entry == null && !_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'ไม่มีกิจกรรมที่เล่นต่อได้ในประวัติล่าสุด',
              key: ValueKey('today-resume-count'),
            ),
            TextButton.icon(
              key: const ValueKey('today-resume-open-history'),
              onPressed: _visible && !_opening ? _openHistory : null,
              icon: const Icon(Icons.history),
              label: const Text('ดูประวัติ'),
            ),
          ],
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'กิจกรรมที่ทำค้างไว้',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (_failed) ...[
              const Text(
                'อ่านกิจกรรมที่ทำค้างไว้ไม่สำเร็จ',
                key: ValueKey('today-resume-error'),
              ),
              TextButton.icon(
                onPressed: _visible && !_opening ? _reload : null,
                icon: const Icon(Icons.refresh),
                label: const Text('อ่านใหม่'),
              ),
            ] else if (history == null)
              const Text('กำลังอ่านประวัติกิจกรรมล่าสุด')
            else ...[
              Text(
                '${learningHistoryActivityName(entry!.activityType)} · เริ่มล่าสุด',
                key: const ValueKey('today-resume-count'),
              ),
              Text('ตอบแล้ว ${entry.answerCount} คำตอบ'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('today-resume-start'),
                onPressed: _visible && !_opening
                    ? () => _resume(entry, history, read)
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(_opening ? 'กำลังเปิด' : 'เล่นต่อ'),
              ),
              TextButton.icon(
                key: const ValueKey('today-resume-open-history'),
                onPressed: _visible && !_opening ? _openHistory : null,
                icon: const Icon(Icons.history),
                label: const Text('ดูประวัติ'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
