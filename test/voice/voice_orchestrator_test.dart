// RED phase: defines the behavior contract for VoiceOrchestrator before its
// implementation exists. This file is expected NOT to compile until the
// orchestrator and route-handler types are added under lib/voice/.
//
// Scope: fallback ordering, mirror gating, and the mirror operational-fallback
// request rewrite. Cancellation and telemetry recording are covered elsewhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_orchestrator.dart';
import 'package:vocab_learning_app/voice/voice_policy.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';
import 'package:vocab_learning_app/voice/voice_provider_registry.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';

const _online = VoiceRouteContext(
  isOnline: true,
  remoteStandardEnabled: true,
  offlinePackAvailable: true,
  voiceMirrorEnabled: true,
  hasVoiceMirrorConsent: true,
  hasActiveVoiceMirrorSession: true,
);

const _offline = VoiceRouteContext(
  isOnline: false,
  remoteStandardEnabled: true,
  offlinePackAvailable: true,
  voiceMirrorEnabled: false,
  hasVoiceMirrorConsent: false,
  hasActiveVoiceMirrorSession: false,
);

VoiceRequest _request({
  VoiceMode mode = VoiceMode.practice,
  VoiceEngine? assignedEngine,
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) {
  return VoiceRequest.create(
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
}

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

/// Minimal deterministic handler: optionally throws a [VoiceFailure] on speak
/// and records the engine call order plus every request handed to native.
class _FakeHandler implements VoiceRouteHandler {
  _FakeHandler(this.descriptor, {this.speakFailure});

  @override
  final VoiceProviderDescriptor descriptor;

  final VoiceFailure? speakFailure;

  final List<VoiceEngine> calls = <VoiceEngine>[];
  final List<VoiceRequest> requests = <VoiceRequest>[];

  @override
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    calls.add(descriptor.engine);
    requests.add(request);
    if (speakFailure case final failure?) {
      throw failure;
    }
    return VoicePlaybackResult(
      requestedEngine: descriptor.engine,
      actualEngine: descriptor.engine,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

VoiceProviderRegistry<VoiceRouteHandler> _registry(
  List<VoiceRouteHandler> handlers,
) {
  return VoiceProviderRegistry<VoiceRouteHandler>(
    handlers
        .map(
          (handler) => MapEntry<VoiceEngine, VoiceRouteHandler>(
            handler.descriptor.engine,
            handler,
          ),
        )
        .toList(growable: false),
  );
}

void main() {
  const resolver = VoicePolicyResolver();

  group('online practice', () {
    test(
      'OmniVoice network failure falls back to native exactly once and reports '
      'the fallback',
      () async {
        final omniVoice = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.omniVoice,
            capabilities: {
              VoiceCapability.standardTargetSpeech,
              VoiceCapability.dynamicTargetSpeech,
            },
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
          speakFailure: const VoiceFailure(
            category: VoiceFailureCategory.network,
            message: 'OmniVoice unreachable.',
          ),
        );
        // The online plan lists several engines between OmniVoice and native;
        // they are all configured to fail so the orchestrator exhausts them and
        // lands on native as the single successful handler.
        final offlinePack = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.offlinePack,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
          speakFailure: const VoiceFailure(
            category: VoiceFailureCategory.network,
            message: 'offline pack unavailable online.',
          ),
        );
        final voxCpmStandard = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.voxCpmStandard,
            capabilities: {
              VoiceCapability.standardTargetSpeech,
              VoiceCapability.dynamicTargetSpeech,
            },
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
          speakFailure: const VoiceFailure(
            category: VoiceFailureCategory.network,
            message: 'VoxCPM standard unreachable.',
          ),
        );
        final native = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.nativeTts,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: false,
          ),
        );

        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_online),
          policyResolver: resolver,
          handlerRegistry: _registry([
            offlinePack,
            voxCpmStandard,
            omniVoice,
            native,
          ]),
        );

        final result = await orchestrator.speak(_request());

        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(result.usedFallback, isTrue);

        expect(native.calls, const <VoiceEngine>[VoiceEngine.nativeTts]);
        expect(
          [omniVoice.calls, voxCpmStandard.calls].expand((e) => e),
          isNotEmpty,
          reason: 'upstream engines are attempted before native fallback',
        );
      },
    );
  });

  group('offline standard speech', () {
    test(
      'prefers the offline pack and never calls native on success',
      () async {
        final offlinePack = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.offlinePack,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
        );
        final native = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.nativeTts,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: false,
          ),
        );

        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_offline),
          policyResolver: resolver,
          handlerRegistry: _registry([offlinePack, native]),
        );

        final result = await orchestrator.speak(_request());

        expect(result.actualEngine, VoiceEngine.offlinePack);
        expect(offlinePack.calls, const <VoiceEngine>[VoiceEngine.offlinePack]);
        expect(native.calls, isEmpty);
      },
    );
  });

  group('research evaluation', () {
    test(
      'assigned OmniVoice failure never falls back to another engine',
      () async {
        final omniVoice = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.omniVoice,
            capabilities: {
              VoiceCapability.standardTargetSpeech,
              VoiceCapability.dynamicTargetSpeech,
            },
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
          speakFailure: const VoiceFailure(
            category: VoiceFailureCategory.network,
            message: 'OmniVoice unreachable.',
          ),
        );
        final native = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.nativeTts,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: false,
          ),
        );

        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_online),
          policyResolver: resolver,
          handlerRegistry: _registry([omniVoice, native]),
        );

        await expectLater(
          orchestrator.speak(
            _request(
              mode: VoiceMode.researchEvaluation,
              assignedEngine: VoiceEngine.omniVoice,
            ),
          ),
          throwsA(_failure(VoiceFailureCategory.network)),
        );

        expect(omniVoice.calls, const <VoiceEngine>[VoiceEngine.omniVoice]);
        expect(native.calls, isEmpty);
      },
    );
  });

  group('mirror routing', () {
    test('fails before any handler call when consent is missing', () async {
      const context = VoiceRouteContext(
        isOnline: true,
        remoteStandardEnabled: true,
        offlinePackAvailable: true,
        voiceMirrorEnabled: true,
        hasVoiceMirrorConsent: false,
        hasActiveVoiceMirrorSession: true,
      );
      final mirror = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.voxCpmMirror,
          capabilities: {VoiceCapability.sessionVoiceMirror},
          privacyScope: VoicePrivacyScope.participantTransient,
          allowsStandardCache: false,
        ),
      );
      final native = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.nativeTts,
          capabilities: {VoiceCapability.standardTargetSpeech},
          privacyScope: VoicePrivacyScope.standardContent,
          allowsStandardCache: false,
        ),
      );

      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(context),
        policyResolver: resolver,
        handlerRegistry: _registry([mirror, native]),
      );

      await expectLater(
        orchestrator.speak(
          _request(
            capability: VoiceCapability.sessionVoiceMirror,
            privacyScope: VoicePrivacyScope.participantTransient,
          ),
        ),
        throwsA(_failure(VoiceFailureCategory.consentMissing)),
      );

      expect(mirror.calls, isEmpty);
      expect(native.calls, isEmpty);
    });

    test('fails before any handler call without an active session', () async {
      const context = VoiceRouteContext(
        isOnline: true,
        remoteStandardEnabled: true,
        offlinePackAvailable: true,
        voiceMirrorEnabled: true,
        hasVoiceMirrorConsent: true,
        hasActiveVoiceMirrorSession: false,
      );
      final mirror = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.voxCpmMirror,
          capabilities: {VoiceCapability.sessionVoiceMirror},
          privacyScope: VoicePrivacyScope.participantTransient,
          allowsStandardCache: false,
        ),
      );
      final native = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.nativeTts,
          capabilities: {VoiceCapability.standardTargetSpeech},
          privacyScope: VoicePrivacyScope.standardContent,
          allowsStandardCache: false,
        ),
      );

      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(context),
        policyResolver: resolver,
        handlerRegistry: _registry([mirror, native]),
      );

      await expectLater(
        orchestrator.speak(
          _request(
            capability: VoiceCapability.sessionVoiceMirror,
            privacyScope: VoicePrivacyScope.participantTransient,
          ),
        ),
        throwsA(_failure(VoiceFailureCategory.sessionExpired)),
      );

      expect(mirror.calls, isEmpty);
      expect(native.calls, isEmpty);
    });

    test('operational fallback rewrites the native request to '
        'standardTargetSpeech and standardContent', () async {
      final mirror = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.voxCpmMirror,
          capabilities: {VoiceCapability.sessionVoiceMirror},
          privacyScope: VoicePrivacyScope.participantTransient,
          allowsStandardCache: false,
        ),
        speakFailure: const VoiceFailure(
          category: VoiceFailureCategory.network,
          message: 'Mirror endpoint unreachable.',
        ),
      );
      final native = _FakeHandler(
        VoiceProviderDescriptor(
          engine: VoiceEngine.nativeTts,
          capabilities: {VoiceCapability.standardTargetSpeech},
          privacyScope: VoicePrivacyScope.standardContent,
          allowsStandardCache: false,
        ),
      );

      final orchestrator = VoiceOrchestrator(
        policySource: const StaticVoicePolicySource(_online),
        policyResolver: resolver,
        handlerRegistry: _registry([mirror, native]),
      );

      final result = await orchestrator.speak(
        _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
      );

      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isTrue);
      expect(native.calls, const <VoiceEngine>[VoiceEngine.nativeTts]);

      final rewritten = native.requests.single;
      expect(rewritten.capability, VoiceCapability.standardTargetSpeech);
      expect(rewritten.privacyScope, VoicePrivacyScope.standardContent);
    });
  });

  // Compact parameterized coverage of the practice fallback taxonomy. Only
  // omniVoice + native are registered for an online practice request, so a
  // single omniVoice failure either lands on native (operational categories)
  // or is rethrown without invoking native (fail-closed categories). The
  // detailed multi-engine network scenario above remains the canonical case.
  group('practice fallback taxonomy', () {
    final operational = <VoiceFailureCategory>[
      VoiceFailureCategory.authentication,
      // network is covered exhaustively above; included here for completeness.
      VoiceFailureCategory.network,
      VoiceFailureCategory.timeout,
      VoiceFailureCategory.rateLimited,
      VoiceFailureCategory.modelUnavailable,
      VoiceFailureCategory.insufficientStorage,
      VoiceFailureCategory.checksumMismatch,
      VoiceFailureCategory.synthesis,
      VoiceFailureCategory.playback,
      VoiceFailureCategory.configuration,
      VoiceFailureCategory.unknown,
    ];

    for (final category in operational) {
      test('omniVoice ${category.name} failure falls back to native', () async {
        final omniVoice = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.omniVoice,
            capabilities: {
              VoiceCapability.standardTargetSpeech,
              VoiceCapability.dynamicTargetSpeech,
            },
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: true,
          ),
          speakFailure: VoiceFailure(
            category: category,
            message: 'omniVoice ${category.name}.',
          ),
        );
        final native = _FakeHandler(
          VoiceProviderDescriptor(
            engine: VoiceEngine.nativeTts,
            capabilities: {VoiceCapability.standardTargetSpeech},
            privacyScope: VoicePrivacyScope.standardContent,
            allowsStandardCache: false,
          ),
        );

        final orchestrator = VoiceOrchestrator(
          policySource: const StaticVoicePolicySource(_online),
          policyResolver: resolver,
          handlerRegistry: _registry([omniVoice, native]),
        );

        final result = await orchestrator.speak(_request());

        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(result.usedFallback, isTrue);
        expect(native.calls, const <VoiceEngine>[VoiceEngine.nativeTts]);
      });
    }

    final failClosed = <VoiceFailureCategory>[
      VoiceFailureCategory.validation,
      VoiceFailureCategory.consentMissing,
      VoiceFailureCategory.providerDisabled,
      VoiceFailureCategory.unsupportedCapability,
      VoiceFailureCategory.sessionExpired,
      VoiceFailureCategory.cleanupIncomplete,
      VoiceFailureCategory.cancelled,
    ];

    for (final category in failClosed) {
      test(
        'omniVoice ${category.name} failure is rethrown without fallback',
        () async {
          final omniVoice = _FakeHandler(
            VoiceProviderDescriptor(
              engine: VoiceEngine.omniVoice,
              capabilities: {
                VoiceCapability.standardTargetSpeech,
                VoiceCapability.dynamicTargetSpeech,
              },
              privacyScope: VoicePrivacyScope.standardContent,
              allowsStandardCache: true,
            ),
            speakFailure: VoiceFailure(
              category: category,
              message: 'omniVoice ${category.name}.',
            ),
          );
          final native = _FakeHandler(
            VoiceProviderDescriptor(
              engine: VoiceEngine.nativeTts,
              capabilities: {VoiceCapability.standardTargetSpeech},
              privacyScope: VoicePrivacyScope.standardContent,
              allowsStandardCache: false,
            ),
          );

          final orchestrator = VoiceOrchestrator(
            policySource: const StaticVoicePolicySource(_online),
            policyResolver: resolver,
            handlerRegistry: _registry([omniVoice, native]),
          );

          await expectLater(
            orchestrator.speak(_request()),
            throwsA(_failure(category)),
          );

          expect(omniVoice.calls, const <VoiceEngine>[VoiceEngine.omniVoice]);
          expect(native.calls, isEmpty);
        },
      );
    }
  });
}
