import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
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
  test(
    'completion-capable player separates start from natural completion',
    () async {
      final adapter = _RecordingAudioPlayerAdapter();
      final playback = await PluginVoiceAudioPlayer(
        adapter,
      ).playWithCompletion(_wavBytes());
      var completed = false;
      playback.completed!.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      adapter.completeNaturally();
      await playback.completed;
      expect(completed, isTrue);
    },
  );

  test(
    'stop rejects an active completion instead of reporting natural end',
    () async {
      final adapter = _RecordingAudioPlayerAdapter();
      final player = PluginVoiceAudioPlayer(adapter);
      final playback = await player.playWithCompletion(_wavBytes());
      final failure = expectLater(
        playback.completed!,
        throwsA(
          isA<VoiceFailure>().having(
            (value) => value.category,
            'category',
            VoiceFailureCategory.cancelled,
          ),
        ),
      );
      await player.stop();
      await failure;
    },
  );

  test('plain adapter never fabricates a natural completion signal', () async {
    final player = PluginVoiceAudioPlayer(_PlainAudioPlayerAdapter());
    final playback = await player.playWithCompletion(_wavBytes());
    expect(playback.completed, isNull);
  });

  test(
    'audioplayers adapter completes only on the native completion event',
    () async {
      final native = _ControlledNativeAudioPlayer();
      final adapter = AudioplayersAdapter(audioPlayer: native);
      final playback = await adapter.playBytesWithCompletion(_wavBytes());
      var completed = false;
      playback.completed!.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      native.completeNaturally();
      await playback.completed;
      expect(completed, isTrue);
    },
  );

  test(
    'audioplayers adapter rejects completion when native stream closes',
    () async {
      final native = _ControlledNativeAudioPlayer();
      final adapter = AudioplayersAdapter(audioPlayer: native);
      final playback = await adapter.playBytesWithCompletion(_wavBytes());
      final failure = expectLater(
        playback.completed!,
        throwsA(isA<VoiceFailure>()),
      );
      await native.closeCompletionStream();
      await failure;
    },
  );

  test(
    'audioplayers adapter rejects completion on native stream error',
    () async {
      final native = _ControlledNativeAudioPlayer();
      final adapter = AudioplayersAdapter(audioPlayer: native);
      final playback = await adapter.playBytesWithCompletion(_wavBytes());
      final failure = expectLater(
        playback.completed!,
        throwsA(isA<VoiceFailure>()),
      );
      native.failCompletion(StateError('synthetic event error'));
      await failure;
    },
  );

  test('audioplayers adapter retires completion when stop throws', () async {
    final native = _ControlledNativeAudioPlayer(throwOnStop: true);
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final playback = await adapter.playBytesWithCompletion(_wavBytes());
    final completion = expectLater(
      playback.completed!,
      throwsA(isA<VoiceFailure>()),
    );
    await expectLater(adapter.stop(), throwsA(anything));
    await completion;
  });

  test('audioplayers adapter retires completion when dispose throws', () async {
    final native = _ControlledNativeAudioPlayer(throwOnDispose: true);
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final playback = await adapter.playBytesWithCompletion(_wavBytes());
    final completion = expectLater(
      playback.completed!,
      throwsA(isA<VoiceFailure>()),
    );
    await expectLater(adapter.dispose(), throwsA(anything));
    await completion;
  });

  test(
    'replacement rejects old completion and owns a fresh native event',
    () async {
      final native = _ControlledNativeAudioPlayer();
      final adapter = AudioplayersAdapter(audioPlayer: native);
      final first = await adapter.playBytesWithCompletion(_wavBytes());
      final retired = expectLater(
        first.completed!,
        throwsA(isA<VoiceFailure>()),
      );
      final second = await adapter.playBytesWithCompletion(_wavBytes());
      await retired;
      native.completeNaturally();
      await second.completed;
    },
  );

  test('plain play replacement retires the old completion proof', () async {
    final native = _ControlledNativeAudioPlayer();
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final first = await adapter.playBytesWithCompletion(_wavBytes());
    final retired = expectLater(first.completed!, throwsA(isA<VoiceFailure>()));
    await adapter.playBytes(_wavBytes());
    await retired;
    native.completeNaturally();
    expect(native.playCalls, 2);
  });

  test(
    'late failure from replaced native play cannot retire the new proof',
    () async {
      final firstPlay = Completer<void>();
      final native = _ControlledNativeAudioPlayer(playGates: [firstPlay, null]);
      final adapter = AudioplayersAdapter(audioPlayer: native);
      final firstStart = adapter.playBytesWithCompletion(_wavBytes());
      final firstFailure = expectLater(firstStart, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      await adapter.stop();
      final second = await adapter.playBytesWithCompletion(_wavBytes());
      firstPlay.completeError(StateError('late first play failure'));
      await firstFailure;
      var secondCompleted = false;
      second.completed!.then((_) => secondCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);
      native.completeNaturally();
      await second.completed;
    },
  );

  test('late stop acknowledgement cannot retire a replacement proof', () async {
    final stopGate = Completer<void>();
    final native = _ControlledNativeAudioPlayer(stopGate: stopGate);
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final first = await adapter.playBytesWithCompletion(_wavBytes());
    first.completed!.ignore();
    final stopping = adapter.stop();
    await Future<void>.delayed(Duration.zero);
    final second = await adapter.playBytesWithCompletion(_wavBytes());
    stopGate.complete();
    await stopping;
    var secondCompleted = false;
    second.completed!.then((_) => secondCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);
    native.completeNaturally();
    await second.completed;
  });

  test('stop begun without a proof cannot retire a later playback', () async {
    final stopGate = Completer<void>();
    final native = _ControlledNativeAudioPlayer(stopGate: stopGate);
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final stopping = adapter.stop();
    await Future<void>.delayed(Duration.zero);
    final playback = await adapter.playBytesWithCompletion(_wavBytes());
    stopGate.complete();
    await stopping;
    var completed = false;
    playback.completed!.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    native.completeNaturally();
    await playback.completed;
  });

  test(
    'late dispose acknowledgement cannot retire a replacement proof',
    () async {
      final disposeGate = Completer<void>();
      final firstNative = _ControlledNativeAudioPlayer(
        disposeGate: disposeGate,
      );
      final secondNative = _ControlledNativeAudioPlayer();
      final adapter = AudioplayersAdapter(
        audioPlayer: firstNative,
        audioPlayerFactory: () => secondNative,
      );
      final first = await adapter.playBytesWithCompletion(_wavBytes());
      first.completed!.ignore();
      final disposing = adapter.dispose();
      await Future<void>.delayed(Duration.zero);
      final second = await adapter.playBytesWithCompletion(_wavBytes());
      disposeGate.complete();
      await disposing;
      var secondCompleted = false;
      second.completed!.then((_) => secondCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);
      secondNative.completeNaturally();
      await second.completed;
    },
  );
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

final class _ControlledNativeAudioPlayer implements AudioPlayer {
  _ControlledNativeAudioPlayer({
    this.throwOnStop = false,
    this.throwOnDispose = false,
    this.playGates = const [],
    this.stopGate,
    this.disposeGate,
  });
  final bool throwOnStop;
  final bool throwOnDispose;
  final List<Completer<void>?> playGates;
  final Completer<void>? stopGate;
  final Completer<void>? disposeGate;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  int playCalls = 0;
  void completeNaturally() => _completions.add(null);
  void failCompletion(Object error) => _completions.addError(error);
  Future<void> closeCompletionStream() => _completions.close();
  @override
  Stream<void> get onPlayerComplete => _completions.stream;
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    final call = playCalls++;
    if (call < playGates.length) await playGates[call]?.future;
  }

  @override
  Future<void> stop() async {
    await stopGate?.future;
    if (throwOnStop) throw StateError('synthetic stop failure');
  }

  @override
  Future<void> dispose() async {
    await disposeGate?.future;
    if (throwOnDispose) throw StateError('synthetic dispose failure');
    if (disposeGate == null) await _completions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PlainAudioPlayerAdapter implements AudioPlayerAdapter {
  @override
  Future<void> playBytes(Uint8List bytes) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _RecordingAudioPlayerAdapter
    implements AudioPlayerAdapter, AudioPlayerAdapterWithCompletion {
  _RecordingAudioPlayerAdapter({this.failingCall, this.failure});

  final _AdapterCall? failingCall;
  final Object? failure;

  int playBytesCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  Uint8List? lastBytes;
  Completer<void>? _completion;

  void completeNaturally() => _completion!.complete();

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
  Future<VoiceAudioPlayback> playBytesWithCompletion(Uint8List bytes) async {
    await playBytes(bytes);
    _completion = Completer<void>();
    return VoiceAudioPlayback(completed: _completion!.future);
  }

  @override
  Future<void> stop() async {
    await _record(_AdapterCall.stop);
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.completeError(
        const VoiceFailure(
          category: VoiceFailureCategory.cancelled,
          message: 'synthetic stop',
        ),
      );
    }
  }

  @override
  Future<void> dispose() => _record(_AdapterCall.dispose);
}
