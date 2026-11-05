import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning_packs/presentation/rich_lexical_card.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../features/learning_time/presentation/recorded_time_view.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';

class SrsFlashcardsScreen extends StatefulWidget {
  const SrsFlashcardsScreen({
    super.key,
    this.wordList,
    this.sourceWordIds,
    this.packOrigin,
    this.resumeSessionId,
    this.verifySourceOnResume,
    this.voice,
    this.learning,
    this.expectedOwnerId,
    this.ownerChanges,
    this.languageCode = 'th',
    this.learningTime,
    this.timeCallerContext = LearningTimeCallerContext.ordinary,
  }) : assert(wordList == null || sourceWordIds == null),
       assert(
         resumeSessionId == null || (wordList == null && sourceWordIds == null),
       );

  /// A presentation-only snapshot. Preview ratings never create learning facts.
  final List<Map<String, String>>? wordList;
  final List<String>? sourceWordIds;
  final SrsPackOrigin? packOrigin;
  final String? resumeSessionId;
  final Future<void> Function()? verifySourceOnResume;
  final VoiceUseCases? voice;
  final LearningUseCases? learning;
  final String? expectedOwnerId;
  final Stream<String?>? ownerChanges;
  final String languageCode;
  final LearningTimeUseCases? learningTime;
  final LearningTimeCallerContext timeCallerContext;

  @override
  State<SrsFlashcardsScreen> createState() => _SrsFlashcardsScreenState();
}

enum _Step {
  waiting,
  preparing,
  starting,
  loadFailed,
  startFailed,
  empty,
  answering,
  saving,
  saveFailed,
  saved,
  finishing,
  finishFailed,
  completed,
}

