sealed class VocabularyFailure implements Exception {
  const VocabularyFailure();
}

final class DuplicateVocabularyFailure extends VocabularyFailure {
  const DuplicateVocabularyFailure();
}

final class CategoryWordLimitFailure extends VocabularyFailure {
  const CategoryWordLimitFailure(this.limit);

  final int limit;
}

final class VocabularyNotFoundFailure extends VocabularyFailure {
  const VocabularyNotFoundFailure();
}

final class InvalidVocabularyFailure extends VocabularyFailure {
  const InvalidVocabularyFailure(this.field, this.reason);

  final String field;
  final String reason;
}
