final class VocabularyCategory {
  const VocabularyCategory({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.normalizedName,
    required this.sortOrder,
    required this.localRevision,
    required this.isDeleted,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final String ownerId;
  final String name;
  final String normalizedName;
  final int sortOrder;
  final int localRevision;
  final bool isDeleted;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  VocabularyCategory copyWith({
    String? name,
    String? normalizedName,
    int? sortOrder,
    int? localRevision,
    bool? isDeleted,
    DateTime? updatedAtUtc,
  }) {
    return VocabularyCategory(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      sortOrder: sortOrder ?? this.sortOrder,
      localRevision: localRevision ?? this.localRevision,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}
