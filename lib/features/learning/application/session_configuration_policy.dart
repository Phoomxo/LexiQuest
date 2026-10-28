import 'dart:math' as math;

import '../../learning_packs/domain/content_manifest.dart';
import '../domain/session_configuration.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_policy_rollout.dart';
import 'current_activity_evidence.dart';
import 'lesson_mode_registry.dart';

abstract interface class SessionConfigurationProtocolProvider {
  Future<SessionConfigurationProtocolLimits> resolveForOwner(String ownerId);
}

final class SessionConfigurationProtocolBinding {
  const SessionConfigurationProtocolBinding({
    required this.experimentId,
    required this.experimentVersion,
    required this.cohort,
    required this.protocolVersion,
    required this.consentVersion,
    required this.limits,
  });

  final String experimentId;
  final int experimentVersion;
  final String cohort;
  final String protocolVersion;
  final int consentVersion;
  final SessionConfigurationProtocolLimits limits;
}

/// Immutable configuration-policy catalog. Only an upstream consent-gated,
/// current research snapshot may select a non-baseline binding. This catalog
/// never reads assignments and cannot activate a cohort.
final class SessionConfigurationProtocolCatalog {
  SessionConfigurationProtocolCatalog({
    required this.baseline,
    Iterable<SessionConfigurationProtocolBinding> bindings = const [],
  }) : bindings = List<SessionConfigurationProtocolBinding>.unmodifiable(
         bindings,
       );

  final SessionConfigurationProtocolLimits baseline;
  final List<SessionConfigurationProtocolBinding> bindings;

  SessionConfigurationProtocolLimits resolveCurrentResearch(
    CurrentActivityResearchSnapshot snapshot,
  ) {
    final experiment = snapshot.experimentContext;
    final consentVersion = snapshot.consentContext.researchConsentVersion;
    if (!snapshot.engagementAllowed ||
        !snapshot.hasCompleteResearchProtocol ||
        experiment == null ||
        consentVersion <= 0) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.staleProtocol,
      );
    }
    final exact = bindings.where(
      (binding) =>
          binding.experimentId == experiment.experimentId &&
          binding.experimentVersion == snapshot.experimentVersion &&
          binding.cohort == experiment.variantId &&
          binding.protocolVersion == snapshot.protocolVersion &&
          binding.consentVersion == consentVersion,
    );
    if (exact.length != 1) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.staleProtocol,
      );
    }
    final binding = exact.single;
    if (binding.consentVersion <= 0 ||
        binding.limits.protocolId != snapshot.protocolId ||
        binding.limits.protocolVersion != binding.protocolVersion) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    return binding.limits.copyWith(
      authorityIdentity:
          'assignment:${snapshot.assignmentId}:'
          '${experiment.experimentId}@${snapshot.experimentVersion}:'
          '${experiment.variantId}:${snapshot.protocolVersion}:'
          'consent:$consentVersion',
    );
  }
}

final class PersistedSessionConfigurationProtocolProvider
    implements SessionConfigurationProtocolProvider {
  const PersistedSessionConfigurationProtocolProvider({
    required this.currentResearchState,
    required this.rolloutMode,
    required this.nowUtc,
    required this.catalog,
  });

  final CurrentActivityResearchStateProvider currentResearchState;
  final EvidencePolicyRolloutModeProvider rolloutMode;
  final DateTime Function() nowUtc;
  final SessionConfigurationProtocolCatalog catalog;

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async {
    SessionConfigurationPolicy.requireCanonical(ownerId, 'ownerId');
    try {
      final mode = await rolloutMode.resolve(
        ownerId: ownerId,
        evidenceContext: null,
      );
      if (mode == EvidencePolicyRolloutMode.legacy) return catalog.baseline;
      final occurredAtUtc = nowUtc();
      if (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.invalidProtocol,
        );
      }
      final snapshot = await currentResearchState.resolveActivity(
        ownerId: ownerId,
        input: CurrentActivityInput.meaningMultipleChoice,
        occurredAtUtc: occurredAtUtc,
        rolloutMode: mode,
      );
      return catalog.resolveCurrentResearch(snapshot);
    } on SessionConfigurationResetRequired {
      rethrow;
    } catch (_) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
  }
}

final class SessionConfigurationPolicy {
  const SessionConfigurationPolicy();

