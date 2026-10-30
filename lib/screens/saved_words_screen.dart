import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/vocabulary/application/saved_words_use_cases.dart';
import '../features/vocabulary/domain/saved_words.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../widgets/adaptive_content_pane.dart';
import 'quiz_screen.dart';

/// UI state shared by the vocabulary list and the saved list. The repository
/// remains the only saved-word writer; unresolved retries keep their command.
final class SavedWordsViewBinding extends ChangeNotifier {
  SavedWordsViewBinding({
    required this.useCases,
    required this.ownerChanges,
    required this.visible,
    String? expectedOwnerId,
  }) : _ownerId = expectedOwnerId {
    _owners = ownerChanges.listen(
      _ownerChanged,
      onError: (Object _, StackTrace _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
  }

  final SavedWordsUseCases useCases;
  final Stream<String?> ownerChanges;
  final bool Function() visible;
  StreamSubscription<String?>? _owners;
  StreamSubscription<SavedWordsSnapshot>? _rows;
  String? _ownerId;
  bool ownerKnown = false;
  bool ownerObserved = false;
  bool blocked = false;
  bool loading = false;
  bool readFailed = false;
  bool _wasVisible = false;
  bool _closed = false;
  bool _notificationScheduled = false;
  int generation = 0;
  int ownerGeneration = 0;
  SavedWordsSnapshot? snapshot;
  final _pending = <String, SavedWordsPending>{};
  final _states = <String, SavedWordState>{};
  final _conflicts = <String>{};
  Future<void>? _closeFuture;

  String? get ownerId => _ownerId;
  bool get current =>
      !_closed && !blocked && ownerKnown && _ownerId != null && visible();
  bool get ready => current && snapshot != null && !readFailed;
  bool isCurrent(int epoch) => current && epoch == generation;
  bool get hasPending => _pending.isNotEmpty;
  Iterable<MapEntry<String, SavedWordsPending>> get pending => _pending.entries;
  Iterable<String> get conflicts => _conflicts;
  SavedWordsPending? pendingFor(String wordId) => _pending[wordId];
  bool conflicted(String wordId) => _conflicts.contains(wordId);
  SavedWordState? stateFor(String wordId) =>
      _states[wordId] ?? snapshot?.stateFor(wordId);

  void _ownerChanged(String? value) {
    if (_closed) {
      return;
    }
    ownerObserved = true;
    if (value == null) {
      ownerGeneration++;
      ownerKnown = false;
      _invalidate();
      return;
    }
    if (_ownerId != null && _ownerId != value) {
      ownerGeneration++;
      blocked = true;
      ownerKnown = false;
      _invalidate();
      return;
    }
    if (blocked) {
      return;
    }
    if (!ownerKnown) {
      ownerGeneration++;
      _ownerId = value;
      ownerKnown = true;
      generation++;
    }
    syncVisibility();
  }

  void _invalidate() {
    generation++;
    _clearRows();
    _notify();
  }

  void _clearRows() {
    final rows = _rows;
    _rows = null;
    unawaited(rows?.cancel());
    snapshot = null;
    _states.clear();
    _conflicts.clear();
    loading = false;
    readFailed = false;
  }

  void syncVisibility() {
    if (_closed) {
      return;
    }
    final nowVisible = visible();
    if (_wasVisible && !nowVisible) {
      _invalidate();
    }
    _wasVisible = nowVisible;
    if (current && _rows == null && !readFailed) {
      _watch();
    } else {
      _notify();
    }
  }

  void _watch() {
    final epoch = generation;
    final owner = _ownerId!;
    loading = true;
    _notify();
    _rows = useCases
        .watchOwner(owner)
        .listen(
          (value) {
            if (!isCurrent(epoch)) {
              return;
            }
            if (value.ownerId != owner) {
              ownerKnown = false;
              blocked = true;
              _invalidate();
              return;
            }
            snapshot = value;
            loading = false;
            readFailed = false;
            _states.removeWhere(
              (id, state) =>
                  value.stateFor(id).localRevision >= state.localRevision,
            );
            _notify();
          },
          onError: (Object _, StackTrace _) {
            if (!isCurrent(epoch)) {
              return;
            }
            snapshot = null;
            loading = false;
            readFailed = true;
            _notify();
          },
          onDone: () {
            if (!isCurrent(epoch)) {
              return;
            }
            _rows = null;
            snapshot = null;
            loading = false;
            readFailed = true;
            _notify();
          },
        );
  }

  void retryRead() {
    if (!current) {
      return;
    }
    _invalidate();
    _watch();
  }

  Future<void> setSaved(String wordId, bool desired, int epoch) async {
    if (!ready ||
        !isCurrent(epoch) ||
        _pending.containsKey(wordId) ||
        conflicted(wordId)) {
      return;
    }
    final state = stateFor(wordId);
    if (state == null || state.ownerId != ownerId) {
      return;
    }
    try {
      final command = useCases.prepareSet(
        state: state,
        desiredIsSaved: desired,
      );
      final pending = SavedWordsPending(command);
      _pending[wordId] = pending;
      await _apply(pending, epoch);
    } on Object {
      if (isCurrent(epoch)) {
        readFailed = true;
        snapshot = null;
        _notify();
      }
    }
  }

  Future<void> retry(String wordId, int epoch) async {
    final pending = _pending[wordId];
    if (!ready || !isCurrent(epoch) || pending == null || pending.busy) {
      return;
    }
    await _apply(pending, epoch);
  }

  Future<void> _apply(SavedWordsPending pending, int epoch) async {
    final command = pending.command;
    pending.busy = true;
    pending.failed = false;
    _notify();
    try {
      final result = await useCases.apply(command);
      if (!isCurrent(epoch)) {
        return;
      }
      if (result.state.ownerId != ownerId ||
          result.state.wordId != command.wordId) {
        throw const SavedWordsException(SavedWordsFailureCode.unavailable);
      }
      _pending.remove(command.wordId);
      _states[command.wordId] = result.state;
      if (result.status == SavedWordApplyStatus.conflict) {
        _conflicts.add(command.wordId);
      }
      _notify();
    } on Object {
      if (isCurrent(epoch)) {
        pending.busy = false;
        pending.failed = true;
        _notify();
      }
    } finally {
      if (!_closed &&
          identical(_pending[command.wordId], pending) &&
          pending.busy) {
        // A stale ACK may have committed. Only the original command can retry.
        pending.busy = false;
        pending.failed = true;
        _notify();
      }
    }
  }

  void _notify() {
    if (_closed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationScheduled) {
        return;
      }
      _notificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_closed) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    generation++;
    final owners = _owners;
    final rows = _rows;
    _owners = null;
    _rows = null;
    await Future.wait([
      if (owners != null) owners.cancel(),
      if (rows != null) rows.cancel(),
    ]);
    super.dispose();
  }
}

final class SavedWordsPending {
  SavedWordsPending(this.command);
  final SavedWordMutation command;
  bool busy = true;
  bool failed = false;
}

class SavedWordsScreen extends StatefulWidget {
  const SavedWordsScreen({
    super.key,
    required this.expectedOwnerId,
    this.savedWords,
    this.learning,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final String expectedOwnerId;
  final SavedWordsUseCases? savedWords;
  final LearningUseCases? learning;
  final Stream<String?>? ownerChanges;
  final String languageCode;

  @override
  State<SavedWordsScreen> createState() => _SavedWordsScreenState();
}

class _SavedWordsScreenState extends State<SavedWordsScreen>
    with WidgetsBindingObserver {
  AppDependencies? _dependencies;
  SavedWordsUseCases? _cases;
  LearningUseCases? _learning;
  Stream<String?>? _owners;
  SavedWordsViewBinding? _binding;
  ModalRoute<dynamic>? _route;
  bool _paneVisible = false;
  bool _foreground = false;
  bool _bound = false;
  bool _invalidated = false;
  bool _opening = false;
  int _lifecycleGeneration = 0;

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _visible =>
      mounted &&
      !_invalidated &&
      _foreground &&
      _paneVisible &&
      _route?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _paneVisible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final cases = widget.savedWords ?? dependencies?.savedWords;
    final learning = widget.learning ?? dependencies?.learning;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _cases = cases;
      _learning = learning;
      _owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (cases != null && _owners != null) {
        _binding = SavedWordsViewBinding(
          useCases: cases,
          ownerChanges: _owners!,
          visible: () => _visible,
          expectedOwnerId: widget.expectedOwnerId,
        )..addListener(_changed);
      }
    } else if (!identical(dependencies, _dependencies) ||
        !identical(cases, _cases) ||
        !identical(learning, _learning)) {
      _invalidateBinding();
    }
    _binding?.syncVisibility();
  }

