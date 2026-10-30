import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/domain/learning_history_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';
import 'quiz_screen.dart';

typedef LearningHistoryLoader =
    Future<LearningHistorySnapshot> Function({LearningHistoryCursor? before});

class LearningHistoryScreen extends StatefulWidget {
  const LearningHistoryScreen({super.key, this.loader, this.ownerChanges});

  final LearningHistoryLoader? loader;
  final Stream<String?>? ownerChanges;

  @override
  State<LearningHistoryScreen> createState() => _LearningHistoryScreenState();
}

class _LearningHistoryScreenState extends State<LearningHistoryScreen>
    with WidgetsBindingObserver {
  ProgressUseCases? _progress;
  LearningHistoryLoader? _loader;
  Stream<String?>? _ownerChanges;
  StreamSubscription<String?>? _ownerSubscription;
  LearningHistorySnapshot? _history;
  String? _observedOwner;
  bool _ownerKnown = false;
  bool _configured = false;
  bool _loading = true;
  bool _failed = false;
  bool _loadingMore = false;
  bool _moreFailed = false;
  int _generation = 0;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(LearningHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final progress = AppDependenciesScope.maybeOf(context)?.progress;
    final loader = widget.loader ?? progress?.loadHistory;
    if (_configured &&
        _progress == progress &&
        _loader == loader &&
        _ownerChanges == widget.ownerChanges) {
      return;
    }
    _configured = true;
    _progress = progress;
    _loader = loader;
    _ownerChanges = widget.ownerChanges;
    _ownerKnown = false;
    _observedOwner = null;
    unawaited(_ownerSubscription?.cancel());
    _ownerSubscription = (widget.ownerChanges ?? progress?.watchActiveOwnerId())
        ?.listen(
          _ownerChanged,
          onError: (Object error) {
            if (!mounted) return;
            _generation++;
            setState(() {
              _history = null;
              _loading = false;
              _failed = true;
              _loadingMore = false;
            });
          },
        );
    unawaited(_reload());
  }

  void _ownerChanged(String? ownerId) {
    if (!mounted || (_ownerKnown && ownerId == _observedOwner)) return;
    _ownerKnown = true;
    _observedOwner = ownerId;
    unawaited(_reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _history = null;
      _loading = true;
      _failed = false;
      _loadingMore = false;
      _moreFailed = false;
    });
    try {
      final loader = _loader;
      if (loader == null) throw StateError('history dependency unavailable');
      final result = await loader();
      if (!mounted || generation != _generation) return;
      if (_ownerKnown && result.ownerId != _observedOwner) {
        throw LearningHistoryOwnerChanged();
      }
      setState(() {
        _history = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final previous = _history;
    final cursor = previous?.nextCursor;
    final loader = _loader;
    if (_loadingMore || previous == null || cursor == null || loader == null) {
      return;
    }
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final result = await loader(before: cursor);
      if (!mounted || generation != _generation) return;
      if (result.ownerId != previous.ownerId ||
          (_ownerKnown && result.ownerId != _observedOwner)) {
        throw LearningHistoryOwnerChanged();
      }
      final seen = previous.entries.map((entry) => entry.sessionId).toSet();
      setState(() {
        _history = LearningHistorySnapshot(
          ownerId: previous.ownerId,
          entries: [
            ...previous.entries,
            ...result.entries.where((entry) => seen.add(entry.sessionId)),
          ],
          days: result.days,
          nextCursor: result.nextCursor,
        );
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        if (error is LearningHistoryOwnerChanged) {
          _history = null;
          _failed = true;
        } else {
          _moreFailed = true;
        }
      });
    }
  }

  Future<void> _resume(LearningHistoryEntry entry, String ownerId) async {
    if (_resuming ||
        _history?.ownerId != ownerId ||
        (_ownerKnown && _observedOwner != ownerId)) {
      return;
    }
    final generation = _generation;
    final learning = AppDependenciesScope.maybeOf(context)?.learning;
    setState(() => _resuming = true);
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/resume-quiz',
          builder: (_) => QuizScreen(
            resumeSessionId: entry.sessionId,
            expectedOwnerId: ownerId,
            learning: learning,
            ownerChanges: widget.ownerChanges,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resuming = false);
        if (generation == _generation) await _reload();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ownerSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ประวัติการเรียน'),
        actions: [
          IconButton(
            tooltip: 'อ่านประวัติใหม่',
            onPressed: _loading ? null : () => unawaited(_reload()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AdaptiveContentPane(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'กำลังอ่านประวัติการเรียน',
        ),
      );
    }
    if (_failed) {
      return _HistoryMessage(
        message: 'ไม่สามารถอ่านประวัติการเรียนในเครื่องได้',
        onRetry: () => unawaited(_reload()),
      );
    }
    final history = _history;
    if (history == null || history.entries.isEmpty) {
      return const _HistoryMessage(message: 'ยังไม่มีประวัติการเรียน');
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('คำตอบ 7 วันล่าสุด', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'นับตามวันที่ในเครื่อง จากคำตอบที่บันทึกไว้',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            for (final day in history.days)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_date(day.day), style: textTheme.bodyMedium),
                  Text(
                    '${day.answerCount} คำตอบ',
                    style: textTheme.titleMedium,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text('รอบฝึก เรียงจากล่าสุด', style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'แสดงทั้งรอบที่จบแล้วและรอบที่ยังไม่จบ',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        for (final entry in history.entries) ...[
          _HistoryRound(
            entry,
            onResume:
                entry.hasAcceptedQuiz &&
                    entry.state == 'active' &&
                    const {
                      'quiz',
                      'weaknessPractice',
                      'sourcePractice',
                    }.contains(entry.activityType)
                ? _resuming
                      ? null
                      : () => unawaited(_resume(entry, history.ownerId))
                : null,
          ),
          const Divider(height: 1),
        ],
        if (_moreFailed) ...[
          const SizedBox(height: 16),
          const Text('ไม่สามารถอ่านรอบก่อนหน้าได้ ลองโหลดเพิ่มอีกครั้ง'),
        ],
        if (history.hasMore) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loadingMore ? null : () => unawaited(_loadMore()),
              icon: const Icon(Icons.expand_more),
              label: Text(_loadingMore ? 'กำลังอ่านรอบก่อนหน้า' : 'โหลดเพิ่ม'),
            ),
          ),
        ],
      ],
    );
  }
}

