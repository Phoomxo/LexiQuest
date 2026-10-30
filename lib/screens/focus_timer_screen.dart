import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/m3_theme.dart';
import '../features/focus/application/focus_timer.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

class FocusTimerScreen extends StatefulWidget {
  const FocusTimerScreen({
    super.key,
    required this.expectedOwnerId,
    required this.ownerChanges,
    this.monotonicMicros,
    this.languageCode = 'th',
  });

  final String expectedOwnerId;
  final Stream<String?> ownerChanges;
  final FocusMonotonicMicros? monotonicMicros;
  final String languageCode;

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen>
    with WidgetsBindingObserver {
  final _clock = Stopwatch();
  late final FocusTimer _timer;
  TextEditingController _minutes = TextEditingController(
    text: FocusTimer.defaultMinutes.toString(),
  );
  StreamSubscription<String?>? _owners;
  Timer? _redraw;
  AppDependencies? _dependencies;
  ModalRoute<dynamic>? _route;
  bool _bound = false;
  bool _closed = false;
  bool _invalidated = false;
  bool _ownerKnown = false;
  bool _foreground = false;
  bool _paneVisible = true;
  bool _wasVisible = false;
  bool _exitWasVisible = false;
  bool _notificationScheduled = false;
  int _epoch = 0;
  String? _inputError;

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;

  bool get _visible =>
      mounted &&
      !_closed &&
      !_invalidated &&
      _ownerKnown &&
      _foreground &&
      _paneVisible &&
      _route?.isCurrent == true;

  bool get _exitVisible =>
      mounted &&
      !_closed &&
      _foreground &&
      _paneVisible &&
      _route?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _clock.start();
    _timer = FocusTimer(
      monotonicMicros:
          widget.monotonicMicros ?? () => _clock.elapsedMicroseconds,
    );
    WidgetsBinding.instance.addObserver(this);
    if (widget.expectedOwnerId.trim().isEmpty) {
      _invalidate();
      return;
    }
    final subscription = widget.ownerChanges.listen(
      (owner) {
        if (_invalidated || _closed) return;
        if (owner != widget.expectedOwnerId) {
          _invalidate();
          return;
        }
        _ownerKnown = true;
        _syncVisibility();
      },
      onError: (Object _, StackTrace _) => _invalidate(),
      onDone: _invalidate,
    );
    if (_invalidated) {
      unawaited(subscription.cancel());
    } else {
      _owners = subscription;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final route = ModalRoute.of(context);
    ModalRoute.isCurrentOf(context);
    _paneVisible = Visibility.of(context);
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _route = route;
    } else if (!identical(_dependencies, dependencies) ||
        !identical(_route, route)) {
      _invalidate();
    }
    _syncVisibility();
  }