  @override
  void didUpdateWidget(covariant SavedWordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.savedWords, widget.savedWords) ||
        !identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidateBinding();
    }
  }

  void _invalidateBinding() {
    _invalidated = true;
    final binding = _binding;
    _binding = null;
    binding?.removeListener(_changed);
    unawaited(binding?.close());
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _lifecycleGeneration++;
    }
    _foreground = state == AppLifecycleState.resumed;
    _binding?.syncVisibility();
    _changed();
  }

  @override
  void dispose() {
    _invalidateBinding();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(
        context,
        _text('คำศัพท์ที่บันทึก', 'Saved words'),
      ),
    ),
    body: AdaptiveContentPane(child: _body()),
  );

  Widget _body() {
    final binding = _binding;
    if (binding == null ||
        _invalidated ||
        binding.blocked ||
        (!binding.current && binding.ownerObserved)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _text(
              'รายการนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่',
              'This list is unavailable. Go back and open it again.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (binding.readFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _text(
                'อ่านคำศัพท์ที่บันทึกไม่สำเร็จ',
                'Could not load saved words.',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('saved-read-retry'),
              onPressed: binding.retryRead,
              child: Text(_text('ลองใหม่', 'Retry')),
            ),
          ],
        ),
      );
    }
    final snapshot = binding.snapshot;
    if (!binding.ready || snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('saved-loading')),
      );
    }
    final epoch = binding.generation;
    final eligible = snapshot.savedItems
        .where((item) => item.isEligible)
        .take(20)
        .toList(growable: false);
    final canQuiz =
        _learning != null &&
        (_dependencies == null ||
            _dependencies!.fieldFeatures.isVisible(FieldFeature.quiz));
    return ListView(
      key: const ValueKey('saved-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _text(
            'เลือกได้สูงสุด 20 คำที่พร้อมใช้ต่อรอบ',
            'Up to 20 currently available words per round.',
          ),
        ),
        const SizedBox(height: 12),
        if (eligible.isNotEmpty && canQuiz)
          FilledButton.icon(
            key: const ValueKey('saved-practice'),
            onPressed: _opening || binding.hasPending
                ? null
                : () => _practice(
                    binding,
                    epoch,
                    eligible.map((item) => item.wordId).toList(growable: false),
                  ),
            icon: const Icon(Icons.school_outlined),
            label: Text(
              _text(
                'เริ่มฝึก (สูงสุด ${eligible.length} คำ)',
                'Start practice (up to ${eligible.length} words)',
              ),
            ),
          ),
        if (!canQuiz && eligible.isNotEmpty)
          Text(_text('การฝึกยังไม่พร้อมใช้งาน', 'Practice is unavailable.')),
        for (final entry in binding.pending)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.value.busy
                        ? _text(
                            'กำลังยืนยันการเปลี่ยนแปลง',
                            'Confirming this change…',
                          )
                        : _text(
                            'ยังยืนยันการเปลี่ยนแปลงไม่ได้ ลองคำสั่งเดิมอีกครั้ง',
                            'This change is unconfirmed. Retry the same command.',
                          ),
                  ),
                  if (entry.value.busy) const LinearProgressIndicator(),
                  if (!entry.value.busy)
                    OutlinedButton(
                      key: ValueKey('saved-retry:${entry.key}'),
                      onPressed: () => binding.retry(entry.key, epoch),
                      child: Text(_text('ลองใหม่', 'Retry')),
                    ),
                ],
              ),
            ),
          ),
        for (final id in binding.conflicts)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(
                      'สถานะเปลี่ยนแล้ว โหลดสถานะล่าสุดก่อนเลือกอีกครั้ง',
                      'The saved state changed. Refresh it, then choose again.',
                    ),
                  ),
                  OutlinedButton(
                    key: ValueKey('saved-refresh-conflict:$id'),
                    onPressed: binding.retryRead,
                    child: Text(
                      _text('โหลดสถานะล่าสุด', 'Refresh saved state'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (snapshot.savedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _text('ยังไม่มีคำศัพท์ที่บันทึก', 'No saved words yet.'),
              key: const ValueKey('saved-empty'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final item in snapshot.savedItems)
          Card(
            child: ListTile(
              title: item.isEligible
                  ? Text(item.word!.spelling)
                  : Text(
                      _text(
                        'คำศัพท์นี้ไม่พร้อมใช้งาน',
                        'This saved word is unavailable.',
                      ),
                      key: ValueKey('saved-unavailable:${item.wordId}'),
                    ),
              subtitle: item.isEligible
                  ? Text(
                      '${item.word!.meaning} · ${item.word!.partOfSpeech}\n${item.categoryName}',
                    )
                  : Text(
                      _text(
                        'นำออกจากที่บันทึกได้',
                        'You can remove this saved entry.',
                      ),
                    ),
              trailing: IconButton(
                key: ValueKey('saved-remove:${item.wordId}'),
                tooltip: _text('นำออกจากที่บันทึก', 'Remove saved word'),
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed:
                    binding.pendingFor(item.wordId) != null ||
                        binding.conflicted(item.wordId)
                    ? null
                    : () => binding.setSaved(item.wordId, false, epoch),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _practice(
    SavedWordsViewBinding binding,
    int epoch,
    List<String> ids,
  ) async {
    final learning = _learning;
    if (learning == null ||
        _opening ||
        binding.hasPending ||
        !binding.isCurrent(epoch) ||
        ids.isEmpty) {
      return;
    }
    final owner = binding.ownerId!;
    final ownerGeneration = binding.ownerGeneration;
    final lifecycleGeneration = _lifecycleGeneration;
    final captured = List<String>.unmodifiable(ids.take(20));
    final dependencies = _dependencies;
    setState(() => _opening = true);
    try {
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'vocabulary/saved-practice',
          builder: (_) {
            if (!mounted ||
                _invalidated ||
                !identical(binding, _binding) ||
                !identical(learning, _learning) ||
                !identical(dependencies, _dependencies) ||
                !binding.ownerKnown ||
                binding.blocked ||
                binding.ownerId != owner ||
                binding.ownerGeneration != ownerGeneration ||
                _lifecycleGeneration != lifecycleGeneration ||
                !_foreground) {
              return const Scaffold(
                body: Center(
                  child: Text('การฝึกไม่พร้อมใช้งาน / Practice unavailable'),
                ),
              );
            }
            return QuizScreen(
              wordIds: captured,
              selectionMode: QuizWordSelectionMode.sourcePractice,
              expectedOwnerId: owner,
              learning: learning,
              ownerChanges: _owners,
            );
          },
        ),
      );
    } on Object {
      if (binding.isCurrent(epoch) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('เปิดการฝึกไม่สำเร็จ', 'Could not open practice.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        _binding?.syncVisibility();
      }
    }
  }
}
