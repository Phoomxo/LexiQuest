import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  group('VoiceUseCases session ownership', () {
    test('replacement stops blocked predecessor before speaking', () async {
      final first = Completer<VoicePlaybackResult>();
      final provider = _RecordingVoiceProvider(
        responses: <Future<VoicePlaybackResult>>[
          first.future,
          Future<VoicePlaybackResult>.value(_playback),
        ],
      );
      final useCases = _useCases(provider);
      final sessionA = useCases.acquireSession();
      final resultA = sessionA.speak(_request('a'));
      final resultAExpectation = expectLater(
        resultA,
        throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
      );
      await _flush();

      final sessionB = useCases.acquireSession();
      final resultB = sessionB.speak(_request('b'));

      expect(await resultB, _playback);
      expect(provider.events, <String>['speak:a', 'stop', 'speak:b']);
      await resultAExpectation;

      first.complete(_playback);
      await _flush();
      expect(provider.stopCalls, 1);
      await sessionB.release();
      await useCases.dispose();
    });

    test('stale stop and release cannot stop the replacement', () async {
      final provider = _RecordingVoiceProvider(
        responses: <Future<VoicePlaybackResult>>[
          Future<VoicePlaybackResult>.value(_playback),
          Future<VoicePlaybackResult>.value(_playback),
        ],
      );
      final useCases = _useCases(provider);
      final sessionA = useCases.acquireSession();
      await sessionA.speak(_request('a'));
      final sessionB = useCases.acquireSession();
      await sessionB.speak(_request('b'));
      final stopsAfterTakeover = provider.stopCalls;

      await sessionA.stop();
      await sessionA.release();

      expect(provider.stopCalls, stopsAfterTakeover);
      expect(sessionB.isCurrent, isTrue);
      await sessionB.release();
      await useCases.dispose();
    });

    test(
      'release after successful speak stops playback exactly once',
      () async {
        final provider = _RecordingVoiceProvider(
          responses: <Future<VoicePlaybackResult>>[
            Future<VoicePlaybackResult>.value(_playback),
          ],
        );
        final useCases = _useCases(provider);
        final sessionA = useCases.acquireSession();
        await sessionA.speak(_request('a'));

        await sessionA.release();
        useCases.acquireSession();

        expect(provider.stopCalls, 1);
        await useCases.dispose();
      },
    );

    test('latest acquisition owns a queued takeover stop', () async {
      final blockedStop = Completer<void>();
      final provider = _RecordingVoiceProvider(
        responses: <Future<VoicePlaybackResult>>[
          Future<VoicePlaybackResult>.value(_playback),
          Future<VoicePlaybackResult>.value(_playback),
        ],
        stopResponses: <Future<void>>[blockedStop.future, Future<void>.value()],
      );
      final useCases = _useCases(provider);
      final sessionA = useCases.acquireSession();
      await sessionA.speak(_request('a'));

      final sessionB = useCases.acquireSession();
      final speakingB = sessionB.speak(_request('b'));
      final speakingBExpectation = expectLater(
        speakingB,
        throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
      );
      await _flush();
      final sessionC = useCases.acquireSession();
      final speakingC = sessionC.speak(_request('c'));

      blockedStop.complete();
      await speakingBExpectation;
      expect(await speakingC, _playback);
      expect(provider.events, <String>['speak:a', 'stop', 'stop', 'speak:c']);
      await sessionC.release();
      await useCases.dispose();
    });

    test(
      'second speak in one session stops the first before it starts',
      () async {
        final blockedSpeak = Completer<VoicePlaybackResult>();
        final blockedStop = Completer<void>();
        final provider = _RecordingVoiceProvider(
          responses: <Future<VoicePlaybackResult>>[
            blockedSpeak.future,
            Future<VoicePlaybackResult>.value(_playback),
          ],
          stopResponses: <Future<void>>[blockedStop.future],
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        final first = session.speak(_request('a'));
        final firstExpectation = expectLater(
          first,
          throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
        );
        await _flush();

        final second = session.speak(_request('b'));
        await _flush();
        expect(provider.events, <String>['speak:a', 'stop']);
        blockedStop.complete();

        await firstExpectation;
        expect(await second, _playback);
        expect(provider.events, <String>['speak:a', 'stop', 'speak:b']);
        blockedSpeak.complete(_playback);
        await session.release();
        await useCases.dispose();
      },
    );

    test(
      'eager takeover failure is consumed and reported on later speak',
      () async {
        final provider = _RecordingVoiceProvider(
          responses: <Future<VoicePlaybackResult>>[
            Future<VoicePlaybackResult>.value(_playback),
          ],
          stopFailures: 1,
        );
        final useCases = _useCases(provider);
        final sessionA = useCases.acquireSession();
        await sessionA.speak(_request('a'));

        final sessionB = useCases.acquireSession();
        await _flush();

        await expectLater(
          sessionB.speak(_request('b')),
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );
        expect(await sessionB.speak(_request('b-retry')), _playback);
        expect(provider.stopCalls, 2);
        await useCases.dispose();
      },
    );

    test('public stop normalizes provider cleanup errors', () async {
      final provider = _RecordingVoiceProvider(
        responses: <Future<VoicePlaybackResult>>[
          Future<VoicePlaybackResult>.value(_playback),
        ],
        stopError: StateError('stop failed'),
      );
      final useCases = _useCases(provider);
      final session = useCases.acquireSession();
      await session.speak(_request('a'));

      await expectLater(
        session.stop(),
        throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
      );
      await useCases.dispose();
    });

    for (final action in <String>['stop', 'release']) {
      test(
        'public $action is bounded while uncertain playback blocks replacement',
        () async {
          final blockedStop = Completer<void>();
          final provider = _RecordingVoiceProvider(
            responses: <Future<VoicePlaybackResult>>[
              Future<VoicePlaybackResult>.value(_playback),
              Future<VoicePlaybackResult>.value(_playback),
            ],
            stopResponses: <Future<void>>[blockedStop.future],
          );
          final useCases = VoiceUseCases(
            provider: provider,
            disposeProvider: provider.dispose,
            operationTimeout: const Duration(milliseconds: 80),
            cleanupTimeout: const Duration(milliseconds: 20),
          );
          final sessionA = useCases.acquireSession();
          await sessionA.speak(_request('a'));

          final cleanup = action == 'stop'
              ? sessionA.stop()
              : sessionA.release();
          await expectLater(
            cleanup.timeout(const Duration(seconds: 1)),
            throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
          );

          final sessionB = useCases.acquireSession();
          await expectLater(
            sessionB.speak(_request('b')),
            throwsA(_voiceFailure(VoiceFailureCategory.timeout)),
          );
          expect(provider.events, <String>['speak:a', 'stop']);

          blockedStop.complete();
          await _flush();
          await expectLater(useCases.dispose(), completes);
        },
      );
    }

    test('deadline wins and schedules one stop without awaiting it', () async {
      final blockedSpeak = Completer<VoicePlaybackResult>();
      final blockedStop = Completer<void>();
      final provider = _RecordingVoiceProvider(
        responses: <Future<VoicePlaybackResult>>[blockedSpeak.future],
        stopResponses: <Future<void>>[blockedStop.future],
      );
      final useCases = VoiceUseCases(
        provider: provider,
        disposeProvider: provider.dispose,
        operationTimeout: const Duration(milliseconds: 20),
      );
      final session = useCases.acquireSession();
      final speaking = session.speak(_request('timeout'));

      await expectLater(
        speaking,
        throwsA(_voiceFailure(VoiceFailureCategory.timeout)),
      );
      await _flush();
      expect(provider.stopCalls, 1);

      blockedSpeak.complete(_playback);
      await _flush();
      expect(provider.stopCalls, 1);
      blockedStop.complete();
      await session.release();
      await useCases.dispose();
    });

    test(
      'dispose awaits and invokes the managed disposer exactly once',
      () async {
        final blockedSpeak = Completer<VoicePlaybackResult>();
        final allowDispose = Completer<void>();
        var disposeCalls = 0;
        final provider = _RecordingVoiceProvider(
          responses: <Future<VoicePlaybackResult>>[blockedSpeak.future],
        );
        final useCases = VoiceUseCases(
          provider: provider,
          disposeProvider: () async {
            disposeCalls++;
            blockedSpeak.completeError(
              const VoiceFailure(
                category: VoiceFailureCategory.cancelled,
                message: 'disposed',
              ),
            );
            await allowDispose.future;
          },
        );
        final session = useCases.acquireSession();
        final speaking = session.speak(_request('blocked'));
        final speakingExpectation = expectLater(
          speaking,
          throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
        );
        await _flush();

        final firstDispose = useCases.dispose();
        final secondDispose = useCases.dispose();
        expect(identical(firstDispose, secondDispose), isTrue);
        await _flush();
        expect(disposeCalls, 1);
        await speakingExpectation;

        var completed = false;
        firstDispose.then((_) => completed = true);
        await _flush();
        expect(completed, isFalse);
        allowDispose.complete();
        await firstDispose;
        expect(disposeCalls, 1);
        expect(
          useCases.acquireSession,
          throwsA(_voiceFailure(VoiceFailureCategory.providerDisabled)),
        );
      },
    );

    test(
      'dispose bounds stuck control and provider work but invokes disposer once',
      () async {
        final blockedSpeak = Completer<VoicePlaybackResult>();
        final blockedStop = Completer<void>();
        var disposeCalls = 0;
        final provider = _RecordingVoiceProvider(
          responses: <Future<VoicePlaybackResult>>[blockedSpeak.future],
          stopResponses: <Future<void>>[blockedStop.future],
        );
        final useCases = VoiceUseCases(
          provider: provider,
          disposeProvider: () async {
            disposeCalls += 1;
          },
          operationTimeout: const Duration(seconds: 1),
          cleanupTimeout: const Duration(milliseconds: 20),
        );
        final session = useCases.acquireSession();
        final speakingExpectation = expectLater(
          session.speak(_request('blocked')),
          throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
        );
        await _flush();
        final stoppingExpectation = expectLater(
          session.stop(),
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );
        await _flush();

        final firstDispose = useCases.dispose();
        final secondDispose = useCases.dispose();
        expect(identical(firstDispose, secondDispose), isTrue);
        await expectLater(
          firstDispose.timeout(const Duration(seconds: 1)),
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );
        expect(disposeCalls, 1);
        await speakingExpectation;
        await expectLater(
          secondDispose,
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );

        blockedStop.complete();
        blockedSpeak.complete(_playback);
        await stoppingExpectation;
        await _flush();
      },
    );
  });
}

