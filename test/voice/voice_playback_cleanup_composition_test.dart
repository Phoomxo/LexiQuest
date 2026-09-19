import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/synthesized_voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_orchestrator.dart';
import 'package:vocab_learning_app/voice/voice_policy.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';
import 'package:vocab_learning_app/voice/voice_provider_registry.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';

VoiceRequest _request() => VoiceRequest.create(
  text: 'Hello',
  language: 'en',
  voiceId: 'teacher',
  speed: 1,
  contentId: 'hello',
  contentType: 'word',
  mode: VoiceMode.practice,
);

Matcher _failure(VoiceFailureCategory category) => isA<VoiceFailure>().having(
  (failure) => failure.category,
  'category',
  category,
);

void main() {
  for (final cached in [false, true]) {
    for (final startOnly in [false, true]) {
      test('partial start cleanup precedes fallback '
          '(cached=$cached, startOnly=$startOnly)', () async {
        final native = _SdkPlayer()..cleanupGate = Completer<void>();
        final stack = await _Stack.create(
          native,
          cached: cached,
          startOnly: startOnly,
        );
        final session = stack.facade.acquireSession();
        final result = session.speak(_request());
        await native.started.future;
        await Future<void>.delayed(Duration.zero);
        expect(stack.fallback.calls, 0, reason: 'audio is still active');
        expect(native.active, isTrue);
        expect(native.cleanupCalls, 1);
        native.cleanupGate!.complete();
        final playback = await result;
        expect(native.active, isFalse);
        expect(playback.usedFallback, isTrue);
        expect(stack.fallback.calls, 1);
        expect(stack.fallback.overlapped, isFalse);
        expect(stack.synthesis.calls, cached ? 0 : 1);
        await session.release();
        await stack.facade.dispose();
      });
    }
  }

  for (final completionOwned in [false, true]) {
    test('cleanup failure blocks fallback and retains stop obligation '
        '(completionOwned=$completionOwned)', () async {
      final native = _SdkPlayer()..failCleanup = true;
      final stack = await _Stack.create(native);
      final session = stack.facade.acquireSession();
      final result = completionOwned
          ? session.speakUntilCompleted(_request())
          : session.speak(_request());
      await expectLater(
        result,
        throwsA(_failure(VoiceFailureCategory.cleanupIncomplete)),
      );
      expect(stack.fallback.calls, 0);
      expect(native.active, isTrue);
      final beforeRetry = native.cleanupCalls;
      native.failCleanup = false;
      await session.stop();
      expect(native.cleanupCalls, greaterThan(beforeRetry));
      expect(native.active, isFalse);
      await session.release();
      await stack.facade.dispose();
    });
  }

  test('late global completion cannot prove replacement content ended', () async {
    final native = _SdkPlayer()..failStart = false;
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final first = await adapter.playBytesWithCompletion(
      Uint8List.fromList([1]),
    );
    first.completed!.ignore();
    await adapter.stop();
    final second = await adapter.playBytesWithCompletion(
      Uint8List.fromList([2]),
    );
    var falselyCompleted = false;
    second.completed?.then((_) => falselyCompleted = true);
    native
        .complete(); // Delayed A, delivered to the global stream after B starts.
    await Future<void>.delayed(Duration.zero);
    expect(falselyCompleted, isFalse);
    expect(
      second.completed,
      isNull,
      reason: 'the SDK supplies no utterance ID',
    );
    native.complete(); // Actual B is indistinguishable from delayed A.
    await Future<void>.delayed(Duration.zero);
    expect(falselyCompleted, isFalse);
    await adapter.dispose();
  });

  test(
    'completion-owned facade fails closed after interrupted SDK playback',
    () async {
      final native = _SdkPlayer()..failStart = false;
      final stack = await _Stack.create(native);
      final session = stack.facade.acquireSession();
      await session.speak(_request());
      await session.stop();
      final result = session.speakUntilCompleted(_request());
      await expectLater(
        result,
        throwsA(_failure(VoiceFailureCategory.unsupportedCapability)),
      );
      expect(native.active, isFalse);
      expect(stack.fallback.calls, 0);
      native.complete();
      await session.release();
      await stack.facade.dispose();
    },
  );

  test('late retired start failure cannot stop replacement speech', () async {
    final startGate = Completer<void>();
    final native = _SdkPlayer()
      ..failStart = false
      ..startGate = startGate;
    final stack = await _Stack.create(native);
    final session = stack.facade.acquireSession();
    final first = session.speak(_request());
    final cancelled = expectLater(
      first,
      throwsA(_failure(VoiceFailureCategory.cancelled)),
    );
    await native.started.future;
    await session.stop();
    native.startGate = null;
    final replacement = await session.speak(_request());
    expect(replacement.playbackCompleted, isNull);
    final stopCalls = native.cleanupCalls;
    startGate.completeError(StateError('late start failure'));
    await cancelled;
    await Future<void>.delayed(Duration.zero);
    expect(native.active, isTrue);
    expect(native.cleanupCalls, stopCalls);
    expect(stack.fallback.calls, 0);
    await session.release();
    await stack.facade.dispose();
  });

  test(
    'uninterrupted natural end preserves proof for subsequent playback',
    () async {
      final native = _SdkPlayer()..failStart = false;
      final adapter = AudioplayersAdapter(audioPlayer: native);
      for (var index = 0; index < 2; index++) {
        final playback = await adapter.playBytesWithCompletion(
          Uint8List.fromList([index]),
        );
        expect(playback.completed, isNotNull);
        var completed = false;
        playback.completed!.then((_) => completed = true);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        native.complete();
        await playback.completed;
        expect(completed, isTrue);
      }
      await adapter.dispose();
    },
  );
}

