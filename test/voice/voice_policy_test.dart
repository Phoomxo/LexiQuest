import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_policy.dart';

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

const _allEngines = <VoiceEngine>{
  VoiceEngine.nativeTts,
  VoiceEngine.offlinePack,
  VoiceEngine.omniVoice,
  VoiceEngine.voxCpmStandard,
  VoiceEngine.voxCpmMirror,
};

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

List<VoiceEngine> _engines(VoiceRoutePlan plan) =>
    plan.steps.map((step) => step.engine).toList(growable: false);

void main() {
  const resolver = VoicePolicyResolver();

  test('offline standard speech uses verified pack then native', () {
    final plan = resolver.resolve(
      request: _request(),
      context: _offline,
      registeredEngines: _allEngines,
    );

    expect(_engines(plan), const <VoiceEngine>[
      VoiceEngine.offlinePack,
      VoiceEngine.nativeTts,
    ]);
  });

  test(
    'online standard speech prefers pack, VoxCPM, OmniVoice, then native',
    () {
      final plan = resolver.resolve(
        request: _request(),
        context: _online,
        registeredEngines: _allEngines,
      );

      expect(_engines(plan), const <VoiceEngine>[
        VoiceEngine.offlinePack,
        VoiceEngine.voxCpmStandard,
        VoiceEngine.omniVoice,
        VoiceEngine.nativeTts,
      ]);
      for (final step in plan.steps) {
        expect(step.capability, VoiceCapability.standardTargetSpeech);
        expect(step.privacyScope, VoicePrivacyScope.standardContent);
      }
    },
  );

  test('dynamic speech skips offline pack', () {
    final plan = resolver.resolve(
      request: _request(capability: VoiceCapability.dynamicTargetSpeech),
      context: _online,
      registeredEngines: _allEngines,
    );

    expect(_engines(plan), const <VoiceEngine>[
      VoiceEngine.voxCpmStandard,
      VoiceEngine.omniVoice,
      VoiceEngine.nativeTts,
    ]);
  });

  test('strict research uses only its assigned registered engine', () {
    final plan = resolver.resolve(
      request: _request(
        mode: VoiceMode.researchEvaluation,
        assignedEngine: VoiceEngine.omniVoice,
      ),
      context: _online,
      registeredEngines: _allEngines,
    );

    expect(_engines(plan), const <VoiceEngine>[VoiceEngine.omniVoice]);
  });

  test('strict research rejects an unavailable assigned engine', () {
    expect(
      () => resolver.resolve(
        request: _request(
          mode: VoiceMode.researchEvaluation,
          assignedEngine: VoiceEngine.omniVoice,
        ),
        context: _online,
        registeredEngines: const <VoiceEngine>{VoiceEngine.nativeTts},
      ),
      throwsA(_failure(VoiceFailureCategory.providerDisabled)),
    );
  });

  test('mirror requires separate consent before provider lookup', () {
    const context = VoiceRouteContext(
      isOnline: true,
      remoteStandardEnabled: true,
      offlinePackAvailable: true,
      voiceMirrorEnabled: true,
      hasVoiceMirrorConsent: false,
      hasActiveVoiceMirrorSession: true,
    );

    expect(
      () => resolver.resolve(
        request: _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
        context: context,
        registeredEngines: _allEngines,
      ),
      throwsA(_failure(VoiceFailureCategory.consentMissing)),
    );
  });

  test('mirror requires an active session', () {
    const context = VoiceRouteContext(
      isOnline: true,
      remoteStandardEnabled: true,
      offlinePackAvailable: true,
      voiceMirrorEnabled: true,
      hasVoiceMirrorConsent: true,
      hasActiveVoiceMirrorSession: false,
    );

    expect(
      () => resolver.resolve(
        request: _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
        context: context,
        registeredEngines: _allEngines,
      ),
      throwsA(_failure(VoiceFailureCategory.sessionExpired)),
    );
  });

  test('disabled mirror provider fails closed', () {
    const context = VoiceRouteContext(
      isOnline: true,
      remoteStandardEnabled: true,
      offlinePackAvailable: true,
      voiceMirrorEnabled: false,
      hasVoiceMirrorConsent: true,
      hasActiveVoiceMirrorSession: true,
    );

    expect(
      () => resolver.resolve(
        request: _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
        context: context,
        registeredEngines: _allEngines,
      ),
      throwsA(_failure(VoiceFailureCategory.providerDisabled)),
    );
  });

  test(
    'mirror fallback rewrites capability and privacy for standard voices',
    () {
      final plan = resolver.resolve(
        request: _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
        context: _online,
        registeredEngines: _allEngines,
      );

      expect(_engines(plan), const <VoiceEngine>[
        VoiceEngine.voxCpmMirror,
        VoiceEngine.offlinePack,
        VoiceEngine.voxCpmStandard,
        VoiceEngine.omniVoice,
        VoiceEngine.nativeTts,
      ]);
      expect(plan.steps.first.capability, VoiceCapability.sessionVoiceMirror);
      expect(
        plan.steps.first.privacyScope,
        VoicePrivacyScope.participantTransient,
      );
      for (final step in plan.steps.skip(1)) {
        expect(step.capability, VoiceCapability.standardTargetSpeech);
        expect(step.privacyScope, VoicePrivacyScope.standardContent);
      }
    },
  );

  test('resolver removes engines that are not registered', () {
    final plan = resolver.resolve(
      request: _request(),
      context: _online,
      registeredEngines: const <VoiceEngine>{VoiceEngine.nativeTts},
    );

    expect(_engines(plan), const <VoiceEngine>[VoiceEngine.nativeTts]);
  });

  test('resolver fails when no permitted provider is registered', () {
    expect(
      () => resolver.resolve(
        request: _request(),
        context: _online,
        registeredEngines: const <VoiceEngine>{},
      ),
      throwsA(_failure(VoiceFailureCategory.providerDisabled)),
    );
  });

  test('static policy source returns its exact immutable context', () async {
    const source = StaticVoicePolicySource(_online);

    expect(await source.load(), same(_online));
  });
}
