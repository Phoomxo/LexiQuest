import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../screens/dictation_quiz_screen.dart';
import '../../../screens/fill_in_the_blanks_screen.dart';
import '../../../screens/score_screen.dart';
import '../../../screens/sentence_scramble_screen.dart';
import '../../../screens/word_scramble_screen.dart';
import '../../learning_time/application/learning_time_use_cases.dart';
import '../../voice/application/voice_use_cases.dart';
import '../application/learning_use_cases.dart';
import '../domain/learning_models.dart';
import '../domain/learning_time_admission.dart';

/// Reads an existing local checkpoint. Each lesson reissues its own private
/// capability before accepting edits or admitting foreground learning time.
class NativeExerciseResumeScreen extends StatefulWidget {
  const NativeExerciseResumeScreen({
    super.key,
    required this.sessionId,
    required this.expectedOwnerId,
    required this.learning,
    required this.stillCurrent,
    this.ownerChanges,
    this.voice,
    this.learningTime,
    this.languageCode = 'th',
  });

  final String sessionId;
  final String expectedOwnerId;
  final LearningUseCases learning;
  final bool Function() stillCurrent;
  final Stream<String?>? ownerChanges;
  final VoiceUseCases? voice;
  final LearningTimeUseCases? learningTime;
  final String languageCode;

  @override
  State<NativeExerciseResumeScreen> createState() =>
      _NativeExerciseResumeScreenState();
}

