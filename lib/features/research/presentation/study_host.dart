import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../config/m3_theme.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../screens/quiz_screen.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../adventure/presentation/study_presentations.dart';
import '../../learning/domain/learning_models.dart';
import '../application/study_runtime.dart';
import '../domain/motivation_instrument.dart';
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
    _generation++;
    _expiry?.cancel();
    _formCurrent.value = false;
    _view = null;
    _busy = false;
    _failed = false;
    _rendered = null;
    _scheduled = null;
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
    int generation,
  ) async {
    final elapsed = Stopwatch()..start();
    final view = await read();
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
      _ => false,
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
    setState(() {
      _view = view;
      _rendered = null;
      _scheduled = null;
    });
    _formCurrent.value =
        collectible &&
        view.run != null &&
        (view.phase == StudyPhase.baseline || view.phase == StudyPhase.post);
    if (widget._postOnly && view.phase != StudyPhase.post) {
      _closePost(generation);
    } else if (view.phase == StudyPhase.ready &&
        view.opportunity?.presentation == null) {
      _afterPresentationFrame(view, generation);
    }
  }

  Future<void> _reload() => _run(
    (generation) =>
        _readView(() => widget.runtime.load(widget.ownerId), generation),
  );

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
    return decoded;
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

  void _afterPresentationFrame(StudyView view, int generation) {
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
          if (opportunity == null) {
            await _readView(
              () => widget.runtime.openPresentation(
                widget.ownerId,
                entryAttemptId: _entryAttemptId,
              ),
              current,
            );
          } else {
            await _readView(
              () => widget.runtime.recordPresented(
                widget.ownerId,
                opportunity.id,
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
        return _form(run, MotivationTimepoint.baseline);
      case StudyPhase.post:
        final run = view.run;
        return run == null
            ? _message(
                _text(
                  'เปิดแบบสอบถามไม่ได้',
                  'The questionnaire is unavailable.',
                ),
              )
            : _form(run, MotivationTimepoint.post);
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
          canStart: view.canStart || view.phase == StudyPhase.activeIndex,
          busy: _busy,
          languageCode: widget.languageCode,
          onStart: () => _launch(view),
        );
      case StudyPhase.completed:
        return _message(
          _text(
            'บันทึกคำตอบของรอบนี้แล้ว ขอบคุณที่ร่วมตอบ',
            'Your responses for this session have been saved. Thank you.',
          ),
        );
      case StudyPhase.stopped:
        return _message(
          _text(
            'กิจกรรมเสริมรอบนี้สิ้นสุดแล้ว คุณยังเรียนตามปกติได้',
            'This optional session has ended. Ordinary learning is available.',
          ),
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

  Widget _message(String text, {bool retry = false, bool begin = false}) =>
      Center(
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
                  child: Text(
                    _text('เริ่มตอบแบบสอบถาม', 'Start questionnaire'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
