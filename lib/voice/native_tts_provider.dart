import 'package:flutter_tts/flutter_tts.dart';

import 'voice_models.dart';
import 'voice_provider.dart';

FlutterTts? _retainFlutterTts(FlutterTts? value) => value;

/// Narrow boundary over the on-device plugin for platform-free provider tests.
abstract interface class NativeTtsAdapter {
  Future<void> setLanguage(String language);

  Future<void> setSpeechRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> setPitch(double pitch);

  Future<void> speak(String text);

  Future<void> stop();
}

/// Production [NativeTtsAdapter] backed by an injected-or-default [FlutterTts].
final class FlutterTtsAdapter implements NativeTtsAdapter {
  FlutterTtsAdapter({FlutterTts? flutterTts})
    : _flutterTts = _retainFlutterTts(flutterTts);

  FlutterTts? _flutterTts;

  // Plugin construction is deliberately deferred until the first native
  // request. Bootstrap can therefore expose native speech even when a
  // headless host has no platform messenger, and remote composition failure
  // cannot remove the native route.
  FlutterTts get _resolved => _flutterTts ??= FlutterTts();

  @override
  Future<void> setLanguage(String language) async {
    await _resolved.setLanguage(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _resolved.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _resolved.setVolume(volume);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _resolved.setPitch(pitch);
  }

  @override
  Future<void> speak(String text) async {
    await _resolved.speak(text);
  }

  @override
  Future<void> stop() async {
    final flutterTts = _flutterTts;
    if (flutterTts != null) {
      await flutterTts.stop();
    }
  }
}

const _nativeSynthesisFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'On-device speech synthesis failed.',
);

const _nativePlaybackFailure = VoiceFailure(
  category: VoiceFailureCategory.playback,
  message: 'On-device speech playback failed.',
);

String _languageTagFor(String language) => language == 'th' ? 'th-TH' : 'en-US';

/// Synthesizes speech through the native on-device TTS engine.
final class NativeTtsProvider implements VoiceProvider {
  NativeTtsProvider(this._adapter);

  final NativeTtsAdapter _adapter;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    try {
      await _adapter.setLanguage(_languageTagFor(request.language));
      await _adapter.setSpeechRate(request.speed / 2);
      await _adapter.setVolume(1.0);
      await _adapter.setPitch(1.0);
      await _adapter.speak(request.text);
      return VoicePlaybackResult(
        requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );
    } on Object {
      throw _nativeSynthesisFailure;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _adapter.stop();
    } on Object {
      throw _nativePlaybackFailure;
    }
  }
}
