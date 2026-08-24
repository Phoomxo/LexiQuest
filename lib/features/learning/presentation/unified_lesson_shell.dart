import 'dart:async';

import 'package:flutter/material.dart';

import '../application/unified_lesson_controller.dart';
import '../application/learning_use_cases.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/lesson_session_state.dart';
import '../../../runtime/app_dependencies.dart';
import '../../time_tracking/presentation/focus_timer_widget.dart';
import 'answer_feedback_panel.dart';
import 'hint_panel.dart';

typedef LessonUtcNow = DateTime Function();
typedef LessonLifecycleStateReader = AppLifecycleState? Function();

final class UnifiedLessonSessionLifecycle {
  const UnifiedLessonSessionLifecycle._(this._controller, this._nowUtc);

  final UnifiedLessonController _controller;
  final LessonUtcNow _nowUtc;

  Future<void> start({
    required String sessionId,
    required DateTime startedAtUtc,
    required int itemCount,
  }) => _controller.start(
    LessonStartCommand(
      sessionId: sessionId,
      mode: _controller.state.mode,
      itemCount: itemCount,
      startedAtUtc: startedAtUtc,
    ),
  );

  Future<LearningSessionSummary> complete(PendingLearningSessionClose close) =>
      _controller.completeCapturedSession(close, _nowUtc());

  Future<void> abandon() => _controller.abandon(_nowUtc());

  void recordInteraction() =>
      _controller.noteActiveLearningInteraction(_nowUtc());
}

final class UnifiedLessonSessionLifecycleScope extends InheritedWidget {
  const UnifiedLessonSessionLifecycleScope({
    super.key,
    required this.lifecycle,
    required super.child,
  });

  final UnifiedLessonSessionLifecycle lifecycle;

  static UnifiedLessonSessionLifecycle? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<UnifiedLessonSessionLifecycleScope>()
      ?.lifecycle;

  @override
  bool updateShouldNotify(UnifiedLessonSessionLifecycleScope oldWidget) =>
      !identical(lifecycle, oldWidget.lifecycle);
}

final class UnifiedLessonModeHost extends StatefulWidget {
  const UnifiedLessonModeHost({
    super.key,
    required this.adapter,
    required this.createController,
    required this.builder,
  });

  final LessonModeAdapter adapter;
  final UnifiedLessonControllerFactory createController;
  final WidgetBuilder builder;

  @override
  State<UnifiedLessonModeHost> createState() => _UnifiedLessonModeHostState();
}

final class _UnifiedLessonModeHostState extends State<UnifiedLessonModeHost> {
  late final UnifiedLessonController _controller = widget.createController(
    widget.adapter,
  );

  @override
  Widget build(BuildContext context) =>
      UnifiedLessonShell(controller: _controller, builder: widget.builder);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

final class UnifiedLessonShell extends StatefulWidget {
  const UnifiedLessonShell({
    super.key,
    required this.builder,
    this.controller,
    this.nowUtc,
    this.lifecycleStateReader,
  });

  final WidgetBuilder builder;
  final UnifiedLessonController? controller;
  final LessonUtcNow? nowUtc;
  final LessonLifecycleStateReader? lifecycleStateReader;

  @override
  State<UnifiedLessonShell> createState() => _UnifiedLessonShellState();
}

final class _UnifiedLessonShellState extends State<UnifiedLessonShell>
    with WidgetsBindingObserver {
  bool _pausedByLifecycle = false;
  late bool _lifecycleWantsActive;
  Future<void>? _lifecycleTransitionInFlight;
  Object? _lifecycleFailure;
  bool _pauseRetryRequired = false;
  Listenable? _focusFeatureChanges;
  UnifiedLessonController? _focusGateController;
  bool _focusGateEnabled = false;

  @override
  void initState() {
    super.initState();
    _lifecycleWantsActive = _bindingWantsActive(
      (widget.lifecycleStateReader ?? _bindingLifecycleState).call(),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_onControllerChanged);
    final initiallyAttachedController = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(widget.controller, initiallyAttachedController)) {
        return;
      }
      unawaited(_reconcileLifecycle());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observeFocusFeatureGate();
  }

