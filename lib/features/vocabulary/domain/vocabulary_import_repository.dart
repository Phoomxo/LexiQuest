import 'vocabulary_import.dart';

abstract interface class VocabularyImportRepository {
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  });
}
