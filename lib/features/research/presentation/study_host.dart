import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../config/m3_theme.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../screens/quiz_screen.dart';
import '../../../screens/pre_post_assessment_screen.dart';
import '../../assessment/application/assessment_comparison.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../adventure/presentation/study_presentations.dart';
import '../../learning/domain/learning_models.dart';
import '../application/study_runtime.dart';
import '../domain/motivation_instrument.dart';
import '../domain/measurement_opportunity.dart' show oppositePresentation;
import '../domain/motivation_measurement.dart';
import 'motivation_measurement_form.dart';

typedef _PresentationBinding = ({
  String owner,
  String run,
  String? opportunity,
  String catalog,
  String mission,
  String language,
  TodayExperiencePresentation presentation,
});

typedef _PresentationChange = ({
  StudyRuntime runtime,
  String owner,
  String opportunity,
  String attempt,
  int expectedRevision,
  TodayExperiencePresentation target,
});

class StudyHost extends StatefulWidget {
  const StudyHost({
    super.key,
    required this.runtime,
    required this.ownerId,
    this.languageCode = 'th',
    this.ownerChanges,
  }) : _postOnly = false;

  const StudyHost._post({
    required this.runtime,
    required this.ownerId,
    required this.languageCode,
    required this.ownerChanges,
  }) : _postOnly = true;

  final StudyRuntime runtime;
  final String ownerId;
  final String languageCode;
  final Stream<String?>? ownerChanges;
  final bool _postOnly;

  @override
  State<StudyHost> createState() => _StudyHostState();
}

class _StudyHostState extends State<StudyHost> with WidgetsBindingObserver {
  final _formCurrent = ValueNotifier<bool>(false);
  final _presentationKey = GlobalKey();
  StudyView? _view;
  StreamSubscription<String?>? _ownerSubscription;
  Stream<String?>? _ownerStream;
  Object? _ownerSource;
  String? _activeOwner;
  bool _ownerKnown = false;
  ModalRoute<dynamic>? _route;
  bool _foreground = true;
  bool _visible = false;
  bool _busy = false;
  bool _failed = false;
  int _generation = 0;
  int _binding = 0;
  String _entryAttemptId = const Uuid().v4();
  _PresentationBinding? _rendered;
  _PresentationBinding? _scheduled;
  Timer? _expiry;
  ({StudyRuntime runtime, String owner, String entry})? _opening;
  bool _openingMayRender = false;
  _PresentationChange? _change;
  bool _changeMayRender = false;
  bool? _chooseAssessment;
  AssessmentComparisonResult? _comparison;

