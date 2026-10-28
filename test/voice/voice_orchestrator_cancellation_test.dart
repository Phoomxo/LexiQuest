import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_orchestrator.dart';
import 'package:vocab_learning_app/voice/voice_policy.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';
import 'package:vocab_learning_app/voice/voice_provider_registry.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';

/// Controllable fake route handler whose `speak` blocks on a [Completer].
///
/// Each [speak] call enqueues a fresh completer, records the call, and only
/// resolves when a test drives it via [completeNext], [failNext], or
/// [cancelNext]. [stop] is recorded but never throws, mirroring the contract
/// that aborting a handler must remain side-effect free.
class _ControllableHandler implements VoiceRouteHandler {
  _ControllableHandler(this.descriptor);

  @override
  final VoiceProviderDescriptor descriptor;

  final List<VoiceRequest> speakRequests = <VoiceRequest>[];
  final List<VoiceCancellationToken> speakTokens = <VoiceCancellationToken>[];
  final List<Completer<VoicePlaybackResult>> completers =
      <Completer<VoicePlaybackResult>>[];
  final List<Completer<void>> _startedCompleters = <Completer<void>>[];
  int stopCount = 0;

  @override
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  ) {
    speakRequests.add(request);
    speakTokens.add(cancellation);
    final completer = Completer<VoicePlaybackResult>();
    completers.add(completer);
    // Signal that this speak has actually begun by completing the starter for
    // this call index. If [started] was awaited before the call, that
    // pre-registered completer is reused; otherwise a fresh, already-complete
    // completer is created so a later await resolves immediately.
    final callIndex = speakRequests.length - 1;
    if (callIndex < _startedCompleters.length) {
      final starter = _startedCompleters[callIndex];
      if (!starter.isCompleted) {
        starter.complete();
      }
    } else {
      _startedCompleters.add(Completer<void>()..complete());
    }
    return completer.future;
  }

  /// Resolves once the [index]-th `speak` call has begun.
  ///
  /// Deterministically gates the test on the orchestrator having reached (and
  /// parked on) a given handler attempt, so stops, second speaks, and
  /// completions land against a real in-flight call rather than racing the
  /// orchestrator's pre-speak handler stops. Works whether awaited before or
  /// after the call starts: when awaited early it pre-registers a completer
  /// that the matching [speak] later completes.
  Future<void> started(int index) {
    while (_startedCompleters.length <= index) {
      _startedCompleters.add(Completer<void>());
    }
    return _startedCompleters[index].future;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  /// Resolves the oldest in-flight speak with a successful playback result.
  void completeNext({VoiceEngine? actual}) {
    final engine = actual ?? descriptor.engine;
    completers
        .removeAt(0)
        .complete(
          VoicePlaybackResult(
            requestedEngine: descriptor.engine,
            actualEngine: engine,
            usedFallback: false,
            cacheHit: false,
          ),
        );
  }

  /// Fails the oldest in-flight speak with [failure].
  void failNext(VoiceFailure failure) {
    completers.removeAt(0).completeError(failure);
  }
}

Matcher _failure(VoiceFailureCategory category) =>
    isA<VoiceFailure>().having((f) => f.category, 'category', category);

