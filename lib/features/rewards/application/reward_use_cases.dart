import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_reward_repository.dart';
import '../domain/reward_models.dart';

typedef RewardIdGenerator = String Function();
typedef RewardUtcNow = DateTime Function();

abstract interface class RewardShopOperations {
  Future<RewardSession> loadSession();

  Stream<RewardAppearance> watchAppearance();

  Future<PurchaseResult> purchase({
    required String expectedOwnerId,
    required String itemId,
    required int catalogVersion,
    required String idempotencyKey,
  });

  Future<EquipResult> equip({
    required String expectedOwnerId,
    required String itemId,
    required String idempotencyKey,
  });
}

final class RewardUseCases implements RewardShopOperations {
  const RewardUseCases({
    required this.owners,
    required this.repository,
    required this.generateId,
    required this.nowUtc,
    this.onLocalMutation,
  });

  final LocalOwnerRepository owners;
  final DriftRewardRepository repository;
  final RewardIdGenerator generateId;
  final RewardUtcNow nowUtc;
  final void Function()? onLocalMutation;

  Future<RewardAccount> load() async {
    return (await loadSession()).account;
  }

  @override
  Future<RewardSession> loadSession() async {
    final owner = await owners.getOrCreateActiveOwner();
    final session = RewardSession(
      ownerId: owner.id,
      account: await repository.load(owner.id),
    );
    await _requireActiveOwner(owner.id);
    return session;
  }

  @override
  Stream<RewardAppearance> watchAppearance() => repository.watchAppearance();

  @override
  Future<PurchaseResult> purchase({
    required String expectedOwnerId,
    required String itemId,
    required int catalogVersion,
    required String idempotencyKey,
  }) async {
    final item = RewardCatalog.byId(itemId);
    if (item == null) {
      throw const RewardException(RewardFailureCode.unknownItem);
    }
    if (catalogVersion != RewardCatalog.version ||
        item.catalogVersion != catalogVersion) {
      throw const RewardException(RewardFailureCode.staleCatalog);
    }
    final key = idempotencyKey.trim();
    if (key.isEmpty || key.length > 256) {
      throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
    }
    final ownerId = await _requireActiveOwner(expectedOwnerId);
    final result = await repository.purchase(
      ownerId: ownerId,
      item: item,
      idempotencyKey: key,
      transactionId: 'reward:${_nextId()}',
      occurredAtUtc: _now(),
    );
    if (result.status == PurchaseStatus.purchased) onLocalMutation?.call();
    await _requireActiveOwner(ownerId);
    return result;
  }

  @override
  Future<EquipResult> equip({
    required String expectedOwnerId,
    required String itemId,
    required String idempotencyKey,
  }) async {
    final item = RewardCatalog.byId(itemId);
    if (item == null) {
      throw const RewardException(RewardFailureCode.unknownItem);
    }
    final key = idempotencyKey.trim();
    if (key.isEmpty || key.length > 256) {
      throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
    }
    final ownerId = await _requireActiveOwner(expectedOwnerId);
    final result = await repository.equip(
      ownerId: ownerId,
      item: item,
      idempotencyKey: key,
      transactionId: 'reward:${_nextId()}',
      occurredAtUtc: _now(),
    );
    if (result.status == EquipStatus.equipped) onLocalMutation?.call();
    await _requireActiveOwner(ownerId);
    return result;
  }

  Future<String> _requireActiveOwner(String expectedOwnerId) async {
    final expected = expectedOwnerId.trim();
    if (expected.isEmpty) {
      throw const RewardException(RewardFailureCode.ownerChanged);
    }
    final active = await owners.getOrCreateActiveOwner();
    if (active.id != expected) {
      throw const RewardException(RewardFailureCode.ownerChanged);
    }
    return active.id;
  }

  String _nextId() {
    final id = generateId().trim();
    if (id.isEmpty) throw StateError('reward id generator returned blank');
    return id;
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}
