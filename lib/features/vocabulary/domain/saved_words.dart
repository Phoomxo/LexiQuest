import 'dart:convert';

import 'vocabulary_word.dart';

const int savedWordsMaxRevision = 0x7fffffffffffffff;
const int savedWordsMutationIdMaxBytes = 256;

sealed class SavedWordState {
  const SavedWordState._();

  factory SavedWordState.absent({
    required String ownerId,
    required String wordId,
  }) = AbsentSavedWordState;
  factory SavedWordState.stored({
    required String ownerId,
    required String wordId,
    required bool isSaved,
    required int localRevision,
    required DateTime firstSavedAtUtc,
    required DateTime updatedAtUtc,
    required String lastMutationId,
  }) = StoredSavedWordState;

  String get ownerId;
  String get wordId;
  bool get isSaved;
  int get localRevision;
  DateTime? get firstSavedAtUtc;
  DateTime? get updatedAtUtc;
  String? get lastMutationId;

  bool sameFacts(SavedWordState other) =>
      (
        ownerId,
        wordId,
        isSaved,
        localRevision,
        firstSavedAtUtc,
        updatedAtUtc,
        lastMutationId,
      ) ==
      (
        other.ownerId,
        other.wordId,
        other.isSaved,
        other.localRevision,
        other.firstSavedAtUtc,
        other.updatedAtUtc,
        other.lastMutationId,
      );
}

final class AbsentSavedWordState extends SavedWordState {
  AbsentSavedWordState({required this.ownerId, required this.wordId})
    : super._() {
    _identifier(ownerId);
    _identifier(wordId);
  }

  @override
  final String ownerId;
  @override
  final String wordId;
  @override
  bool get isSaved => false;
  @override
  int get localRevision => 0;
  @override
  DateTime? get firstSavedAtUtc => null;
  @override
  DateTime? get updatedAtUtc => null;
  @override
  String? get lastMutationId => null;
}

final class StoredSavedWordState extends SavedWordState {
  StoredSavedWordState({
    required this.ownerId,
    required this.wordId,
    required this.isSaved,
    required this.localRevision,
    required this.firstSavedAtUtc,
    required this.updatedAtUtc,
    required this.lastMutationId,
  }) : super._() {
    _identifier(ownerId);
    _identifier(wordId);
    if (localRevision < 1 || localRevision > savedWordsMaxRevision) {
      throw ArgumentError('Invalid saved-word revision');
    }
    _millisecondUtc(firstSavedAtUtc);
    _millisecondUtc(updatedAtUtc);
    _mutationId(lastMutationId);
  }

  factory StoredSavedWordState.fromStorage(Map<String, Object?> row) {
    const fields = {
      'owner_id',
      'word_id',
      'is_saved',
      'local_revision',
      'first_saved_at_utc_ms',
      'updated_at_utc_ms',
      'last_mutation_id',
    };
    if (row.length != fields.length || !row.keys.every(fields.contains)) {
      throw const FormatException('Invalid saved-word state');
    }
    final owner = row['owner_id'];
    final word = row['word_id'];
    final saved = row['is_saved'];
    final revision = row['local_revision'];
    final first = row['first_saved_at_utc_ms'];
    final updated = row['updated_at_utc_ms'];
    final mutation = row['last_mutation_id'];
    if (owner is! String ||
        word is! String ||
        !(saved is bool || (saved is int && (saved == 0 || saved == 1))) ||
        revision is! int ||
        first is! int ||
        updated is! int ||
        mutation is! String ||
        first < 0 ||
        first > 8640000000000000 ||
        updated < 0 ||
        updated > 8640000000000000) {
      throw const FormatException('Invalid saved-word state');
    }
    try {
      return StoredSavedWordState(
        ownerId: owner,
        wordId: word,
        isSaved: saved == true || saved == 1,
        localRevision: revision,
        firstSavedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          first,
          isUtc: true,
        ),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true),
        lastMutationId: mutation,
      );
    } on ArgumentError {
      throw const FormatException('Invalid saved-word state');
    }
  }

  @override
  final String ownerId;
  @override
  final String wordId;
  @override
  final bool isSaved;
  @override
  final int localRevision;
  @override
  final DateTime firstSavedAtUtc;
  @override
  final DateTime updatedAtUtc;
  @override
  final String lastMutationId;
}

