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
    final status = await repository.load(
      ownerId: owner.id,
      version: currentVersion,
    );
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (status.ownerId != owner.id || currentOwner.id != owner.id) {
      throw StateError('active owner changed while loading research consent');
    }
    return status;
  }

  Future<bool> accept({String? expectedOwnerId}) =>
      _decide(true, expectedOwnerId: expectedOwnerId);

  Future<bool> withdraw({String? expectedOwnerId}) =>
      _decide(false, expectedOwnerId: expectedOwnerId);

  Future<bool> _decide(bool accepted, {String? expectedOwnerId}) async {
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final owner = await owners.getOrCreateActiveOwner();
    if (expectedOwnerId != null && owner.id != expectedOwnerId) return false;
    return repository.decide(
      ownerId: owner.id,
      version: currentVersion,
      accepted: accepted,
      decidedAtUtc: now,
    );
  }
}
