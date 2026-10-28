import 'dart:async';

import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';

/// Plays a route-owned word playlist through one opaque voice session.
final class BackgroundAudioPlayerService {
  BackgroundAudioPlayerService(
    VoiceSession voiceSession, {
    this.interItemDelay = const Duration(seconds: 2),
  }) : _voiceSession = voiceSession {
    if (interItemDelay < Duration.zero) {
      throw ArgumentError.value(
        interItemDelay,
        'interItemDelay',
        'must not be negative',
      );
    }
  }

  final VoiceSession _voiceSession;
  final Duration interItemDelay;

  bool _isPlaying = false;
  int _currentIndex = 0;
  int _runEpoch = 0;
  Completer<void>? _delayStopSignal;
  Timer? _delayTimer;
  Future<void>? _runFuture;
  Future<void>? _stopFuture;
  Future<void>? _disposeFuture;

  bool get isPlaying => _isPlaying;
  int get currentIndex => _currentIndex;

  Future<void> startPlaylist({
    required List<Map<String, String>> wordList,
    required void Function(int index) onWordChanged,
    void Function(VoiceFailure failure)? onFailure,
  }) {
    if (_disposeFuture != null || !_voiceSession.isCurrent) {
      return Future<void>.error(_cancelledFailure);
    }
    if (wordList.isEmpty) return Future<void>.value();
    final stopping = _stopFuture;
    if (stopping != null) {
      return stopping.then(
        (_) => startPlaylist(
          wordList: wordList,
          onWordChanged: onWordChanged,
          onFailure: onFailure,
        ),
      );
    }
    final activeRun = _runFuture;
    if (_isPlaying && activeRun != null) return activeRun;

    final runEpoch = ++_runEpoch;
    _isPlaying = true;
    _currentIndex = 0;
    late final Future<void> run;
    run =
        _playSequence(
          runEpoch: runEpoch,
          wordList: List<Map<String, String>>.unmodifiable(wordList),
          onWordChanged: onWordChanged,
          onFailure: onFailure,
        ).whenComplete(() {
          if (_runEpoch == runEpoch) {
            _isPlaying = false;
            _runFuture = null;
          }
        });
    _runFuture = run;
    return run;
  }

  Future<void> _playSequence({
    required int runEpoch,
    required List<Map<String, String>> wordList,
    required void Function(int index) onWordChanged,
    required void Function(VoiceFailure failure)? onFailure,
  }) async {
    for (var index = 0; index < wordList.length; index++) {
      if (!_accepts(runEpoch)) return;
      _currentIndex = index;
      if (!_accepts(runEpoch)) return;
      onWordChanged(index);

      final word = wordList[index]['word']?.trim() ?? '';
      if (word.isNotEmpty) {
        try {
          if (!_accepts(runEpoch)) return;
          await _voiceSession.speak(
            VoiceRequest.create(
              text: word,
              language: 'en',
              voiceId: 'teacher_female',
              speed: 1,
              mode: VoiceMode.practice,
              contentId: word,
              contentType: 'background_playlist',
            ),
          );
          if (!_accepts(runEpoch)) return;
        } on VoiceFailure catch (failure) {
          if (failure.category == VoiceFailureCategory.cancelled ||
              !_accepts(runEpoch)) {
            return;
          }
          onFailure?.call(failure);
          return;
        } on Object {
          if (!_accepts(runEpoch)) return;
          onFailure?.call(_unknownFailure);
          return;
        }
      }

      if (index == wordList.length - 1) return;
      if (!await _waitForNextItem(runEpoch)) return;
    }
  }

  bool _accepts(int runEpoch) =>
      _isPlaying &&
      _runEpoch == runEpoch &&
      _disposeFuture == null &&
      _voiceSession.isCurrent;

  Future<bool> _waitForNextItem(int runEpoch) async {
    if (!_accepts(runEpoch)) return false;
    final stopSignal = Completer<void>();
    _delayStopSignal = stopSignal;
    _delayTimer = Timer(interItemDelay, () {
      if (!stopSignal.isCompleted) stopSignal.complete();
    });
    await stopSignal.future;
    _delayTimer?.cancel();
    _delayTimer = null;
    if (identical(_delayStopSignal, stopSignal)) {
      _delayStopSignal = null;
    }
    return _accepts(runEpoch);
  }

  Future<void> stop() {
    final stopping = _stopFuture;
    if (stopping != null) return stopping;
    late final Future<void> operation;
    operation = _stopOnce().whenComplete(() {
      if (identical(_stopFuture, operation)) _stopFuture = null;
    });
    _stopFuture = operation;
    return operation;
  }

  Future<void> _stopOnce() async {
    final run = _runFuture;
    _isPlaying = false;
    _runEpoch++;
    final delaySignal = _delayStopSignal;
    if (delaySignal != null && !delaySignal.isCompleted) {
      delaySignal.complete();
    }
    _delayTimer?.cancel();
    _delayTimer = null;
    _delayStopSignal = null;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _voiceSession.stop();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    if (run != null) {
      await run.then<void>((_) {}, onError: (_) {});
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await stop();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _voiceSession.release();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}

const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'Playlist playback is no longer active.',
);

const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Playlist playback is unavailable.',
);
