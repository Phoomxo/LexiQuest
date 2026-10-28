final class VocabularyWord {
  const VocabularyWord({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.spelling,
    required this.normalizedSpelling,
    required this.meaning,
    required this.normalizedMeaning,
    required this.partOfSpeech,
    required this.source,
    required this.isGlobal,
    required this.localRevision,
    required this.isDeleted,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.cefrLevel,
  });

  final String id;
  final String ownerId;
  final String categoryId;
  final String spelling;
  final String normalizedSpelling;
  final String meaning;
  final String normalizedMeaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
  final bool isGlobal;
  final int localRevision;
  final bool isDeleted;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  VocabularyWord copyWith({
    String? categoryId,
    String? spelling,
    String? normalizedSpelling,
    String? meaning,
    String? normalizedMeaning,
    String? partOfSpeech,
    String? cefrLevel,
    String? source,
    bool? isGlobal,
    int? localRevision,
    bool? isDeleted,
    DateTime? updatedAtUtc,
  }) {
    return VocabularyWord(
      id: id,
      ownerId: ownerId,
      categoryId: categoryId ?? this.categoryId,
      spelling: spelling ?? this.spelling,
      normalizedSpelling: normalizedSpelling ?? this.normalizedSpelling,
      meaning: meaning ?? this.meaning,
      normalizedMeaning: normalizedMeaning ?? this.normalizedMeaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      source: source ?? this.source,
      isGlobal: isGlobal ?? this.isGlobal,
      localRevision: localRevision ?? this.localRevision,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}