  bool get _thai => widget.languageCode != 'en';
  String _text(String th, String en) => _thai ? th : en;
  bool get _ownerCurrent => !_ownerKnown || _activeOwner == widget.ownerId;
  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _visible &&
      _foreground &&
      _route?.isCurrent == true &&
      _ownerCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant StudyHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime) ||
        oldWidget.ownerId != widget.ownerId ||
        oldWidget.languageCode != widget.languageCode) {
      _binding++;
      _invalidate();
      if (!identical(oldWidget.runtime, widget.runtime) ||
          oldWidget.ownerId != widget.ownerId) {
        _entryAttemptId = const Uuid().v4();
      }
    }
    _configure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  void _configure() {
    final progress = AppDependenciesScope.maybeOf(context)?.progress;
    final source = widget.ownerChanges ?? progress;
    if (!identical(source, _ownerSource)) {
      _invalidate();
      _ownerSource = source;
      _ownerKnown = false;
      _activeOwner = null;
      unawaited(_ownerSubscription?.cancel());
      final stream = widget.ownerChanges ?? progress?.watchActiveOwnerId();
      _ownerStream = stream == null || stream.isBroadcast
          ? stream
          : stream.asBroadcastStream(
              onCancel: (subscription) {
                unawaited(subscription.cancel());
              },
            );
      _ownerSubscription = _ownerStream?.listen(
        (owner) {
          if (!mounted || !identical(source, _ownerSource)) return;
          _ownerKnown = true;
          _activeOwner = owner;
          if (!_ownerCurrent) setState(_invalidate);
        },
        onError: (Object _) {
          if (!mounted || !identical(source, _ownerSource)) return;
          _ownerKnown = true;
          _activeOwner = null;
          setState(_invalidate);
        },
        onDone: () {
          if (!mounted || !identical(source, _ownerSource)) return;
          _ownerKnown = true;
          _activeOwner = null;
          setState(_invalidate);
        },
      );
    }
    _route = ModalRoute.of(context);
    _updateVisibility();
    if (_visible && _ownerCurrent && _view == null && !_busy && !_failed) {
      unawaited(_reload());
    }
  }

  void _invalidate() {
    _invalidateOpening();
    _invalidateChange();
    _generation++;
    _expiry?.cancel();
    _formCurrent.value = false;
    _view = null;
    _busy = false;
    _failed = false;
    _rendered = null;
    _scheduled = null;
    _chooseAssessment = null;
    _comparison = null;
  }

  void _updateVisibility() {
    final visible = _foreground && _route?.isCurrent == true;
    if (visible == _visible) return;
    _visible = visible;
    _invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!mounted) return;
    setState(_updateVisibility);
    if (_visible && _ownerCurrent) unawaited(_reload());
  }

  @override
  void dispose() {
    _invalidateOpening();
    _invalidateChange();
    _generation++;
    _binding++;
    _expiry?.cancel();
    _formCurrent.dispose();
    unawaited(_ownerSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run(Future<void> Function(int generation) action) async {
    if (_busy || !_current(_generation)) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action(generation);
    } on Object {
      if (_current(generation)) {
        if (_openingMayRender) _invalidateOpening(forget: false);
        if (_changeMayRender) _invalidateChange(forget: false);
        _expiry?.cancel();
        _formCurrent.value = false;
        setState(() {
          _view = null;
          _failed = true;
          _rendered = null;
          _scheduled = null;
        });
        if (widget._postOnly) _closePost(generation);
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _readView(
    Future<StudyView> Function() read,
    int generation, {
    bool alreadyPrepared = false,
    _PresentationChange? presentationChange,
  }) async {
    final elapsed = Stopwatch()..start();
    var view = await read();
    if (!_current(generation)) return;
    if (widget._postOnly &&
        (view.phase != StudyPhase.post ||
            !_motivationPending(view, MotivationTimepoint.post))) {
      _closePost(generation);
      return;
    }
    final needsOpening =
        view.phase == StudyPhase.ready &&
        view.opportunity?.presentation == null;
    if (needsOpening) {
      if (_openingMayRender || (view.opportunity != null && _opening == null)) {
        throw StateError('unresolved study opening is unavailable');
      }
      if (!alreadyPrepared) view = await _prepareOpening(generation);
    }
    elapsed.stop();
    if (!_current(generation)) return;
    if (view.ownerId != widget.ownerId ||
        view.catalog.version != widget.runtime.catalog.version ||
        view.catalog.missionId != widget.runtime.catalog.missionId ||
        (view.run != null && view.run!.ownerId != widget.ownerId)) {
      throw StateError('study view binding changed');
    }
    _expiry?.cancel();
    final collectible = switch (view.phase) {
      StudyPhase.baseline ||
      StudyPhase.ready ||
      StudyPhase.activeIndex ||
      StudyPhase.post => true,
      _ => view.hasCompletedAssessmentPair,
    };
    if (collectible) {
      final evaluated = view.evaluatedAtUtc;
      final expires = view.promptExpiresAtUtc;
      if (evaluated == null ||
          expires == null ||
          !evaluated.isUtc ||
          !expires.isUtc) {
        throw StateError('study prompt has no evaluated deadline');
      }
      final remaining = expires.difference(evaluated) - elapsed.elapsed;
      if (remaining <= Duration.zero) throw StateError('study prompt expired');
      _expiry = Timer(remaining, () {
        if (!_current(generation)) return;
        setState(_invalidate);
        unawaited(_reload());
      });
    }
    if (view.phase == StudyPhase.ready ||
        view.phase == StudyPhase.activeIndex) {
      _presentation(view);
    }
    if (needsOpening) {
      final opening = _opening;
      final opportunity = view.opportunity;
      if (opening == null ||
          opportunity == null ||
          view.phase != StudyPhase.ready ||
          opportunity.presentation != null) {
        throw StateError('study opening was not prepared');
      }
      opening.runtime.markPresentationMayRender(
        opening.owner,
        opportunity.id,
        entryAttemptId: opening.entry,
      );
      _openingMayRender = true;
    }
    if (presentationChange != null) {
      final pending = view.opportunity?.pendingPresentationChange;
      if (_change != presentationChange ||
          pending == null ||
          pending.attemptId != presentationChange.attempt ||
          pending.opportunityId != presentationChange.opportunity ||
          pending.ownerId != presentationChange.owner) {
        throw StateError('target frame has no live prepared change');
      }
      presentationChange.runtime.markPresentationChangeMayRender(
        presentationChange.owner,
        presentationChange.opportunity,
        attemptId: presentationChange.attempt,
      );
      _changeMayRender = true;
    }
    setState(() {
      _view = view;
      _rendered = null;
      _scheduled = null;
      _chooseAssessment = null;
      _comparison = null;
    });
    _formCurrent.value =
        collectible &&
        view.run != null &&
        (view.phase == StudyPhase.baseline || view.phase == StudyPhase.post);
    if (widget._postOnly &&
        (view.phase != StudyPhase.post ||
            !_motivationPending(view, MotivationTimepoint.post))) {
      _closePost(generation);
    } else if (presentationChange != null) {
      _afterPresentationFrame(view, generation, change: presentationChange);
    } else if (view.phase == StudyPhase.ready &&
        view.opportunity?.presentation == null) {
      _afterPresentationFrame(view, generation);
    }
  }

  Future<void> _reload() => _run((generation) {
    final change = _change;
    if (change != null && !_changeMayRender) {
      return _readView(
        () => _prepareChange(change, generation),
        generation,
        presentationChange: change,
      );
    }
    final retryPreparation = _opening != null && !_openingMayRender;
    return _readView(
      retryPreparation
          ? () => _prepareOpening(generation)
          : () => widget.runtime.load(widget.ownerId),
      generation,
      alreadyPrepared: retryPreparation,
    );
  });

  Future<StudyView> _prepareOpening(int generation) {
    if (_openingMayRender) {
      throw StateError('study opening may already have rendered');
    }
    final opening = _opening ??= (
      runtime: widget.runtime,
      owner: widget.ownerId,
      entry: _entryAttemptId,
    );
    return opening.runtime.openPresentation(
      opening.owner,
      entryAttemptId: opening.entry,
      stillCurrent: () =>
          _current(generation) && _opening == opening && !_openingMayRender,
    );
  }

  void _invalidateOpening({bool forget = true}) {
    final opening = _opening;
    if (opening != null) {
      opening.runtime.invalidatePresentationOpening(
        opening.owner,
        entryAttemptId: opening.entry,
      );
    }
    if (forget) {
      _opening = null;
      _openingMayRender = false;
    }
  }

  void _invalidateChange({bool forget = true}) {
    final change = _change;
    if (change != null) {
      change.runtime.invalidatePresentationChange(
        change.owner,
        change.opportunity,
        attemptId: change.attempt,
      );
    }
    if (forget) {
      _change = null;
      _changeMayRender = false;
    }
  }

  Future<StudyView> _prepareChange(
    _PresentationChange change,
    int generation,
  ) => change.runtime.preparePresentationChange(
    change.owner,
    change.opportunity,
    attemptId: change.attempt,
    expectedRevision: change.expectedRevision,
    target: change.target,
    stillCurrent: () =>
        _current(generation) && _change == change && !_changeMayRender,
  );

  Future<void> _switchPresentation(StudyView view) => _run((generation) async {
    final opportunity = view.opportunity;
    if (!identical(view, _view) ||
        opportunity?.presentation == null ||
        opportunity!.pendingPresentationChange != null) {
      throw StateError('study presentation cannot change');
    }
    final change = (
      runtime: widget.runtime,
      owner: widget.ownerId,
      opportunity: opportunity.id,
      attempt: const Uuid().v4(),
      expectedRevision: opportunity.localRevision,
      target: oppositePresentation(opportunity.currentPresentation),
    );
    _change = change;
    _changeMayRender = false;
    await _readView(
      () => _prepareChange(change, generation),
      generation,
      presentationChange: change,
    );
  });

  Future<void> _begin() => _run(
    (generation) =>
        _readView(() => widget.runtime.begin(widget.ownerId), generation),
  );

  TodayExperiencePresentation _presentation(StudyView view) {
    final decoded = TodayExperiencePresentationCodec.tryDecode(
      view.run?.treatment,
    );
    if (decoded == null ||
        (view.opportunity != null &&
            (view.opportunity!.ownerId != widget.ownerId ||
                view.opportunity!.effectivePresentation != decoded ||
                view.opportunity!.assignedTreatment != decoded))) {
      throw StateError('study presentation is unavailable');
    }
    final opportunity = view.opportunity;
    final pending = opportunity?.pendingPresentationChange;
    if (pending != null) {
      final change = _change;
      if (change == null ||
          !identical(change.runtime, widget.runtime) ||
          change.owner != widget.ownerId ||
          change.opportunity != opportunity!.id ||
          change.attempt != pending.attemptId ||
          change.target != pending.to ||
          change.expectedRevision != pending.baseRevision) {
        throw StateError('pending presentation has no original process handle');
      }
      return pending.to;
    }
    return opportunity?.currentPresentation ?? decoded;
  }

  _PresentationBinding _presentationBinding(StudyView view) => (
    owner: widget.ownerId,
    run: view.run!.id,
    opportunity: view.opportunity?.id,
    catalog: view.catalog.version,
    mission: view.catalog.missionId,
    language: widget.languageCode,
    presentation: _presentation(view),
  );

  bool _stillPresented(
    StudyView view,
    _PresentationBinding binding,
    int generation,
  ) {
    final actual = _presentationKey.currentWidget;
    return _current(generation) &&
        identical(_view, view) &&
        _rendered == binding &&
        actual is StudyPresentations &&
        actual.catalog.version == binding.catalog &&
        actual.catalog.missionId == binding.mission &&
        actual.languageCode == binding.language &&
        actual.presentation == binding.presentation;
  }

  void _afterPresentationFrame(
    StudyView view,
    int generation, {
    _PresentationChange? change,
  }) {
    final binding = _presentationBinding(view);
    if (_scheduled == binding) return;
    _scheduled = binding;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_current(generation) || !identical(_view, view)) return;
      final actual = _presentationKey.currentWidget;
      if (actual is! StudyPresentations ||
          actual.catalog.version != binding.catalog ||
          actual.catalog.missionId != binding.mission ||
          actual.presentation != binding.presentation) {
        return;
      }
      _rendered = binding;
      unawaited(
        _run((current) async {
          final opportunity = view.opportunity;
          final opening = _opening;
          if (change != null) {
            if (_change != change ||
                !_changeMayRender ||
                opportunity?.id != change.opportunity) {
              throw StateError('target frame has no prepared change');
            }
            await _readView(
              () => change.runtime.recordPresentationChanged(
                change.owner,
                change.opportunity,
                attemptId: change.attempt,
                stillVisible: () =>
                    _change == change &&
                    _changeMayRender &&
                    _stillPresented(view, binding, current),
              ),
              current,
            );
            if (_current(current) && _change == change) {
              _change = null;
              _changeMayRender = false;
            }
          } else if (opportunity == null ||
              opening == null ||
              !_openingMayRender) {
            throw StateError('target frame has no prepared opening');
          } else {
            await _readView(
              () => widget.runtime.recordPresented(
                widget.ownerId,
                opportunity.id,
                entryAttemptId: opening.entry,
                stillVisible: () => _stillPresented(view, binding, current),
              ),
              current,
            );
          }
        }),
      );
    });
  }

  Future<void> _launch(StudyView view) => _run((generation) async {
    final binding = _binding;
    final opportunity = view.opportunity;
    final index = view.phase == StudyPhase.activeIndex
        ? await widget.runtime.resumeIndex(widget.ownerId)
        : opportunity == null
        ? throw StateError('study opportunity is unavailable')
        : await widget.runtime.startIndex(
            widget.ownerId,
            opportunity.id,
            stillVisible: () =>
                _stillPresented(view, _presentationBinding(view), generation),
          );
    if (!mounted || !_current(generation) || binding != _binding) return;
    if (index.ownerId != widget.ownerId ||
        (view.index != null && view.index!.sessionId != index.sessionId)) {
      throw StateError('study index binding changed');
    }
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'study/quiz',
        builder: (quizContext) => QuizScreen(
          learning: widget.runtime.learning,
          resumeSessionId: index.sessionId,
          expectedOwnerId: index.ownerId,
          ownerChanges: _ownerStream,
          onCanonicalFinished: (result) =>
              _offerPost(result, quizContext, binding),
        ),
      ),
    );
  });

  Future<void> _offerPost(
    ConfiguredQuizFinishResult result,
    BuildContext quizContext,
    int binding,
  ) async {
    bool currentQuiz() =>
        mounted &&
        binding == _binding &&
        _foreground &&
        _ownerCurrent &&
        quizContext.mounted &&
        (ModalRoute.of(quizContext)?.isCurrent ?? false) &&
        result.state.ownerId == widget.ownerId;
    if (!currentQuiz()) return;
    final elapsed = Stopwatch()..start();
    await widget.runtime.resumeIndex(widget.ownerId);
    if (!currentQuiz()) return;
    final view = await widget.runtime.load(widget.ownerId);
    elapsed.stop();
    final evaluated = view.evaluatedAtUtc;
    final expires = view.promptExpiresAtUtc;
    if (!currentQuiz() ||
        view.ownerId != widget.ownerId ||
        view.phase != StudyPhase.post ||
        !_motivationPending(view, MotivationTimepoint.post) ||
        view.index?.sessionId != result.state.sessionId ||
        evaluated == null ||
        expires == null ||
        !evaluated.isUtc ||
        !expires.isUtc ||
        expires.difference(evaluated) - elapsed.elapsed <= Duration.zero) {
      return;
    }
    if (!quizContext.mounted) return;
    await AppNavigator.pushPage<void>(
      quizContext,
      AppPage<void>(
        name: 'study/post',
        builder: (_) => StudyHost._post(
          runtime: widget.runtime,
          ownerId: widget.ownerId,
          languageCode: widget.languageCode,
          ownerChanges: _ownerStream,
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  void _closePost(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(generation)) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(
        context,
        _text('กิจกรรมเสริม', 'Optional activity'),
      ),
    ),
    body: SafeArea(
      child: !_visible
          ? const SizedBox.shrink()
          : Column(
              children: [
                if (_busy)
                  LinearProgressIndicator(
                    semanticsLabel: _text(
                      'กำลังตรวจสอบกิจกรรม',
                      'Checking the activity',
                    ),
                  ),
                Expanded(child: _body()),
              ],
            ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: OutlinedButton(
          key: const ValueKey('study-ordinary-exit'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => Navigator.maybePop(context),
          child: Text(
            widget._postOnly
                ? _text('กลับไปดูผลการเรียน', 'Continue to results')
                : _text('กลับไปเรียนตามปกติ', 'Back to ordinary learning'),
          ),
        ),
      ),
    ),
  );

  Widget _body() {
    if (!_ownerCurrent) {
      return _message(
        _text(
          'บัญชีเปลี่ยนแล้ว กรุณากลับไปเรียนตามปกติ',
          'The account changed. Return to ordinary learning.',
        ),
      );
    }
    if (_failed) {
      return _message(
        _text(
          'เปิดกิจกรรมเสริมไม่ได้ คุณยังเรียนตามปกติได้',
          'This optional activity is unavailable. Ordinary learning is available.',
        ),
        retry: true,
      );
    }
    final view = _view;
    if (view == null) return const SizedBox.shrink();
    switch (view.phase) {
      case StudyPhase.unavailable:
        return _message(
          _text(
            'กิจกรรมเสริมยังไม่พร้อม คุณยังเรียนตามปกติได้',
            'This optional activity is unavailable. Ordinary learning is available.',
          ),
          retry: true,
        );
      case StudyPhase.baseline:
        final run = view.run;
        if (run == null) {
          return _message(
            _text(
              'การตอบเป็นทางเลือก คุณข้ามกิจกรรมนี้และเรียนตามปกติได้',
              'Responding is optional. You can leave and continue ordinary learning.',
            ),
            begin: true,
          );
        }
        return _pendingForm(view, MotivationTimepoint.baseline);
      case StudyPhase.post:
        final run = view.run;
        return run == null
            ? _message(
                _text(
                  'เปิดแบบสอบถามไม่ได้',
                  'The questionnaire is unavailable.',
                ),
              )
            : _pendingForm(view, MotivationTimepoint.post);
      case StudyPhase.ready:
      case StudyPhase.activeIndex:
        final presentation = _presentation(view);
        final binding = _presentationBinding(view);
        if (view.opportunity?.presentation != null) {
          final generation = _generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_current(generation) &&
                identical(_view, view) &&
                _presentationKey.currentWidget is StudyPresentations) {
              _rendered = binding;
            }
          });
        }
        return StudyPresentations(
          key: _presentationKey,
          catalog: view.catalog,
          presentation: presentation,
          index: view.index,
          canStart:
              view.opportunity?.pendingPresentationChange == null &&
              (view.canStart || view.phase == StudyPhase.activeIndex),
          busy: _busy,
          languageCode: widget.languageCode,
          onStart: () => _launch(view),
          onSwitch:
              view.opportunity?.presentation != null &&
                  view.opportunity?.pendingPresentationChange == null
              ? () => _switchPresentation(view)
              : null,
        );
      case StudyPhase.completed:
        return _message(
          _text(
            'บันทึกคำตอบของรอบนี้แล้ว ขอบคุณที่ร่วมตอบ',
            'Your responses for this session have been saved. Thank you.',
          ),
          extra: _assessmentComparison(view),
        );
      case StudyPhase.stopped:
        return _message(
          _text(
            'กิจกรรมเสริมรอบนี้สิ้นสุดแล้ว คุณยังเรียนตามปกติได้',
            'This optional session has ended. Ordinary learning is available.',
          ),
          extra: _assessmentComparison(view),
        );
    }
  }

  Widget _form(MotivationMeasurementRun run, MotivationTimepoint point) =>
      MotivationMeasurementForm(
        key: ValueKey((run.ownerId, run.id, point)),
        repository: widget.runtime.measurementsFor(widget.ownerId),
        ownerId: widget.ownerId,
        runId: run.id,
        timepoint: point,
        current: _formCurrent,
        languageCode: widget.languageCode,
        onFinished: (_) => _reload(),
      );

  bool _motivationPending(StudyView view, MotivationTimepoint point) {
    final run = view.run;
    if (run == null || run.score(point) != null) return false;
    if (point == MotivationTimepoint.baseline) return true;
    final ended = view.index?.endedAtUtc;
    final evaluated = view.evaluatedAtUtc;
    return ended != null &&
        evaluated != null &&
        !evaluated.isBefore(ended) &&
        !evaluated.isAfter(ended.add(const Duration(minutes: 30)));
  }

  Widget _pendingForm(StudyView view, MotivationTimepoint point) {
    final service = view.assessment;
    final command = view.assessmentCommand;
    final assessmentPending =
        !widget._postOnly &&
        service != null &&
        command != null &&
        command.studyCycleId == view.run?.id &&
        command.phase ==
            (point == MotivationTimepoint.baseline
                ? AssessmentPhase.pre
                : AssessmentPhase.post);
    final motivationPending = _motivationPending(view, point);
    if (assessmentPending && motivationPending && _chooseAssessment == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _text(
                  'เลือกทำส่วนใดก่อนก็ได้',
                  'Choose which part to complete first',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('study-choose-motivation'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _chooseAssessment = false),
                child: Text(
                  _text('แบบสอบถามความรู้สึก', 'Motivation questionnaire'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('study-choose-assessment'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _chooseAssessment = true),
                child: Text(_text('แบบประเมินการเรียน', 'Learning assessment')),
              ),
            ],
          ),
        ),
      );
    }
    if (assessmentPending &&
        (!motivationPending || _chooseAssessment == true)) {
      return PrePostAssessmentScreen(
        key: ValueKey((
          widget.runtime,
          widget.ownerId,
          command.runId,
          _generation,
          _binding,
        )),
        useCases: service.useCases,
        command: command,
        ownerId: widget.ownerId,
        current: _formCurrent,
        onFinished: _reload,
        languageCode: widget.languageCode,
        onExit: () {
          _formCurrent.value = false;
          unawaited(Navigator.maybePop(context));
        },
      );
    }
    if (motivationPending) return _form(view.run!, point);
    return _message(
      _text(
        'กิจกรรมส่วนนี้ยังไม่พร้อม คุณยังเรียนตามปกติได้',
        'This part is unavailable. Ordinary learning is available.',
      ),
    );
  }

  Future<void> _compareAssessment(StudyView view) => _run((generation) async {
    final service = view.assessment;
    if (service == null ||
        !view.hasCompletedAssessmentPair ||
        view.run == null ||
        !identical(view, _view)) {
      throw StateError('Assessment pair is unavailable');
    }
    final result = await service.comparison.compare(
      ownerId: widget.ownerId,
      studyCycleId: view.run!.id,
      stillVisible: () => _current(generation) && identical(view, _view),
    );
    if (_current(generation) && identical(view, _view)) {
      setState(() => _comparison = result);
    }
  });

  Widget? _assessmentComparison(StudyView view) {
    if (!view.hasCompletedAssessmentPair || view.assessment == null) {
      return null;
    }
    final result = _comparison;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('study-assessment-compare'),
          onPressed: _busy ? null : () => _compareAssessment(view),
          child: Text(
            _text('ดูสรุปคำตอบก่อนและหลัง', 'View pre and post answer summary'),
          ),
        ),
        if (result is AssessmentComparisonReady) ...[
          const SizedBox(height: 12),
          Text(
            _text(
              'ก่อน: ${result.preOutcome.correctCount}/${result.preOutcome.sampleSize} คำตอบถูก',
              'Pre: ${result.preOutcome.correctCount}/${result.preOutcome.sampleSize} correct answers',
            ),
          ),
          Text(
            _text(
              'หลัง: ${result.postOutcome.correctCount}/${result.postOutcome.sampleSize} คำตอบถูก',
              'Post: ${result.postOutcome.correctCount}/${result.postOutcome.sampleSize} correct answers',
            ),
          ),
          Text(
            _text(
              'ผลต่างจำนวนคำตอบถูก: ${result.comparison.correctCountDelta}',
              'Correct-answer difference: ${result.comparison.correctCountDelta}',
            ),
          ),
        ] else if (result != null) ...[
          const SizedBox(height: 12),
          Text(
            _text(
              'ข้อมูลรอบนี้ยังเปรียบเทียบไม่ได้',
              'This session cannot be compared.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _message(
    String text, {
    bool retry = false,
    bool begin = false,
    Widget? extra,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(text, textAlign: TextAlign.center),
          ),
          if (retry) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _reload,
              child: Text(_text('ลองอีกครั้ง', 'Try again')),
            ),
          ],
          if (begin) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('study-begin'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : _begin,
              child: Text(_text('เริ่มตอบแบบสอบถาม', 'Start questionnaire')),
            ),
          ],
          ?extra,
        ],
      ),
    ),
  );
}
