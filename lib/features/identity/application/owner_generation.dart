import '../domain/owner_upgrade.dart';

final class OwnerGenerationToken {
  OwnerGenerationToken._(
    this.ownerId,
    this._authority,
    this._generation,
    this._durableStamp,
  );
  final String ownerId;
  final Object _authority;
  final int _generation;
  final String? _durableStamp;
}

/// In-memory capability for a single composed runtime. Never serialize/recreate
/// a token from an owner ID: reopening a draft must acquire a fresh capability.
/// Production also binds the durable epoch, so transitions in another runtime
/// invalidate this capability. The canonical lease still fences every write.
final class OwnerGeneration implements OwnerTransitionLifecycle {
  OwnerGeneration({
    required this.activeOwnerId,
    this.delegate,
    this.readDurableStamp,
  });
  final Future<String> Function() activeOwnerId;
  final OwnerTransitionLifecycle? delegate;
  final Future<String> Function()? readDurableStamp;
  Future<void> requireCurrentAsync(OwnerGenerationToken token) async {
    requireCurrent(token);
    final stamp = await readDurableStamp?.call();
    requireCurrent(token);
    if (stamp != token._durableStamp) {
      throw StateError('Durable owner generation changed');
    }
  }

  final Object _authority = Object();
  int _generation = 0;
  int _transitions = 0;

  Future<OwnerGenerationToken> capture() async {
    if (_transitions != 0) throw StateError('Owner transition is in progress');
    final generation = _generation;
    final durableStamp = await readDurableStamp?.call();
    final owner = await activeOwnerId();
    final token = OwnerGenerationToken._(
      owner,
      _authority,
      generation,
      durableStamp,
    );
    if (owner.isEmpty || owner != owner.trim()) {
      throw StateError('Invalid active owner');
    }
    await requireCurrentAsync(token);
    return token;
  }

  void requireCurrent(OwnerGenerationToken token) {
    if (!identical(token._authority, _authority) ||
        token._generation != _generation ||
        _transitions != 0) {
      throw StateError('Owner generation is no longer current');
    }
  }

  Future<T> duringTransition<T>(Future<T> Function() operation) async {
    _generation++;
    _transitions++;
    try {
      return await operation();
    } finally {
      _generation++;
      _transitions--;
    }
  }

  @override
  Future<T> run<T>({
    required String sourceOwnerId,
    required String operationToken,
    required Future<T> Function() operation,
    required String Function(T) targetOwnerId,
  }) => duringTransition(
    () =>
        delegate?.run(
          sourceOwnerId: sourceOwnerId,
          operationToken: operationToken,
          operation: operation,
          targetOwnerId: targetOwnerId,
        ) ??
        operation(),
  );
}
