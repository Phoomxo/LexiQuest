import 'voice_capability.dart';
import 'voice_models.dart';

const _providerDisabledFailure = VoiceFailure(
  category: VoiceFailureCategory.providerDisabled,
  message: 'No permitted voice provider is available.',
);

const _consentMissingFailure = VoiceFailure(
  category: VoiceFailureCategory.consentMissing,
  message: 'Voice mirror consent is required.',
);

const _sessionExpiredFailure = VoiceFailure(
  category: VoiceFailureCategory.sessionExpired,
  message: 'The voice mirror session is no longer active.',
);

final class VoiceRouteContext {
  const VoiceRouteContext({
    required this.isOnline,
    required this.remoteStandardEnabled,
    required this.offlinePackAvailable,
    required this.voiceMirrorEnabled,
    required this.hasVoiceMirrorConsent,
    required this.hasActiveVoiceMirrorSession,
  });

  final bool isOnline;
  final bool remoteStandardEnabled;
  final bool offlinePackAvailable;
  final bool voiceMirrorEnabled;
  final bool hasVoiceMirrorConsent;
  final bool hasActiveVoiceMirrorSession;
}

abstract interface class VoicePolicySource {
  Future<VoiceRouteContext> load();
}

final class StaticVoicePolicySource implements VoicePolicySource {
  const StaticVoicePolicySource(this.context);

  final VoiceRouteContext context;

  @override
  Future<VoiceRouteContext> load() async => context;
}

/// Policy source that overlays live voice-mirror consent/session state from
/// the controller onto a base [VoiceRouteContext]. The base flags
/// ([VoiceRouteContext.voiceMirrorEnabled], [VoiceRouteContext.isOnline], etc.)
/// describe deployment availability; consent and active-session state are read
/// dynamically so policy reflects the participant's current choice.
final class MirrorAwareVoicePolicySource implements VoicePolicySource {
  MirrorAwareVoicePolicySource({
    required this._baseContext,
    required this._readMirrorState,
  });

  final VoiceRouteContext _baseContext;
  final MirrorPolicyState Function() _readMirrorState;

  @override
  Future<VoiceRouteContext> load() async {
    final mirror = _readMirrorState();
    return VoiceRouteContext(
      isOnline: _baseContext.isOnline,
      remoteStandardEnabled: _baseContext.remoteStandardEnabled,
      offlinePackAvailable: _baseContext.offlinePackAvailable,
      voiceMirrorEnabled:
          _baseContext.voiceMirrorEnabled && mirror.capabilityEnabled,
      hasVoiceMirrorConsent:
          _baseContext.voiceMirrorEnabled && mirror.capabilityEnabled
          ? mirror.hasConsent
          : _baseContext.hasVoiceMirrorConsent,
      hasActiveVoiceMirrorSession:
          _baseContext.voiceMirrorEnabled && mirror.capabilityEnabled
          ? mirror.hasActiveSession
          : _baseContext.hasActiveVoiceMirrorSession,
    );
  }
}

/// Live consent/session snapshot supplied to [MirrorAwareVoicePolicySource].
final class MirrorPolicyState {
  const MirrorPolicyState({
    required this.capabilityEnabled,
    required this.hasConsent,
    required this.hasActiveSession,
  });

  /// Whether the deployment offers the mirror capability at all (Cloud config
  /// and gateway present).
  final bool capabilityEnabled;
  final bool hasConsent;
  final bool hasActiveSession;
}

final class VoiceRouteStep {
  const VoiceRouteStep({
    required this.engine,
    required this.capability,
    required this.privacyScope,
  });

  final VoiceEngine engine;
  final VoiceCapability capability;
  final VoicePrivacyScope privacyScope;
}

final class VoiceRoutePlan {
  VoiceRoutePlan(Iterable<VoiceRouteStep> steps)
    : steps = List<VoiceRouteStep>.unmodifiable(steps) {
    if (this.steps.isEmpty) {
      throw ArgumentError.value(steps, 'steps', 'must not be empty');
    }
  }

  final List<VoiceRouteStep> steps;
}

final class VoicePolicyResolver {
  const VoicePolicyResolver();

  VoiceRoutePlan resolve({
    required VoiceRequest request,
    required VoiceRouteContext context,
    required Set<VoiceEngine> registeredEngines,
  }) {
    if (request.mode == VoiceMode.researchEvaluation) {
      return _strictPlan(request, context, registeredEngines);
    }

    final steps = switch (request.capability) {
      VoiceCapability.standardTargetSpeech => _standardSteps(
        context,
        registeredEngines,
      ),
      VoiceCapability.dynamicTargetSpeech => _dynamicSteps(
        context,
        registeredEngines,
      ),
      VoiceCapability.sessionVoiceMirror => _mirrorSteps(
        context,
        registeredEngines,
      ),
      VoiceCapability.speechToText ||
      VoiceCapability.pronunciationEvidence => const <VoiceRouteStep>[],
    };
    if (steps.isEmpty) {
      throw _providerDisabledFailure;
    }
    return VoiceRoutePlan(steps);
  }

