import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

import '../domain/vocabulary_category.dart';
import '../domain/vocabulary_failure.dart';
import '../domain/vocabulary_repository.dart';
import '../domain/vocabulary_word.dart';

typedef VocabularyIdGenerator = String Function();
typedef VocabularyUtcNow = DateTime Function();
typedef LocalMutationNotifier = void Function();

const int maxCategoryNameLength = 80;
const int maxSpellingLength = 120;
const int maxMeaningLength = 500;
const int maxPartOfSpeechLength = 60;

final class CreateWordCommand {
  const CreateWordCommand({
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.cefrLevel,
    this.source = 'manual',
  });

  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
}

final class UpdateWordCommand {
  const UpdateWordCommand({
    required this.id,
    required this.categoryId,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    this.cefrLevel,
    this.source = 'manual',
  });

  final String id;
  final String categoryId;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
}

final class VocabularyUseCases {
  VocabularyUseCases({
    required this.owners,
    required this.vocabulary,
    required this.generateId,
    required this.nowUtc,
    this.onLocalMutation,
  });

  final LocalOwnerRepository owners;
  final VocabularyRepository vocabulary;
  final VocabularyIdGenerator generateId;
  final VocabularyUtcNow nowUtc;
  final LocalMutationNotifier? onLocalMutation;

  Stream<List<VocabularyCategory>> watchCategories() {
    return Stream.fromFuture(
      owners.getOrCreateActiveOwner(),
    ).asyncExpand((owner) => vocabulary.watchCategories(owner.id));
  }

  Stream<List<VocabularyWord>> watchWords(String categoryId) {
    final canonicalCategoryId = _required(
      categoryId,
      'categoryId',
      maxLength: 256,
    );
    return Stream.fromFuture(owners.getOrCreateActiveOwner()).asyncExpand(
      (owner) => vocabulary.watchWords(owner.id, canonicalCategoryId),
    );
  }

