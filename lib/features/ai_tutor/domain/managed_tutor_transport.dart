import 'ai_tutor_contracts.dart';

/// Local correlation only: accountId is an opaque non-secret reference, never
/// an OAuth token, API key, email, or proof of provider authorization.
final class ManagedTutorBinding {
  const ManagedTutorBinding({
    required this.ownerId,
    required this.accountId,
    required this.generation,
  });
  final String ownerId;
  final String accountId;
  final int generation;
}

/// Application seam, deliberately not wired to production. A future authorized
/// adapter must bind a supported session to this identity, respect cancellation,
/// and perform no late credential/persistence writes. No billing/retry fallback.
/// The host owns adapter/session cleanup and provider revocation separately.
abstract interface class ManagedTutorTransport {
  /// Prepares an already-authorized session; this is not an OAuth/login route.
  Future<void> connect({
    required ManagedTutorBinding binding,
    required AiCancellation cancellation,
  });
  Future<AiGatewayReply> reply({
    required ManagedTutorBinding binding,
    required String learnerMessage,
    required AiCancellation cancellation,
  });
}
