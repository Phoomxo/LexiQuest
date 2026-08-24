import 'dart:async';

import 'package:flutter/material.dart';

import '../application/focus_timer_controller.dart';
import '../domain/focus_timer.dart';

typedef FocusTimerUtcNow = DateTime Function();
typedef FocusTimerAction = Future<void> Function(DateTime occurredAtUtc);

final class FocusTimerWidget extends StatefulWidget {
  const FocusTimerWidget({
    super.key,
    required this.controller,
    required this.nowUtc,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final FocusTimerController controller;
  final FocusTimerUtcNow nowUtc;
  final FocusTimerAction onStart;
  final FocusTimerAction onPause;
  final FocusTimerAction onResume;
  final FocusTimerAction onFinish;

  @override
  State<FocusTimerWidget> createState() => _FocusTimerWidgetState();
}

final class _FocusTimerWidgetState extends State<FocusTimerWidget> {
  Timer? _ticker;
  bool _transitionPending = false;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(FocusTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _failure = null;
      _transitionPending = false;
      _syncTicker();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(_syncTicker);
  }

  void _syncTicker() {
    final running =
        widget.controller.snapshot.status == FocusTimerStatus.running;
    if (!running) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_transitionPending) return;
    setState(() {
      _transitionPending = true;
      _failure = null;
    });
    try {
      await action();
    } catch (error) {
      _failure = error;
    } finally {
      if (mounted) {
        setState(() {
          _transitionPending = false;
          _syncTicker();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final statusLabel = switch (snapshot.status) {
      FocusTimerStatus.notStarted => 'Ready',
      FocusTimerStatus.running => 'Focusing',
      FocusTimerStatus.paused => 'Paused',
      FocusTimerStatus.finished => 'Finished',
    };
    return Semantics(
      container: true,
      label: 'Focus timer, $statusLabel, ${_format(snapshot.activeDuration)}',
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LayoutBuilder(
                builder: (context, constraints) {
                  final titleStyle = Theme.of(context).textTheme.titleMedium;
                  final duration = Text(
                    _format(snapshot.activeDuration),
                    key: const ValueKey<String>('focus-timer/duration'),
                    style: titleStyle,
                  );
                  final title = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.timer_outlined),
                      const SizedBox(width: 8),
                      Flexible(child: Text('Focus timer', style: titleStyle)),
                    ],
                  );
                  final textScaler = MediaQuery.textScalerOf(context);
                  final useStackedHeader =
                      constraints.maxWidth < 360 || textScaler.scale(16) >= 28;
                  if (useStackedHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(width: constraints.maxWidth, child: title),
                        const SizedBox(height: 4),
                        duration,
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      duration,
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(statusLabel),
              if (_failure != null)
                const Text(
                  'Focus timer is temporarily unavailable.',
                  key: ValueKey<String>('focus-timer/error'),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (snapshot.status == FocusTimerStatus.notStarted)
                    FilledButton.icon(
                      key: const ValueKey<String>('focus-timer/start'),
                      onPressed: _transitionPending
                          ? null
                          : () => _run(() => widget.onStart(widget.nowUtc())),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start focus'),
                    ),
                  if (snapshot.status == FocusTimerStatus.running)
                    OutlinedButton.icon(
                      key: const ValueKey<String>('focus-timer/pause'),
                      onPressed: _transitionPending
                          ? null
                          : () => _run(() => widget.onPause(widget.nowUtc())),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  if (snapshot.status == FocusTimerStatus.paused)
                    FilledButton.icon(
                      key: const ValueKey<String>('focus-timer/resume'),
                      onPressed: _transitionPending
                          ? null
                          : () => _run(() => widget.onResume(widget.nowUtc())),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                    ),
                  if (snapshot.status == FocusTimerStatus.running ||
                      snapshot.status == FocusTimerStatus.paused)
                    TextButton.icon(
                      key: const ValueKey<String>('focus-timer/finish'),
                      onPressed: _transitionPending
                          ? null
                          : () => _run(() => widget.onFinish(widget.nowUtc())),
                      icon: const Icon(Icons.stop),
                      label: const Text('Finish'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _format(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}
