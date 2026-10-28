import 'vocabulary_import.dart';

abstract interface class VocabularyImportRepository {
  Future<VocabularyImportResult?> readResult({
    required String importId,
    required String ownerId,
    required String categoryId,
  });

  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  });
}
