import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_orchestrator.dart';
import 'package:vocab_learning_app/voice/voice_policy.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';
import 'package:vocab_learning_app/voice/voice_provider_registry.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

/// Controllable fake route handler whose `speak` blocks on a [Completer].
///
/// Each [speak] call enqueues a fresh completer, records the call, and only
/// resolves when a test drives it via [completeNext] or [failNext]. [started]
/// gates the test on the orchestrator having reached (and parked on) a given
/// attempt, so stops and completions land against a real in-flight call rather
/// than racing the orchestrator's pre-speak handler stops. [stop] is recorded
/// but never throws, mirroring the contract that aborting a handler is
/// side-effect free. This avoids any polling for in-flight state.
class _ControllableHandler implements VoiceRouteHandler {
  _ControllableHandler(this.descriptor);

  @override
  final VoiceProviderDescriptor descriptor;

  final List<VoiceRequest> speakRequests = <VoiceRequest>[];
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
    final completer = Completer<VoicePlaybackResult>();
    completers.add(completer);
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

  /// Resolves once the [index]-th `speak` call has begun. Works whether awaited
  /// before or after the call starts.
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

  /// Resolves the oldest in-flight speak with a successful playback result,
  /// carrying provenance fields (requestId/modelVersion) when supplied.
  void completeNext({
    VoiceEngine? actual,
    String? requestId,
    String? modelVersion,
    bool cacheHit = false,
  }) {
    final engine = actual ?? descriptor.engine;
    completers
        .removeAt(0)
        .complete(
          VoicePlaybackResult(
            requestedEngine: descriptor.engine,
            actualEngine: engine,
            usedFallback: false,
            cacheHit: cacheHit,
            requestId: requestId,
            modelVersion: modelVersion,
          ),
        );
  }

  /// Fails the oldest in-flight speak with [failure].
  void failNext(VoiceFailure failure) {
    completers.removeAt(0).completeError(failure);
  }
}

/// [VoiceTelemetrySink] that captures every recorded event in order. Each
/// [record] resolves synchronously after appending, so an awaited
/// [flushMicrotasks] after a `speak` lets the test observe the event without
/// polling.
class _CapturingSink implements VoiceTelemetrySink {
  final List<VoiceTelemetryEvent> events = <VoiceTelemetryEvent>[];

  @override
  Future<void> record(VoiceTelemetryEvent event) async {
    events.add(event);
  }
}

/// [VoiceTelemetrySink] whose [record] throws, to prove telemetry is best-effort
/// and never alters playback.
class _ThrowingSink implements VoiceTelemetrySink {
  int calls = 0;

  @override
  Future<void> record(VoiceTelemetryEvent event) async {
    calls++;
    throw StateError('telemetry sink exploded');
  }
}

/// [VoiceTelemetrySink] whose [record] never completes, to prove a stalled sink
/// never delays playback.
class _HangingSink implements VoiceTelemetrySink {
  int calls = 0;

  @override
  Future<void> record(VoiceTelemetryEvent event) {
    calls++;
    return Completer<void>().future;
  }
}

/// Banned token substrings: telemetry must never expose spoken text, voice id,
/// audio bytes, or any raw identifier beyond the allowlisted scalars.
const _bannedKeyTokens = <String>[
  'text',
  'voiceId',
  'audio',
  'message',
  'token',
];

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

// Online, remote-standard enabled, no offline pack, no mirror: a practice
// standardTargetSpeech request resolves to [omniVoice, nativeTts].
const _onlineContext = VoiceRouteContext(
  isOnline: true,
  remoteStandardEnabled: true,
  offlinePackAvailable: false,
  voiceMirrorEnabled: false,
  hasVoiceMirrorConsent: false,
  hasActiveVoiceMirrorSession: false,
);

/// Flushes pending microtasks so the orchestrator's fire-and-forget telemetry
/// (queued via `unawaited`) is observable deterministically.
Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

VoiceProviderDescriptor _descriptor(VoiceEngine engine) {
  switch (engine) {
    case VoiceEngine.omniVoice:
      return VoiceProviderDescriptor(
        engine: VoiceEngine.omniVoice,
        capabilities: const {
          VoiceCapability.standardTargetSpeech,
          VoiceCapability.dynamicTargetSpeech,
        },
        privacyScope: VoicePrivacyScope.standardContent,
        allowsStandardCache: true,
      );
    case VoiceEngine.nativeTts:
      return VoiceProviderDescriptor(
        engine: VoiceEngine.nativeTts,
        capabilities: const {
          VoiceCapability.standardTargetSpeech,
          VoiceCapability.dynamicTargetSpeech,
        },
        privacyScope: VoicePrivacyScope.standardContent,
        allowsStandardCache: false,
      );
    case VoiceEngine.offlinePack:
    case VoiceEngine.voxCpmStandard:
    case VoiceEngine.voxCpmMirror:
      throw ArgumentError('Unsupported engine for this suite: $engine');
  }
}