class _HistoryRound extends StatelessWidget {
  const _HistoryRound(this.entry, {this.onResume});
  final LearningHistoryEntry entry;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final started = entry.startedAtUtc.toLocal();
    final ended = entry.endedAtUtc?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_mode(entry.activityType), style: textTheme.titleMedium),
          Text(_state(entry.state), style: textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'เริ่ม ${_date(started)} ${_time(started)}',
            style: textTheme.bodyMedium,
          ),
          if (ended != null)
            Text(
              'สิ้นสุด ${_date(ended)} ${_time(ended)}',
              style: textTheme.bodyMedium,
            ),
          const SizedBox(height: 8),
          Text(
            entry.answerCount == 0
                ? 'ยังไม่มีคำตอบ'
                : 'ถูก ${entry.correctCount} จาก ${entry.answerCount} คำตอบ',
            style: textTheme.bodyLarge,
          ),
          if (onResume != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('เล่นต่อ'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('ลองอีกครั้ง')),
          ],
        ],
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _mode(String value) => switch (value) {
  'quiz' || 'meaningChoice' => 'แบบทดสอบ',
  'flashcard' || 'flashcards' => 'แฟลชการ์ด',
  'srsReview' => 'ทบทวนคำศัพท์',
  'listening' => 'ฝึกฟัง',
  'dictation' => 'เขียนตามเสียง',
  'cloze' => 'เติมคำในบริบท',
  'wordScramble' => 'เกมเรียงตัวอักษร',
  'pronunciation' || 'pronunciationTranscript' => 'ฝึกออกเสียง',
  'shadowing' => 'ฝึกพูดตาม',
  'ghostSpelling' => 'ฝึกสะกดคำ',
  'associativeRecall' => 'ฝึกจำคำศัพท์',
  _ => 'ฝึกคำศัพท์',
};

String _state(String value) => switch (value) {
  'completed' => 'จบแล้ว',
  'active' => 'ยังไม่จบ',
  'abandoned' => 'หยุดไว้',
  _ => 'สถานะไม่ระบุ',
};
