import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  group('completion-owned narration', () {
    test('provider failure retains cleanup until stop acknowledges', () async {
      final stopped = Completer<void>();
      final failed = Future<VoicePlaybackResult>.error(
        const VoiceFailure(
          category: VoiceFailureCategory.synthesis,
          message: 'Synthetic failure.',
        ),
      );
      // The provider is reached after an ownership barrier. Observe the eagerly
      // constructed fixture now, while preserving its error for that caller.
      unawaited(failed.then<void>((_) {}, onError: (_, _) {}));
      final provider = _RecordingVoiceProvider(
        responses: [failed],
        stopResponses: [stopped.future],
      );
      final useCases = _useCases(provider);
      final session = useCases.acquireSession();
      var settled = false;
      final expectation = expectLater(
        session.speakUntilCompleted(_request('a')),
        throwsA(_voiceFailure(VoiceFailureCategory.synthesis)),
      ).then((_) => settled = true);
      await _flush();
      expect(provider.events, ['speak:a', 'stop']);
      expect(settled, isFalse);
      stopped.complete();
      await expectation;
      await useCases.dispose();
    });
    test(
      'ordinary speak still acknowledges start without awaiting end',
      () async {
        final ended = Completer<void>();
        final result = _CompletingPlayback(ended.future);
        final provider = _RecordingVoiceProvider(
          responses: [Future.value(result)],
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        expect(await session.speak(_request('a')), same(result));
        expect(ended.isCompleted, isFalse);
        ended.complete();
        await session.release();
        await useCases.dispose();
      },
    );

    test(
      'start acknowledgement is separate from natural playback end',
      () async {
        final ended = Completer<void>();
        final result = _CompletingPlayback(ended.future);
        final provider = _RecordingVoiceProvider(
          responses: [Future.value(result)],
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        var completed = false;
        final playing =
            (session as dynamic).speakUntilCompleted(_request('a'))
                as Future<VoicePlaybackResult>;
        playing.then((_) => completed = true);
        await _flush();
        expect(provider.events, ['speak:a']);
        expect(completed, isFalse);
        ended.complete();
        expect(await playing, same(result));
        await session.release();
        await useCases.dispose();
      },
    );

    test('takeover waits for confirmed stop and ignores stale end', () async {
      final endedA = Completer<void>();
      final endedB = Completer<void>();
      final stopped = Completer<void>();
      final provider = _RecordingVoiceProvider(
        responses: [
          Future.value(_CompletingPlayback(endedA.future)),
          Future.value(_CompletingPlayback(endedB.future)),
        ],
        stopResponses: [stopped.future],
      );
      final useCases = _useCases(provider);
      final first = useCases.acquireSession();
      var cancelled = false;
      final playingA =
          (first as dynamic).speakUntilCompleted(_request('a'))
              as Future<VoicePlaybackResult>;
      final expectationA = expectLater(
        playingA,
        throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
      ).then((_) => cancelled = true);
      await _flush();
      final second = useCases.acquireSession();
      var completedB = false;
      final playingB =
          (second as dynamic).speakUntilCompleted(_request('b'))
              as Future<VoicePlaybackResult>;
      playingB.then((_) => completedB = true);
      await _flush();
      expect(cancelled, isFalse);
      expect(provider.events, ['speak:a', 'stop']);
      stopped.complete();
      await expectationA;
      await _flush();
      endedA.complete();
      await _flush();
      expect(completedB, isFalse);
      endedB.complete();
      await playingB;
      await second.release();
      await useCases.dispose();
    });

    test(
      'missing completion proof waits for stop then reports unavailable',
      () async {
        final stopped = Completer<void>();
        final provider = _RecordingVoiceProvider(
          responses: [Future.value(_playback)],
          stopResponses: [stopped.future],
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        var settled = false;
        final playing =
            (session as dynamic).speakUntilCompleted(_request('a'))
                as Future<VoicePlaybackResult>;
        final expectation = expectLater(
          playing,
          throwsA(_voiceFailure(VoiceFailureCategory.unsupportedCapability)),
        ).then((_) => settled = true);
        await _flush();
        expect(provider.events, ['speak:a', 'stop']);
        expect(settled, isFalse);
        stopped.complete();
        await expectation;
        await useCases.dispose();
      },
    );

    test(
      'failed stop reports uncertain cleanup rather than cancellation',
      () async {
        final ended = Completer<void>();
        final provider = _RecordingVoiceProvider(
          responses: [Future.value(_CompletingPlayback(ended.future))],
          stopError: StateError('synthetic stop failure'),
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        final playing =
            (session as dynamic).speakUntilCompleted(_request('a'))
                as Future<VoicePlaybackResult>;
        final expectation = expectLater(
          playing,
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );
        await _flush();
        await expectLater(
          session.stop(),
          throwsA(_voiceFailure(VoiceFailureCategory.cleanupIncomplete)),
        );
        await expectation;
        ended.complete();
        await useCases.dispose();
      },
    );

    test('playback deadline waits for stop before reporting timeout', () async {
      final ended = Completer<void>();
      final stopped = Completer<void>();
      final provider = _RecordingVoiceProvider(
        responses: [Future.value(_CompletingPlayback(ended.future))],
        stopResponses: [stopped.future],
      );
      final useCases = VoiceUseCases(
        provider: provider,
        disposeProvider: provider.dispose,
        operationTimeout: const Duration(milliseconds: 20),
        cleanupTimeout: const Duration(seconds: 1),
      );
      final session = useCases.acquireSession();
      var settled = false;
      final expectation = expectLater(
        session.speakUntilCompleted(_request('a')),
        throwsA(_voiceFailure(VoiceFailureCategory.timeout)),
      ).then((_) => settled = true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(provider.events, ['speak:a', 'stop']);
      expect(settled, isFalse);
      stopped.complete();
      await expectation;
      ended.complete();
      await useCases.dispose();
    });

    test(
      'disposal does not release completion wait before managed cleanup',
      () async {
        final ended = Completer<void>();
        final disposed = Completer<void>();
        final provider = _RecordingVoiceProvider(
          responses: [Future.value(_CompletingPlayback(ended.future))],
        );
        final useCases = VoiceUseCases(
          provider: provider,
          disposeProvider: () => disposed.future,
        );
        final session = useCases.acquireSession();
        var settled = false;
        final expectation = expectLater(
          session.speakUntilCompleted(_request('a')),
          throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
        ).then((_) => settled = true);
        await _flush();
        final disposing = useCases.dispose();
        ended.complete();
        await _flush();
        expect(settled, isFalse);
        disposed.complete();
        await disposing;
        await expectation;
      },
    );

    test(
      'takeover of unacknowledged playback requires stop before cancellation',
      () async {
        final started = Completer<VoicePlaybackResult>();
        final stopped = Completer<void>();
        final provider = _RecordingVoiceProvider(
          responses: [started.future],
          stopResponses: [stopped.future],
        );
        final useCases = _useCases(provider);
        final session = useCases.acquireSession();
        var settled = false;
        final expectation = expectLater(
          session.speakUntilCompleted(_request('a')),
          throwsA(_voiceFailure(VoiceFailureCategory.cancelled)),
        ).then((_) => settled = true);
        await _flush();
        useCases.acquireSession();
        await _flush();
        expect(settled, isFalse);
        stopped.complete();
        await expectation;
        started.complete(_playback);
        await _flush();
        await useCases.dispose();
      },
    );
  });
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

final class _CompletingPlayback extends VoicePlaybackResult {
  _CompletingPlayback(Future<void> playbackCompleted)
    : super(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
        playbackCompleted: playbackCompleted,
      );
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