class _NativeExerciseResumeScreenState extends State<NativeExerciseResumeScreen>
    with WidgetsBindingObserver {
  final _childOwners = StreamController<String?>.broadcast(sync: true);
  late final Stream<String?> _childOwnerStream = Stream<String?>.multi((sink) {
    final subscription = _childOwners.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    if (_ownerKnown) sink.add(_ownerId);
    sink.onCancel = subscription.cancel;
  });
  StreamSubscription<String?>? _owners;
  AppDependencies? _dependencies;
  ModalRoute<dynamic>? _route;
  NativeExerciseState? _state;
  bool _bound = false;
  bool _ownerKnown = false;
  String? _ownerId;
  bool _requested = false;
  bool _unavailable = false;
  bool _loaderRetired = false;
  int _generation = 0;

  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;
  bool get _scopeCurrent =>
      mounted &&
      !_unavailable &&
      (!_ownerKnown || _ownerId == widget.expectedOwnerId) &&
      widget.stillCurrent() &&
      identical(_dependencies, AppDependenciesScope.maybeOf(context)) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _readCurrent(int generation) =>
      _scopeCurrent &&
      !_loaderRetired &&
      generation == _generation &&
      _route?.isCurrent == true &&
      Visibility.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final route = ModalRoute.of(context);
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _route = route;
      final source =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (source == null) {
        _unavailable = true;
      } else {
        _owners = source.listen(
          _ownerChanged,
          onError: (Object _, StackTrace _) => _retire(),
          onDone: _retire,
        );
      }
    } else if (!identical(dependencies, _dependencies) ||
        !identical(route, _route)) {
      _retire();
    } else if (!visible && _requested) {
      // A lesson owns its own route/dialog lease after reissue. The loader's
      // private handle is retired permanently, without retiring that lesson.
      _loaderRetired = true;
      if (_state == null || _state?.completedSummary != null) _retire();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryRead());
  }

  @override
  void didUpdateWidget(covariant NativeExerciseResumeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionId != oldWidget.sessionId ||
        widget.expectedOwnerId != oldWidget.expectedOwnerId ||
        !identical(widget.learning, oldWidget.learning) ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges) ||
        !identical(widget.stillCurrent, oldWidget.stillCurrent) ||
        !identical(widget.voice, oldWidget.voice) ||
        !identical(widget.learningTime, oldWidget.learningTime) ||
        widget.languageCode != oldWidget.languageCode) {
      _retire();
    }
  }

  void _ownerChanged(String? ownerId) {
    if (!mounted || _unavailable) return;
    if (ownerId != widget.expectedOwnerId ||
        (_ownerKnown && ownerId != _ownerId)) {
      _retire();
      return;
    }
    _ownerKnown = true;
    _ownerId = ownerId;
    _childOwners.add(ownerId);
    _tryRead();
  }

  void _retire() {
    if (!mounted || _unavailable) return;
    _generation++;
    _loaderRetired = true;
    _childOwners.add(null);
    setState(() {
      _unavailable = true;
      _state = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _retire();
  }

  Future<void> _tryRead() async {
    final generation = _generation;
    if (_requested || !_readCurrent(generation)) return;
    _requested = true;
    try {
      final state = await widget.learning.resumeNativeExercise(
        sessionId: widget.sessionId,
        expectedOwnerId: widget.expectedOwnerId,
        stillCurrent: () => _readCurrent(generation),
      );
      if (!_readCurrent(generation)) return;
      // Broadcast owner sources may have emitted before this route subscribed.
      // Only the successful canonical SELECT supplies the initial replay.
      if (!_ownerKnown) {
        _ownerKnown = true;
        _ownerId = state.exercise.ownerId;
      }
      if (state.phase == NativeCheckpointPhase.abandoned) {
        _retire();
      } else {
        setState(() => _state = state);
      }
    } catch (_) {
      if (mounted && generation == _generation) _retire();
    }
  }

  void _back() {
    if (mounted && _route?.isCurrent == true) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _generation++;
    _loaderRetired = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_owners?.cancel());
    unawaited(_childOwners.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (_unavailable || !widget.stillCurrent()) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_copy('รอบฝึกในเครื่อง', 'Local lesson')),
          leading: BackButton(onPressed: _back),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(
              _copy(
                'ไม่สามารถเปิดรอบฝึกนี้ได้ ข้อมูลอาจไม่มีในเครื่อง เปลี่ยนไป หรือไม่ใช่ของบัญชีปัจจุบัน',
                'This lesson is unavailable. Its local checkpoint may be missing, changed, or owned by another account.',
              ),
              key: const ValueKey('native-resume-unavailable'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (state == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: _back)),
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: _copy(
              'กำลังอ่านรอบฝึกในเครื่อง',
              'Reading the local lesson',
            ),
          ),
        ),
      );
    }
    final summary = state.completedSummary;
    if (summary != null) {
      return ScoreScreen(
        correctAnswers: summary.correctCount,
        wrongAnswers: summary.wrongCount,
        score: summary.score,
        onBack: _back,
        learningTime:
            state.exercise is DictationSession || state.exercise is ClozeSession
            ? widget.learningTime
            : null,
        resultOwnerId: widget.expectedOwnerId,
        resultSessionId: widget.sessionId,
      );
    }
    return switch (state.exercise) {
      DictationSession exercise => DictationQuizScreen(
        session: exercise,
        learning: widget.learning,
        resumeState: state,
        ownerChanges: _childOwnerStream,
        voice: widget.voice,
        learningTime: widget.learningTime,
        learningTimeCallerContext: LearningTimeCallerContext.ordinary,
        languageCode: widget.languageCode,
      ),
      WordScrambleSession exercise => WordScrambleScreen(
        session: exercise,
        learning: widget.learning,
        resumeState: state,
        ownerChanges: _childOwnerStream,
        languageCode: widget.languageCode,
      ),
      SentenceScrambleSession exercise => SentenceScrambleScreen(
        session: exercise,
        learning: widget.learning,
        resumeState: state,
        ownerChanges: _childOwnerStream,
        voice: widget.voice,
        languageCode: widget.languageCode,
      ),
      ClozeSession exercise => FillInTheBlanksScreen(
        session: exercise,
        learning: widget.learning,
        resumeState: state,
        ownerChanges: _childOwnerStream,
        learningTime: widget.learningTime,
        learningTimeCallerContext: LearningTimeCallerContext.ordinary,
        languageCode: widget.languageCode,
      ),
    };
  }
}
