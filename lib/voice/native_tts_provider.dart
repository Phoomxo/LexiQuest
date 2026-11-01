import 'package:flutter_tts/flutter_tts.dart';

import 'voice_models.dart';
import 'voice_provider.dart';

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
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  @override
  Future<void> setLanguage(String language) async {
    await _flutterTts.setLanguage(language);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _flutterTts.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _flutterTts.setVolume(volume);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _flutterTts.setPitch(pitch);
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
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

const _nativeCancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'The voice request was cancelled.',
);

String _languageTagFor(String language) => language == 'th' ? 'th-TH' : 'en-US';

/// Synthesizes speech through the native on-device TTS engine.
final class NativeTtsProvider implements VoiceProvider {
  NativeTtsProvider(this._adapter);

  final NativeTtsAdapter _adapter;
  int _generation = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    final generation = ++_generation;
    try {
      await _adapter.setLanguage(_languageTagFor(request.language));
      _requireCurrentGeneration(generation);
      await _adapter.setSpeechRate(request.speed / 2);
      _requireCurrentGeneration(generation);
      await _adapter.setVolume(1.0);
      _requireCurrentGeneration(generation);
      await _adapter.setPitch(1.0);
      _requireCurrentGeneration(generation);
      await _adapter.speak(request.text);
      _requireCurrentGeneration(generation);
      return VoicePlaybackResult(
        requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );
    } on Object {
      _requireCurrentGeneration(generation);
      throw _nativeSynthesisFailure;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _adapter.stop();
    } on Object {
      throw _nativePlaybackFailure;
    }
  }

  void _requireCurrentGeneration(int generation) {
    if (generation != _generation) {
      throw _nativeCancelledFailure;
    }
  }
}
