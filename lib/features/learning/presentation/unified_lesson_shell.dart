import 'dart:async';

import 'package:flutter/material.dart';

import '../application/unified_lesson_controller.dart';
import '../domain/lesson_session_state.dart';
import '../../../runtime/app_dependencies.dart';
import 'answer_feedback_panel.dart';
import 'hint_panel.dart';

typedef LessonUtcNow = DateTime Function();
typedef LessonLifecycleStateReader = AppLifecycleState? Function();

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
  void didUpdateWidget(UnifiedLessonShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _pausedByLifecycle = false;
      _lifecycleTransitionInFlight = null;
      unawaited(_reconcileLifecycle());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _lifecycleWantsActive = false;
        unawaited(_reconcileLifecycle());
      case AppLifecycleState.resumed:
        _lifecycleWantsActive = true;
        unawaited(_reconcileLifecycle());
      case AppLifecycleState.inactive:
        break;
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
          if (outcome == _LifecycleDriveOutcome.conflict ||
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
        try {
          await controller.pause(_now());
        } on StateError {
          // A simultaneous user action may already have left the active state.
          return _LifecycleDriveOutcome.conflict;
        }
        if (!mounted || !identical(widget.controller, controller)) {
          return _LifecycleDriveOutcome.settled;
        }
        _pausedByLifecycle = true;
        continue;
      }
      if (!_pausedByLifecycle ||
          controller.state.status != LessonSessionStatus.paused) {
        return _LifecycleDriveOutcome.settled;
      }
      try {
        await controller.resume(_now());
      } on StateError {
        // A simultaneous user action may already have left the paused state.
        if (mounted &&
            identical(widget.controller, controller) &&
            controller.state.status != LessonSessionStatus.paused) {
          _pausedByLifecycle = false;
        }
        return _LifecycleDriveOutcome.conflict;
      }
      if (!mounted || !identical(widget.controller, controller)) {
        return _LifecycleDriveOutcome.settled;
      }
      _pausedByLifecycle = false;
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
      AppLifecycleState.detached => false,
      AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
    };
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    scheduleMicrotask(() {
      if (mounted) unawaited(_reconcileLifecycle());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return widget.builder(context);
    final hintState = controller.hintState;
    final bookmarkLearningItem = AppDependenciesScope.maybeOf(
      context,
    )?.bookmarkLearningItem;
    return Semantics(
      container: true,
      label: 'Lesson ${controller.state.status.name}',
      child: Column(
        children: <Widget>[
          LinearProgressIndicator(value: controller.state.progress),
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
            ),
          Expanded(child: Builder(builder: widget.builder)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

enum _LifecycleDriveOutcome { settled, conflict }
