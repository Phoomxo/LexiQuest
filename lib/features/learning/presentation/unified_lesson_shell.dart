import 'dart:async';

import 'package:flutter/material.dart';

import '../application/unified_lesson_controller.dart';
import '../domain/lesson_session_state.dart';

typedef LessonUtcNow = DateTime Function();

final class UnifiedLessonShell extends StatefulWidget {
  const UnifiedLessonShell({
    super.key,
    required this.builder,
    this.controller,
    this.nowUtc,
  });

  final WidgetBuilder builder;
  final UnifiedLessonController? controller;
  final LessonUtcNow? nowUtc;

  @override
  State<UnifiedLessonShell> createState() => _UnifiedLessonShellState();
}

final class _UnifiedLessonShellState extends State<UnifiedLessonShell>
    with WidgetsBindingObserver {
  bool _pausedByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(UnifiedLessonShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _pausedByLifecycle = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_pauseForBackground());
      case AppLifecycleState.resumed:
        unawaited(_resumeFromBackground());
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _pauseForBackground() async {
    final controller = widget.controller;
    if (controller == null ||
        controller.state.status != LessonSessionStatus.active) {
      return;
    }
    try {
      await controller.pause(_now());
      _pausedByLifecycle = true;
    } on StateError {
      // A simultaneous user action may already have left the active state.
    }
  }

  Future<void> _resumeFromBackground() async {
    final controller = widget.controller;
    if (!_pausedByLifecycle ||
        controller == null ||
        controller.state.status != LessonSessionStatus.paused) {
      return;
    }
    _pausedByLifecycle = false;
    try {
      await controller.resume(_now());
    } on StateError {
      // A simultaneous user action may already have left the paused state.
    }
  }

  DateTime _now() => (widget.nowUtc ?? _systemUtcNow).call();

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return widget.builder(context);
    return Semantics(
      container: true,
      label: 'Lesson ${controller.state.status.name}',
      child: Column(
        children: <Widget>[
          LinearProgressIndicator(value: controller.state.progress),
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
