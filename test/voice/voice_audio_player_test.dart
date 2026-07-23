import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

const String _credentialSentinel = 'COINTH_GLM_API_KEY=super-secret-token';
const String _bodySentinel = 'omnivoice-response-body-7c9f3a-leak';

Uint8List _wavBytes() => Uint8List.fromList(<int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x57,
  0x41,
  0x56,
  0x45,
]);

Future<VoiceFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
    fail('Expected a VoiceFailure.');
  } on VoiceFailure catch (failure) {
    return failure;
  }
}

void main() {
  test('delegates non-empty WAV bytes to playBytes exactly once', () async {
    final adapter = _RecordingAudioPlayerAdapter();
    final bytes = _wavBytes();

    await PluginVoiceAudioPlayer(adapter).play(bytes);

    expect(adapter.playBytesCount, 1);
    expect(adapter.lastBytes, bytes);
  });

  test('passes a defensive copy of caller bytes to adapter', () async {
    final adapter = _RecordingAudioPlayerAdapter();
    final bytes = _wavBytes();
    final player = PluginVoiceAudioPlayer(adapter);

    await player.play(bytes);

    expect(
      identical(adapter.lastBytes, bytes),
      isFalse,
      reason: 'adapter must receive a copy, not the caller reference',
    );
    expect(adapter.lastBytes, _wavBytes());

    bytes[0] = 0xFF;

    expect(adapter.lastBytes, _wavBytes());
    expect(adapter.lastBytes![0], 0x52);
  });

  test('rejects empty input before touching adapter', () async {
    final adapter = _RecordingAudioPlayerAdapter();
    final player = PluginVoiceAudioPlayer(adapter);

    final failure = await _captureFailure(() => player.play(Uint8List(0)));

    expect(failure.category, VoiceFailureCategory.validation);
    expect(adapter.playBytesCount, 0);
    expect(adapter.stopCount, 0);
    expect(adapter.disposeCount, 0);
  });

  test('uses one fixed safe message for empty input', () async {
    final first = await _captureFailure(
      () => PluginVoiceAudioPlayer(
        _RecordingAudioPlayerAdapter(),
      ).play(Uint8List(0)),
    );
    final second = await _captureFailure(
      () => PluginVoiceAudioPlayer(
        _RecordingAudioPlayerAdapter(),
      ).play(Uint8List(0)),
    );

    expect(first.category, VoiceFailureCategory.validation);
    expect(second.category, VoiceFailureCategory.validation);
    expect(first.toString(), second.toString());
  });

  test('stop delegates exactly once', () async {
    final adapter = _RecordingAudioPlayerAdapter();

    await PluginVoiceAudioPlayer(adapter).stop();

    expect(adapter.stopCount, 1);
  });

  test('dispose delegates exactly once', () async {
    final adapter = _RecordingAudioPlayerAdapter();

    await PluginVoiceAudioPlayer(adapter).dispose();

    expect(adapter.disposeCount, 1);
  });

  group('adapter failures', () {
    for (final call in <_AdapterCall>[
      _AdapterCall.playBytes,
      _AdapterCall.stop,
      _AdapterCall.dispose,
    ]) {
      test('${call.name} becomes a safe playback failure', () async {
        final adapter = _RecordingAudioPlayerAdapter(
          failingCall: call,
          failure: Exception(
            'playback crashed exposing $_credentialSentinel and $_bodySentinel',
          ),
        );
        final player = PluginVoiceAudioPlayer(adapter);

        final failure = await _captureFailure(() => _perform(player, call));

        expect(failure.category, VoiceFailureCategory.playback);
        expect(failure.toString(), isNot(contains(_credentialSentinel)));
        expect(failure.toString(), isNot(contains(_bodySentinel)));
      });
    }

    test('uses one fixed safe message for any playback failure', () async {
      final playFailure = await _captureFailure(
        () => PluginVoiceAudioPlayer(
          _RecordingAudioPlayerAdapter(
            failingCall: _AdapterCall.playBytes,
            failure: StateError('boom one'),
          ),
        ).play(_wavBytes()),
      );
      final stopFailure = await _captureFailure(
        () => PluginVoiceAudioPlayer(
          _RecordingAudioPlayerAdapter(
            failingCall: _AdapterCall.stop,
            failure: Exception('different underlying reason'),
          ),
        ).stop(),
      );
      final disposeFailure = await _captureFailure(
        () => PluginVoiceAudioPlayer(
          _RecordingAudioPlayerAdapter(
            failingCall: _AdapterCall.dispose,
            failure: Exception('dispose broke differently'),
          ),
        ).dispose(),
      );

      expect(playFailure.category, VoiceFailureCategory.playback);
      expect(stopFailure.category, VoiceFailureCategory.playback);
      expect(disposeFailure.category, VoiceFailureCategory.playback);
      expect(playFailure.toString(), stopFailure.toString());
      expect(stopFailure.toString(), disposeFailure.toString());
    });
  });

  test('implements VoiceAudioPlayer', () {
    expect(
      PluginVoiceAudioPlayer(_RecordingAudioPlayerAdapter()),
      isA<VoiceAudioPlayer>(),
    );
  });
}

Future<void> _perform(PluginVoiceAudioPlayer player, _AdapterCall call) {
  return switch (call) {
    _AdapterCall.playBytes => player.play(_wavBytes()),
    _AdapterCall.stop => player.stop(),
    _AdapterCall.dispose => player.dispose(),
  };
}

enum _AdapterCall { playBytes, stop, dispose }

class _RecordingAudioPlayerAdapter implements AudioPlayerAdapter {
  _RecordingAudioPlayerAdapter({this.failingCall, this.failure});

  final _AdapterCall? failingCall;
  final Object? failure;

  int playBytesCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  Uint8List? lastBytes;

  Future<void> _record(_AdapterCall call, [Object? argument]) async {
    if (failingCall == call && failure != null) {
      throw failure!;
    }
    switch (call) {
      case _AdapterCall.playBytes:
        lastBytes = argument as Uint8List;
        playBytesCount++;
      case _AdapterCall.stop:
        stopCount++;
      case _AdapterCall.dispose:
        disposeCount++;
    }
  }

  @override
  Future<void> playBytes(Uint8List bytes) =>
      _record(_AdapterCall.playBytes, bytes);

  @override
  Future<void> stop() => _record(_AdapterCall.stop);

  @override
  Future<void> dispose() => _record(_AdapterCall.dispose);
}
