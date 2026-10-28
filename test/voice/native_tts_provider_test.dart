import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
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
  bool localOnly = false,
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
    localOnly: localOnly,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native playback completion proof', () {
    test(
      'native cancellation stays cancelled through completion-owned facade',
      () async {
        final plugin = _CompletionFlutterTts()..stopBarrier = Completer<void>();
        final provider = NativeTtsProvider(
          FlutterTtsAdapter(flutterTts: plugin),
        );
        final useCases = VoiceUseCases(
          provider: provider,
          disposeProvider: provider.stop,
        );
        final session = useCases.acquireSession();
        var settled = false;
        final expectation = expectLater(
          session.speakUntilCompleted(_validRequest()),
          throwsA(
            isA<VoiceFailure>().having(
              (e) => e.category,
              'category',
              VoiceFailureCategory.cancelled,
            ),
          ),
        ).then((_) => settled = true);
        await Future<void>.delayed(Duration.zero);
        final stopping = session.stop();
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        plugin.stopBarrier!.complete();
        await stopping;
        await expectation;
        await useCases.dispose();
      },
    );
    test('actual adapter start acknowledgement precedes natural end', () async {
      final plugin = _CompletionFlutterTts();
      final provider = NativeTtsProvider(FlutterTtsAdapter(flutterTts: plugin));
      final result = await provider.speak(_validRequest());
      var ended = false;
      final completion = result.playbackCompleted!;
      completion.then((_) => ended = true);
      await Future<void>.delayed(Duration.zero);
      expect(plugin.speakCalls, 1);
      expect(ended, isFalse);
      plugin.completionHandler!();
      await completion;
      expect(ended, isTrue);
      await provider.stop();
    });

    test(
      'stop requires acknowledgement and quarantines untagged late events',
      () async {
        final plugin = _CompletionFlutterTts()..stopBarrier = Completer<void>();
        final provider = NativeTtsProvider(
          FlutterTtsAdapter(flutterTts: plugin),
        );
        final first = await provider.speak(_validRequest());
        final oldEnd = plugin.completionHandler!;
        var ended = false;
        final stoppedExpectation = expectLater(
          first.playbackCompleted,
          throwsA(
            isA<VoiceFailure>().having(
              (e) => e.category,
              'category',
              VoiceFailureCategory.cancelled,
            ),
          ),
        ).then((_) => ended = true);
        final stopping = provider.stop();
        oldEnd();
        await Future<void>.delayed(Duration.zero);
        expect(ended, isFalse);
        plugin.stopBarrier!.complete();
        await stopping;
        await stoppedExpectation;
        final replacement = await provider.speak(
          _validRequest(text: 'Replacement.'),
        );
        expect(plugin.speakCalls, 2);
        expect(
          replacement.playbackCompleted,
          isNull,
          reason:
              'Untagged interrupted native completion stays unavailable for this adapter lifetime.',
        );
        oldEnd();
        await provider.stop();
      },
    );

    test(
      'retired natural-end closure cannot settle a fresh utterance',
      () async {
        final plugin = _CompletionFlutterTts();
        final provider = NativeTtsProvider(
          FlutterTtsAdapter(flutterTts: plugin),
        );
        final first = await provider.speak(_validRequest());
        final oldEnd = plugin.completionHandler!;
        oldEnd();
        await first.playbackCompleted;
        final second = await provider.speak(_validRequest(text: 'Second.'));
        var ended = false;
        second.playbackCompleted!.then((_) => ended = true);
        oldEnd();
        await Future<void>.delayed(Duration.zero);
        expect(ended, isFalse);
        plugin.completionHandler!();
        await second.playbackCompleted;
        expect(ended, isTrue);
        await provider.stop();
      },
    );
  });
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

  group('local-only installed voice proof', () {
    Future<VoiceFailure> localFailure(NativeTtsAdapter adapter) async {
      try {
        await NativeTtsProvider(adapter).speak(_validRequest(localOnly: true));
        fail('Expected local-only native synthesis to fail closed.');
      } on VoiceFailure catch (failure) {
        return failure;
      }
    }

    test(
      'adapter without local proof capability fails before text speak',
      () async {
        final adapter = _LegacyTtsAdapter();

        final failure = await localFailure(adapter);

        expect(failure.category, VoiceFailureCategory.synthesis);
        expect(adapter.speakCalls, 0);
        expect(adapter.setLanguageCalls, 0);
      },
    );

    test(
      'not-installed language fails before voice lookup and speak',
      () async {
        final adapter = _RecordingTtsAdapter(languageInstalled: false);

        final failure = await localFailure(adapter);

        expect(failure.category, VoiceFailureCategory.synthesis);
        expect(adapter.invocations, const <_TtsInvocation>[
          _TtsInvocation(_TtsCall.isLanguageInstalled, 'en-US'),
        ]);
      },
    );

    test('missing voices fail before selection and speak', () async {
      final adapter = _RecordingTtsAdapter(voices: const <Object?>[]);

      final failure = await localFailure(adapter);

      expect(failure.category, VoiceFailureCategory.synthesis);
      expect(adapter.invocations.map((call) => call.call), const <_TtsCall>[
        _TtsCall.isLanguageInstalled,
        _TtsCall.loadVoices,
      ]);
      expect(
        adapter.invocations.where((call) => call.call == _TtsCall.speak),
        isEmpty,
      );
    });

    test('network-only voice fails before selection and speak', () async {
      final adapter = _RecordingTtsAdapter(
        voices: const <Object?>[
          <String, Object?>{
            'name': 'network-en',
            'locale': 'en-US',
            'network_required': '1',
            'features': 'networkTts',
          },
        ],
      );

      final failure = await localFailure(adapter);

      expect(failure.category, VoiceFailureCategory.synthesis);
      expect(
        adapter.invocations.where((call) => call.call == _TtsCall.setVoice),
        isEmpty,
      );
      expect(
        adapter.invocations.where((call) => call.call == _TtsCall.speak),
        isEmpty,
      );
    });

    test(
      'voice marked not installed fails before selection and speak',
      () async {
        final adapter = _RecordingTtsAdapter(
          voices: const <Object?>[
            <String, Object?>{
              'name': 'missing-en',
              'locale': 'en-US',
              'network_required': '0',
              'features': 'notInstalled',
            },
          ],
        );

        final failure = await localFailure(adapter);

        expect(failure.category, VoiceFailureCategory.synthesis);
        expect(
          adapter.invocations.where((call) => call.call == _TtsCall.speak),
          isEmpty,
        );
      },
    );

    test('selection failure returns no text to the native engine', () async {
      final adapter = _RecordingTtsAdapter(selectVoiceResult: 0);

      final failure = await localFailure(adapter);

      expect(failure.category, VoiceFailureCategory.synthesis);
      expect(
        adapter.invocations.where((call) => call.call == _TtsCall.setVoice),
        hasLength(1),
      );
      expect(
        adapter.invocations.where((call) => call.call == _TtsCall.speak),
        isEmpty,
      );
    });

    test(
      'installed non-network voice is selected before text is spoken',
      () async {
        final adapter = _RecordingTtsAdapter(
          voices: const <Object?>[
            <String, Object?>{
              'name': 'network-en',
              'locale': 'en-US',
              'network_required': '1',
              'features': '',
            },
            <String, Object?>{
              'name': 'local-en',
              'locale': 'en-US',
              'network_required': '0',
              'features': 'embeddedTts',
            },
          ],
        );

        final result = await NativeTtsProvider(
          adapter,
        ).speak(_validRequest(localOnly: true));

        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(
          adapter.invocations.map((invocation) => invocation.call),
          const <_TtsCall>[
            _TtsCall.isLanguageInstalled,
            _TtsCall.loadVoices,
            _TtsCall.setLanguage,
            _TtsCall.setVoice,
            _TtsCall.setSpeechRate,
            _TtsCall.setVolume,
            _TtsCall.setPitch,
            _TtsCall.speak,
          ],
        );
        expect(adapter.invocations[0].argument, 'en-US');
        expect(adapter.invocations[2].argument, 'en-US');
        expect(adapter.invocations[3].argument, const <String, String>{
          'name': 'local-en',
          'locale': 'en-US',
        });
        expect(adapter.invocations.last.argument, 'Hello world.');
      },
    );
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

enum _TtsCall {
  isLanguageInstalled,
  loadVoices,
  setVoice,
  setLanguage,
  setSpeechRate,
  setVolume,
  setPitch,
  speak,
  stop,
}

final class _CompletionFlutterTts extends FlutterTts {
  Completer<void>? stopBarrier;
  int speakCalls = 0;

  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    speakCalls++;
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    await stopBarrier?.future;
    return 1;
  }
}

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

class _RecordingTtsAdapter
    implements NativeTtsAdapter, NativeTtsLocalVoiceAdapter {
  _RecordingTtsAdapter({
    this.failingCall,
    this.failure,
    this.languageInstalled = true,
    this.voices = const <Object?>[
      <String, Object?>{
        'name': 'local-en',
        'locale': 'en-US',
        'network_required': '0',
        'features': '',
      },
    ],
    this.selectVoiceResult = 1,
  });

  final List<_TtsInvocation> invocations = [];
  final _TtsCall? failingCall;
  final Object? failure;
  final Object? languageInstalled;
  final Object? voices;
  final Object? selectVoiceResult;

  Future<void> _invoke(_TtsCall call, [Object? argument]) async {
    if (failingCall == call && failure != null) {
      throw failure!;
    }
    invocations.add(_TtsInvocation(call, argument));
  }

  Future<Object?> _invokeResult(
    _TtsCall call,
    Object? result, [
    Object? argument,
  ]) async {
    await _invoke(call, argument);
    return result;
  }

  @override
  Future<Object?> isLanguageInstalled(String language) =>
      _invokeResult(_TtsCall.isLanguageInstalled, languageInstalled, language);

  @override
  Future<Object?> loadVoices() => _invokeResult(_TtsCall.loadVoices, voices);

  @override
  Future<Object?> selectVoice({required String name, required String locale}) =>
      _invokeResult(_TtsCall.setVoice, selectVoiceResult, <String, String>{
        'name': name,
        'locale': locale,
      });

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

final class _LegacyTtsAdapter implements NativeTtsAdapter {
  int setLanguageCalls = 0;
  int speakCalls = 0;

  @override
  Future<void> setLanguage(String language) async {
    setLanguageCalls += 1;
  }

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {
    speakCalls += 1;
  }

  @override
  Future<void> stop() async {}
}