class _SrsFlashcardsScreenState extends State<SrsFlashcardsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<Map<String, String>>? _previewInput;
  late final List<_CardText>? _preview;
  late final List<String>? _sourceIds;
  final _latency = Stopwatch();
  final _mistakeWordIds = <String>{};
  final _autoplayed = <int>{};
  final _cardScroll = ScrollController(keepScrollOffset: false);
  double? _resumeOffset;
  AppDependencies? _dependencies;
  LearningUseCases? _learning;
  VoiceUseCases? _voice;
  StreamSubscription<String?>? _owners;
  ModalRoute<dynamic>? _route;
  SrsReviewSession? _review;
  SrsReviewAnswerIntent? _rating;
  SrsReviewFinishIntent? _finish;
  Future<void>? _playbackStop;
  String? _ownerId;
  bool? _selectedRating;
  bool _bound = false;
  bool _ownerRequired = false;
  bool _beginRequested = false;
  bool _invalidated = false;
  bool _routeVisible = false;
  bool _redrawScheduled = false;
  bool _operationPending = false;
  bool _suspended = false;
  int _pauseGeneration = 0;
  bool _isFlipped = false;
  bool _ownsPlayback = false;
  bool _voiceBusy = false;
  bool _voiceFailed = false;
  int _epoch = 0;
  int _audioEpoch = 0;
  int _index = 0;
  int _correctCount = 0;
  _Step _step = _Step.waiting;
  LearningTimeUseCases? _time;
  LearningTimeBinding? _timeBinding;
  LearningSessionSummary? _summary;
  int _timeRequest = 0;

  void _suspendTime() {
    _timeRequest++;
    _timeBinding?.suspend();
  }

  Future<void> _readyTime() async {
    final learning = _learning;
    final review = _review;
    final time = _time;
    final epoch = _epoch;
    final index = _index;
    final flipped = _isFlipped;
    bool ready() =>
        !_isPreview &&
        widget.timeCallerContext == LearningTimeCallerContext.ordinary &&
        _cardCurrent(epoch, index) &&
        _step == _Step.answering &&
        !_operationPending &&
        !_voiceBusy &&
        !_ownsPlayback &&
        _playbackStop == null &&
        _isFlipped == flipped;
    if (learning == null || review == null || time == null || !ready()) return;
    var binding = _timeBinding;
    if (binding == null) {
      binding = LearningTimeBinding(
        time: time,
        expectedOwnerId: review.ownerId,
        visible: () =>
            _current(_epoch) &&
            TickerMode.valuesOf(context).enabled &&
            Visibility.of(context),
      );
      _timeBinding = binding;
    }
    final request = ++_timeRequest;
    bool current() =>
        request == _timeRequest &&
        identical(_timeBinding, binding) &&
        identical(_time, time) &&
        identical(_review, review) &&
        ready();
    try {
      final proof = await learning.admitCanonicalLearningTime(
        OwnedSrsTimeAdmission(
          review,
          cardIndex: index,
          phase: flipped ? SrsTimePhase.revealed : SrsTimePhase.front,
          callerContext: widget.timeCallerContext,
        ),
        expectedOwnerId: review.ownerId,
        stillCurrent: current,
      );
      if (!current()) return;
      await binding.ready(
        CanonicalTimeSource(proof, callerContext: widget.timeCallerContext),
      );
    } on Object {
      if (current()) binding.suspend();
    }
  }

  bool get _isPreview => _preview != null;
  bool get _isSource =>
      _sourceIds != null || _review?.selection == SrsReviewSelection.source;
  int get _length => _preview?.length ?? _review?.words.length ?? 0;
  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sourceIds = widget.sourceWordIds == null
        ? null
        : List<String>.unmodifiable(widget.sourceWordIds!);
    _previewInput = widget.wordList == null
        ? null
        : List<Map<String, String>>.unmodifiable([
            for (final row in widget.wordList!)
              Map<String, String>.unmodifiable(row),
          ]);
    _preview = _previewInput == null
        ? null
        : List<_CardText>.unmodifiable([
            for (final row in _previewInput)
              _CardText(
                row['word'] ?? '',
                row['translation'] ?? '',
                row['example'] ?? '',
              ),
          ]);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  void _redraw() {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_redrawScheduled) {
        return;
      }
      _redrawScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redrawScheduled = false;
        if (mounted) {
          setState(() {});
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if ((_routeVisible && !visible) ||
        !Visibility.of(context) ||
        (_route != null && !identical(route, _route))) {
      _invalidate();
    }
    _route = route;
    _routeVisible = visible;
    final reduced = MediaQuery.disableAnimationsOf(context);
    _controller.duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 400);
    if (reduced && _controller.isAnimating) {
      _controller.value = _isFlipped ? 1 : 0;
    }
    final dependencies = AppDependenciesScope.maybeOf(context);
    final learning = widget.learning ?? dependencies?.learning;
    final voice = widget.voice ?? dependencies?.voice;
    final time = widget.learningTime ?? dependencies?.learningTime;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _learning = learning;
      _voice = voice;
      _time = time;
      final source =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      _ownerRequired = source != null;
      if ((widget.packOrigin != null && _sourceIds == null) ||
          (widget.resumeSessionId != null &&
              (_isPreview ||
                  _sourceIds != null ||
                  widget.expectedOwnerId == null)) ||
          (!_isPreview && (learning == null || source == null)) ||
          (widget.expectedOwnerId != null &&
              (widget.expectedOwnerId!.trim().isEmpty || source == null))) {
        _invalidate();
      } else if (source != null) {
        _owners = source.listen(
          (owner) {
            if (!mounted || _invalidated) {
              return;
            }
            if (owner == null ||
                owner.trim().isEmpty ||
                (widget.expectedOwnerId != null &&
                    owner != widget.expectedOwnerId) ||
                (_ownerId != null && owner != _ownerId)) {
              _invalidate();
              return;
            }
            _ownerId = owner;
            _redraw();
            WidgetsBinding.instance.addPostFrameCallback((_) => _tryBegin());
          },
          onError: (Object _, StackTrace _) => _invalidate(),
          onDone: _invalidate,
        );
      }
    } else if (!identical(_dependencies, dependencies) ||
        !identical(_learning, learning) ||
        !identical(_voice, voice) ||
        !identical(_time, time)) {
      _timeBinding?.retireDependencies();
      _invalidate();
    }
    final timeBinding = _timeBinding;
    final visibility = timeBinding?.visibilityGeneration;
    timeBinding?.syncVisibility();
    if (timeBinding != null && visibility != timeBinding.visibilityGeneration) {
      _timeRequest++;
      if (timeBinding.current) unawaited(_readyTime());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBegin());
  }

  @override
  void didUpdateWidget(covariant SrsFlashcardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rows = widget.wordList;
    final samePreview =
        (_previewInput == null && rows == null) ||
        (_previewInput != null &&
            rows != null &&
            _previewInput.length == rows.length &&
            Iterable<int>.generate(
              rows.length,
            ).every((i) => mapEquals(_previewInput[i], rows[i])));
    if (!identical(oldWidget.learning, widget.learning) ||
        oldWidget.verifySourceOnResume != widget.verifySourceOnResume ||
        !identical(oldWidget.voice, widget.voice) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        oldWidget.resumeSessionId != widget.resumeSessionId ||
        oldWidget.packOrigin != widget.packOrigin ||
        oldWidget.languageCode != widget.languageCode ||
        oldWidget.timeCallerContext != widget.timeCallerContext ||
        !identical(oldWidget.learningTime, widget.learningTime) ||
        !listEquals(_sourceIds, widget.sourceWordIds) ||
        !samePreview) {
      _timeBinding?.retireDependencies();
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _invalidate();
    } else if (state == AppLifecycleState.resumed) {
      _tryBegin();
    } else {
      if (!_suspended && _hasCard && _cardScroll.hasClients) {
        _resumeOffset ??= _cardScroll.offset;
      }
      _pauseGeneration++;
      _suspended = true;
      _latency.stop();
      _suspendTime();
      unawaited(_stopPlayback());
      _redraw();
    }
  }

  bool _scopeCurrent(int epoch) =>
      mounted &&
      !_invalidated &&
      epoch == _epoch &&
      (!_ownerRequired || _ownerId != null) &&
      _routeVisible &&
      _route?.isCurrent == true &&
      Visibility.of(context);

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool _current(int epoch) =>
      _scopeCurrent(epoch) && _foreground && !_suspended;

  bool get _hasCard => switch (_step) {
    _Step.answering ||
    _Step.saving ||
    _Step.saveFailed ||
    _Step.saved ||
    _Step.finishing ||
    _Step.finishFailed => true,
    _ => false,
  };

  bool _cardCurrent(int epoch, int index) =>
      _foreground && !_suspended && _sameCard(epoch, index);

  bool _sameCard(int epoch, int index) =>
      _scopeCurrent(epoch) &&
      _hasCard &&
      index == _index &&
      index >= 0 &&
      index < _length;

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _invalidated = true;
    _timeRequest++;
    _timeBinding?.close();
    _epoch++;
    _latency.stop();
    unawaited(_stopPlayback());
    _redraw();
  }

  void _tryBegin() {
    if (_suspended) {
      unawaited(_resumeStudy());
      return;
    }
    if (_beginRequested || !_current(_epoch)) {
      return;
    }
    _beginRequested = true;
    if (_isPreview) {
      _step = _preview!.isEmpty ? _Step.empty : _Step.answering;
      _latency.start();
      _redraw();
      _autoplay(_epoch, _index);
    } else {
      unawaited(_prepare(_epoch));
    }
  }

  Future<void> _resumeStudy() async {
    final epoch = _epoch;
    if (!_foreground || !_scopeCurrent(epoch) || _operationPending) return;
    final generation = _pauseGeneration;
    _operationPending = true;
    try {
      await widget.verifySourceOnResume?.call();
      final review = _review;
      if (review != null && _scopeCurrent(epoch)) {
        await _learning!.requireCurrentSrsReview(review);
      }
    } on Object {
      if (_scopeCurrent(epoch) && generation == _pauseGeneration) _invalidate();
    } finally {
      _operationPending = false;
    }
    if (!_scopeCurrent(epoch) || !_foreground) return;
    if (generation != _pauseGeneration) {
      unawaited(_resumeStudy());
      return;
    }
    _suspended = false;
    _redraw();
    if (!_beginRequested) {
      _tryBegin();
    } else if (_step == _Step.starting) {
      unawaited(_start(epoch));
    } else if (_step == _Step.answering) {
      _latency.start();
      _autoplay(epoch, _index);
      unawaited(_readyTime());
    } else if (_step == _Step.finishing && _summary != null) {
      _complete(_summary);
    }
  }

  void _operationSettled() {
    _operationPending = false;
    _redraw();
    if (_suspended) unawaited(_resumeStudy());
  }

  Future<void> _prepare(int epoch) async {
    if (!_current(epoch) || _operationPending) {
      return;
    }
    _operationPending = true;
    _step = _Step.preparing;
    _redraw();
    try {
      final sessionId = widget.resumeSessionId;
      if (sessionId != null) {
        final state = await _learning!.resumeSrsReview(
          sessionId: sessionId,
          expectedOwnerId: _ownerId!,
          stillCurrent: () => _scopeCurrent(epoch),
        );
        if (!_scopeCurrent(epoch)) return;
        _review = state.review;
        _index = state.cardIndex;
        _isFlipped = state.revealed;
        _controller.value = _isFlipped ? 1 : 0;
        for (final answer in state.answers) {
          if (answer.command.isCorrect) {
            _correctCount++;
          } else {
            _mistakeWordIds.add(answer.command.wordId);
          }
        }
        if (state.answers.length > _index) {
          _rating = state.answers[_index];
          _selectedRating = _rating!.command.isCorrect;
          _step = _Step.saved;
        } else {
          _step = _Step.answering;
        }
      } else {
        final review = await _learning!.prepareSrsReview(
          expectedOwnerId: _ownerId!,
          sourceWordIds: _sourceIds,
          packOrigin: widget.packOrigin,
          stillCurrent: () => _scopeCurrent(epoch),
        );
        if (!_scopeCurrent(epoch)) return;
        _review = review;
        _step = review == null ? _Step.empty : _Step.starting;
      }
    } on Object {
      if (_scopeCurrent(epoch)) {
        _step = _Step.loadFailed;
      }
    } finally {
      _operationSettled();
    }
    if (_current(epoch) && _review != null && _step == _Step.starting) {
      await _start(epoch);
    } else if (_current(epoch) && _step == _Step.answering) {
      _latency.start();
      _autoplay(epoch, _index);
      unawaited(_readyTime());
    }
  }

  Future<void> _start(int epoch) async {
    if (!_current(epoch) || _operationPending || _review == null) {
      return;
    }
    _operationPending = true;
    _step = _Step.starting;
    _redraw();
    try {
      await _learning!.startSrsReview(
        _review!,
        stillCurrent: () => _scopeCurrent(epoch),
      );
      if (!_scopeCurrent(epoch)) {
        return;
      }
      _step = _Step.answering;
      if (_current(epoch)) _latency.start();
    } on Object {
      if (_scopeCurrent(epoch)) {
        _step = _Step.startFailed;
      }
    } finally {
      _operationSettled();
    }
    if (_current(epoch) && _step == _Step.answering) {
      _autoplay(epoch, _index);
      unawaited(_readyTime());
    }
  }

  _CardText get _card {
    if (_isPreview) {
      return _preview![_index];
    }
    final word = _review!.words[_index];
    return _CardText(word.spelling, word.meaning, word.partOfSpeech);
  }

  Future<void> _flip(int epoch, int index) async {
    if (!_cardCurrent(epoch, index) ||
        _operationPending ||
        _step != _Step.answering ||
        _selectedRating != null) {
      return;
    }
    _timeBinding?.interacted();
    _suspendTime();
    final revealed = !_isFlipped;
    if (!_isPreview) {
      _operationPending = true;
      _redraw();
      try {
        await _learning!.saveSrsCardPosition(
          _review!,
          cardIndex: index,
          revealed: revealed,
          stillCurrent: () => _sameCard(epoch, index),
        );
      } on Object {
        if (mounted && _cardCurrent(epoch, index)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _copy(
                  'บันทึกด้านของบัตรไม่สำเร็จ ลองอีกครั้ง',
                  'Could not save this side of the card. Try again.',
                ),
              ),
            ),
          );
        }
        return;
      } finally {
        _operationSettled();
      }
    }
    if (!mounted || !_sameCard(epoch, index)) return;
    _isFlipped = revealed;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = _isFlipped ? 1 : 0;
    } else if (_isFlipped) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _redraw();
    unawaited(_readyTime());
  }

  Future<void> _rate(int epoch, int index, bool recalled) async {
    if (!_cardCurrent(epoch, index) ||
        _operationPending ||
        !_isFlipped ||
        (_step != _Step.answering && _step != _Step.saveFailed) ||
        (_selectedRating != null && _selectedRating != recalled)) {
      return;
    }
    if (_step == _Step.answering) _timeBinding?.interacted();
    _suspendTime();
    _selectedRating ??= recalled;
    _operationPending = true;
    _step = _Step.saving;
    _redraw();
    try {
      if (!_isPreview) {
        if (_rating == null) {
          final responseTimeMs = _latency.elapsedMilliseconds;
          await _learning!.prepareOrdinaryAnswer(
            expectedOwnerId: _review!.ownerId,
            sessionId: _review!.id,
            stillCurrent: () => _sameCard(epoch, index),
          );
          if (!_sameCard(epoch, index)) return;
          _rating = _learning!.prepareSrsRating(
            review: _review!,
            cardIndex: index,
            recalled: recalled,
            responseTimeMs: responseTimeMs,
          );
        }
        await _learning!.commitSrsRating(
          _rating!,
          stillCurrent: () => _sameCard(epoch, index),
        );
      }
      if (!_sameCard(epoch, index)) {
        return;
      }
      _latency.stop();
      if (!_isPreview) {
        if (_selectedRating!) {
          _correctCount++;
        } else {
          _mistakeWordIds.add(_review!.words[index].id);
        }
      }
      _step = _Step.saved;
    } on Object {
      if (_sameCard(epoch, index)) {
        _step = _Step.saveFailed;
      }
    } finally {
      _operationSettled();
    }
  }

  Future<void> _next(int epoch, int index) async {
    if (!_cardCurrent(epoch, index) ||
        _operationPending ||
        (_step != _Step.saved && _step != _Step.finishFailed)) {
      return;
    }
    _operationPending = true;
    final last = index == _length - 1;
    _suspendTime();
    try {
      if (last && !_isPreview) {
        _finish ??= _learning!.prepareSrsFinish(_review!);
        _step = _Step.finishing;
      }
      _redraw();
      // The next autoplay joins this stop; audio cannot hold a saved rating open.
      unawaited(_stopPlayback());
      if (!_cardCurrent(epoch, index)) {
        return;
      }
      if (!last) {
        if (!_isPreview) {
          await _learning!.saveSrsCardPosition(
            _review!,
            cardIndex: index + 1,
            revealed: false,
            stillCurrent: () => _sameCard(epoch, index),
          );
          if (!_sameCard(epoch, index)) return;
        }
        _resumeOffset = null;
        _index++;
        _controller.value = 0;
        _isFlipped = false;
        _rating = null;
        _selectedRating = null;
        _voiceFailed = false;
        _latency
          ..reset()
          ..start();
        _step = _Step.answering;
      } else {
        LearningSessionSummary? summary;
        if (!_isPreview) {
          summary = await _learning!.finishSrsReview(
            _finish!,
            stillCurrent: () => _sameCard(epoch, index),
          );
          if (!_sameCard(epoch, index)) {
            return;
          }
          if (!_validSummary(summary)) {
            throw StateError('Invalid SRS summary');
          }
          _summary = summary;
        }
        if (_cardCurrent(epoch, index)) {
          _complete(summary);
        }
      }
    } on Object {
      if (_sameCard(epoch, index)) {
        _step = _Step.finishFailed;
      }
    } finally {
      _operationSettled();
    }
    if (!last && _cardCurrent(epoch, _index) && _step == _Step.answering) {
      _autoplay(epoch, _index);
      unawaited(_readyTime());
    }
  }

  bool _validSummary(LearningSessionSummary summary) {
    final total = _length;
    final wrong = total - _correctCount;
    return summary.id == _review?.id &&
        summary.state == 'completed' &&
        summary.correctCount == _correctCount &&
        summary.wrongCount == wrong &&
        summary.score == ((_correctCount * 100) / total).round() &&
        _mistakeWordIds.length == wrong;
  }

  void _complete(LearningSessionSummary? summary) {
    final route = _route;
    if (!_current(_epoch) || route?.isActive != true) {
      return;
    }
    final result =
        widget.resumeSessionId == null && _isSource && summary != null
        ? LearningSessionResult(
            summary: summary,
            mistakeWordIds: _mistakeWordIds,
          )
        : null;
    _step = _Step.completed;
    _timeRequest++;
    _timeBinding?.close();
    _summary = summary;
    _latency.stop();
    if (widget.resumeSessionId == null &&
        !_isSource &&
        !_isPreview &&
        _time != null &&
        summary != null) {
      _redraw();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  void _retry(int epoch, int index) {
    if (!_current(epoch) || _operationPending) {
      return;
    }
    switch (_step) {
      case _Step.loadFailed:
        unawaited(_prepare(epoch));
      case _Step.startFailed:
        unawaited(_start(epoch));
      case _Step.saveFailed:
        if (_selectedRating != null) {
          unawaited(_rate(epoch, index, _selectedRating!));
        }
      case _Step.finishFailed:
        unawaited(_next(epoch, index));
      default:
        return;
    }
  }

  Future<void> _stopPlayback() {
    _audioEpoch++;
    _voiceBusy = false;
    final pending = _playbackStop;
    if (pending != null) {
      return pending;
    }
    if (!_ownsPlayback) {
      return Future<void>.value();
    }
    _ownsPlayback = false;
    final voice = _voice;
    final stopping = () async {
      try {
        await voice?.stop();
      } on Object {
        // Audio failure never changes the canonical rating receipt.
      }
    }();
    _playbackStop = stopping;
    unawaited(
      stopping.whenComplete(() {
        if (identical(_playbackStop, stopping)) {
          _playbackStop = null;
          unawaited(_readyTime());
        }
      }),
    );
    return stopping;
  }

  void _autoplay(int epoch, int index) {
    if (!_cardCurrent(epoch, index) ||
        _step != _Step.answering ||
        !_autoplayed.add(index)) {
      return;
    }
    unawaited(_listen(epoch, index));
  }

  bool _canListen(int epoch, int index) =>
      _cardCurrent(epoch, index) &&
      !_operationPending &&
      _voice != null &&
      _card.spelling.trim().isNotEmpty &&
      _card.spelling.length <= 500;

  Future<void> _listen(int epoch, int index) async {
    if (!_canListen(epoch, index) || _voiceBusy) {
      return;
    }
    final voice = _voice!;
    _timeBinding?.interacted();
    _suspendTime();
    final card = _card;
    final contentId = _isPreview ? 'preview:$index' : _review!.words[index].id;
    final stop = _stopPlayback();
    final audioEpoch = _audioEpoch;
    _voiceBusy = true;
    _voiceFailed = false;
    _redraw();
    await stop;
    if (!_cardCurrent(epoch, index) ||
        audioEpoch != _audioEpoch ||
        !identical(voice, _voice)) {
      return;
    }
    _ownsPlayback = true;
    try {
      await voice.speak(
        VoiceRequest.create(
          text: card.spelling,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: contentId,
          contentType: 'srs_flashcard',
        ),
      );
    } on Object {
      if (_cardCurrent(epoch, index) && audioEpoch == _audioEpoch) {
        _voiceFailed = true;
      }
    } finally {
      if (_cardCurrent(epoch, index) && audioEpoch == _audioEpoch) {
        _voiceBusy = false;
        _redraw();
      }
    }
  }

  void _stopCard(int epoch, int index) {
    if (!_cardCurrent(epoch, index)) {
      return;
    }
    unawaited(_stopPlayback());
    _redraw();
  }

  void _leave(ModalRoute<dynamic>? route) {
    if (!mounted ||
        !identical(route, _route) ||
        route?.isCurrent != true ||
        route?.isActive != true) {
      return;
    }
    _invalidate();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _timeRequest++;
    _timeBinding?.dispose();
    _invalidated = true;
    _epoch++;
    _latency.stop();
    unawaited(_owners?.cancel());
    unawaited(_stopPlayback());
    WidgetsBinding.instance.removeObserver(this);
    _cardScroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _invalidate();
        }
      },
      child: LessonScaffold(
        leading: Navigator.of(context).canPop()
            ? BackButton(onPressed: () => _leave(route))
            : null,
        title: _isPreview
            ? _copy('ชุดตัวอย่างบัตรคำ', 'Flashcard preview')
            : _isSource
            ? _copy('บัตรคำจากเนื้อหานี้', 'Source flashcards')
            : _copy('ทบทวนคำที่ถึงกำหนด', 'Due flashcards'),
        body: _invalidated
            ? _message(
                _copy('กิจกรรมไม่พร้อมใช้งาน', 'Activity unavailable'),
                leave: true,
              )
            : _hasCard && _current(_epoch)
            ? NotificationListener<Notification>(
                onNotification: _restoreCardScroll,
                child: _buildCard(_epoch, _index),
              )
            : _buildMessage(),
      ),
    );
  }

  Widget _buildMessage() {
    switch (_suspended ? _Step.waiting : _step) {
      case _Step.loadFailed:
        return _message(
          widget.resumeSessionId != null
              ? _copy(
                  'เปิดรอบบัตรคำเดิมไม่ได้ กรุณาตรวจคำศัพท์หรือกลับไปดูประวัติ',
                  'Cannot open this flashcard round. Check the words or return to history.',
                )
              : _copy(
                  'เปิดข้อมูลทบทวนในเครื่องไม่สำเร็จ',
                  'Unable to load local review',
                ),
          retry: true,
        );
      case _Step.startFailed:
        return _message(
          _copy(
            'เริ่มการทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง',
            'Unable to confirm review start. Retry.',
          ),
          retry: true,
        );
      case _Step.empty:
        return _message(
          _isPreview
              ? _copy('ชุดตัวอย่างนี้ไม่มีคำศัพท์', 'This preview has no words')
              : _isSource
              ? _copy(
                  'ไม่พบคำศัพท์จากแหล่งเรียนสำหรับฝึก',
                  'Source words are unavailable',
                )
              : _copy(
                  'ยังไม่มีคำศัพท์ที่ถึงกำหนดทบทวน',
                  'No words are due for review',
                ),
        );
      case _Step.completed:
        final summary = _summary;
        if (!_isPreview && !_isSource && summary != null && _time != null) {
          final epoch = _epoch;
          final route = _route;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _copy(
                    'ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว',
                    'Due flashcards complete',
                  ),
                  key: const Key('srs-status'),
                ),
                const SizedBox(height: 16),
                RecordedTimeView(
                  time: _time,
                  expectedOwnerId: _ownerId!,
                  target: SessionTimeRead(summary.id),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('srs-done'),
                  onPressed: () {
                    if (!_current(epoch) || _step != _Step.completed) return;
                    _leave(route);
                  },
                  child: Text(_copy('เสร็จแล้ว', 'Done')),
                ),
              ],
            ),
          );
        }
        return _message(
          _isPreview
              ? _copy(
                  'ดูชุดตัวอย่างครบแล้ว (ไม่บันทึกผล)',
                  'Preview complete. No results saved.',
                )
              : _isSource
              ? _copy(
                  'ฝึกบัตรคำจากเนื้อหานี้ครบแล้ว',
                  'Source flashcards complete',
                )
              : _copy(
                  'ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว',
                  'Due flashcards complete',
                ),
        );
      default:
        return Center(
          child: CircularProgressIndicator(
            semanticsLabel: _copy(
              'กำลังเตรียมคำศัพท์สำหรับทบทวน',
              'Preparing review words',
            ),
          ),
        );
    }
  }

  Widget _message(String text, {bool retry = false, bool leave = false}) {
    final epoch = _epoch;
    final index = _index;
    final route = _route;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                key: const Key('srs-status'),
                textAlign: TextAlign.center,
              ),
            ),
            if (retry) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('srs-retry'),
                onPressed: () => _retry(epoch, index),
                child: Text(_copy('ลองอีกครั้ง', 'Retry')),
              ),
            ],
            if (leave) ...[
              const SizedBox(height: 16),
              TextButton(
                key: const Key('srs-leave'),
                onPressed: () => _leave(route),
                child: Text(_copy('กลับ', 'Back')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _restoreCardScroll(Notification event) {
    if (event is ScrollStartNotification && event.depth == 0) {
      _resumeOffset = null;
    }
    final target = _resumeOffset;
    if (event is ScrollMetricsNotification &&
        event.depth == 0 &&
        target != null &&
        _cardScroll.hasClients) {
      final position = _cardScroll.position;
      final offset = target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (position.pixels != offset) _cardScroll.jumpTo(offset);
      // Pack details can grow the card after its first layout.
      _resumeOffset = offset < target ? target : null;
    }
    return false;
  }

  Widget _buildCard(int epoch, int index) {
    final card = _card;
    final saved =
        _step == _Step.saved ||
        _step == _Step.finishing ||
        _step == _Step.finishFailed;
    final canFlip =
        !_operationPending &&
        _step == _Step.answering &&
        _selectedRating == null;
    final failed = _step == _Step.saveFailed || _step == _Step.finishFailed;
    return SafeArea(
      child: SingleChildScrollView(
        key: ValueKey(index),
        controller: _cardScroll,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isPreview) ...[
              Text(
                _copy(
                  'ชุดตัวอย่าง • ไม่บันทึกผล',
                  'Preview • results are not saved',
                ),
                key: const Key('srs-preview-label'),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '${index + 1}/$_length',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              key: const Key('srs-card'),
              onTap: canFlip ? () => _flip(epoch, index) : null,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final angle = _controller.value * pi;
                  final front = angle < pi / 2;
                  return Transform(
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    alignment: Alignment.center,
                    child: Card(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 280),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: front
                              ? _front(card)
                              : Transform(
                                  transform: Matrix4.identity()..rotateY(pi),
                                  alignment: Alignment.center,
                                  child: _back(card),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (!_isPreview && _isFlipped && _review != null)
              OwnedLexicalDetails(
                key: ValueKey(('srs-lexical', _review!.id, index)),
                word: _review!.words[index],
                expectedOwnerId: _review!.ownerId,
                visible: () => _current(epoch) && _index == index && _isFlipped,
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                IconButton(
                  key: const Key('srs-listen'),
                  onPressed: _canListen(epoch, index) && !_voiceBusy
                      ? () => unawaited(_listen(epoch, index))
                      : null,
                  icon: const Icon(Icons.volume_up_outlined),
                  iconSize: 40,
                  tooltip: _copy('ฟังเสียง', 'Listen / Replay'),
                ),
                IconButton(
                  key: const Key('srs-stop'),
                  onPressed: _ownsPlayback || _voiceBusy
                      ? () => _stopCard(epoch, index)
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  tooltip: _copy('หยุดเสียง', 'Stop audio'),
                ),
              ],
            ),
            if (_voiceFailed)
              Text(
                _copy(
                  'ฟังเสียงไม่สำเร็จ ลองอีกครั้งได้',
                  'Audio unavailable. You can retry.',
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            if (_operationPending)
              LinearProgressIndicator(
                semanticsLabel: _copy(
                  'กำลังบันทึกผลทบทวน',
                  'Confirming review result',
                ),
              ),
            if (failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _step == _Step.saveFailed
                      ? _copy(
                          'บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง',
                          'Unable to confirm rating. Retry the same choice.',
                        )
                      : index < _length - 1
                      ? _copy(
                          'ไปคำถัดไปไม่สำเร็จ กรุณาลองอีกครั้ง',
                          'Could not open the next word. Retry.',
                        )
                      : _copy(
                          'ปิดการทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง',
                          'Unable to confirm review completion. Retry.',
                        ),
                  key: const Key('srs-status'),
                ),
              ),
              TextButton(
                key: const Key('srs-retry'),
                onPressed: () => _retry(epoch, index),
                child: Text(_copy('ลองอีกครั้ง', 'Retry')),
              ),
            ],
            if (saved) ...[
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isPreview
                          ? _copy(
                              'ชุดตัวอย่างนี้ไม่บันทึกผล',
                              'Preview results are not saved',
                            )
                          : _copy('บันทึกแล้ว', 'Saved'),
                      key: failed ? null : const Key('srs-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _copy(
                        'ผลที่คุณเลือก: ${_selectedRating! ? 'จำได้แล้ว' : 'จำไม่ได้'}',
                        'Your choice: ${_selectedRating! ? 'Got it' : 'Again'}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('srs-next'),
                onPressed: _operationPending
                    ? null
                    : () => unawaited(_next(epoch, index)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(
                  index == _length - 1
                      ? _isSource
                            ? _copy('จบการฝึก', 'Finish practice')
                            : _copy('จบการทบทวน', 'Finish review')
                      : _copy('คำถัดไป', 'Next word'),
                ),
              ),
            ] else if (!_operationPending && _isFlipped) ...[
              OutlinedButton(
                key: const Key('srs-again'),
                onPressed: _selectedRating == true
                    ? null
                    : () => unawaited(_rate(epoch, index, false)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_copy('ยังจำไม่ได้', 'Again')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('srs-got'),
                onPressed: _selectedRating == false
                    ? null
                    : () => unawaited(_rate(epoch, index, true)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_copy('จำได้แล้ว', 'Got it')),
              ),
            ] else if (!_operationPending)
              TextButton(
                key: const Key('srs-flip'),
                onPressed: canFlip ? () => _flip(epoch, index) : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_copy('ดูคำแปล', 'Show meaning')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _front(_CardText card) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        card.spelling,
        key: const Key('srs-spelling'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
    ],
  );

  Widget _back(_CardText card) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        card.spelling,
        key: const Key('srs-spelling'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        card.meaning,
        key: const Key('srs-meaning'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      if (card.detail.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(card.detail, textAlign: TextAlign.center),
      ],
    ],
  );
}

final class _CardText {
  const _CardText(this.spelling, this.meaning, this.detail);
  final String spelling;
  final String meaning;
  final String detail;
}