  /// Reads immutable pack-pinned vocabulary identities without creating an
  /// owner or introducing a second vocabulary authority.
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds) =>
      vocabulary.readPinnedByIds(wordIds);

  /// Returns up to [limit] random words from the active owner's vocabulary.
  /// Used by game screens (Word Scramble, Dictation, Boss Battle, etc.)
  /// that need content injection. Returns empty list if no words exist.
  Future<List<VocabularyWord>> getGameWords({int limit = 10}) async {
    final owner = await owners.getOrCreateActiveOwner();
    final all = await vocabulary.listAllWords(owner.id);
    if (all.length <= limit) return all;
    all.shuffle();
    return all.take(limit).toList(growable: false);
  }

  Future<VocabularyCategory> createCategory(String name) async {
    final canonicalName = _required(
      name,
      'categoryName',
      maxLength: maxCategoryNameLength,
    );
    final now = _currentUtc();
    final owner = await owners.getOrCreateActiveOwner();
    final created = await vocabulary.createCategory(
      VocabularyCategory(
        id: 'category:${_nextId()}',
        ownerId: owner.id,
        name: canonicalName,
        normalizedName: normalizeVocabularyText(canonicalName),
        sortOrder: 0,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    onLocalMutation?.call();
    return created;
  }

  Future<VocabularyCategory> renameCategory(
    String categoryId,
    String name,
  ) async {
    final canonicalCategoryId = _required(
      categoryId,
      'categoryId',
      maxLength: 256,
    );
    final canonicalName = _required(
      name,
      'categoryName',
      maxLength: maxCategoryNameLength,
    );
    final owner = await owners.getOrCreateActiveOwner();
    final renamed = await vocabulary.renameCategory(
      ownerId: owner.id,
      categoryId: canonicalCategoryId,
      name: canonicalName,
      normalizedName: normalizeVocabularyText(canonicalName),
      nowUtc: _currentUtc(),
    );
    onLocalMutation?.call();
    return renamed;
  }

  Future<void> deleteCategory(String categoryId) async {
    final canonicalCategoryId = _required(
      categoryId,
      'categoryId',
      maxLength: 256,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await vocabulary.deleteCategory(
      ownerId: owner.id,
      categoryId: canonicalCategoryId,
      nowUtc: _currentUtc(),
    );
    onLocalMutation?.call();
  }

  Future<VocabularyWord> createWord(CreateWordCommand command) async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _currentUtc();
    final created = await vocabulary.createWord(
      _wordFromInput(
        id: 'word:${_nextId()}',
        ownerId: owner.id,
        categoryId: command.categoryId,
        spelling: command.spelling,
        meaning: command.meaning,
        partOfSpeech: command.partOfSpeech,
        cefrLevel: command.cefrLevel,
        source: command.source,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    onLocalMutation?.call();
    return created;
  }

  Future<VocabularyWord> updateWord(UpdateWordCommand command) async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _currentUtc();
    final updated = await vocabulary.updateWord(
      _wordFromInput(
        id: _required(command.id, 'wordId', maxLength: 256),
        ownerId: owner.id,
        categoryId: command.categoryId,
        spelling: command.spelling,
        meaning: command.meaning,
        partOfSpeech: command.partOfSpeech,
        cefrLevel: command.cefrLevel,
        source: command.source,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    onLocalMutation?.call();
    return updated;
  }

  Future<void> deleteWord(String wordId) async {
    final canonicalWordId = _required(wordId, 'wordId', maxLength: 256);
    final owner = await owners.getOrCreateActiveOwner();
    await vocabulary.deleteWord(
      ownerId: owner.id,
      wordId: canonicalWordId,
      nowUtc: _currentUtc(),
    );
    onLocalMutation?.call();
  }

  VocabularyWord _wordFromInput({
    required String id,
    required String ownerId,
    required String categoryId,
    required String spelling,
    required String meaning,
    required String partOfSpeech,
    required String? cefrLevel,
    required String source,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
  }) {
    final canonicalCategoryId = _required(
      categoryId,
      'categoryId',
      maxLength: 256,
    );
    final canonicalSpelling = _required(
      spelling,
      'spelling',
      maxLength: maxSpellingLength,
    );
    final canonicalMeaning = _required(
      meaning,
      'meaning',
      maxLength: maxMeaningLength,
    );
    final canonicalPartOfSpeech = _required(
      partOfSpeech,
      'partOfSpeech',
      maxLength: maxPartOfSpeechLength,
    );
    final canonicalSource = _required(source, 'source', maxLength: 60);
    final canonicalCefr = cefrLevel == null
        ? null
        : _required(cefrLevel, 'cefrLevel', maxLength: 12);
    return VocabularyWord(
      id: id,
      ownerId: ownerId,
      categoryId: canonicalCategoryId,
      spelling: canonicalSpelling,
      normalizedSpelling: normalizeVocabularyText(canonicalSpelling),
      meaning: canonicalMeaning,
      normalizedMeaning: normalizeVocabularyText(canonicalMeaning),
      partOfSpeech: canonicalPartOfSpeech,
      cefrLevel: canonicalCefr,
      source: canonicalSource,
      isGlobal: false,
      localRevision: 1,
      isDeleted: false,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
    );
  }

  String _nextId() {
    final id = generateId().trim();
    if (id.isEmpty) {
      throw StateError('vocabulary id generator returned a blank id');
    }
    return id;
  }

  DateTime _currentUtc() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }
}

String normalizeVocabularyText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _required(String value, String field, {required int maxLength}) {
  final canonical = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (canonical.isEmpty) {
    throw InvalidVocabularyFailure(field, 'must not be blank');
  }
  if (canonical.length > maxLength) {
    throw InvalidVocabularyFailure(
      field,
      'must not exceed $maxLength characters',
    );
  }
  return canonical;
}
