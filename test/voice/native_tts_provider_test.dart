import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

const _credentialSentinel = 'COINTH_GLM_API_KEY=super-secret-token';

VoiceRequest _validRequest({
  String text = 'Hello world.',
  String language = 'en',
  double speed = 1.0,
  VoiceMode mode = VoiceMode.practice,
  VoiceEngine? assignedEngine,
}) {
  return VoiceRequest.create(
    text: text,
    language: language,
    voiceId: 'teacher_female',
    speed: speed,
    contentId: 'word-001',
    contentType: 'word',
    mode: mode,
    assignedEngine: assignedEngine,
  );
}

double _recordedRate(_RecordingTtsAdapter adapter) {
  final invocation = adapter.invocations.firstWhere(
    (invocation) => invocation.call == _TtsCall.setSpeechRate,
  );
  return invocation.argument as double;
}

String _recordedLanguage(_RecordingTtsAdapter adapter) {
  final invocation = adapter.invocations.firstWhere(
    (invocation) => invocation.call == _TtsCall.setLanguage,
  );
  return invocation.argument as String;
}

Future<VoiceFailure> _captureSpeakFailure({
  required _TtsCall failingCall,
  required Object failure,
}) async {
  final adapter = _RecordingTtsAdapter(
    failingCall: failingCall,
    failure: failure,
  );
  final provider = NativeTtsProvider(adapter);
  try {
    await provider.speak(_validRequest());
    fail('Expected a VoiceFailure during speak.');
  } on VoiceFailure catch (voiceFailure) {
    return voiceFailure;
  }
}

Future<VoiceFailure> _captureStopFailure(Object failure) async {
  final adapter = _RecordingTtsAdapter(
    failingCall: _TtsCall.stop,
    failure: failure,
  );
  final provider = NativeTtsProvider(adapter);
  try {
    await provider.stop();
    fail('Expected a VoiceFailure during stop.');
  } on VoiceFailure catch (voiceFailure) {
    return voiceFailure;
  }
}

