import 'dart:async';

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

/// Optional native capability used to prove that a selected voice is fully
/// installed and does not require a network connection.
abstract interface class NativeTtsLocalVoiceAdapter {
  Future<Object?> isLanguageInstalled(String language);

  Future<Object?> loadVoices();

  Future<Object?> selectVoice({required String name, required String locale});
}

/// Optional natural-end proof for the most recently acknowledged utterance.
abstract interface class NativeTtsPlaybackAdapter {
  Future<void>? get playbackCompleted;
}

/// Production [NativeTtsAdapter] backed by an injected-or-default [FlutterTts].
final class FlutterTtsAdapter
    implements
        NativeTtsAdapter,
        NativeTtsLocalVoiceAdapter,
        NativeTtsPlaybackAdapter {
  FlutterTtsAdapter({FlutterTts? flutterTts})
    : _flutterTts = _retainFlutterTts(flutterTts);

  FlutterTts? _flutterTts;
  Completer<void>? _activePlayback;
  Future<void>? _lastPlaybackCompleted;
  bool _completionTrusted = true;

  @override
  Future<void>? get playbackCompleted => _lastPlaybackCompleted;

  // Plugin construction is deliberately deferred until the first native
  // request. Bootstrap can therefore expose native speech even when a
  // headless host has no platform messenger, and remote composition failure
  // cannot remove the native route.
  FlutterTts get _resolved => _flutterTts ??= FlutterTts();

  @override
  Future<Object?> isLanguageInstalled(String language) async {
    return await _resolved.isLanguageInstalled(language);
  }

  @override
  Future<Object?> loadVoices() async {
    return await _resolved.getVoices;
  }

  @override
  Future<Object?> selectVoice({
    required String name,
    required String locale,
  }) async {
    return await _resolved.setVoice(<String, String>{
      'name': name,
      'locale': locale,
    });
  }

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
    if (_activePlayback != null) await stop();
    final playback = _completionTrusted ? Completer<void>() : null;
    _activePlayback = playback;
    _lastPlaybackCompleted = playback?.future;
    if (playback != null) {
      // Observe errors even for callers that only request a start acknowledgement.
      unawaited(playback.future.then<void>((_) {}, onError: (_, _) {}));
      _resolved.setCompletionHandler(() {
        if (!identical(_activePlayback, playback)) return;
        _activePlayback = null;
        if (!playback.isCompleted) playback.complete();
      });
      void interrupted() {
        if (!identical(_activePlayback, playback)) return;
        _completionTrusted = false;
        if (!playback.isCompleted) {
          playback.completeError(_nativePlaybackFailure);
        }
      }

      _resolved.setCancelHandler(interrupted);
      _resolved.setErrorHandler((_) => interrupted());
    }
    try {
      await _resolved.speak(text);
    } on Object {
      if (playback != null && !playback.isCompleted) {
        _completionTrusted = false;
        playback.completeError(_nativeSynthesisFailure);
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final flutterTts = _flutterTts;
    final playback = _activePlayback;
    if (playback != null) {
      // flutter_tts terminal callbacks carry no utterance ID. After interruption
      // a late callback cannot authenticate a replacement's natural end. Keep
      // ordinary speech available, but withhold completion proof until this
      // runtime adapter is replaced. Never infer completion from a delay.
      _completionTrusted = false;
      _activePlayback = null;
    }
    if (flutterTts != null) {
      try {
        await flutterTts.stop();
      } on Object {
        if (playback != null && !playback.isCompleted) {
          playback.completeError(_nativePlaybackFailure);
        }
        rethrow;
      }
    }
    if (playback != null && !playback.isCompleted) {
      playback.completeError(
        const VoiceFailure(
          category: VoiceFailureCategory.cancelled,
          message: 'On-device speech was stopped.',
        ),
      );
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
      final languageTag = _languageTagFor(request.language);
      final localVoice = request.localOnly
          ? await _requireInstalledLocalVoice(languageTag)
          : null;

      await _adapter.setLanguage(languageTag);
      if (localVoice != null) {
        final localAdapter = _adapter as NativeTtsLocalVoiceAdapter;
        final selected = await localAdapter.selectVoice(
          name: localVoice.name,
          locale: localVoice.locale,
        );
        if (selected != 1) {
          throw StateError('Native local voice selection failed.');
        }
      }
      await _adapter.setSpeechRate(request.speed / 2);
      await _adapter.setVolume(1.0);
      await _adapter.setPitch(1.0);
      await _adapter.speak(request.text);
      return VoicePlaybackResult(
        requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
        playbackCompleted: _adapter is NativeTtsPlaybackAdapter
            ? (_adapter as NativeTtsPlaybackAdapter).playbackCompleted
            : null,
      );
    } on Object {
      throw _nativeSynthesisFailure;
    }
  }

  Future<_InstalledLocalVoice> _requireInstalledLocalVoice(
    String languageTag,
  ) async {
    final adapter = _adapter;
    if (adapter is! NativeTtsLocalVoiceAdapter) {
      throw StateError('Native local voice proof is unavailable.');
    }
    final localAdapter = adapter as NativeTtsLocalVoiceAdapter;

    final installed = await localAdapter.isLanguageInstalled(languageTag);
    if (installed != true) {
      throw StateError('Native language is not installed.');
    }

    final rawVoices = await localAdapter.loadVoices();
    if (rawVoices is! Iterable<Object?>) {
      throw StateError('Native voice inventory is unavailable.');
    }

    final candidates = <_InstalledLocalVoice>[];
    for (final rawVoice in rawVoices) {
      if (rawVoice is! Map<Object?, Object?>) {
        continue;
      }
      final name = rawVoice['name'];
      final locale = rawVoice['locale'];
      final networkRequired = rawVoice['network_required'];
      final features = rawVoice['features'];
      if (name is! String ||
          name.trim().isEmpty ||
          locale is! String ||
          locale.toLowerCase() != languageTag.toLowerCase() ||
          networkRequired != '0' ||
          features is! String ||
          _hasNotInstalledFeature(features)) {
        continue;
      }
      candidates.add(_InstalledLocalVoice(name: name.trim(), locale: locale));
    }
    if (candidates.isEmpty) {
      throw StateError('No installed local voice is available.');
    }
    candidates.sort((left, right) {
      final byName = left.name.compareTo(right.name);
      return byName != 0 ? byName : left.locale.compareTo(right.locale);
    });
    return candidates.first;
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

bool _hasNotInstalledFeature(String features) {
  return features
      .split('\t')
      .map((feature) => feature.trim().toLowerCase())
      .contains('notinstalled');
}

final class _InstalledLocalVoice {
  const _InstalledLocalVoice({required this.name, required this.locale});

  final String name;
  final String locale;
}
