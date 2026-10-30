import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30);
  Map<String, Object?> row() => {
    'owner_id': 'synthetic-owner',
    'word_id': 'synthetic-word',
    'is_saved': 1,
    'local_revision': 1,
    'first_saved_at_utc_ms': now.millisecondsSinceEpoch,
    'updated_at_utc_ms': now.millisecondsSinceEpoch,
    'last_mutation_id': 'saved-merge:synthetic',
  };

  test('absence is typed revision zero without invented receipt or time', () {
    final state = SavedWordState.absent(
      ownerId: 'synthetic-owner',
      wordId: 'synthetic-word',
    );
    expect(state, isA<AbsentSavedWordState>());
    expect(
      (
        state.isSaved,
        state.localRevision,
        state.firstSavedAtUtc,
        state.updatedAtUtc,
        state.lastMutationId,
      ),
      (false, 0, null, null, null),
    );
  });

  test(
    'seven stored facts parse exactly and allow reversed ordinary clock',
    () {
      final source = row()
        ..['updated_at_utc_ms'] = now
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch;
      final state = StoredSavedWordState.fromStorage(source);
      expect(state.isSaved, isTrue);
      expect(state.updatedAtUtc.isBefore(state.firstSavedAtUtc), isTrue);
      expect(state.lastMutationId, 'saved-merge:synthetic');
      expect(state.sameFacts(StoredSavedWordState.fromStorage(source)), isTrue);
    },
  );

  for (final invalid in [
    ('is_saved', 2),
    ('is_saved', 1.0),
    ('local_revision', 0),
    ('owner_id', ''),
    ('word_id', ' '),
    ('first_saved_at_utc_ms', -1),
    ('updated_at_utc_ms', '1'),
    ('last_mutation_id', ' '),
  ]) {
    test('storage rejects malformed ${invalid.$1}=${invalid.$2}', () {
      expect(
        () =>
            StoredSavedWordState.fromStorage(row()..[invalid.$1] = invalid.$2),
        throwsFormatException,
      );
    });
  }

  test('storage rejects extra or missing fields', () {
    expect(
      () => StoredSavedWordState.fromStorage(row()..['id'] = 'invented'),
      throwsFormatException,
    );
    expect(
      () => StoredSavedWordState.fromStorage(row()..remove('word_id')),
      throwsFormatException,
    );
  });

  test(
    'mutation identity bound counts UTF8 bytes without a namespace restriction',
    () {
      SavedWordMutation command(String id) => SavedWordMutation(
        mutationId: id,
        expectedOwnerId: 'synthetic-owner',
        wordId: 'synthetic-word',
        desiredIsSaved: true,
        expectedRevision: 0,
        occurredAtUtc: now,
      );
      expect(command(List.filled(64, '😀').join()).mutationId, hasLength(128));
      expect(() => command(List.filled(65, '😀').join()), throwsArgumentError);
      expect(command('saved-merge:synthetic').expectedRevision, 0);
      expect(() => command(' \t '), throwsArgumentError);
    },
  );

  test(
    'direct commands reject non-UTC non-millisecond and negative timestamps',
    () {
      for (final invalid in [
        now.toLocal(),
        now.add(const Duration(microseconds: 1)),
        DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
      ]) {
        expect(
          () => SavedWordMutation(
            mutationId: 'synthetic',
            expectedOwnerId: 'synthetic-owner',
            wordId: 'synthetic-word',
            desiredIsSaved: true,
            expectedRevision: 0,
            occurredAtUtc: invalid,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'snapshot copies caller lists, retains tombstone and exposes immutable saved items',
    () {
      final saved = StoredSavedWordState.fromStorage(row());
      final tombstone = StoredSavedWordState.fromStorage(
        row()
          ..['word_id'] = 'synthetic-unsaved'
          ..['is_saved'] = 0,
      );
      final states = [saved, tombstone];
      final items = [SavedWordItem(state: saved)];
      final snapshot = SavedWordsSnapshot(
        ownerId: saved.ownerId,
        states: states,
        savedItems: items,
      );
      states.clear();
      items.clear();
      expect(snapshot.savedItems.single.isEligible, isFalse);
      expect(snapshot.savedItems.single.word, isNull);
      expect(snapshot.stateFor(tombstone.wordId).localRevision, 1);
      expect(
        snapshot.stateFor('synthetic-absent'),
        isA<AbsentSavedWordState>(),
      );
      expect(() => snapshot.savedItems.clear(), throwsUnsupportedError);
    },
  );

  test('snapshot rejects duplicate, foreign-owner or hidden saved states', () {
    final saved = StoredSavedWordState.fromStorage(row());
    expect(
      () => SavedWordsSnapshot(
        ownerId: saved.ownerId,
        states: [saved, saved],
        savedItems: [SavedWordItem(state: saved)],
      ),
      throwsArgumentError,
    );
    expect(
      () => SavedWordsSnapshot(
        ownerId: 'other-owner',
        states: [saved],
        savedItems: [SavedWordItem(state: saved)],
      ),
      throwsArgumentError,
    );
    expect(
      () => SavedWordsSnapshot(
        ownerId: saved.ownerId,
        states: [saved],
        savedItems: [],
      ),
      throwsArgumentError,
    );
  });
}
