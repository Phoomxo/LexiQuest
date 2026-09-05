import '../../identity/domain/local_owner_repository.dart';
import '../domain/research_consent.dart';

typedef ConsentUtcNow = DateTime Function();

final class ResearchConsentUseCases {
  const ResearchConsentUseCases({
    required this.owners,
    required this.repository,
    required this.nowUtc,
    this.consentVersion = currentVersion,
    this.onLocalMutation,
  });

  static const currentVersion = 1;

  final LocalOwnerRepository owners;
  final ResearchConsentRepository repository;
  final ConsentUtcNow nowUtc;
  final int consentVersion;
  final Future<void> Function(String ownerId)? onLocalMutation;

  Future<ResearchConsentStatus> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.load(ownerId: owner.id, version: consentVersion);
  }

  Future<void> accept() => _decide(true);

  Future<void> withdraw() => _decide(false);

  Future<void> _decide(bool accepted) async {
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final owner = await owners.getOrCreateActiveOwner();
    await repository.decide(
      ownerId: owner.id,
      version: consentVersion,
      accepted: accepted,
      decidedAtUtc: now,
    );
    // A committed decision must not appear to fail because its secondary queue
    // is offline. The existing sync claim path recovers durable withdrawal.
    try {
      await onLocalMutation?.call(owner.id);
    } on Object {
      // Do not repeat or undo the consent write; retry only its sync transport.
    }
  }
}
