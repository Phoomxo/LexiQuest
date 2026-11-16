import 'dart:math' as math;

import '../domain/media_practice_contracts.dart';

final class SpeechPracticeUseCases {
  SpeechPracticeUseCases(this.gateway);

  final SpeechRecognitionGateway gateway;
  Future<void>? _startup;
  Future<void>? _cleanup;
  int _generation = 0;
  bool _starting = false;
  bool _acceptCallbacks = false;
  bool _listenDispatched = false;
  bool _stopped = false;
  bool _disposed = false;

  bool get isListening => _acceptCallbacks && !_stopped && gateway.isListening;

  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) {
    if (_disposed) {
      return Future.error(
        const SpeechPracticeException(SpeechFailureCode.cancelled),
      );
    }
    if (_starting || (_acceptCallbacks && !_stopped)) {
      return _startup ?? Future<void>.value();
    }
    final generation = ++_generation;
    final previous = _startup;
    _starting = true;
    _acceptCallbacks = true;
    _listenDispatched = false;
    _stopped = false;
    late final Future<void> operation;
    operation =
        _start(
          generation: generation,
          previous: previous,
          locale: locale,
          onEvent: onEvent,
          onFailure: onFailure,
          onStatus: onStatus,
        ).whenComplete(() {
          if (identical(_startup, operation)) _startup = null;
          if (generation == _generation) _starting = false;
        });
    _startup = operation;
    return operation;
  }

  Future<void> _start({
    required int generation,
    required Future<void>? previous,
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    var dispatched = false;
    try {
      if (previous != null) {
        await previous.then<void>((_) {}, onError: (_) {});
      }
      // Cancelled startup may have scheduled a compensating platform cancel.
      final cleanup = _cleanup;
      if (cleanup != null) await cleanup;
      _requireCurrent(generation);
      final permission = await gateway.requestPermission();
      _requireCurrent(generation);
      switch (permission) {
        case MediaPermissionState.granted:
          break;
        case MediaPermissionState.permanentlyDenied:
          throw const SpeechPracticeException(
            SpeechFailureCode.permissionPermanentlyDenied,
          );
        case MediaPermissionState.denied:
        case MediaPermissionState.restricted:
          throw const SpeechPracticeException(
            SpeechFailureCode.permissionDenied,
          );
        case MediaPermissionState.unavailable:
          throw const SpeechPracticeException(SpeechFailureCode.unavailable);
      }
      bool accepts() =>
          generation == _generation && _acceptCallbacks && !_disposed;
      await gateway.initialize(
        onFailure: (failure) {
          if (!accepts()) return;
          _acceptCallbacks = false;
          onFailure(failure);
        },
        onStatus: (status) {
          if (!accepts()) return;
          if (status == 'notListening') _stopped = true;
          if (status == 'done') {
            _acceptCallbacks = false;
            onFailure(SpeechFailureCode.noMatch);
          }
          onStatus(status);
        },
      );
      _requireCurrent(generation);
      if (!_acceptCallbacks) return;
      _stopped = false;
      _listenDispatched = true;
      dispatched = true;
      await gateway.start(
        locale: locale,
        onEvent: (event) {
          if (!accepts()) return;
          if (event.isFinal) _acceptCallbacks = false;
          if (event.transcript.trim().isEmpty) {
            if (event.isFinal) onFailure(SpeechFailureCode.noMatch);
            return;
          }
          onEvent(event);
        },
      );
      _requireCurrent(generation);
    } on Object {
      if (generation == _generation) _acceptCallbacks = false;
      if (_disposed || generation != _generation) {
        // A delayed platform start can activate the mic after the first cancel.
        if (dispatched) await _runCleanup(gateway.cancel);
        _requireCurrent(generation);
      }
      rethrow;
    }
  }

  Future<void> stop() {
    if (!_listenDispatched) return cancel();
    // A normal stop may deliver the recognizer's final result.
    _stopped = true;
    return _runCleanup(gateway.stop);
  }

  Future<void> cancel() {
    _generation += 1;
    _acceptCallbacks = false;
    _starting = false;
    _listenDispatched = false;
    return _runCleanup(gateway.cancel);
  }

  Future<void> _runCleanup(Future<void> Function() action) {
    final previous = _cleanup;
    final operation = () async {
      if (previous != null) {
        await previous.then<void>((_) {}, onError: (_) {});
      }
      await action();
    }();
    _cleanup = operation;
    return operation;
  }

  void _requireCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw const SpeechPracticeException(SpeechFailureCode.cancelled);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
  }

  TranscriptPronunciationAssessment assess({
    required String target,
    required SpeechRecognitionEvent event,
  }) {
    final canonicalTarget = _canonical(target);
    final canonicalTranscript = _canonical(event.transcript);
    if (canonicalTarget.isEmpty || canonicalTranscript.isEmpty) {
      throw const SpeechPracticeException(SpeechFailureCode.noMatch);
    }
    final distance = _levenshtein(canonicalTarget, canonicalTranscript);
    final denominator = math.max(
      canonicalTarget.runes.length,
      canonicalTranscript.runes.length,
    );
    final score = ((1 - (distance / denominator)) * 100).clamp(0, 100).round();
    return TranscriptPronunciationAssessment(
      target: target,
      transcript: event.transcript,
      similarityPercent: score,
      isExactMatch: canonicalTarget == canonicalTranscript,
      method: 'transcript-edit-distance-v1',
      engine: event.engine,
      locale: event.locale,
      occurredAtUtc: event.recognizedAtUtc,
    );
  }

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static int _levenshtein(String left, String right) {
    final a = left.runes.toList(growable: false);
    final b = right.runes.toList(growable: false);
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var row = 0; row < a.length; row += 1) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = row + 1;
      for (var column = 0; column < b.length; column += 1) {
        final substitution = previous[column] + (a[row] == b[column] ? 0 : 1);
        current[column + 1] = math.min(
          math.min(current[column] + 1, previous[column + 1] + 1),
          substitution,
        );
      }
      previous = current;
    }
    return previous.last;
  }
}
