import '../../identity/domain/local_owner_repository.dart';
import '../domain/research_consent.dart';

typedef ConsentUtcNow = DateTime Function();

final class ResearchConsentUseCases {
  const ResearchConsentUseCases({
    required this.owners,
    required this.repository,
    required this.nowUtc,
    this.version = currentVersion,
  });

  static const currentVersion = 1;

  final LocalOwnerRepository owners;
  final ResearchConsentRepository repository;
  final ConsentUtcNow nowUtc;
  final int version;

  Future<ResearchConsentStatus> load() async {
    _requireVersion();
    final owner = await owners.getOrCreateActiveOwner();
    final status = await repository.load(ownerId: owner.id, version: version);
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (status.ownerId != owner.id || currentOwner.id != owner.id) {
      throw StateError('active owner changed while loading research consent');
    }
    if (status.version != version) {
      throw StateError(
        'research consent version does not match requested version',
      );
    }
    return status;
  }

  Future<bool> accept({String? expectedOwnerId, int? expectedVersion}) =>
      _decide(
        true,
        expectedOwnerId: expectedOwnerId,
        expectedVersion: expectedVersion,
      );

  Future<bool> withdraw({String? expectedOwnerId, int? expectedVersion}) =>
      _decide(
        false,
        expectedOwnerId: expectedOwnerId,
        expectedVersion: expectedVersion,
      );

  void _requireVersion() {
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be positive');
    }
  }

  Future<bool> _decide(
    bool accepted, {
    String? expectedOwnerId,
    int? expectedVersion,
  }) async {
    _requireVersion();
    if (expectedVersion != null && expectedVersion != version) return false;
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final status = await load();
    if (expectedOwnerId != null && status.ownerId != expectedOwnerId) {
      return false;
    }
    return repository.decide(
      ownerId: status.ownerId,
      version: version,
      accepted: accepted,
      decidedAtUtc: now,
    );
  }
}
