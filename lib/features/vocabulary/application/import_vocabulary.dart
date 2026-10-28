import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

import '../domain/vocabulary_import.dart';
import '../domain/vocabulary_import_repository.dart';
import '../domain/vocabulary_word.dart';
import 'vocabulary_use_cases.dart';

typedef ImportIdGenerator = String Function();
typedef ImportUtcNow = DateTime Function();

final class ImportVocabulary {
  const ImportVocabulary({
    required this.owners,
    required this.repository,
    required this.generateId,
    required this.nowUtc,
    this.onLocalMutation,
  });

  final LocalOwnerRepository owners;
  final VocabularyImportRepository repository;
  final ImportIdGenerator generateId;
  final ImportUtcNow nowUtc;
  final LocalMutationNotifier? onLocalMutation;

  Future<VocabularyImportResult> call({
    required String categoryId,
    required List<Map<String, String>> rows,
    required String sourceName,
    bool Function()? isCancelled,
    String? expectedOwnerId,
    int? expectedCategoryRevision,
    void Function(PreparedVocabularyImport)? onPrepared,
  }) async {
    final cancellation = isCancelled ?? _neverCancelled;
    if (cancellation()) {
      throw const VocabularyImportCancelled();
    }
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    final owner = await owners.getOrCreateActiveOwner();
    if (expectedOwnerId != null && owner.id != expectedOwnerId ||
        cancellation()) {
      throw const VocabularyImportCancelled();
    }
    final canonicalCategoryId = categoryId.trim();
    if (canonicalCategoryId.isEmpty) {
      throw ArgumentError.value(categoryId, 'categoryId', 'must not be blank');
    }
    final canonicalSourceName = sourceName.trim();
    if (canonicalSourceName.isEmpty) {
      throw ArgumentError.value(sourceName, 'sourceName', 'must not be blank');
    }

    final preparedRows = <PreparedVocabularyImportRow>[];
    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 1;
      final row = rows[index];
      final canonical = canonicalImportRow(row);
      final payloadHash = _sha256(canonical);
      final failureCode = _validateRow(row);
      preparedRows.add(
        PreparedVocabularyImportRow(
          rowNumber: rowNumber,
          payloadHash: payloadHash,
          failureCode: failureCode,
          word: failureCode == null
              ? VocabularyWord(
                  id: 'word:${_nextId()}',
                  ownerId: owner.id,
                  categoryId: canonicalCategoryId,
                  spelling: _canonical(row['word']!),
                  normalizedSpelling: normalizeVocabularyText(row['word']!),
                  meaning: _canonical(row['meaning']!),
                  normalizedMeaning: normalizeVocabularyText(row['meaning']!),
                  partOfSpeech: _canonical(row['partOfSpeech']!),
                  cefrLevel: _validCefrLevel(row['cefrLevel']),
                  source: 'import',
                  isGlobal: false,
                  localRevision: 1,
                  isDeleted: false,
                  createdAtUtc: now,
                  updatedAtUtc: now,
                )
              : null,
        ),
      );
    }
    final sourceHash = _sha256(
      jsonEncode({
        'sourceName': canonicalSourceName,
        'rows': preparedRows.map((row) => row.payloadHash).toList(),
      }),
    );

    final prepared = PreparedVocabularyImport(
      importId: 'import:${_nextId()}',
      ownerId: owner.id,
      categoryId: canonicalCategoryId,
      sourceName: canonicalSourceName,
      sourceHash: sourceHash,
      rows: preparedRows,
      nowUtc: now,
      requireActiveOwner: expectedOwnerId != null,
      expectedCategoryRevision: expectedCategoryRevision,
    );
    onPrepared?.call(prepared);
    final result = await repository.persist(
      prepared,
      isCancelled: cancellation,
    );
    notifyCommittedVocabularyMutation(onLocalMutation);
    return result;
  }

  List<VocabularyImportRowFailure> previewRows(
    List<Map<String, String>> rows,
  ) => [
    for (var i = 0; i < rows.length; i++)
      if (_validateRow(rows[i]) case final String code)
        VocabularyImportRowFailure(rowNumber: i + 1, code: code),
  ];

  Future<bool> verifyResult(
    VocabularyImportResult result, {
    required String expectedOwnerId,
    required String categoryId,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (owner.id != expectedOwnerId) return false;
    final stored = await repository.readResult(
      importId: result.importId,
      ownerId: expectedOwnerId,
      categoryId: categoryId,
    );
    if (stored == null ||
        stored.importId != result.importId ||
        stored.accepted != result.accepted ||
        stored.duplicates != result.duplicates ||
        stored.rejected.length != result.rejected.length) {
      return false;
    }
    for (var i = 0; i < stored.rejected.length; i++) {
      if (stored.rejected[i].rowNumber != result.rejected[i].rowNumber ||
          stored.rejected[i].code != result.rejected[i].code) {
        return false;
      }
    }
    final currentOwner = await owners.getOrCreateActiveOwner();
    return currentOwner.id == expectedOwnerId;
  }

  String _nextId() {
    final id = generateId().trim();
    if (id.isEmpty) {
      throw StateError('import id generator returned a blank id');
    }
    return id;
  }
}

String canonicalImportRow(Map<String, String> row) => [
  normalizeVocabularyText(row['word'] ?? ''),
  normalizeVocabularyText(row['meaning'] ?? ''),
  normalizeVocabularyText(row['partOfSpeech'] ?? ''),
].join('\u001f');

String? _validateRow(Map<String, String> row) {
  final word = _canonical(row['word'] ?? '');
  final meaning = _canonical(row['meaning'] ?? '');
  final partOfSpeech = _canonical(row['partOfSpeech'] ?? '');
  if (word.isEmpty) return 'missingWord';
  if (meaning.isEmpty) return 'missingMeaning';
  if (partOfSpeech.isEmpty) return 'missingPartOfSpeech';
  if (word.length > maxSpellingLength) return 'spellingTooLong';
  if (meaning.length > maxMeaningLength) return 'meaningTooLong';
  if (partOfSpeech.length > maxPartOfSpeechLength) {
    return 'partOfSpeechTooLong';
  }
  return null;
}

String _canonical(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Valid CEFR levels accepted from import rows. Case-insensitive.
const _validCefrLevels = {'a1', 'a2', 'b1', 'b2', 'c1', 'c2'};

/// Returns the uppercased CEFR level if [raw] is valid, otherwise null.
String? _validCefrLevel(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toUpperCase();
  if (_validCefrLevels.contains(trimmed.toLowerCase())) return trimmed;
  return null;
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

bool _neverCancelled() => false;
