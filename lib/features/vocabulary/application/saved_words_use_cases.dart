import '../domain/saved_words.dart';

final class SavedWordsUseCases {
  const SavedWordsUseCases({
    required this.repository,
    required this.generateId,
    required this.nowUtc,
  });

  final SavedWordsRepository repository;
  final String Function() generateId;
  final DateTime Function() nowUtc;

  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId) =>
      repository.watchOwner(expectedOwnerId);

  SavedWordMutation prepareSet({
    required SavedWordState state,
    required bool desiredIsSaved,
  }) {
    final now = nowUtc();
    if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
      throw ArgumentError('Saved-word clock must be nonnegative UTC');
    }
    return SavedWordMutation(
      mutationId: generateId(),
      expectedOwnerId: state.ownerId,
      wordId: state.wordId,
      desiredIsSaved: desiredIsSaved,
      expectedRevision: state.localRevision,
      occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  Future<SavedWordApplyResult> apply(SavedWordMutation command) =>
      repository.apply(command);
}