void main() {
  group('language mapping', () {
    test('maps English to en-US', () async {
      final adapter = _RecordingTtsAdapter();
      await NativeTtsProvider(adapter).speak(_validRequest(language: 'en'));
      expect(_recordedLanguage(adapter), 'en-US');
    });

    test('maps Thai to th-TH', () async {
      final adapter = _RecordingTtsAdapter();
      await NativeTtsProvider(adapter).speak(_validRequest(language: 'th'));
      expect(_recordedLanguage(adapter), 'th-TH');
    });
  });

  group('speed mapping', () {
    const cases = <(double, double)>[
      (0.5, 0.25),
      (0.75, 0.375),
      (1.0, 0.5),
      (1.25, 0.625),
      (1.5, 0.75),
    ];

    for (final (semantic, flutterRate) in cases) {
      test(
        'maps semantic speed $semantic to FlutterTts rate $flutterRate',
        () async {
          final adapter = _RecordingTtsAdapter();
          await NativeTtsProvider(
            adapter,
          ).speak(_validRequest(speed: semantic));
          expect(_recordedRate(adapter), flutterRate);
        },
      );
    }
  });

  test('configures the adapter and speaks normalized text in order', () async {
    final adapter = _RecordingTtsAdapter();
    final provider = NativeTtsProvider(adapter);

    await provider.speak(
      _validRequest(text: '  Hello   world.  ', language: 'en', speed: 1.0),
    );

    expect(adapter.invocations, [
      const _TtsInvocation(_TtsCall.setLanguage, 'en-US'),
      const _TtsInvocation(_TtsCall.setSpeechRate, 0.5),
      const _TtsInvocation(_TtsCall.setVolume, 1.0),
      const _TtsInvocation(_TtsCall.setPitch, 1.0),
      const _TtsInvocation(_TtsCall.speak, 'Hello world.'),
    ]);
  });

  group('successful speak result', () {
    test('reports native provenance without fallback or cache', () async {
      final adapter = _RecordingTtsAdapter();
      final result = await NativeTtsProvider(adapter).speak(_validRequest());

      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.requestedEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, isNull);
      expect(result.modelVersion, isNull);
    });

    test('requestedEngine follows the assigned engine', () async {
      final adapter = _RecordingTtsAdapter();
      final result = await NativeTtsProvider(
        adapter,
      ).speak(_validRequest(assignedEngine: VoiceEngine.omniVoice));

      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.requestedEngine, VoiceEngine.omniVoice);
    });
  });

  test('stop delegates exactly once to the adapter', () async {
    final adapter = _RecordingTtsAdapter();
    final provider = NativeTtsProvider(adapter);

    await provider.stop();

    expect(
      adapter.invocations
          .where((invocation) => invocation.call == _TtsCall.stop)
          .length,
      1,
    );
  });

  test('implements VoiceProvider', () {
    expect(NativeTtsProvider(_RecordingTtsAdapter()), isA<VoiceProvider>());
  });

  group('adapter failures during speak', () {
    for (final failingCall in <_TtsCall>[
      _TtsCall.setLanguage,
      _TtsCall.setSpeechRate,
      _TtsCall.setVolume,
      _TtsCall.setPitch,
      _TtsCall.speak,
    ]) {
      test('${failingCall.name} becomes a synthesis VoiceFailure', () async {
        final failure = await _captureSpeakFailure(
          failingCall: failingCall,
          failure: Exception('platform error exposing $_credentialSentinel'),
        );

        expect(failure.category, VoiceFailureCategory.synthesis);
        expect(failure.toString(), isNot(contains(_credentialSentinel)));
        expect(failure.toString(), isNot(contains('platform error exposing')));
      });
    }

    test('uses a fixed safe message for any source exception', () async {
      final first = await _captureSpeakFailure(
        failingCall: _TtsCall.speak,
        failure: StateError('boom one'),
      );
      final second = await _captureSpeakFailure(
        failingCall: _TtsCall.setLanguage,
        failure: Exception('completely different underlying reason'),
      );

      expect(first.category, VoiceFailureCategory.synthesis);
      expect(second.category, VoiceFailureCategory.synthesis);
      expect(first.toString(), second.toString());
    });
  });

  test('stop failure is a safe playback VoiceFailure', () async {
    final first = await _captureStopFailure(
      Exception('stop blew up exposing $_credentialSentinel'),
    );
    final second = await _captureStopFailure(StateError('other reason'));

    expect(first.category, VoiceFailureCategory.playback);
    expect(second.category, VoiceFailureCategory.playback);
    expect(first.toString(), second.toString());
    expect(first.toString(), isNot(contains(_credentialSentinel)));
    expect(first.toString(), isNot(contains('stop blew up exposing')));
  });
}

enum _TtsCall { setLanguage, setSpeechRate, setVolume, setPitch, speak, stop }

class _TtsInvocation {
  const _TtsInvocation(this.call, [this.argument]);

  final _TtsCall call;
  final Object? argument;

  @override
  bool operator ==(Object other) {
    if (other is! _TtsInvocation) return false;
    return other.call == call && other.argument == argument;
  }

  @override
  int get hashCode => Object.hash(call, argument);

  @override
  String toString() => '${call.name}($argument)';
}

class _RecordingTtsAdapter implements NativeTtsAdapter {
  _RecordingTtsAdapter({this.failingCall, this.failure});

  final List<_TtsInvocation> invocations = [];
  final _TtsCall? failingCall;
  final Object? failure;

  Future<void> _invoke(_TtsCall call, [Object? argument]) async {
    if (failingCall == call && failure != null) {
      throw failure!;
    }
    invocations.add(_TtsInvocation(call, argument));
  }

  @override
  Future<void> setLanguage(String language) =>
      _invoke(_TtsCall.setLanguage, language);

  @override
  Future<void> setSpeechRate(double rate) =>
      _invoke(_TtsCall.setSpeechRate, rate);

  @override
  Future<void> setVolume(double volume) => _invoke(_TtsCall.setVolume, volume);

  @override
  Future<void> setPitch(double pitch) => _invoke(_TtsCall.setPitch, pitch);

  @override
  Future<void> speak(String text) => _invoke(_TtsCall.speak, text);

  @override
  Future<void> stop() => _invoke(_TtsCall.stop);
}