  SessionConfigurationDraft defaultsFor({
    required LessonModeRegistration registration,
    required SessionConfigurationProtocolLimits limits,
  }) {
    final capabilities = _requireContext(registration, limits);
    final maximumItems = math.min(
      capabilities.maximumItemCount,
      limits.maximumItemCount,
    );
    final minimumItems = math.max(
      capabilities.minimumItemCount,
      limits.minimumItemCount,
    );
    if (minimumItems > maximumItems) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    final direction = capabilities.directions.first;
    final difficulty =
        capabilities.difficulties.contains(SessionDifficulty.standard)
        ? SessionDifficulty.standard
        : capabilities.difficulties.first;
    final timing = capabilities.supportsTimed
        ? SessionTiming.timed(
            Duration(
              seconds: 600.clamp(
                limits.minimumTimedSeconds,
                limits.maximumTimedSeconds,
              ),
            ),
          )
        : capabilities.supportsUntimedAlternative &&
              limits.allowsUntimedAlternative
        ? SessionTiming.untimedAlternative(
            maximumActiveEffort: Duration(
              seconds: limits.maximumUntimedActiveEffortSeconds,
            ),
          )
        : throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.invalidProtocol,
          );
    return SessionConfigurationDraft(
      itemCount: capabilities.defaultItemCount.clamp(
        minimumItems,
        maximumItems,
      ),
      direction: direction,
      difficulty: difficulty,
      hintBudget: 0,
      timing: timing,
    );
  }

  SessionConfiguration validate({
    required SessionConfigurationDraft draft,
    required LessonModeRegistration registration,
    required SessionConfigurationProtocolLimits limits,
    required String ownerId,
    required Iterable<ContentIdentity> availablePackIdentities,
  }) {
    final capabilities = _requireContext(registration, limits);
    try {
      requireCanonical(ownerId, 'ownerId');
    } on ArgumentError {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    if (!capabilities.directions.contains(draft.direction) ||
        !capabilities.difficulties.contains(draft.difficulty)) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    final minimumItems = math.max(
      capabilities.minimumItemCount,
      limits.minimumItemCount,
    );
    final maximumItems = math.min(
      capabilities.maximumItemCount,
      limits.maximumItemCount,
    );
    if (minimumItems > maximumItems) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    final maximumHintBudget = math.min(
      capabilities.maximumHintBudget,
      limits.maximumHintBudget,
    );
    final timing = _boundedTiming(draft.timing, capabilities, limits);
    final packIdentity = draft.packIdentity;
    if (limits.pinnedPackIdentities.isNotEmpty && packIdentity == null) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
    if (packIdentity != null) {
      if (!capabilities.supportsPackSelection ||
          !_isValidPackIdentity(packIdentity)) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.unsupportedOption,
        );
      }
      if (limits.pinnedPackIdentities.isNotEmpty &&
          !limits.pinnedPackIdentities.contains(packIdentity)) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.packDrift,
        );
      }
      if (!availablePackIdentities.contains(packIdentity)) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.packDrift,
        );
      }
    }
    return SessionConfiguration.validated(
      schemaVersion: sessionConfigurationSchemaVersion,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: ownerId,
      mode: registration.mode,
      itemCount: draft.itemCount.clamp(minimumItems, maximumItems),
      direction: draft.direction,
      difficulty: draft.difficulty,
      hintBudget: draft.hintBudget.clamp(0, maximumHintBudget),
      timing: timing,
      packIdentity: packIdentity,
      protocolId: limits.protocolId,
      protocolVersion: limits.protocolVersion,
      protocolLimitsIdentity: limits.contentIdentity,
    );
  }

  SessionConfiguration revalidate({
    required SessionConfiguration configuration,
    required LessonModeRegistration registration,
    required SessionConfigurationProtocolLimits limits,
    required String ownerId,
    required Iterable<ContentIdentity> availablePackIdentities,
  }) {
    if (configuration.mode != registration.mode) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.modeDrift,
      );
    }
    if (configuration.ownerId != ownerId) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.ownerDrift,
      );
    }
    if (configuration.protocolId != limits.protocolId ||
        configuration.protocolVersion != limits.protocolVersion ||
        configuration.protocolLimitsIdentity != limits.contentIdentity) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.staleProtocol,
      );
    }
    final packIdentity = configuration.packIdentity;
    if (packIdentity != null &&
        !availablePackIdentities.contains(packIdentity)) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
    final refreshed = validate(
      draft: configuration.draft,
      registration: registration,
      limits: limits,
      ownerId: ownerId,
      availablePackIdentities: availablePackIdentities,
    );
    if (refreshed != configuration) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    return refreshed;
  }

  SessionConfigurationCapabilities _requireContext(
    LessonModeRegistration registration,
    SessionConfigurationProtocolLimits limits,
  ) {
    if (!registration.isDeliverable) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.modeUnavailable,
      );
    }
    _validateLimits(limits);
    final adapter = registration.adapter;
    if (adapter is! SessionConfigurableLessonModeAdapter) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    final capabilities = adapter.sessionConfigurationCapabilities;
    if (capabilities.minimumItemCount < 1 ||
        capabilities.maximumItemCount < capabilities.minimumItemCount ||
        capabilities.defaultItemCount < capabilities.minimumItemCount ||
        capabilities.defaultItemCount > capabilities.maximumItemCount ||
        capabilities.directions.isEmpty ||
        capabilities.difficulties.isEmpty ||
        capabilities.maximumHintBudget < 0 ||
        (!capabilities.supportsTimed &&
            !capabilities.supportsUntimedAlternative)) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    return capabilities;
  }

  void _validateLimits(SessionConfigurationProtocolLimits limits) {
    if (limits.schemaVersion != sessionConfigurationSchemaVersion) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unknownVersion,
      );
    }
    try {
      requireCanonical(limits.protocolId, 'protocolId');
      requireCanonical(limits.protocolVersion, 'protocolVersion');
      requireCanonical(limits.authorityIdentity, 'authorityIdentity');
    } on ArgumentError {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    if (limits.minimumItemCount < 1 ||
        limits.maximumItemCount < limits.minimumItemCount ||
        limits.maximumHintBudget < 0 ||
        limits.minimumTimedSeconds < 1 ||
        limits.maximumTimedSeconds < limits.minimumTimedSeconds ||
        (limits.allowsUntimedAlternative &&
            limits.maximumUntimedActiveEffortSeconds < 1)) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    final identities = <ContentIdentity>{};
    for (final identity in limits.pinnedPackIdentities) {
      if (!_isValidPackIdentity(identity) || !identities.add(identity)) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.invalidProtocol,
        );
      }
    }
  }

  SessionTiming _boundedTiming(
    SessionTiming requested,
    SessionConfigurationCapabilities capabilities,
    SessionConfigurationProtocolLimits limits,
  ) => switch (requested.kind) {
    SessionTimingKind.timed => _boundedTimed(requested, capabilities, limits),
    SessionTimingKind.untimedAlternative => _boundedUntimed(
      requested,
      capabilities,
      limits,
    ),
  };

  SessionTiming _boundedTimed(
    SessionTiming requested,
    SessionConfigurationCapabilities capabilities,
    SessionConfigurationProtocolLimits limits,
  ) {
    final value = requested.timedLimit;
    if (!capabilities.supportsTimed || value == null) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    return SessionTiming.timed(
      Duration(
        seconds: value.inSeconds.clamp(
          limits.minimumTimedSeconds,
          limits.maximumTimedSeconds,
        ),
      ),
    );
  }

  SessionTiming _boundedUntimed(
    SessionTiming requested,
    SessionConfigurationCapabilities capabilities,
    SessionConfigurationProtocolLimits limits,
  ) {
    final value = requested.maximumActiveEffort;
    if (!capabilities.supportsUntimedAlternative ||
        !limits.allowsUntimedAlternative ||
        value == null ||
        value.inSeconds < 1) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.unsupportedOption,
      );
    }
    return SessionTiming.untimedAlternative(
      maximumActiveEffort: Duration(
        seconds: math.min(
          value.inSeconds,
          limits.maximumUntimedActiveEffortSeconds,
        ),
      ),
    );
  }

  static bool _isValidPackIdentity(ContentIdentity identity) =>
      identity.type == ContentType.learningPack &&
      identity.id.isNotEmpty &&
      identity.id == identity.id.trim() &&
      identity.id.runes.length <= 256 &&
      identity.revision > 0;

  static void requireCanonical(String value, String name) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw ArgumentError.value(value, name, 'must be canonical');
    }
  }
}