  VoiceRoutePlan _strictPlan(
    VoiceRequest request,
    VoiceRouteContext context,
    Set<VoiceEngine> registeredEngines,
  ) {
    final engine = request.assignedEngine!;
    if (!registeredEngines.contains(engine) || !_isPermitted(engine, context)) {
      throw _providerDisabledFailure;
    }
    return VoiceRoutePlan([
      VoiceRouteStep(
        engine: engine,
        capability: request.capability,
        privacyScope: request.privacyScope,
      ),
    ]);
  }

  List<VoiceRouteStep> _standardSteps(
    VoiceRouteContext context,
    Set<VoiceEngine> registeredEngines,
  ) {
    final steps = <VoiceRouteStep>[];
    _addStandard(
      steps,
      VoiceEngine.offlinePack,
      context.offlinePackAvailable,
      registeredEngines,
    );
    _addStandard(
      steps,
      VoiceEngine.voxCpmStandard,
      context.isOnline && context.remoteStandardEnabled,
      registeredEngines,
    );
    _addStandard(
      steps,
      VoiceEngine.omniVoice,
      context.isOnline && context.remoteStandardEnabled,
      registeredEngines,
    );
    _addStandard(steps, VoiceEngine.nativeTts, true, registeredEngines);
    return steps;
  }

  List<VoiceRouteStep> _dynamicSteps(
    VoiceRouteContext context,
    Set<VoiceEngine> registeredEngines,
  ) {
    final steps = <VoiceRouteStep>[];
    _add(
      steps,
      engine: VoiceEngine.voxCpmStandard,
      capability: VoiceCapability.dynamicTargetSpeech,
      privacyScope: VoicePrivacyScope.standardContent,
      permitted: context.isOnline && context.remoteStandardEnabled,
      registeredEngines: registeredEngines,
    );
    _add(
      steps,
      engine: VoiceEngine.omniVoice,
      capability: VoiceCapability.dynamicTargetSpeech,
      privacyScope: VoicePrivacyScope.standardContent,
      permitted: context.isOnline && context.remoteStandardEnabled,
      registeredEngines: registeredEngines,
    );
    _add(
      steps,
      engine: VoiceEngine.nativeTts,
      capability: VoiceCapability.dynamicTargetSpeech,
      privacyScope: VoicePrivacyScope.standardContent,
      permitted: true,
      registeredEngines: registeredEngines,
    );
    return steps;
  }

  List<VoiceRouteStep> _mirrorSteps(
    VoiceRouteContext context,
    Set<VoiceEngine> registeredEngines,
  ) {
    if (!context.voiceMirrorEnabled) {
      throw _providerDisabledFailure;
    }
    if (!context.hasVoiceMirrorConsent) {
      throw _consentMissingFailure;
    }
    if (!context.hasActiveVoiceMirrorSession) {
      throw _sessionExpiredFailure;
    }

    final steps = <VoiceRouteStep>[];
    _add(
      steps,
      engine: VoiceEngine.voxCpmMirror,
      capability: VoiceCapability.sessionVoiceMirror,
      privacyScope: VoicePrivacyScope.participantTransient,
      permitted: context.isOnline,
      registeredEngines: registeredEngines,
    );
    steps.addAll(_standardSteps(context, registeredEngines));
    return steps;
  }

  void _addStandard(
    List<VoiceRouteStep> steps,
    VoiceEngine engine,
    bool permitted,
    Set<VoiceEngine> registeredEngines,
  ) {
    _add(
      steps,
      engine: engine,
      capability: VoiceCapability.standardTargetSpeech,
      privacyScope: VoicePrivacyScope.standardContent,
      permitted: permitted,
      registeredEngines: registeredEngines,
    );
  }

  void _add(
    List<VoiceRouteStep> steps, {
    required VoiceEngine engine,
    required VoiceCapability capability,
    required VoicePrivacyScope privacyScope,
    required bool permitted,
    required Set<VoiceEngine> registeredEngines,
  }) {
    if (permitted && registeredEngines.contains(engine)) {
      steps.add(
        VoiceRouteStep(
          engine: engine,
          capability: capability,
          privacyScope: privacyScope,
        ),
      );
    }
  }

  bool _isPermitted(VoiceEngine engine, VoiceRouteContext context) {
    return switch (engine) {
      VoiceEngine.nativeTts => true,
      VoiceEngine.offlinePack => context.offlinePackAvailable,
      VoiceEngine.omniVoice || VoiceEngine.voxCpmStandard =>
        context.isOnline && context.remoteStandardEnabled,
      VoiceEngine.voxCpmMirror =>
        context.isOnline &&
            context.voiceMirrorEnabled &&
            context.hasVoiceMirrorConsent &&
            context.hasActiveVoiceMirrorSession,
    };
  }
}
