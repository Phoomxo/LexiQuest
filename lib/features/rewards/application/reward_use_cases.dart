import '../../identity/domain/local_owner_repository.dart';
import '../../progress/application/progress_use_cases.dart';
import '../data/drift_reward_repository.dart';
import '../domain/avatar_progression_policy.dart';
import '../domain/reward_models.dart';

typedef RewardIdGenerator = String Function();
typedef RewardUtcNow = DateTime Function();

final class RewardUseCases {
  const RewardUseCases({
    required this.owners,
    required this.repository,
    required this.progress,
    required this.generateId,
    required this.nowUtc,
    this.onLocalMutation,
    this.avatarProgressionPolicy = const AvatarProgressionPolicy(),
  });

  final LocalOwnerRepository owners;
  final DriftRewardRepository repository;
  final ProgressUseCases progress;
  final RewardIdGenerator generateId;
  final RewardUtcNow nowUtc;
  final void Function()? onLocalMutation;
  final AvatarProgressionPolicy avatarProgressionPolicy;

  Future<RewardAccount> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    return _avatarOperation(owner.id, () => repository.load(owner.id));
  }

  Future<AvatarRewardState> loadAvatar() async {
    final owner = await owners.getOrCreateActiveOwner();
    final progression = await _loadAvatarProgression(owner.id);
    final account = await _avatarOperation(
      owner.id,
      () => repository.load(owner.id),
    );
    return AvatarRewardState(account: account, progression: progression);
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
    final currentAccount = await _avatarOperation(
      owner.id,
      () => repository.load(owner.id),
    );
    if (item.price > 0 && !currentAccount.ownedItemIds.contains(item.id)) {
      final progression = await _loadAvatarProgression(owner.id);
      if (!progression.isItemUnlocked(item.id)) {
        throw const RewardException(RewardFailureCode.lockedByProgression);
      }
    }
    final result = await _avatarOperation(
      owner.id,
      () => repository.purchase(
        ownerId: owner.id,
        item: item,
        idempotencyKey: key,
        transactionId: 'reward:${_nextId()}',
        occurredAtUtc: _now(),
      ),
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

  Future<EquipResult> equip(
    String itemId, {
    required String idempotencyKey,
  }) async {
    final item = RewardCatalog.byId(itemId);
    if (item == null) {
      throw const RewardException(RewardFailureCode.unknownItem);
    }
    final key = idempotencyKey.trim();
    if (key.isEmpty || key != idempotencyKey || key.runes.length > 256) {
      throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
    }
    final owner = await owners.getOrCreateActiveOwner();
    final result = await _avatarOperation(
      owner.id,
      () => repository.equip(
        ownerId: owner.id,
        item: item,
        idempotencyKey: key,
        transactionId: 'reward:${_nextId()}',
        occurredAtUtc: _now(),
      ),
    );
    if (result.status == EquipStatus.equipped) onLocalMutation?.call();
    return result;
  }

  Future<AvatarProgression> _loadAvatarProgression(String ownerId) async {
    final snapshot = await progress.loadForOwner(ownerId);
    final progression = avatarProgressionPolicy.evaluate(
      lifetimeXp: snapshot.totalXp,
    );
    if (progression.level != snapshot.gameLevel) {
      throw StateError(
        'avatar level disagrees with canonical progress snapshot',
      );
    }
    return progression;
  }

  Future<T> _avatarOperation<T>(
    String ownerId,
    Future<T> Function() operation,
  ) async {
    if (!await repository.avatarProjectionAvailable(ownerId)) {
      throw const RewardException(RewardFailureCode.evidenceUnavailable);
    }
    try {
      return await operation();
    } on StateError {
      throw const RewardException(RewardFailureCode.evidenceUnavailable);
    }
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