void main() {
  group('VoiceOrchestrator telemetry', () {
    test(
      'successful Omni practice emits exactly one succeeded event with '
      'requested/actual Omni, standard capability/scope, and no fallback',
      () async {
        final sink = _CapturingSink();
        final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
        final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_onlineContext),
          policyResolver: const VoicePolicyResolver(),
          handlerRegistry: _registry([omni, native]),
          telemetrySink: sink,
        );

        final pending = orchestrator.speak(_request());
        await omni.started(0);
        omni.completeNext(requestId: 'req-omni-1', modelVersion: 'omni-2024');
        final result = await pending;
        await _flushMicrotasks();

        // Playback itself is unaffected by telemetry.
        expect(result.requestedEngine, VoiceEngine.omniVoice);
        expect(result.actualEngine, VoiceEngine.omniVoice);
        expect(result.usedFallback, isFalse);
        expect(result.requestId, 'req-omni-1');
        expect(result.modelVersion, 'omni-2024');

        // Exactly one telemetry event, no fallback attempt.
        expect(sink.events, hasLength(1));
        expect(native.speakRequests, isEmpty);

        final event = sink.events.single;
        expect(event.outcome, VoiceTelemetryOutcome.succeeded);
        expect(event.requestedEngine, VoiceEngine.omniVoice);
        expect(event.actualEngine, VoiceEngine.omniVoice);
        expect(event.usedFallback, isFalse);
        expect(event.fallbackReason, isNull);
        expect(event.capability, VoiceCapability.standardTargetSpeech);
        expect(event.privacyScope, VoicePrivacyScope.standardContent);
        expect(event.mode, VoiceMode.practice);
        expect(event.contentId, 'phrase-001');
        expect(event.contentType, 'phrase');
        expect(event.cacheHit, isFalse);
        expect(event.requestId, 'req-omni-1');
        expect(event.modelVersion, 'omni-2024');

        final map = event.toMap();
        expect(map['schemaVersion'], 'voice_telemetry_v2');
        expect(map['outcome'], 'succeeded');
        expect(map['requestedEngine'], 'omniVoice');
        expect(map['actualEngine'], 'omniVoice');
        expect(map['usedFallback'], isFalse);
        expect(map['fallbackReason'], isNull);
        // Safe content/provenance only: speech text and voice id must never
        // appear as keys or values.
        for (final key in map.keys) {
          for (final token in _bannedKeyTokens) {
            expect(key.toLowerCase(), isNot(contains(token)));
          }
        }
        for (final value in map.values) {
          if (value is! String) continue;
          expect(value, isNot(equals('Good morning.')));
          expect(value, isNot(equals('teacher_female')));
        }
      },
    );

    test(
      'Omni authentication failure then native success emits exactly one '
      'succeeded event with fallback reason authentication and actual native',
      () async {
        final sink = _CapturingSink();
        final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
        final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_onlineContext),
          policyResolver: const VoicePolicyResolver(),
          handlerRegistry: _registry([omni, native]),
          telemetrySink: sink,
        );

        final pending = orchestrator.speak(_request());
        await omni.started(0);
        omni.failNext(
          const VoiceFailure(
            category: VoiceFailureCategory.authentication,
            message: 'omni credentials rejected',
          ),
        );
        await native.started(0);
        native.completeNext(actual: VoiceEngine.nativeTts);
        final result = await pending;
        await _flushMicrotasks();

        // The orchestrator fell back from Omni to native.
        expect(result.requestedEngine, VoiceEngine.omniVoice);
        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(result.usedFallback, isTrue);
        expect(omni.speakRequests, hasLength(1));
        expect(native.speakRequests, hasLength(1));

        // Exactly one telemetry event describing the terminal fallback.
        expect(sink.events, hasLength(1));
        final event = sink.events.single;
        expect(event.outcome, VoiceTelemetryOutcome.succeeded);
        expect(event.requestedEngine, VoiceEngine.omniVoice);
        expect(event.actualEngine, VoiceEngine.nativeTts);
        expect(event.usedFallback, isTrue);
        expect(event.fallbackReason, VoiceFailureCategory.authentication);

        final map = event.toMap();
        expect(map['fallbackReason'], 'authentication');
        expect(map['actualEngine'], 'nativeTts');
        // The failure message must never leak into telemetry.
        expect(map.values, isNot(contains('omni credentials rejected')));
      },
    );

    test('strict research Omni modelUnavailable emits exactly one failed event '
        'and never calls native', () async {
      final sink = _CapturingSink();
      final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
      final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(_onlineContext),
        policyResolver: const VoicePolicyResolver(),
        handlerRegistry: _registry([omni, native]),
        telemetrySink: sink,
      );

      final pending = orchestrator.speak(
        _request(
          mode: VoiceMode.researchEvaluation,
          assignedEngine: VoiceEngine.omniVoice,
        ),
      );
      await omni.started(0);
      omni.failNext(
        const VoiceFailure(
          category: VoiceFailureCategory.modelUnavailable,
          message: 'omni model is offline',
        ),
      );
      await expectLater(
        pending,
        throwsA(_failure(VoiceFailureCategory.modelUnavailable)),
      );
      await _flushMicrotasks();

      // Strict research never falls back: native was never consulted.
      expect(native.speakRequests, isEmpty);

      // Exactly one telemetry event, a failure with no provenance.
      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event.outcome, VoiceTelemetryOutcome.failed);
      expect(event.requestedEngine, VoiceEngine.omniVoice);
      expect(event.actualEngine, isNull);
      expect(event.usedFallback, isFalse);
      expect(event.fallbackReason, isNull);
      expect(event.failureCategory, VoiceFailureCategory.modelUnavailable);
      expect(event.requestId, isNull);
      expect(event.modelVersion, isNull);
      expect(event.cacheHit, isFalse);

      final map = event.toMap();
      expect(map['outcome'], 'failed');
      expect(map['failureCategory'], 'modelUnavailable');
      expect(map['actualEngine'], isNull);
      expect(map['requestId'], isNull);
      expect(map['modelVersion'], isNull);
      expect(map.values, isNot(contains('omni model is offline')));
    });

    test('stopping an in-flight Omni attempt emits exactly one cancelled event '
        'after the handler completes', () async {
      final sink = _CapturingSink();
      final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
      final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(_onlineContext),
        policyResolver: const VoicePolicyResolver(),
        handlerRegistry: _registry([omni, native]),
        telemetrySink: sink,
      );

      final inFlight = orchestrator.speak(_request());
      // Wait until the remote handler is actually parked before aborting, so
      // the stop lands against a real in-flight attempt.
      await omni.started(0);
      await orchestrator.stop();
      expect(omni.stopCount, greaterThanOrEqualTo(1));

      // No event yet: cancellation only finalises once the handler resolves.
      await _flushMicrotasks();
      expect(sink.events, isEmpty);

      // The remote attempt later reports success anyway; the superseded
      // attempt resolves as cancelled and the event is emitted afterwards.
      omni.completeNext();
      await expectLater(
        inFlight,
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );
      await _flushMicrotasks();

      // Exactly one telemetry event, a cancellation with no fallback.
      expect(native.speakRequests, isEmpty);
      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event.outcome, VoiceTelemetryOutcome.cancelled);
      expect(event.requestedEngine, VoiceEngine.omniVoice);
      expect(event.actualEngine, isNull);
      expect(event.usedFallback, isFalse);
      expect(event.fallbackReason, isNull);
      expect(event.failureCategory, VoiceFailureCategory.cancelled);

      final map = event.toMap();
      expect(map['outcome'], 'cancelled');
      expect(map['failureCategory'], 'cancelled');
      expect(map['actualEngine'], isNull);
    });

    test(
      'a telemetry sink that throws does not change successful playback',
      () async {
        final sink = _ThrowingSink();
        final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
        final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_onlineContext),
          policyResolver: const VoicePolicyResolver(),
          handlerRegistry: _registry([omni, native]),
          telemetrySink: sink,
        );

        final pending = orchestrator.speak(_request());
        await omni.started(0);
        omni.completeNext();
        final result = await pending;
        await _flushMicrotasks();

        // Playback succeeds normally despite the sink throwing.
        expect(result.requestedEngine, VoiceEngine.omniVoice);
        expect(result.actualEngine, VoiceEngine.omniVoice);
        expect(result.usedFallback, isFalse);
        // The sink was attempted, and nothing else was harmed by the throw.
        expect(sink.calls, greaterThanOrEqualTo(1));
        expect(native.speakRequests, isEmpty);
      },
    );

    test('a sink that never completes does not delay playback', () async {
      final sink = _HangingSink();
      final omni = _ControllableHandler(_descriptor(VoiceEngine.omniVoice));
      final native = _ControllableHandler(_descriptor(VoiceEngine.nativeTts));
      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(_onlineContext),
        policyResolver: const VoicePolicyResolver(),
        handlerRegistry: _registry([omni, native]),
        telemetrySink: sink,
      );

      final pending = orchestrator.speak(_request());
      await omni.started(0);
      omni.completeNext();
      // The handler resolves playback promptly; telemetry is fire-and-forget
      // so the never-completing sink cannot stall this future.
      final result = await pending.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TestFailure(
          'playback was delayed by a never-completing telemetry sink',
        ),
      );

      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(sink.calls, greaterThanOrEqualTo(1));
    });
  });
}
