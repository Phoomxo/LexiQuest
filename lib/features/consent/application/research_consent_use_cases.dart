import '../../identity/domain/local_owner_repository.dart';
import '../domain/research_consent.dart';

typedef ConsentUtcNow = DateTime Function();

final class ResearchConsentUseCases {
  const ResearchConsentUseCases({
    required this.owners,
    required this.repository,
    required this.nowUtc,
  });

  static const currentVersion = 1;

  final LocalOwnerRepository owners;
  final ResearchConsentRepository repository;
  final ConsentUtcNow nowUtc;

  Future<ResearchConsentStatus> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.load(ownerId: owner.id, version: currentVersion);
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
      version: currentVersion,
      accepted: accepted,
      decidedAtUtc: now,
    );
  }
}
