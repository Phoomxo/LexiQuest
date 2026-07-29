import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'voice_models.dart';

/// Provider-neutral boundary for playing synthesized WAV bytes.
abstract interface class VoiceAudioPlayer {
  Future<void> play(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

/// Narrow plugin boundary for platform-free player tests.
abstract interface class AudioPlayerAdapter {
  Future<void> playBytes(Uint8List bytes);

  Future<void> stop();

  Future<void> dispose();
}

/// Production adapter backed by an injected-or-default [AudioPlayer].
final class AudioplayersAdapter implements AudioPlayerAdapter {
  AudioplayersAdapter({AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer();

  final AudioPlayer _audioPlayer;

  @override
  Future<void> playBytes(Uint8List bytes) =>
      _audioPlayer.play(BytesSource(bytes, mimeType: 'audio/wav'));

  @override
  Future<void> stop() => _audioPlayer.stop();

  @override
  Future<void> dispose() => _audioPlayer.dispose();
}

const _emptyBytesFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'Audio bytes are missing and cannot be played.',
);

const _playbackFailure = VoiceFailure(
  category: VoiceFailureCategory.playback,
  message: 'Audio playback failed.',
);

/// Plays WAV bytes through an injected [AudioPlayerAdapter].
final class PluginVoiceAudioPlayer implements VoiceAudioPlayer {
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
