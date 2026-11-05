import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/matching_use_cases.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/matching_exercise.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../runtime/app_dependencies.dart';
import 'score_screen.dart';

class MatchingQuizScreen extends StatefulWidget {
  const MatchingQuizScreen({
    super.key,
    required this.matching,
    required this.expectedOwnerId,
    required this.ownerChanges,
    this.preparedPlan,
    this.resumeSessionId,
    this.learning,
    this.learningTime,
    this.languageCode = 'th',
    this.resultBackLabel,
  }) : assert((preparedPlan == null) != (resumeSessionId == null));
  final MatchingUseCases matching;
  final String expectedOwnerId;
  final Stream<String?> ownerChanges;
  final MatchingPlan? preparedPlan;
  final String? resumeSessionId;
  final LearningUseCases? learning;
  final LearningTimeUseCases? learningTime;
  final String languageCode;
  final String? resultBackLabel;

  @override
  State<MatchingQuizScreen> createState() => _MatchingQuizScreenState();
}

class _MatchingQuizScreenState extends State<MatchingQuizScreen>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _owners;
  MatchingState? _state;
  String? _openedSessionId;
  ModalRoute<Object?>? _route;
  AppDependencies? _dependencies;
  bool _configured = false;
  bool _retired = false;
  bool _foreground = true;
  bool _busy = true;
  bool _failed = false;
  int _generation = 0;
  int? _word;
  int? _meaning;
  final Stopwatch _latency = Stopwatch();
  Future<MatchingState> Function()? _retry;
  LearningTimeBinding? _timeBinding;
  int _timeRequest = 0;

  bool get _english => widget.languageCode == 'en';

  bool _current(int generation) {
    if (!mounted || _retired || generation != _generation || !_foreground) {
      return false;
    }
    if (_route?.isCurrent != true) {
      _retired = true;
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _owners = widget.ownerChanges.listen(
      (owner) {
        if (owner != widget.expectedOwnerId) _retire();
      },
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
  }

  void _retire() {
    if (!mounted || _retired) return;
    _retired = true;
    _generation++;
    _latency.stop();
    _timeBinding?.retireDependencies();
    setState(() {
      _state = null;
      _retry = null;
      _word = null;
      _meaning = null;
      _busy = false;
      _failed = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (_configured) {
      if (!identical(_dependencies, dependencies) ||
          !identical(_route, route) ||
          route?.isCurrent != true) {
        _retire();
      }
      return;
    }
    _configured = true;
    _dependencies = dependencies;
    _route = route;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MatchingQuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.matching, widget.matching) ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        oldWidget.preparedPlan != widget.preparedPlan ||
        oldWidget.resumeSessionId != widget.resumeSessionId ||
        oldWidget.learning != widget.learning ||
        oldWidget.learningTime != widget.learningTime) {
      _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_retired || _foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _latency.stop();
      _generation++;
      setState(() {
        _state = null;
        _retry = null;
        _busy = true;
        _failed = false;
        _word = null;
        _meaning = null;
      });
    } else if (_configured) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final prepared = widget.preparedPlan;
    if ((prepared != null &&
            prepared.session.ownerId != widget.expectedOwnerId) ||
        (_dependencies?.matching != null &&
            !identical(_dependencies!.matching, widget.matching))) {
      _retire();
      return;
    }
    final generation = ++_generation;
    if (_retired || !_foreground) return;
    final sessionId = _openedSessionId ?? widget.resumeSessionId;
    Future<MatchingState> load() => sessionId == null
        ? widget.matching.start(
            prepared!,
            stillCurrent: () => _current(generation),
          )
        : widget.matching.resume(
            sessionId: sessionId,
            expectedOwnerId: widget.expectedOwnerId,
            stillCurrent: () => _current(generation),
          );
    await _run(load, generation: generation);
  }

  Future<void> _run(
    Future<MatchingState> Function() operation, {
    int? generation,
  }) async {
    final currentGeneration = generation ?? _generation;
    if (!_current(currentGeneration)) return;
    _timeRequest++;
    _timeBinding?.suspend();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final saved = await operation();
      if (!_current(currentGeneration)) return;
      if (saved.plan.session.ownerId != widget.expectedOwnerId ||
          saved.plan.session.id !=
              (widget.resumeSessionId ?? widget.preparedPlan!.session.id)) {
        throw StateError('Matching session changed');
      }
      setState(() {
        _openedSessionId = saved.plan.session.id;
        _state = saved;
        _word = saved.checkpoint.selectedWord;
        _meaning = saved.checkpoint.selectedMeaning;
        _retry = null;
        _busy = false;
      });
      _latency
        ..reset()
        ..start();
      unawaited(_readyTime());
    } on Object {
      if (!_current(currentGeneration)) return;
      setState(() {
        _retry = operation;
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _readyTime() async {
    final state = _state;
    final learning = widget.learning;
    final time = widget.learningTime;
    final generation = _generation;
    if (state == null ||
        learning == null ||
        time == null ||
        _busy ||
        _failed ||
        state.checkpoint.phase != MatchingPhase.selecting ||
        !_current(generation)) {
      return;
    }
    final binding = _timeBinding ??= LearningTimeBinding(
      time: time,
      expectedOwnerId: widget.expectedOwnerId,
      visible: () =>
          _current(_generation) &&
          TickerMode.valuesOf(context).enabled &&
          Visibility.of(context),
    );
    final request = ++_timeRequest;
    bool current() =>
        request == _timeRequest &&
        identical(state, _state) &&
        !_busy &&
        !_failed &&
        _current(generation);
    try {
      final proof = await learning.admitCanonicalLearningTime(
        MatchingTimeAdmission(
          state,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: widget.expectedOwnerId,
        stillCurrent: current,
      );
      if (current()) {
        await binding.ready(
          CanonicalTimeSource(
            proof,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
        );
      }
    } on Object {
      if (current()) binding.suspend();
    }
  }

  Future<void> _saveSelection({bool submit = false}) async {
    final state = _state;
    if (state == null || _busy || !_current(_generation)) return;
    _timeBinding?.interacted();
    final generation = _generation;
    final word = _word;
    final meaning = _meaning;
    final elapsed = _latency.elapsed;
    MatchingState? selected;
    MatchingState? prepared;
    MatchingCheckpoint? pending;
    Future<MatchingState> operation() async {
      selected ??= await widget.matching.saveSelection(
        state,
        wordIndex: word,
        meaningIndex: meaning,
        stillCurrent: () => _current(generation),
      );
      if (!submit) return selected!;
      pending ??= widget.matching.preparePair(selected!, responseTime: elapsed);
      prepared ??= await widget.matching.save(
        selected!,
        pending!,
        stillCurrent: () => _current(generation),
      );
      return widget.matching.commit(
        prepared!,
        stillCurrent: () => _current(generation),
      );
    }

    await _run(operation);
  }

  Future<void> _commit() async {
    final state = _state;
    final generation = _generation;
    if (state == null) return;
    await _run(
      () => widget.matching.commit(
        state,
        stillCurrent: () => _current(generation),
      ),
    );
  }

  Future<void> _continue() async {
    final state = _state;
    final generation = _generation;
    if (state == null) return;
    if (state.checkpoint.matched.length < state.plan.words.length) {
      await _run(
        () => widget.matching.next(
          state,
          stillCurrent: () => _current(generation),
        ),
      );
    } else {
      final close = widget.matching.prepareFinish(state);
      MatchingState? closing;
      await _run(() async {
        closing ??= await widget.matching.save(
          state,
          close,
          stillCurrent: () => _current(generation),
        );
        return widget.matching.finish(
          closing!,
          stillCurrent: () => _current(generation),
        );
      });
    }
  }

  Future<void> _finish() async {
    final state = _state;
    final generation = _generation;
    if (state == null) return;
    await _run(
      () => widget.matching.finish(
        state,
        stillCurrent: () => _current(generation),
      ),
    );
  }

  @override
  void dispose() {
    _retired = true;
    _generation++;
    _latency.stop();
    _timeBinding?.dispose();
    unawaited(_owners?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _timeBinding?.syncVisibility();
    final state = _state;
    final retry = _retry;
    final summary = state?.completedSummary;
    if (summary != null && !_retired) {
      return ScoreScreen(
        backLabel: widget.resultBackLabel,
        languageCode: widget.languageCode,
        correctAnswers: summary.correctCount,
        wrongAnswers: summary.wrongCount,
        score: summary.score,
        resultOwnerId: widget.expectedOwnerId,
        resultSessionId: summary.id,
        learningTime: widget.learningTime,
      );
    }
    return LessonScaffold(
      title: _english ? 'Match words and meanings' : 'จับคู่คำกับความหมาย',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _english
                    ? 'Select one word and one meaning, then check the pair.'
                    : 'เลือกคำหนึ่งคำและความหมายหนึ่งข้อ แล้วตรวจคู่ที่เลือก',
              ),
              const SizedBox(height: 12),
              Text(
                _english
                    ? 'Recognition practice. This does not update recall mastery or award rewards.'
                    : 'ฝึกการจำแนกคำ ไม่เพิ่มระดับการเรียกคืนคำหรือรับรางวัล',
              ),
              const SizedBox(height: 16),
              if (_busy) const Center(child: CircularProgressIndicator()),
              if (_retired)
                Text(
                  _english
                      ? 'This session is no longer available. Return and open it again.'
                      : 'เซสชันนี้ไม่พร้อมใช้งานแล้ว กรุณากลับและเปิดใหม่',
                  key: const ValueKey('matching-unavailable'),
                ),
              if (_failed && !_retired) ...[
                Text(
                  _english
                      ? 'The operation is unconfirmed. Retry the same operation.'
                      : 'ยังยืนยันการบันทึกไม่ได้ ลองคำสั่งเดิมอีกครั้ง',
                  key: const ValueKey('matching-error'),
                ),
                OutlinedButton(
                  key: const ValueKey('matching-retry'),
                  onPressed: _busy || retry == null
                      ? null
                      : () {
                          if (!_busy && identical(_retry, retry)) _run(retry);
                        },
                  child: Text(_english ? 'Retry' : 'ลองอีกครั้ง'),
                ),
              ],
              if (state != null && !_retired) ..._board(context, state),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _board(BuildContext context, MatchingState state) {
    final plan = state.plan;
    final checkpoint = state.checkpoint;
    final generation = _generation;
    VoidCallback? guarded(VoidCallback? action) => action == null
        ? null
        : () {
            if (identical(state, _state) &&
                !_busy &&
                !_failed &&
                _current(generation)) {
              action();
            }
          };
    final selecting =
        checkpoint.phase == MatchingPhase.selecting && !_busy && !_failed;
    Widget tile(int index, {required bool meaning}) {
      final matched = checkpoint.matched.contains(index);
      final selected = (meaning ? _meaning : _word) == index;
      final label = meaning
          ? plan.words[index].meaning
          : plan.words[index].spelling;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          selected: selected,
          label: matched
              ? '$label ${_english ? 'matched' : 'จับคู่แล้ว'}'
              : null,
          child: OutlinedButton(
            key: ValueKey('matching-${meaning ? 'meaning' : 'word'}-$index'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 64),
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
            ),
            onPressed: guarded(
              !selecting || matched
                  ? null
                  : () {
                      _timeBinding?.interacted();
                      setState(() {
                        if (meaning) {
                          _meaning = selected ? null : index;
                        } else {
                          _word = selected ? null : index;
                        }
                      });
                    },
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (matched)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check, size: 20),
                  ),
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
          ),
        ),
      );
    }

    return [
      Semantics(
        liveRegion: true,
        child: Text(
          _english
              ? '${checkpoint.matched.length} of ${plan.words.length} pairs matched'
              : 'จับคู่แล้ว ${checkpoint.matched.length} จาก ${plan.words.length} คู่',
          key: const ValueKey('matching-progress'),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_english ? 'Words' : 'คำศัพท์'),
                  const SizedBox(height: 8),
                  for (var index = 0; index < plan.words.length; index++)
                    tile(index, meaning: false),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_english ? 'Meanings' : 'ความหมาย'),
                  const SizedBox(height: 8),
                  for (final index in plan.meaningOrder)
                    tile(index, meaning: true),
                ],
              ),
            ),
          ),
        ],
      ),
      if (checkpoint.phase == MatchingPhase.selecting) ...[
        OutlinedButton(
          key: const ValueKey('matching-save-selection'),
          onPressed: guarded(selecting ? _saveSelection : null),
          child: Text(_english ? 'Save selection' : 'บันทึกคู่ที่เลือก'),
        ),
        FilledButton(
          key: const ValueKey('matching-check'),
          onPressed: guarded(
            selecting && _word != null && _meaning != null
                ? () => _saveSelection(submit: true)
                : null,
          ),
          child: Text(_english ? 'Check pair' : 'ตรวจคู่'),
        ),
      ],
      if (checkpoint.phase == MatchingPhase.pending)
        FilledButton(
          key: const ValueKey('matching-confirm'),
          onPressed: guarded(_busy || _failed ? null : _commit),
          child: Text(_english ? 'Save answer' : 'บันทึกคำตอบ'),
        ),
      if (checkpoint.phase == MatchingPhase.answered) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            checkpoint.answer!.isCorrect
                ? (_english ? 'Matched correctly' : 'จับคู่ถูกแล้ว')
                : (_english
                      ? 'These do not match. Try another pair.'
                      : 'คู่นี้ยังไม่ตรงกัน ลองเลือกใหม่'),
            key: const ValueKey('matching-feedback'),
          ),
        ),
        FilledButton(
          key: const ValueKey('matching-continue'),
          onPressed: guarded(_busy || _failed ? null : _continue),
          child: Text(
            checkpoint.matched.length == plan.words.length
                ? (_english ? 'Finish practice' : 'จบแบบฝึก')
                : (_english ? 'Continue' : 'เลือกคู่ต่อไป'),
          ),
        ),
      ],
      if (checkpoint.phase == MatchingPhase.closing)
        FilledButton(
          key: const ValueKey('matching-finish'),
          onPressed: guarded(_busy || _failed ? null : _finish),
          child: Text(_english ? 'Save result' : 'บันทึกผล'),
        ),
      if (checkpoint.phase == MatchingPhase.abandoned)
        Text(
          _english
              ? 'Practice ended without completion.'
              : 'ยุติแบบฝึกโดยยังไม่จบ',
        ),
    ];
  }
}
