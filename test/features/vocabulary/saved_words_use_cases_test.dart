import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

void main() {
  test(
    'prepare captures original state and one millisecond ID/time; retries are passed unchanged',
    () async {
      final repository = _Repository();
      var ids = 0;
      var clockReads = 0;
      final now = DateTime.utc(2026, 10, 30, 1, 2, 3, 4, 567);
      final useCases = SavedWordsUseCases(
        repository: repository,
        generateId: () => 'synthetic-${++ids}',
        nowUtc: () {
          clockReads++;
          return now;
        },
      );
      final state = SavedWordState.absent(
        ownerId: 'synthetic-owner',
        wordId: 'synthetic-word',
      );
      final command = useCases.prepareSet(state: state, desiredIsSaved: true);
      expect(
        (command.expectedOwnerId, command.wordId, command.expectedRevision),
        (state.ownerId, state.wordId, 0),
      );
      expect(command.occurredAtUtc.microsecondsSinceEpoch % 1000, 0);
      expect(
        command.occurredAtUtc.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      await useCases.apply(command);
      await useCases.apply(command);
      expect(repository.received, [same(command), same(command)]);
      expect((ids, clockReads), (1, 1));
    },
  );

  test(
    'conflict is delivered once without allocating or submitting a replacement',
    () async {
      final repository = _Repository();
      final useCases = SavedWordsUseCases(
        repository: repository,
        generateId: () => 'synthetic',
        nowUtc: () => DateTime.utc(2026, 10, 30),
      );
      final command = useCases.prepareSet(
        state: SavedWordState.absent(
          ownerId: 'synthetic-owner',
          wordId: 'synthetic-word',
        ),
        desiredIsSaved: true,
      );
      final result = await useCases.apply(command);
      expect(result.status, SavedWordApplyStatus.conflict);
      expect(repository.received, hasLength(1));
    },
  );

  test(
    'owner watch delegates the captured owner without creating one',
    () async {
      final repository = _Repository();
      final useCases = SavedWordsUseCases(
        repository: repository,
        generateId: () => 'unused',
        nowUtc: () => throw StateError('clock unused'),
      );
      final snapshot = await useCases.watchOwner('synthetic-owner').first;
      expect(snapshot.ownerId, 'synthetic-owner');
      expect(repository.watched, ['synthetic-owner']);
    },
  );
}

final class _Repository implements SavedWordsRepository {
  final received = <SavedWordMutation>[];
  final watched = <String>[];
  @override
  Future<SavedWordApplyResult> apply(SavedWordMutation command) async {
    received.add(command);
    return SavedWordApplyResult(
      status: SavedWordApplyStatus.conflict,
      state: SavedWordState.absent(
        ownerId: command.expectedOwnerId,
        wordId: command.wordId,
      ),
    );
  }

  @override
  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId) {
    watched.add(expectedOwnerId);
    return Stream.value(
      SavedWordsSnapshot(ownerId: expectedOwnerId, states: [], savedItems: []),
    );
  }
}
