import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';

void main() {
  test(
    'first capture waits for initial owner observation before reading owner',
    () async {
      final repository = _Repository();
      final packs = _packs(repository);
      addTearDown(packs.dispose);
      addTearDown(repository.close);
      final capture = packs.captureOwner(stillCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.readCalls, 0);
      repository.owners.add('a');
      final owner = (await capture)!;
      expect(owner.ownerId, 'a');
      expect(owner.isCurrent, isTrue);
      expect(repository.readCalls, 1);
    },
  );

  test(
    'an already retired caller need not wait for first owner observation',
    () async {
      final repository = _Repository();
      final packs = _packs(repository);
      addTearDown(packs.dispose);
      addTearDown(repository.close);
      await expectLater(
        packs.captureOwner(stillCurrent: () => false),
        _ownerChanged,
      );
      expect(repository.readCalls, 0);
    },
  );

  test(
    'A to B to A while owner read waits cannot issue a fresh old-owner scope',
    () async {
      final repository = _Repository();
      final pending = Completer<String?>();
      repository.ownerResult = pending.future;
      final packs = _packs(repository);
      addTearDown(packs.dispose);
      addTearDown(repository.close);
      repository.owners.add('a');
      final capture = packs.captureOwner(stillCurrent: () => true);
      final rejected = expectLater(capture, _ownerChanged);
      await repository.readStarted.future;
      repository.owners.add('b');
      repository.owners.add('a');
      pending.complete('a');
      await rejected;
    },
  );

  for (final ended in [false, true]) {
    test(
      'owner observer ${ended ? 'completion' : 'error'} retires future captures',
      () async {
        final repository = _Repository();
        final packs = _packs(repository);
        addTearDown(packs.dispose);
        addTearDown(repository.close);
        repository.owners.add('a');
        final previous = (await packs.captureOwner(stillCurrent: () => true))!;
        if (ended) {
          await repository.owners.close();
        } else {
          repository.owners.addError(StateError('synthetic owner failure'));
        }
        expect(previous.isCurrent, isFalse);
        await expectLater(
          packs.captureOwner(stillCurrent: () => true),
          _ownerChanged,
        );
      },
    );
  }

  test(
    'disposing before initial observation releases a pending capture',
    () async {
      final repository = _Repository();
      final packs = _packs(repository);
      addTearDown(repository.close);
      final rejected = expectLater(
        packs.captureOwner(stillCurrent: () => true),
        _ownerChanged,
      );
      await packs.dispose();
      await rejected;
    },
  );

  test(
    'one runtime cannot use another runtime owner scope with the same owner ID',
    () async {
      final first = _Repository();
      final second = _Repository();
      final packs = _packs(first);
      final replacement = _packs(second);
      addTearDown(packs.dispose);
      addTearDown(replacement.dispose);
      addTearDown(first.close);
      addTearDown(second.close);
      first.owners.add('a');
      second.owners.add('a');
      final scope = (await packs.captureOwner(stillCurrent: () => true))!;
      expect(() => replacement.list(scope), _ownerChanged);
      expect(second.listCalls, 0);
    },
  );
}

final _ownerChanged = throwsA(
  isA<PackStorageException>().having(
    (error) => error.code,
    'code',
    PackStorageFailureCode.ownerChanged,
  ),
);

LearningPackUseCases _packs(_Repository repository) => LearningPackUseCases(
  repository: repository,
  nowUtc: () => DateTime.utc(2026, 11, 1),
  generateId: () => 'synthetic-operation',
);

final class _Repository implements LearningPackRepository {
  final owners = StreamController<String?>.broadcast(sync: true);
  final readStarted = Completer<void>();
  Future<String?>? ownerResult;
  var readCalls = 0;
  var listCalls = 0;

  @override
  Future<String?> readActiveOwnerId() {
    readCalls++;
    if (!readStarted.isCompleted) readStarted.complete();
    return ownerResult ?? Future.value('a');
  }

  @override
  Stream<String?> watchActiveOwnerId() => owners.stream;
  @override
  Future<List<StoredLearningPack>> list({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    listCalls++;
    return const [];
  }

  @override
  Future<PackDetail> detail({
    required String expectedOwnerId,
    required String packVersionId,
    required bool Function() stillCurrent,
  }) => throw StateError('unused synthetic detail');
  @override
  Future<StoredLearningPack> importPack(PackImportIntent intent) =>
      throw StateError('unused synthetic import');
  @override
  Future<StoredLearningPack> changeCache(PackCacheIntent intent) =>
      throw StateError('unused synthetic cache');
  @override
  Future<CurrentLexicalContent?> currentLexical({
    required String expectedOwnerId,
    required String wordId,
    String? packVersionId,
    required bool Function() stillCurrent,
  }) => throw StateError('unused synthetic lexical');
  Future<void> close() async {
    if (!owners.isClosed) await owners.close();
  }
}