  @override
  void didUpdateWidget(UnifiedLessonShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _pausedByLifecycle = false;
      _lifecycleTransitionInFlight = null;
      _lifecycleFailure = null;
      _pauseRetryRequired = false;
      _observeFocusFeatureGate();
      unawaited(_reconcileLifecycle());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleFailure = null;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        _lifecycleWantsActive = false;
        unawaited(_reconcileLifecycle());
      case AppLifecycleState.resumed:
        _lifecycleWantsActive = true;
        unawaited(_reconcileLifecycle());
    }
  }

  Future<void> _reconcileLifecycle() {
    final inFlight = _lifecycleTransitionInFlight;
    if (inFlight != null) return inFlight;
    final controller = widget.controller;
    if (controller == null) return Future<void>.value();
    var outcome = _LifecycleDriveOutcome.conflict;
    late final Future<void> future;
    future = _driveLifecycle(controller)
        .then<void>((result) => outcome = result)
        .whenComplete(() {
          if (!identical(_lifecycleTransitionInFlight, future)) return;
          _lifecycleTransitionInFlight = null;
          if (outcome != _LifecycleDriveOutcome.settled ||
              !mounted ||
              !identical(widget.controller, controller)) {
            return;
          }
          final status = controller.state.status;
          final needsPause =
              !_lifecycleWantsActive && status == LessonSessionStatus.active;
          final needsResume =
              _lifecycleWantsActive &&
              _pausedByLifecycle &&
              status == LessonSessionStatus.paused;
          if (needsPause || needsResume) unawaited(_reconcileLifecycle());
        });
    _lifecycleTransitionInFlight = future;
    return future;
  }

  Future<_LifecycleDriveOutcome> _driveLifecycle(
    UnifiedLessonController controller,
  ) async {
    while (mounted && identical(widget.controller, controller)) {
      if (!_lifecycleWantsActive) {
        if (controller.state.status != LessonSessionStatus.active) {
          return _LifecycleDriveOutcome.settled;
        }
        if (controller.terminalMutationInFlight) {
          return _LifecycleDriveOutcome.conflict;
        }
        try {
          await controller.pause(_now(), processBackground: true);
        } catch (error) {
          if (controller.state.status != LessonSessionStatus.active ||
              controller.terminalMutationInFlight) {
            return _LifecycleDriveOutcome.conflict;
          }
          _lifecycleFailure = error;
          _pauseRetryRequired = true;
          return _LifecycleDriveOutcome.failed;
        }
        if (!mounted || !identical(widget.controller, controller)) {
          return _LifecycleDriveOutcome.settled;
        }
        _pausedByLifecycle = true;
        _pauseRetryRequired = false;
        _lifecycleFailure = null;
        continue;
      }
      if (_pauseRetryRequired &&
          controller.state.status == LessonSessionStatus.active) {
        try {
          await controller.pause(_now(), processBackground: true);
        } catch (error) {
          if (controller.state.status != LessonSessionStatus.active ||
              controller.terminalMutationInFlight) {
            return _LifecycleDriveOutcome.conflict;
          }
          _lifecycleFailure = error;
          return _LifecycleDriveOutcome.failed;
        }
        _pausedByLifecycle = true;
        _pauseRetryRequired = false;
        _lifecycleFailure = null;
        continue;
      }
      if (!_pausedByLifecycle ||
          controller.state.status != LessonSessionStatus.paused) {
        return _LifecycleDriveOutcome.settled;
      }
      if (controller.terminalMutationInFlight) {
        return _LifecycleDriveOutcome.conflict;
      }
      try {
        await controller.resume(_now());
      } catch (error) {
        // A simultaneous user action may already have left the paused state.
        if (mounted &&
            identical(widget.controller, controller) &&
            controller.state.status != LessonSessionStatus.paused) {
          _pausedByLifecycle = false;
          return _LifecycleDriveOutcome.conflict;
        }
        _lifecycleFailure = error;
        return _LifecycleDriveOutcome.failed;
      }
      if (!mounted || !identical(widget.controller, controller)) {
        return _LifecycleDriveOutcome.settled;
      }
      _pausedByLifecycle = false;
      _lifecycleFailure = null;
    }
    return _LifecycleDriveOutcome.settled;
  }

  DateTime _now() => (widget.nowUtc ?? _systemUtcNow).call();

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  static AppLifecycleState? _bindingLifecycleState() =>
      WidgetsBinding.instance.lifecycleState;

  static bool _bindingWantsActive(AppLifecycleState? state) {
    return switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached ||
      AppLifecycleState.inactive => false,
      AppLifecycleState.resumed || null => true,
    };
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    scheduleMicrotask(() {
      if (mounted && _lifecycleFailure == null) {
        unawaited(_reconcileLifecycle());
      }
    });
  }

  void _observeFocusFeatureGate() {
    final controller = widget.controller;
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final Listenable? changes = features is Listenable
        ? features as Listenable
        : null;
    if (!identical(changes, _focusFeatureChanges)) {
      _focusFeatureChanges?.removeListener(_onFocusFeatureChanged);
      _focusFeatureChanges = changes;
      changes?.addListener(_onFocusFeatureChanged);
    }
    final wasEnabled = _focusGateEnabled;
    final controllerChanged = !identical(controller, _focusGateController);
    _focusGateController = controller;
    _focusGateEnabled = _isFocusGateEnabled();
    controller?.setFocusTimerGateEnabled(_focusGateEnabled);
    if (!_focusGateEnabled && (wasEnabled || controllerChanged)) {
      _disableFocusTimerForGate(controller);
    }
  }

  bool _isFocusGateEnabled() {
    final controller = widget.controller;
    final feature = controller?.focusTimerFeature;
    final features = AppDependenciesScope.maybeOf(context)?.features;
    return controller?.focusTimer != null &&
        feature != null &&
        features != null &&
        features.isEnabled(feature);
  }

  void _onFocusFeatureChanged() {
    if (!mounted) return;
    final controller = widget.controller;
    final wasEnabled = _focusGateEnabled;
    final isEnabled = _isFocusGateEnabled();
    if (wasEnabled == isEnabled) return;
    setState(() => _focusGateEnabled = isEnabled);
    controller?.setFocusTimerGateEnabled(isEnabled);
    if (wasEnabled && !isEnabled) {
      _disableFocusTimerForGate(controller);
    }
  }

  void _disableFocusTimerForGate(UnifiedLessonController? controller) {
    if (controller == null) return;
    unawaited(
      controller
          .disableFocusTimer(_now())
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return widget.builder(context);
    final hintState = controller.hintState;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final bookmarkLearningItem = dependencies?.bookmarkLearningItem;
    final reportContent = dependencies?.reportContent;
    return UnifiedLessonSessionLifecycleScope(
      lifecycle: UnifiedLessonSessionLifecycle._(controller, _now),
      child: Semantics(
        container: true,
        label: 'Lesson ${controller.state.status.name}',
        child: Column(
          children: <Widget>[
            LinearProgressIndicator(value: controller.state.progress),
            if (_focusGateEnabled)
              if (controller.focusTimer case final timer?)
                if (timer.snapshot.sessionId != null)
                  FocusTimerWidget(
                    controller: timer,
                    nowUtc: _now,
                    onStart: controller.startFocusTimer,
                    onPause: controller.pauseFocusTimer,
                    onResume: controller.resumeFocusTimer,
                    onFinish: controller.finishFocusTimer,
                  ),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    controller.noteActiveLearningInteraction(_now()),
                child: Column(
                  children: <Widget>[
                    if (controller.state.status == LessonSessionStatus.active &&
                        hintState != null)
                      HintPanel(
                        state: hintState,
                        onRevealNext: controller.revealNextHint,
                        enabled: controller.canRevealHint,
                      ),
                    if (controller.feedback case final feedback?)
                      AnswerFeedbackPanel(
                        feedback: feedback,
                        bookmarkIdentity: feedback.bookmarkIdentity,
                        onBookmark: bookmarkLearningItem,
                        reportIdentity: feedback.bookmarkIdentity,
                        onReport: reportContent,
                      ),
                    Expanded(child: Builder(builder: widget.builder)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusFeatureChanges?.removeListener(_onFocusFeatureChanged);
    widget.controller?.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

enum _LifecycleDriveOutcome { settled, conflict, failed }
