import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

import '../../support/saved_words_data_harness.dart';

void main() {
  late SavedWordsDataHarness h;
  setUp(() async => h = await SavedWordsDataHarness.open());
  tearDown(() => h.close());

  test(
    'save has one local row and exact receipt while every other table stays byte-identical',
    () async {
      final before = await h.storage.snapshot();
      final command = await h.command();
      final result = await h.repository.apply(command);
      expect(result.status, SavedWordApplyStatus.applied);
      expect(result.state.isSaved, isTrue);
      expect(result.state.localRevision, 1);
      expect(result.state.firstSavedAtUtc, command.occurredAtUtc);
      expect(result.state.updatedAtUtc, command.occurredAtUtc);
      expect(result.state.lastMutationId, command.mutationId);
      final after = await h.storage.snapshot();
      for (final table in before.keys.where(
        (table) => table != 'saved_words',
      )) {
        expect(after[table], before[table], reason: table);
      }
      expect(await h.storage.count('saved_words'), 1);
    },
  );

  test(
    'lost ACK replay survives repository reconstruction without retiming or rewriting',
    () async {
      final command = await h.command();
      final original = await h.repository.apply(command);
      final before = await h.storage.snapshot();
      h.now = h.now.add(const Duration(days: 1));
      final reconstructed = DriftSavedWordsRepository(
        h.database,
        ownerWrites: h.storage.ownerWrites,
      );
      final replay = await reconstructed.apply(command);
      expect(replay.status, SavedWordApplyStatus.replayed);
      expect(replay.state.sameFacts(original.state), isTrue);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'save unsave save retains tombstone and first time while stale commands only conflict',
    () async {
      final first = await h.command();
      final saved = await h.repository.apply(first);
      h.now = h.now.add(const Duration(seconds: 1));
      final second = await h.command(saved: false);
      final unsaved = await h.repository.apply(second);
      expect((unsaved.state.isSaved, unsaved.state.localRevision), (false, 2));
      expect((await h.snapshot()).savedItems, isEmpty);
      expect((await h.snapshot()).stateFor(first.wordId).localRevision, 2);
      h.now = h.now.add(const Duration(seconds: 1));
      final last = await h.set(true);
      expect((last.state.isSaved, last.state.localRevision), (true, 3));
      expect(last.state.firstSavedAtUtc, saved.state.firstSavedAtUtc);
      final before = await h.storage.snapshot();
      for (final stale in [first, second]) {
        final result = await h.repository.apply(stale);
        expect(result.status, SavedWordApplyStatus.conflict);
        expect(result.state.sameFacts(last.state), isTrue);
      }
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'new same-state command consumes one revision while exact retry does not',
    () async {
      await h.set(true);
      final command = await h.command();
      final applied = await h.repository.apply(command);
      expect(applied.state.localRevision, 2);
      expect(applied.status, SavedWordApplyStatus.applied);
      expect(
        (await h.repository.apply(command)).status,
        SavedWordApplyStatus.replayed,
      );
      expect((await h.state()).localRevision, 2);
    },
  );

  test(
    'absent unsave is read-only and cannot cancel a separately frozen expected-zero save',
    () async {
      final save = await h.command();
      final unsave = await h.command(saved: false);
      final before = await h.storage.snapshot();
      final unchanged = await h.repository.apply(unsave);
      expect(unchanged.status, SavedWordApplyStatus.unchanged);
      expect(unchanged.state, isA<AbsentSavedWordState>());
      expect(await h.storage.snapshot(), before);
      expect(
        (await h.repository.apply(save)).status,
        SavedWordApplyStatus.applied,
      );
      expect(
        (await h.repository.apply(unsave)).status,
        SavedWordApplyStatus.conflict,
      );
      expect((await h.state()).isSaved, isTrue);
    },
  );

  test(
    'concurrent frozen expected-zero saves produce one applied and one conflict',
    () async {
      final first = await h.command();
      final second = await h.command();
      final results = await Future.wait([
        h.repository.apply(first),
        h.repository.apply(second),
      ]);
      expect(
        results.where(
          (result) => result.status == SavedWordApplyStatus.applied,
        ),
        hasLength(1),
      );
      expect(
        results.where(
          (result) => result.status == SavedWordApplyStatus.conflict,
        ),
        hasLength(1),
      );
      expect(await h.storage.count('saved_words'), 1);
      expect((await h.state()).localRevision, 1);
    },
  );

  for (final alteration in ['state', 'revision', 'time']) {
    test(
      'latest mutation identity with altered $alteration is a collision',
      () async {
        final command = await h.command();
        await h.repository.apply(command);
        final altered = SavedWordMutation(
          mutationId: command.mutationId,
          expectedOwnerId: command.expectedOwnerId,
          wordId: command.wordId,
          desiredIsSaved: alteration == 'state'
              ? false
              : command.desiredIsSaved,
          expectedRevision: alteration == 'revision'
              ? 1
              : command.expectedRevision,
          occurredAtUtc: alteration == 'time'
              ? command.occurredAtUtc.add(const Duration(milliseconds: 1))
              : command.occurredAtUtc,
        );
        final before = await h.storage.snapshot();
        await expectLater(h.repository.apply(altered), _collision());
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'clock reversal changes update time but not first-save time or CAS order',
    () async {
      final first = await h.set(true);
      h.now = h.now.subtract(const Duration(days: 1));
      final second = await h.set(false);
      expect(second.state.firstSavedAtUtc, first.state.firstSavedAtUtc);
      expect(
        second.state.updatedAtUtc!.isBefore(second.state.firstSavedAtUtc!),
        isTrue,
      );
      expect(second.state.localRevision, 2);
    },
  );

  test(
    'saturated persisted revision fails closed without signed integer wrap',
    () async {
      await h.set(true);
      await h.database.customUpdate(
        'UPDATE saved_words SET local_revision = ?',
        variables: [const drift.Variable<int>(savedWordsMaxRevision)],
        updates: {h.database.savedWords},
      );
      final command = await h.command(saved: false);
      final before = await h.storage.snapshot();
      await expectLater(h.repository.apply(command), _unavailable());
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'inherited transaction cannot return a receipt before its outer rollback',
    () async {
      final command = await h.command();
      final before = await h.storage.snapshot();
      await h.database.transaction(() async {
        await expectLater(h.repository.apply(command), _unavailable());
      });
      expect(await h.storage.snapshot(), before);
    },
  );

  test('coordinator from another actual database is rejected', () async {
    final other = await SavedWordsDataHarness.open();
    try {
      expect(
        () => DriftSavedWordsRepository(
          h.database,
          ownerWrites: other.storage.ownerWrites,
        ),
        throwsArgumentError,
      );
    } finally {
      await other.close();
    }
  });

  test(
    'soft-deleted saved target is removable and genuine same-ID recreation respects tombstone',
    () async {
      await h.set(true);
      final original = (await h.snapshot()).savedItems.single.word!;
      final vocabulary = DriftVocabularyRepository(h.database);
      await vocabulary.deleteWord(
        ownerId: configuredOwnerId,
        wordId: original.id,
        nowUtc: h.now,
      );
      final unavailable = (await h.snapshot()).savedItems.single;
      expect(unavailable.isEligible, isFalse);
      expect(unavailable.word, isNull);
      expect(unavailable.categoryName, isNull);
      await h.set(false);
      final restored = await vocabulary.createWord(original);
      expect(restored.id, original.id);
      expect(restored.localRevision, greaterThan(original.localRevision));
      expect((await h.snapshot()).savedItems, isEmpty);
      expect((await h.state()).isSaved, isFalse);
      expect((await h.state()).localRevision, 2);
    },
  );

  test(
    'saved state and tombstone survive actual file database restart',
    () async {
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-saved-words-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}saved.sqlite',
      );
      var stored = await SavedWordsDataHarness.open(file: file);
      try {
        final saved = await stored.set(true);
        await stored.set(false, wordId: configuredWordIds[1]);
        await stored.set(true, wordId: configuredWordIds[1]);
        final tombstone = await stored.set(false, wordId: configuredWordIds[1]);
        await stored.close();
        stored = await SavedWordsDataHarness.open(file: file, seed: false);
        expect((await stored.state()).sameFacts(saved.state), isTrue);
        expect(
          (await stored.state(
            wordId: configuredWordIds[1],
          )).sameFacts(tombstone.state),
          isTrue,
        );
        expect((await stored.snapshot()).savedItems, hasLength(1));
      } finally {
        await stored.close();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-saved-words-',
          ),
        );
        expect(resolved, directory.absolute.path);
        await Directory(resolved).delete(recursive: true);
      }
    },
  );

  for (final deletedParent in ['word', 'category']) {
    for (final superseded in [false, true]) {
      test(
        'stored receipt after owned $deletedParent soft-delete returns ${superseded ? 'conflict' : 'replay'}',
        () async {
          final originalCommand = await h.command();
          var expected = (await h.repository.apply(originalCommand)).state;
          if (superseded) {
            expected = (await h.set(false)).state;
          }
          final vocabulary = DriftVocabularyRepository(h.database);
          if (deletedParent == 'word') {
            await vocabulary.deleteWord(
              ownerId: configuredOwnerId,
              wordId: configuredWordIds.first,
              nowUtc: h.now,
            );
          } else {
            await vocabulary.deleteCategory(
              ownerId: configuredOwnerId,
              categoryId: configuredCategoryId,
              nowUtc: h.now,
            );
          }
          final before = await h.storage.snapshot();
          final result = await h.repository.apply(originalCommand);
          expect(
            result.status,
            superseded
                ? SavedWordApplyStatus.conflict
                : SavedWordApplyStatus.replayed,
          );
          expect(result.state.sameFacts(expected), isTrue);
          expect(await h.storage.snapshot(), before);
          final snapshot = await h.snapshot();
          if (superseded) {
            expect(snapshot.savedItems, isEmpty);
          } else {
            expect(snapshot.savedItems.single.isEligible, isFalse);
            expect(snapshot.savedItems.single.word, isNull);
            expect(snapshot.savedItems.single.categoryName, isNull);
          }
          final freshSave = h.useCases.prepareSet(
            state: result.state,
            desiredIsSaved: true,
          );
          await expectLater(h.repository.apply(freshSave), _unavailable());
          expect(await h.storage.snapshot(), before);
        },
      );
    }
  }
}

Matcher _unavailable() => throwsA(
  isA<SavedWordsException>().having(
    (error) => error.code,
    'code',
    SavedWordsFailureCode.unavailable,
  ),
);
Matcher _collision() => throwsA(
  isA<SavedWordsException>().having(
    (error) => error.code,
    'code',
    SavedWordsFailureCode.collision,
  ),
);
