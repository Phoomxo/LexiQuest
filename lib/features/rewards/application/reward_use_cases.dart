import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_reward_repository.dart';
import '../domain/reward_models.dart';

typedef RewardIdGenerator = String Function();
typedef RewardUtcNow = DateTime Function();

final class RewardUseCases {
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
    final owner = await owners.getOrCreateActiveOwner();
    return repository.load(owner.id);
  }

  Future<PurchaseResult> purchase({
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
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.purchase(
      ownerId: owner.id,
      item: item,
      idempotencyKey: key,
      transactionId: 'reward:${_nextId()}',
      occurredAtUtc: _now(),
    );
    if (result.status == PurchaseStatus.purchased) onLocalMutation?.call();
    return result;
  }

  Future<CoinGrantResult> grantCoins({
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
  }) async {
    final key = idempotencyKey.trim();
    if (key.isEmpty || key != idempotencyKey || key.runes.length > 256) {
      throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
    }
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
    if (sourceEventId.isEmpty ||
        sourceEventId.trim() != sourceEventId ||
        sourceEventId.runes.length > 256) {
      throw ArgumentError.value(sourceEventId, 'sourceEventId');
    }
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.grantCoins(
      ownerId: owner.id,
      idempotencyKey: key,
      amount: amount,
      sourceEventId: sourceEventId,
      occurredAtUtc: _now(),
    );
    if (result == CoinGrantResult.inserted) onLocalMutation?.call();
    return result;
  }

  Future<RewardAccount> equip(String itemId) async {
    final item = RewardCatalog.byId(itemId);
    if (item == null) {
      throw const RewardException(RewardFailureCode.unknownItem);
    }
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.equip(
      ownerId: owner.id,
      item: item,
      transactionId: 'reward:${_nextId()}',
      occurredAtUtc: _now(),
    );
    onLocalMutation?.call();
    return result;
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
