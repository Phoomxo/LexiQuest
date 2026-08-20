import 'evidence_context.dart';

/// The single policy-rollout authority shared by every evidence consumer.
///
/// Current-activity capture asks for the owner-scoped configured mode before
/// an [EvidenceContext] exists, so [evidenceContext] is nullable. Consumers
/// that reconstruct persisted evidence always supply it.
abstract interface class EvidencePolicyRolloutModeProvider {
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  });
}

/// Uses the rollout frozen into already-persisted evidence.
///
/// This is useful for bounded replay/test composition. It cannot classify a
/// new activity because no canonical evidence context exists at that point.
final class ContextEvidencePolicyRolloutModeProvider
    implements EvidencePolicyRolloutModeProvider {
  const ContextEvidencePolicyRolloutModeProvider();

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async {
    final context = evidenceContext;
    if (context == null) {
      throw StateError('an evidence context is required for context rollout');
    }
    return context.rolloutMode;
  }
}

/// Explicit fixed policy for bootstrap configuration and direct test seams.
final class FixedEvidencePolicyRolloutModeProvider
    implements EvidencePolicyRolloutModeProvider {
  const FixedEvidencePolicyRolloutModeProvider(this.mode);

  const FixedEvidencePolicyRolloutModeProvider.legacy()
    : mode = EvidencePolicyRolloutMode.legacy;

  final EvidencePolicyRolloutMode mode;

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async => mode;
}