final class _Stack {
  _Stack(this.facade, this.fallback, this.synthesis);
  final VoiceUseCases facade;
  final _Fallback fallback;
  final _Synthesis synthesis;

  static Future<_Stack> create(
    _SdkPlayer native, {
    bool cached = false,
    bool startOnly = false,
  }) async {
    final adapter = AudioplayersAdapter(audioPlayer: native);
    final player = PluginVoiceAudioPlayer(
      startOnly ? _StartOnlyAdapter(adapter) : adapter,
    );
    final synthesis = _Synthesis();
    final cache = MemoryVoiceAudioCache(maxEntries: 2, maxBytes: 100);
    if (cached) {
      await cache.put(
        VoiceAudioCacheKey.create(
          request: _request(),
          engine: VoiceEngine.omniVoice,
          modelVersion: 'fixture',
        ),
        Uint8List.fromList([1, 2]),
      );
    }
    final remote = SynthesizedVoiceRouteHandler(
      provider: synthesis,
      audioPlayer: player,
      audioCache: cache,
      modelVersion: 'fixture',
    );
    final fallback = _Fallback(native);
    final orchestrator = VoiceOrchestrator(
      policySource: const StaticVoicePolicySource(
        VoiceRouteContext(
          isOnline: true,
          remoteStandardEnabled: true,
          offlinePackAvailable: false,
          voiceMirrorEnabled: false,
          hasVoiceMirrorConsent: false,
          hasActiveVoiceMirrorSession: false,
        ),
      ),
      policyResolver: const VoicePolicyResolver(),
      handlerRegistry: VoiceProviderRegistry<VoiceRouteHandler>([
        MapEntry(VoiceEngine.omniVoice, remote),
        MapEntry(VoiceEngine.nativeTts, fallback),
      ]),
    );
    return _Stack(
      VoiceUseCases(
        provider: orchestrator,
        disposeProvider: player.dispose,
        operationTimeout: const Duration(seconds: 2),
      ),
      fallback,
      synthesis,
    );
  }
}

final class _Synthesis implements VoiceSynthesisProvider {
  int calls = 0;
  @override
  VoiceProviderDescriptor get descriptor => VoiceProviderDescriptor(
    engine: VoiceEngine.omniVoice,
    capabilities: const {VoiceCapability.standardTargetSpeech},
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: true,
  );
  @override
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    calls++;
    return VoiceAudio(
      bytes: Uint8List.fromList([1, 2]),
      requestId: 'fixture',
      engine: VoiceEngine.omniVoice,
      modelVersion: 'fixture',
      sampleRate: 24000,
    );
  }
}

final class _Fallback implements VoiceRouteHandler {
  _Fallback(this.player);
  final _SdkPlayer player;
  int calls = 0;
  bool overlapped = false;
  @override
  VoiceProviderDescriptor get descriptor => VoiceProviderDescriptor(
    engine: VoiceEngine.nativeTts,
    capabilities: const {VoiceCapability.standardTargetSpeech},
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: false,
  );
  @override
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  ) async {
    calls++;
    overlapped = player.active;
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

// Models the SDK event/acknowledgement shape, never actual acoustic playback.
final class _SdkPlayer implements AudioPlayer {
  bool active = false;
  bool failStart = true;
  bool failCleanup = false;
  int cleanupCalls = 0;
  Completer<void>? cleanupGate;
  Completer<void>? startGate;
  final started = Completer<void>();
  final events = StreamController<void>.broadcast();
  void complete() => events.add(null);
  @override
  Stream<void> get onPlayerComplete => events.stream;
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    active = true;
    if (!started.isCompleted) started.complete();
    await startGate?.future;
    if (failStart) throw StateError('start acknowledgement failed');
  }

  @override
  Future<void> stop() async {
    if (!active) return;
    cleanupCalls++;
    await cleanupGate?.future;
    if (failCleanup) throw StateError('stop acknowledgement failed');
    active = false;
  }

  @override
  Future<void> dispose() async {
    active = false;
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StartOnlyAdapter implements AudioPlayerAdapter {
  _StartOnlyAdapter(this.adapter);
  final AudioplayersAdapter adapter;
  @override
  Future<void> playBytes(Uint8List bytes) => adapter.playBytes(bytes);
  @override
  Future<void> stop() => adapter.stop();
  @override
  Future<void> dispose() => adapter.dispose();
}