final class SavedWordMutation {
  SavedWordMutation({
    required this.mutationId,
    required this.expectedOwnerId,
    required this.wordId,
    required this.desiredIsSaved,
    required this.expectedRevision,
    required this.occurredAtUtc,
  }) {
    _mutationId(mutationId);
    _identifier(expectedOwnerId);
    _identifier(wordId);
    if (expectedRevision < 0 || expectedRevision > savedWordsMaxRevision) {
      throw ArgumentError('Invalid expected saved-word revision');
    }
    _millisecondUtc(occurredAtUtc);
  }

  final String mutationId;
  final String expectedOwnerId;
  final String wordId;
  final bool desiredIsSaved;
  final int expectedRevision;
  final DateTime occurredAtUtc;
}

enum SavedWordApplyStatus { applied, replayed, unchanged, conflict }

final class SavedWordApplyResult {
  const SavedWordApplyResult({required this.status, required this.state});
  final SavedWordApplyStatus status;
  final SavedWordState state;
}

enum SavedWordsFailureCode { unavailable, collision }

final class SavedWordsException implements Exception {
  const SavedWordsException(this.code);
  final SavedWordsFailureCode code;

  @override
  String toString() => 'SavedWordsException(${code.name})';
}

final class SavedWordItem {
  SavedWordItem({required this.state, this.word, this.categoryName}) {
    final currentWord = word;
    if (!state.isSaved ||
        (currentWord == null) != (categoryName == null) ||
        (currentWord != null &&
            (currentWord.id != state.wordId ||
                currentWord.ownerId != state.ownerId ||
                currentWord.isDeleted))) {
      throw ArgumentError('Invalid saved-word item');
    }
  }

  final StoredSavedWordState state;
  final VocabularyWord? word;
  final String? categoryName;
  bool get isEligible => word != null;
  String get wordId => state.wordId;
}

final class SavedWordsSnapshot {
  factory SavedWordsSnapshot({
    required String ownerId,
    required Iterable<StoredSavedWordState> states,
    required Iterable<SavedWordItem> savedItems,
  }) {
    _identifier(ownerId);
    final byWord = <String, StoredSavedWordState>{};
    for (final state in states) {
      if (state.ownerId != ownerId || byWord.containsKey(state.wordId)) {
        throw ArgumentError('Invalid saved-word snapshot');
      }
      byWord[state.wordId] = state;
    }
    final items = List<SavedWordItem>.unmodifiable(savedItems);
    final ids = <String>{};
    for (final item in items) {
      final state = byWord[item.wordId];
      if (state == null ||
          !state.sameFacts(item.state) ||
          !ids.add(item.wordId)) {
        throw ArgumentError('Invalid saved-word snapshot');
      }
    }
    if (byWord.values.where((state) => state.isSaved).length != items.length) {
      throw ArgumentError('Invalid saved-word snapshot');
    }
    return SavedWordsSnapshot._(ownerId, Map.unmodifiable(byWord), items);
  }

  const SavedWordsSnapshot._(this.ownerId, this._states, this.savedItems);
  final String ownerId;
  final Map<String, StoredSavedWordState> _states;
  final List<SavedWordItem> savedItems;

  SavedWordState stateFor(String wordId) =>
      _states[wordId] ??
      SavedWordState.absent(ownerId: ownerId, wordId: wordId);
}

abstract interface class SavedWordsRepository {
  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId);
  Future<SavedWordApplyResult> apply(SavedWordMutation command);
}

void _identifier(String value) {
  if (value.trim().isEmpty || value.runes.length > 256) {
    throw ArgumentError('Invalid saved-word identifier');
  }
}

void _mutationId(String value) {
  if (value.trim().isEmpty ||
      utf8.encode(value).length > savedWordsMutationIdMaxBytes) {
    throw ArgumentError('Invalid saved-word mutation identity');
  }
}

void _millisecondUtc(DateTime value) {
  if (!value.isUtc ||
      value.microsecondsSinceEpoch < 0 ||
      value.microsecondsSinceEpoch % 1000 != 0) {
    throw ArgumentError('Saved-word time must be nonnegative UTC milliseconds');
  }
}
