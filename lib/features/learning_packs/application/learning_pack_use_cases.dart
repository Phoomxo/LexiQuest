import 'dart:async';

import '../domain/learning_pack.dart';
import '../domain/learning_pack_repository.dart';

final class PackOwnerScope {
  const PackOwnerScope._(this.ownerId, this._current, this._issuer);
  final String ownerId;
  final bool Function() _current;
  final LearningPackUseCases _issuer;
  bool get isCurrent => _current();
}

final class LearningPackUseCases {
  LearningPackUseCases({
    required this.repository,
    required this.nowUtc,
    required this.generateId,
    this.onLocalMutation,
  }) {
    _owners = repository.watchActiveOwnerId().listen(
      (_) {
        _generation++;
        if (!_ownerReady.isCompleted) _ownerReady.complete();
      },
      onError: (Object _) => _retireOwnerStream(),
      onDone: _retireOwnerStream,
    );
  }
  final LearningPackRepository repository;
  final DateTime Function() nowUtc;
  final String Function() generateId;
  final void Function()? onLocalMutation;
  late final StreamSubscription<String?> _owners;
  final _ownerReady = Completer<void>();
  var _generation = 0;
  var _disposed = false;
  var _ownerStreamLive = true;

  Stream<String?> watchActiveOwnerId() => repository.watchActiveOwnerId();

  Future<PackOwnerScope?> captureOwner({
    required bool Function() stillCurrent,
  }) async {
    if (_disposed || !_ownerStreamLive || !stillCurrent()) _retired();
    await _ownerReady.future;
    if (_disposed || !_ownerStreamLive || !stillCurrent()) _retired();
    final generation = _generation;
    final owner = await repository.readActiveOwnerId();
    if (_disposed ||
        !_ownerStreamLive ||
        generation != _generation ||
        !stillCurrent()) {
      _retired();
    }
    if (owner == null) return null;
    return PackOwnerScope._(
      owner,
      () =>
          !_disposed &&
          _ownerStreamLive &&
          generation == _generation &&
          stillCurrent(),
      this,
    );
  }

  Future<List<StoredLearningPack>> list(PackOwnerScope scope) {
    _require(scope);
    return repository.list(
      expectedOwnerId: scope.ownerId,
      stillCurrent: () => scope.isCurrent,
    );
  }

  Future<PackDetail> detail(PackOwnerScope scope, String packVersionId) {
    _require(scope);
    return repository.detail(
      expectedOwnerId: scope.ownerId,
      packVersionId: packVersionId,
      stillCurrent: () => scope.isCurrent,
    );
  }

  PackImportIntent prepareImport({
    required PackOwnerScope scope,
    required LearningPack pack,
    PackSourceDescriptor source = const PackSourceDescriptor.userFile(),
    bool install = true,
    bool pinned = false,
    int expectedRevision = 0,
  }) {
    _require(scope);
    return PackImportIntent(
      expectedOwnerId: scope.ownerId,
      pack: pack,
      source: source,
      install: install,
      pinned: pinned,
      expectedRevision: expectedRevision,
      mutationId: generateId(),
      atUtc: _now(),
      stillCurrent: () => scope.isCurrent,
    );
  }

  Future<StoredLearningPack> importPack(PackImportIntent intent) async {
    if (_disposed || !intent.stillCurrent()) _retired();
    final result = await repository.importPack(intent);
    if (intent.install) onLocalMutation?.call();
    return result;
  }

  PackCacheIntent prepareCacheChange({
    required PackOwnerScope scope,
    required StoredLearningPack stored,
    required bool pinned,
    bool remove = false,
    LearningPack? repair,
  }) {
    _require(scope);
    if (stored.ownerId != scope.ownerId) _retired();
    return PackCacheIntent(
      expectedOwnerId: scope.ownerId,
      packVersionId: stored.id,
      expectedPackageSha256: stored.packageSha256,
      expectedRevision: stored.revision,
      pinned: pinned,
      remove: remove,
      repair: repair,
      mutationId: generateId(),
      atUtc: _now(),
      stillCurrent: () => scope.isCurrent,
    );
  }

  Future<StoredLearningPack> changeCache(PackCacheIntent intent) {
    if (_disposed || !intent.stillCurrent()) _retired();
    return repository.changeCache(intent);
  }

  Future<CurrentLexicalContent?> currentLexical({
    required PackOwnerScope scope,
    required String wordId,
    String? packVersionId,
  }) {
    _require(scope);
    return repository.currentLexical(
      expectedOwnerId: scope.ownerId,
      wordId: wordId,
      packVersionId: packVersionId,
      stillCurrent: () => scope.isCurrent,
    );
  }

  DateTime _now() {
    final time = nowUtc();
    if (!time.isUtc) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
    final result = DateTime.fromMillisecondsSinceEpoch(
      time.millisecondsSinceEpoch,
      isUtc: true,
    );
    requirePackMutationTime(result);
    return result;
  }

  void _require(PackOwnerScope scope) {
    if (_disposed || !identical(scope._issuer, this) || !scope.isCurrent) {
      _retired();
    }
  }

  void _retireOwnerStream() {
    _ownerStreamLive = false;
    _generation++;
    if (!_ownerReady.isCompleted) _ownerReady.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retireOwnerStream();
    await _owners.cancel();
  }

  Never _retired() =>
      throw const PackStorageException(PackStorageFailureCode.ownerChanged);
}
