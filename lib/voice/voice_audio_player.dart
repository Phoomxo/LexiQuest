import 'dart:typed_data';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'voice_models.dart';

AudioPlayer? _retainAudioPlayer(AudioPlayer? value) => value;

/// Provider-neutral boundary for playing synthesized WAV bytes.
abstract interface class VoiceAudioPlayer {
  Future<void> play(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

final class VoiceAudioPlayback {
  const VoiceAudioPlayback({required this.completed});
  final Future<void>? completed;
}

abstract interface class VoiceAudioPlayerWithCompletion
    implements VoiceAudioPlayer {
  Future<VoiceAudioPlayback> playWithCompletion(Uint8List bytes);
}

/// Narrow plugin boundary for platform-free player tests.
abstract interface class AudioPlayerAdapter {
  Future<void> playBytes(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

abstract interface class AudioPlayerAdapterWithCompletion
    implements AudioPlayerAdapter {
  Future<VoiceAudioPlayback> playBytesWithCompletion(Uint8List bytes);
}

/// Production adapter backed by an injected-or-default [AudioPlayer].
final class AudioplayersAdapter
    implements AudioPlayerAdapter, AudioPlayerAdapterWithCompletion {
  AudioplayersAdapter({
    AudioPlayer? audioPlayer,
    AudioPlayer Function()? audioPlayerFactory,
  }) : _audioPlayer = _retainAudioPlayer(audioPlayer),
       _audioPlayerFactory = audioPlayerFactory ?? AudioPlayer.new;

  AudioPlayer? _audioPlayer;
  final AudioPlayer Function() _audioPlayerFactory;
  _AudioPlaybackOperation? _activePlayback;
  int _generation = 0;

  AudioPlayer get _resolved => _audioPlayer ??= _audioPlayerFactory();

  @override
  Future<void> playBytes(Uint8List bytes) async {
    final generation = ++_generation;
    await _retirePlayback(_activePlayback, _playbackCancelledFailure);
    if (generation != _generation) return;
    await _playBytesRaw(bytes);
  }

  Future<void> _playBytesRaw(Uint8List bytes) =>
      _resolved.play(BytesSource(bytes, mimeType: 'audio/wav'));

  @override
  Future<VoiceAudioPlayback> playBytesWithCompletion(Uint8List bytes) async {
    final generation = ++_generation;
    await _retirePlayback(_activePlayback, _playbackCancelledFailure);
    if (generation != _generation) throw _playbackCancelledFailure;
    final completion = Completer<void>();
    completion.future.ignore();
    final operation = _AudioPlaybackOperation(completion);
    _activePlayback = operation;
    operation.subscription = _resolved.onPlayerComplete
        .take(1)
        .listen(
          (_) {
            if (identical(_activePlayback, operation)) _activePlayback = null;
            if (!completion.isCompleted) completion.complete();
          },
          onError: (Object _, StackTrace stackTrace) {
            if (identical(_activePlayback, operation)) _activePlayback = null;
            if (!completion.isCompleted) {
              completion.completeError(_playbackFailure, stackTrace);
            }
          },
          onDone: () {
            if (identical(_activePlayback, operation)) _activePlayback = null;
            if (!completion.isCompleted) {
              completion.completeError(_playbackFailure, StackTrace.current);
            }
          },
        );
    try {
      if (generation != _generation || !identical(_activePlayback, operation)) {
        throw _playbackCancelledFailure;
      }
      await _playBytesRaw(bytes);
      return VoiceAudioPlayback(completed: completion.future);
    } on Object {
      await _retirePlayback(operation, _playbackFailure);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _generation += 1;
    final retirement = _retirePlayback(
      _activePlayback,
      _playbackCancelledFailure,
    );
    try {
      final player = _audioPlayer;
      if (player != null) await player.stop();
    } finally {
      await retirement;
    }
  }

  @override
  Future<void> dispose() async {
    _generation += 1;
    final player = _audioPlayer;
    _audioPlayer = null;
    final retirement = _retirePlayback(
      _activePlayback,
      _playbackCancelledFailure,
    );
    try {
      if (player != null) await player.dispose();
    } finally {
      await retirement;
    }
  }

  Future<void> _retirePlayback(
    _AudioPlaybackOperation? operation,
    VoiceFailure failure,
  ) async {
    if (operation == null) return;
    if (identical(_activePlayback, operation)) _activePlayback = null;
    if (!operation.completion.isCompleted) {
      operation.completion.completeError(failure, StackTrace.current);
    }
    await operation.subscription?.cancel();
  }
}

final class _AudioPlaybackOperation {
  _AudioPlaybackOperation(this.completion);
  final Completer<void> completion;
  StreamSubscription<void>? subscription;
}

const _emptyBytesFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'Audio bytes are missing and cannot be played.',
);

const _playbackFailure = VoiceFailure(
  category: VoiceFailureCategory.playback,
  message: 'Audio playback failed.',
);

const _playbackCancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'Audio playback was stopped before completion.',
);

/// Plays WAV bytes through an injected [AudioPlayerAdapter].
final class PluginVoiceAudioPlayer
    implements VoiceAudioPlayer, VoiceAudioPlayerWithCompletion {
  PluginVoiceAudioPlayer(this._adapter);

  final AudioPlayerAdapter _adapter;

  @override
  Future<void> play(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw _emptyBytesFailure;
    }
    try {
      await _adapter.playBytes(Uint8List.fromList(bytes));
    } on Object {
      throw _playbackFailure;
    }
  }

  @override
  Future<VoiceAudioPlayback> playWithCompletion(Uint8List bytes) async {
    if (bytes.isEmpty) throw _emptyBytesFailure;
    final adapter = _adapter;
    if (adapter is! AudioPlayerAdapterWithCompletion) {
      await play(bytes);
      return const VoiceAudioPlayback(completed: null);
    }
    try {
      return await adapter.playBytesWithCompletion(Uint8List.fromList(bytes));
    } on VoiceFailure {
      rethrow;
    } on Object {
      throw _playbackFailure;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _adapter.stop();
    } on Object {
      throw _playbackFailure;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _adapter.dispose();
    } on Object {
      throw _playbackFailure;
    }
  }
}