VoiceUseCases _useCases(_RecordingVoiceProvider provider) => VoiceUseCases(
  provider: provider,
  disposeProvider: provider.dispose,
  operationTimeout: const Duration(seconds: 1),
);

VoiceRequest _request(String text) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'test',
  speed: 1,
  contentId: text,
  contentType: 'test',
  mode: VoiceMode.practice,
);

const _playback = VoicePlaybackResult(
  requestedEngine: VoiceEngine.nativeTts,
  actualEngine: VoiceEngine.nativeTts,
  usedFallback: false,
  cacheHit: false,
);

Matcher _voiceFailure(VoiceFailureCategory category) => isA<VoiceFailure>()
    .having((failure) => failure.category, 'category', category);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _RecordingVoiceProvider implements VoiceProvider {
  _RecordingVoiceProvider({
    required List<Future<VoicePlaybackResult>> responses,
    List<Future<void>> stopResponses = const <Future<void>>[],
    this.stopError,
    int stopFailures = 0,
  }) : _responses = List<Future<VoicePlaybackResult>>.of(responses),
       _stopResponses = List<Future<void>>.of(stopResponses),
       _stopFailuresRemaining = stopFailures;

  final List<Future<VoicePlaybackResult>> _responses;
  final List<Future<void>> _stopResponses;
  final Object? stopError;
  int _stopFailuresRemaining;
  final List<String> events = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    events.add('speak:${request.text}');
    if (_responses.isEmpty) {
      return Future<VoicePlaybackResult>.value(_playback);
    }
    return _responses.removeAt(0);
  }

  @override
  Future<void> stop() {
    stopCalls++;
    events.add('stop');
    final error = stopError;
    if (error != null) return Future<void>.error(error);
    if (_stopFailuresRemaining > 0) {
      _stopFailuresRemaining--;
      return Future<void>.error(StateError('stop failed'));
    }
    if (_stopResponses.isEmpty) return Future<void>.value();
    return _stopResponses.removeAt(0);
  }

  Future<void> dispose() async {
    disposeCalls++;
  }
}
