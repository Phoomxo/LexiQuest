import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class SavedWordsUiHarness {
  SavedWordsUiHarness._(this.storage) {
    repository = SavedWordsUiRepository(words);
    savedWords = SavedWordsUseCases(
      repository: repository,
      generateId: () => 'synthetic-ui-save-${++ids}',
      nowUtc: () => storage.now,
    );
    vocabulary = VocabularyUseCases(
      owners: storage.owners,
      vocabulary: DriftVocabularyRepository(storage.database),
      generateId: () => 'synthetic-ui-word-${++ids}',
      nowUtc: () => storage.now,
    );
    learning = LearningUseCases(
      owners: storage.owners,
      repository: DriftLearningRepository(
        storage.database,
        ownerWrites: storage.ownerWrites,
      ),
      generateId: () => 'synthetic-ui-learning-${++ids}',
      nowUtc: () => storage.now,
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'saved-ui'),
    );
    progress = ProgressUseCases(
      owners: storage.owners,
      queries: DriftProgressQueries(storage.database),
      nowUtc: () => storage.now,
    );
    ownerChanges = Stream<String?>.multi((events) {
      events.add(ownerId);
      final subscription = owners.stream.listen(
        events.add,
        onError: events.addError,
        onDone: events.close,
      );
      events.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  static Future<SavedWordsUiHarness> open() async =>
      SavedWordsUiHarness._(await ConfiguredQuizHarness.open());
  final ConfiguredQuizHarness storage;
  final owners = StreamController<String?>.broadcast(sync: true);
  String? ownerId = configuredOwnerId;
  late final Stream<String?> ownerChanges;
  late final SavedWordsUiRepository repository;
  late final SavedWordsUseCases savedWords;
  late final VocabularyUseCases vocabulary;
  late final LearningUseCases learning;
  late final ProgressUseCases progress;
  int ids = 0;
  bool closed = false;

  List<VocabularyWord> get words => [
    for (var index = 0; index < configuredWordIds.length; index++)
      uiWord(
        configuredWordIds[index],
        ['station', 'ticket', 'platform', 'journey'][index],
      ),
  ];

  AppDependencies dependencies({SavedWordsUseCases? saved}) => AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    database: storage.database,
    localOwners: storage.owners,
    vocabulary: vocabulary,
    learning: learning,
    progress: progress,
    savedWords: saved ?? savedWords,
  );

  void changeOwner(String? value) {
    ownerId = value;
    owners.add(value);
  }

  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    repository.release();
    await Future.wait([owners.close(), repository.close()]);
    await storage.close();
  }
}

VocabularyWord uiWord(String id, String spelling) => VocabularyWord(
  id: id,
  ownerId: configuredOwnerId,
  categoryId: configuredCategoryId,
  spelling: spelling,
  normalizedSpelling: spelling.toLowerCase(),
  meaning: 'synthetic meaning $spelling',
  normalizedMeaning: 'synthetic meaning $spelling',
  partOfSpeech: 'noun',
  source: 'manual',
  isGlobal: false,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: configuredStart,
  updatedAtUtc: configuredStart,
);

final class SavedWordsUiRepository implements SavedWordsRepository {
  SavedWordsUiRepository(Iterable<VocabularyWord> initialWords)
    : words = {for (final word in initialWords) word.id: word};
  final Map<String, VocabularyWord> words;
  final states = <String, StoredSavedWordState>{};
  final changes = StreamController<void>.broadcast(sync: true);
  final commands = <SavedWordMutation>[];
  Completer<void>? acknowledgement;
  bool loseNextAck = false;
  bool conflictNext = false;
  bool holdWatch = false;
  int failedReads = 0;
  int watchCalls = 0;

  SavedWordsSnapshot snapshot(String ownerId) => SavedWordsSnapshot(
    ownerId: ownerId,
    states: states.values.where((state) => state.ownerId == ownerId),
    savedItems: [
      for (final state in states.values.where(
        (state) => state.ownerId == ownerId && state.isSaved,
      ))
        SavedWordItem(
          state: state,
          word: words[state.wordId],
          categoryName: words.containsKey(state.wordId)
              ? 'Synthetic travel'
              : null,
        ),
    ],
  );

  void seed(String wordId, {bool available = true}) {
    states[wordId] = StoredSavedWordState(
      ownerId: configuredOwnerId,
      wordId: wordId,
      isSaved: true,
      localRevision: 1,
      firstSavedAtUtc: configuredStart,
      updatedAtUtc: configuredStart,
      lastMutationId: 'synthetic-seed:$wordId',
    );
    if (!available) words.remove(wordId);
  }

  void emit() => changes.add(null);

  @override
  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId) =>
      Stream<SavedWordsSnapshot>.multi((events) {
        watchCalls++;
        if (failedReads > 0) {
          failedReads--;
          events.addError(StateError('synthetic saved read failure'));
          events.close();
          return;
        }
        if (!holdWatch) events.add(snapshot(expectedOwnerId));
        final subscription = changes.stream.listen(
          (_) => events.add(snapshot(expectedOwnerId)),
          onError: events.addError,
          onDone: events.close,
        );
        events.onCancel = subscription.cancel;
      }, isBroadcast: true);

  @override
  Future<SavedWordApplyResult> apply(SavedWordMutation command) async {
    commands.add(command);
    final current =
        states[command.wordId] ??
        SavedWordState.absent(
          ownerId: command.expectedOwnerId,
          wordId: command.wordId,
        );
    SavedWordApplyResult result;
    if (conflictNext) {
      conflictNext = false;
      final other = _stored(
        command,
        current.localRevision + 1,
        true,
        'synthetic-concurrent-change',
      );
      states[command.wordId] = other;
      result = SavedWordApplyResult(
        status: SavedWordApplyStatus.conflict,
        state: other,
      );
    } else if (current.lastMutationId == command.mutationId) {
      result = SavedWordApplyResult(
        status: SavedWordApplyStatus.replayed,
        state: current,
      );
    } else if (current.localRevision != command.expectedRevision) {
      result = SavedWordApplyResult(
        status: SavedWordApplyStatus.conflict,
        state: current,
      );
    } else if (!command.desiredIsSaved && current.localRevision == 0) {
      result = SavedWordApplyResult(
        status: SavedWordApplyStatus.unchanged,
        state: current,
      );
    } else {
      final next = _stored(
        command,
        current.localRevision + 1,
        command.desiredIsSaved,
        command.mutationId,
      );
      states[command.wordId] = next;
      result = SavedWordApplyResult(
        status: SavedWordApplyStatus.applied,
        state: next,
      );
    }
    emit();
    await acknowledgement?.future;
    if (loseNextAck) {
      loseNextAck = false;
      throw StateError('synthetic lost acknowledgement');
    }
    return result;
  }

  StoredSavedWordState _stored(
    SavedWordMutation command,
    int revision,
    bool saved,
    String id,
  ) => StoredSavedWordState(
    ownerId: command.expectedOwnerId,
    wordId: command.wordId,
    isSaved: saved,
    localRevision: revision,
    firstSavedAtUtc:
        states[command.wordId]?.firstSavedAtUtc ?? command.occurredAtUtc,
    updatedAtUtc: command.occurredAtUtc,
    lastMutationId: id,
  );

  void release() {
    if (acknowledgement case final gate? when !gate.isCompleted) {
      gate.complete();
    }
  }

  Future<void> close() async {
    release();
    await changes.close();
  }
}

Future<void> savedUiUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 60; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail('SavedWords UI did not reach $finder');
}

Future<void> closeSavedUi(WidgetTester tester, SavedWordsUiHarness h) async {
  h.repository.release();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(h.close);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
