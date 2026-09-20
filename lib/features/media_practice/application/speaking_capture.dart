import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'speech_practice_use_cases.dart';
import '../domain/media_practice_contracts.dart';

/// One owned recognition attempt. Retained cleanup drains before every retry.
/// No callback writes history; submission captures the confirmed event later.
class SpeakingCapture extends ChangeNotifier {
  SpeakingCapture({
    required this.speech,
    required this.requireCurrent,
    this.timeout = const Duration(seconds: 20),
  });
  final SpeechPracticeUseCases speech;
  final Future<void> Function() requireCurrent;
  final Duration timeout;
  String? operationId, failure;
  SpeechRecognitionEvent? event;
  bool confirmed = false, listening = false;
  bool _closed = false, _disposed = false, _finalSeen = false;
  int _epoch = 0, _delivery = 0;
  SpeechPracticeSession? _session;
  Timer? _timer;
  Future<void> _cleanup = Future<void>.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _retain(Future<void> operation) {
    final drain = Future.wait<void>([_cleanup, operation]).then<void>((_) {});
    _cleanup = drain;
    // Retain a failed barrier to prevent unsafe reacquisition, but consume the
    // unhandled branch at asynchronous lifecycle boundaries.
    drain.ignore();
    return drain;
  }

  bool _current(int epoch) => !_closed && !_disposed && epoch == _epoch;
  Future<bool> _validate(int epoch) async {
    if (!_current(epoch)) return false;
    try {
      await requireCurrent();
    } on Object {
      if (_current(epoch)) {
        await close().catchError((Object _) {});
      }
      return false;
    }
    return _current(epoch);
  }

  Future<void> cancel() {
    _epoch++;
    _delivery++;
    _timer?.cancel();
    listening = false;
    confirmed = false;
    event = null;
    operationId = null;
    final session = _session;
    _session = null;
    final drain = _retain(session?.release() ?? Future<void>.value());
    _notify();
    return drain;
  }

  Future<void> close() {
    _closed = true;
    return cancel();
  }

  Future<void> start() async {
    if (_closed || _disposed) return;
    final drain = cancel();
    final epoch = _epoch;
    failure = null;
    try {
      await drain;
      if (!await _validate(epoch)) return;
      operationId = const Uuid().v4();
      _finalSeen = false;
      final session = speech.acquireSession();
      _session = session;
      listening = true;
      _notify();
      _timer = Timer(timeout, () {
        if (_current(epoch)) {
          _fail(epoch, 'Recognition timed out. Repeat or use text fallback.');
        }
      });
      final started = await session.start(
        locale: 'en-US',
        onEvent: (value) {
          if (!_current(epoch) || _finalSeen) return;
          final delivery = ++_delivery;
          if (value.isFinal) _finalSeen = true;
          _deliver(epoch, delivery, value, session).ignore();
        },
        onFailure: (value) {
          if (_current(epoch)) _fail(epoch, value.name);
        },
        onStatus: (_) {},
      );
      if (!started && _current(epoch)) {
        _fail(epoch, 'Recognition session was replaced. Repeat when ready.');
      }
    } on SpeechPracticeException catch (error) {
      if (_current(epoch)) _fail(epoch, error.code.name);
    } on Object {
      if (_current(epoch)) {
        _fail(epoch, 'Recognition unavailable. Retry or use text fallback.');
      }
    }
  }

  Future<void> _deliver(
    int epoch,
    int delivery,
    SpeechRecognitionEvent value,
    SpeechPracticeSession session,
  ) async {
    if (!await _validate(epoch) || delivery != _delivery) return;
    if (!session.isCurrent) {
      await cancel();
      return;
    }
    event = value;
    confirmed = false;
    if (value.isFinal) {
      _timer?.cancel();
      listening = false;
      final session = _session;
      _session = null;
      _retain(session?.release() ?? Future<void>.value());
    }
    _notify();
  }

  void _fail(int epoch, String message) {
    if (!_current(epoch)) return;
    cancel().ignore();
    failure = message;
    _notify();
  }

  Future<void> confirm() async {
    final epoch = _epoch;
    if (!await _validate(epoch)) return;
    final value = event;
    if (value == null || !value.isFinal || value.transcript.trim().isEmpty) {
      return;
    }
    confirmed = true;
    _notify();
  }

  Future<void> stop() async {
    final epoch = _epoch;
    final session = _session;
    if (session == null || !await _validate(epoch)) return;
    try {
      await _retain(session.stop());
    } on Object {
      _fail(epoch, 'Could not finish recognition. Repeat.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    close().ignore();
    super.dispose();
  }
}