  @override
  void didUpdateWidget(covariant FocusTimerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        !identical(oldWidget.monotonicMicros, widget.monotonicMicros)) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncVisibility();
  }

  void _replaceInput(String value) {
    if (_minutes.text == value) return;
    final previous = _minutes;
    _minutes = TextEditingController(text: value);
    // Keep the old IME controller alive until EditableText receives the redraw.
    final rebuilding =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rebuilding) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
        SchedulerBinding.instance.ensureVisualUpdate();
      } else {
        previous.dispose();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _syncVisibility() {
    final exitVisible = _exitVisible;
    if (_exitWasVisible && !exitVisible) _epoch++;
    _exitWasVisible = exitVisible;
    final visible = _visible;
    if (!visible) {
      if (_wasVisible) {
        _timer.pause();
        _inputError = null;
        _replaceInput('');
      }
      _redraw?.cancel();
      _redraw = null;
    } else if (!_wasVisible) {
      final snapshot = _timer.snapshot;
      if (snapshot != null) _replaceInput(snapshot.minutes.toString());
    }
    _wasVisible = visible;
    _syncTicker();
    _changed();
  }

  void _syncTicker() {
    final running =
        _visible && _timer.snapshot?.state == FocusTimerState.running;
    if (!running) {
      _redraw?.cancel();
      _redraw = null;
      return;
    }
    _redraw ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_visible) {
        _syncVisibility();
        return;
      }
      final before = _timer.snapshot?.revision;
      _timer.poll();
      if (_timer.snapshot?.revision != before) _epoch++;
      _syncTicker();
      _changed();
    });
  }

  void _invalidate() {
    if (_invalidated || _closed) return;
    _invalidated = true;
    _ownerKnown = false;
    _epoch++;
    _timer.dispose();
    _redraw?.cancel();
    _redraw = null;
    _inputError = null;
    _replaceInput('');
    unawaited(_owners?.cancel());
    _owners = null;
    _changed();
  }

  void _changed() {
    if (!_bound || !mounted || _closed || _notificationScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _notificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (mounted && !_closed) setState(() {});
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      setState(() {});
    }
  }

  VoidCallback? _action(VoidCallback command) {
    final snapshot = _timer.snapshot;
    if (!_visible || snapshot == null) return null;
    final epoch = _epoch;
    final revision = snapshot.revision;
    return () {
      if (!_visible || epoch != _epoch) return;
      _timer.poll();
      if (_timer.snapshot?.revision != revision) {
        _epoch++;
        _syncTicker();
        _changed();
        return;
      }
      command();
      _epoch++;
      _syncTicker();
      _changed();
    };
  }

  bool _configure() {
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null ||
        minutes < FocusTimer.minimumMinutes ||
        minutes > FocusTimer.maximumMinutes) {
      _inputError = _text(
        'กรอกจำนวนนาทีเต็มตั้งแต่ 1 ถึง 180',
        'Enter a whole number of minutes from 1 to 180.',
      );
      return false;
    }
    _inputError = null;
    return _timer.configureMinutes(minutes);
  }

  VoidCallback? _exitAction() {
    if (!_exitVisible || _route?.canPop != true) return null;
    final epoch = _epoch;
    return () {
      if (!_exitVisible || epoch != _epoch || _route?.canPop != true) return;
      _invalidate();
      Navigator.of(context).pop();
    };
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _timer.dispose();
    _clock.stop();
    _redraw?.cancel();
    unawaited(_owners?.cancel());
    _minutes.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: _route?.canPop == true
          ? BackButton(onPressed: _exitAction() ?? () {})
          : null,
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, _text('จับเวลาโฟกัส', 'Focus Timer')),
    ),
    body: AdaptiveContentPane(
      maxWidth: AdaptiveContentPane.formMaxWidth,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _text(
              'ตัวจับเวลานี้ใช้เฉพาะในเครื่อง และไม่บันทึกเป็นเวลาเรียน',
              'This local timer does not record learning time.',
            ),
          ),
          const SizedBox(height: 24),
          if (_visible && _timer.snapshot != null)
            ..._controls(_timer.snapshot!)
          else
            Text(
              _invalidated
                  ? _text(
                      'ตัวจับเวลาไม่พร้อมใช้งาน กรุณาเปิดใหม่',
                      'Timer unavailable. Open it again.',
                    )
                  : !_ownerKnown
                  ? _text(
                      'กำลังรอผู้ใช้งานปัจจุบัน',
                      'Waiting for the current owner.',
                    )
                  : _text(
                      'พักตัวจับเวลาไว้ขณะหน้านี้ไม่ทำงาน',
                      'Timer paused while this screen is inactive.',
                    ),
              key: const ValueKey('focus-status'),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            key: const ValueKey('focus-untimed'),
            onPressed: _exitAction(),
            child: Text(
              _text('เรียนต่อโดยไม่จับเวลา', 'Learn without a timer'),
            ),
          ),
        ],
      ),
    ),
  );

  String _duration(Duration value) {
    final seconds =
        (value.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  List<Widget> _controls(FocusTimerSnapshot snapshot) {
    final configure = _action(_configure);
    final editable = switch (snapshot.state) {
      FocusTimerState.configured ||
      FocusTimerState.stopped ||
      FocusTimerState.finished => true,
      _ => false,
    };
    final status = switch (snapshot.state) {
      FocusTimerState.configured => _text('พร้อมเริ่ม', 'Ready to start'),
      FocusTimerState.running => _text('กำลังจับเวลา', 'Running'),
      FocusTimerState.paused => _text(
        'พักอยู่ กดทำต่อเมื่อพร้อม',
        'Paused. Resume when ready.',
      ),
      FocusTimerState.stopped => _text(
        'หยุดและล้างช่วงเวลาแล้ว',
        'Stopped and cleared',
      ),
      FocusTimerState.finished =>
        snapshot.finishReason == FocusFinishReason.elapsed
            ? _text('ครบเวลาที่ตั้งไว้แล้ว', 'Interval complete')
            : _text('จบช่วงเวลาก่อนกำหนด', 'Finished early'),
    };
    Widget button(String key, String th, String en, VoidCallback command) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton(
            key: ValueKey(key),
            onPressed: _action(command),
            child: Text(_text(th, en)),
          ),
        );
    return [
      Semantics(
        liveRegion: true,
        child: Text(status, key: const ValueKey('focus-status')),
      ),
      const SizedBox(height: 16),
      Text(
        _duration(snapshot.remaining),
        key: const ValueKey('focus-remaining'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      if (snapshot.state == FocusTimerState.finished)
        Text(
          _text(
            'เวลาโฟกัสในช่วงนี้: ${_duration(snapshot.elapsed)} (ไม่บันทึก)',
            'Local focus interval: ${_duration(snapshot.elapsed)} (not recorded)',
          ),
        ),
      const SizedBox(height: 24),
      TextField(
        key: const ValueKey('focus-minutes'),
        controller: _minutes,
        enabled: editable,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: _text('นาที (1–180)', 'Minutes (1–180)'),
          errorText: _inputError,
          errorMaxLines: 4,
        ),
        onSubmitted: editable ? (_) => configure?.call() : null,
      ),
      if (editable)
        button('focus-configure', 'ตั้งเวลา', 'Set duration', _configure),
      if (snapshot.state == FocusTimerState.configured ||
          snapshot.state == FocusTimerState.stopped)
        button('focus-start', 'เริ่ม', 'Start', () {
          if (_configure()) {
            FocusScope.of(context).unfocus();
            _timer.start();
          }
        }),
      if (snapshot.state == FocusTimerState.running)
        button('focus-pause', 'พัก', 'Pause', _timer.pause),
      if (snapshot.state == FocusTimerState.paused)
        button('focus-resume', 'ทำต่อ', 'Resume', _timer.resume),
      if (snapshot.state == FocusTimerState.running ||
          snapshot.state == FocusTimerState.paused) ...[
        button(
          'focus-stop',
          'หยุดและล้างช่วงเวลา',
          'Stop and clear',
          _timer.stop,
        ),
        button(
          'focus-finish',
          'จบช่วงเวลานี้',
          'Finish this interval',
          _timer.finish,
        ),
      ],
      if (snapshot.state == FocusTimerState.finished)
        button('focus-new-interval', 'ช่วงเวลาใหม่', 'New interval', () {
          _timer.configureMinutes(snapshot.minutes);
          _inputError = null;
          _replaceInput(snapshot.minutes.toString());
        }),
    ];
  }
}