VoiceRequest _request({
  VoiceMode mode = VoiceMode.practice,
  VoiceEngine? assignedEngine,
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) => VoiceRequest.create(
  text: 'Good morning.',
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1,
  contentId: 'phrase-001',
  contentType: 'phrase',
  mode: mode,
  assignedEngine: assignedEngine,
  capability: capability,
  privacyScope: privacyScope,
);

VoiceProviderRegistry<VoiceRouteHandler> _registry(
  List<VoiceRouteHandler> handlers,
) => VoiceProviderRegistry<VoiceRouteHandler>(
  handlers
      .map(
        (h) => MapEntry<VoiceEngine, VoiceRouteHandler>(h.descriptor.engine, h),
      )
      .toList(growable: false),
);

const _onlineContext = VoiceRouteContext(
  isOnline: true,
  remoteStandardEnabled: true,
  offlinePackAvailable: false,
  voiceMirrorEnabled: false,
  hasVoiceMirrorConsent: false,
  hasActiveVoiceMirrorSession: false,
);

void main() {
  // Standard order is voxCpmStandard -> omniVoice -> nativeTts; only omniVoice
  // and nativeTts are registered, so a practice request resolves to
  // [omniVoice, nativeTts].
  late _ControllableHandler omni;
  late _ControllableHandler native;
  late VoiceOrchestrator orchestrator;

  setUp(() {
    omni = _ControllableHandler(
      VoiceProviderDescriptor(
        engine: VoiceEngine.omniVoice,
        capabilities: const {
          VoiceCapability.standardTargetSpeech,
          VoiceCapability.dynamicTargetSpeech,
        },
        privacyScope: VoicePrivacyScope.standardContent,
        allowsStandardCache: true,
      ),
    );
    native = _ControllableHandler(
      VoiceProviderDescriptor(
        engine: VoiceEngine.nativeTts,
        capabilities: const {
          VoiceCapability.standardTargetSpeech,
          VoiceCapability.dynamicTargetSpeech,
        },
        privacyScope: VoicePrivacyScope.standardContent,
        allowsStandardCache: false,
      ),
    );
    orchestrator = VoiceOrchestrator(
      policySource: const StaticVoicePolicySource(_onlineContext),
      policyResolver: const VoicePolicyResolver(),
      handlerRegistry: _registry([omni, native]),
    );
  });

  test(
    'stop after a remote speak begins ends the in-flight speak with cancelled '
    'when the handler later completes',
    () async {
      final inFlight = orchestrator.speak(_request());

      // Wait until the remote handler is actually parked on its completer
      // before aborting, so the stop lands against a real in-flight attempt
      // rather than racing the orchestrator's pre-speak handler stops.
      await omni.started(0);
      await orchestrator.stop();
      expect(omni.stopCount, greaterThanOrEqualTo(1));

      // The remote attempt later reports success anyway.
      omni.completeNext();

      await expectLater(
        inFlight,
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );
      expect(omni.speakRequests, hasLength(1));
      // Native must never have been tried: the superseded attempt does not fall
      // back once cancelled.
      expect(native.speakRequests, isEmpty);
    },
  );

  test(
    'a second speak supersedes the first and only the second succeeds',
    () async {
      final first = orchestrator.speak(_request());
      // Let the first attempt reach the handler before superseding it, so the
      // queued completer exists to be driven.
      await omni.started(0);
      final second = orchestrator.speak(_request());
      // Wait for the second attempt to be parked before driving completions,
      // preserving the order: first queued attempt resolves first.
      await omni.started(1);

      // Let the superseded remote attempt complete; it must resolve as cancelled.
      omni.completeNext();
      await expectLater(
        first,
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );

      // The second speak owns the current generation and succeeds.
      omni.completeNext();
      final result = await second;

      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(omni.speakRequests, hasLength(2));
      expect(native.speakRequests, isEmpty);
    },
  );

  test('a superseded remote attempt that later fails with network is cancelled '
      'and does not fall back to native', () async {
    final first = orchestrator.speak(_request());
    // Let the first attempt reach the handler before superseding it.
    await omni.started(0);
    final second = orchestrator.speak(_request());
    // Wait for the second attempt to be parked before driving the queued
    // failure/completion, so resolution order stays first then second.
    await omni.started(1);

    // The first attempt later surfaces a network failure.
    omni.failNext(
      const VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'remote unreachable',
      ),
    );
    await expectLater(first, throwsA(_failure(VoiceFailureCategory.cancelled)));

    // Second speak still succeeds on the remote engine.
    omni.completeNext();
    final result = await second;

    expect(result.actualEngine, VoiceEngine.omniVoice);
    // Critical: the cancelled first attempt must NOT trigger native fallback.
    expect(native.speakRequests, isEmpty);
  });

  test(
    'strict research remote request stopped in flight is cancelled',
    () async {
      final inFlight = orchestrator.speak(
        _request(
          mode: VoiceMode.researchEvaluation,
          assignedEngine: VoiceEngine.omniVoice,
        ),
      );

      // Wait until the remote attempt is actually in flight before aborting.
      await omni.started(0);
      await orchestrator.stop();

      // Remote completes after the abort; the superseded research plan is
      // cancelled rather than fulfilled.
      omni.completeNext();

      await expectLater(
        inFlight,
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );
      expect(omni.speakRequests, hasLength(1));
      expect(native.speakRequests, isEmpty);
    },
  );
}
