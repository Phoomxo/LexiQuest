import 'dart:convert';

import '../../vocabulary/domain/vocabulary_word.dart';
import 'learning_pack.dart';

const maxLearningPackRevision = 9007199254740991;

enum PackStorageFailureCode {
  ownerChanged,
  conflict,
  unavailable,
  notFound,
  corrupt,
  staleContent,
  invalid,
}

final class PackStorageException implements Exception {
  const PackStorageException(this.code);
  final PackStorageFailureCode code;
}

enum PackCacheState { notCached, cached, verified, corrupt }

final class PackSourceDescriptor {
  const PackSourceDescriptor.userFile() : kind = 'userFile', catalogId = null;
  PackSourceDescriptor.configuredCatalog(String id)
    : kind = 'configuredCatalog',
      catalogId = id {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,79}$').hasMatch(id)) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
  }
  final String kind;
  final String? catalogId;
  String get canonicalJson =>
      jsonEncode({'schemaVersion': 1, 'kind': kind, 'catalogId': catalogId});

  static PackSourceDescriptor parse(String value) {
    if (utf8.encode(value).length > 4096) {
      throw const PackStorageException(PackStorageFailureCode.corrupt);
    }
    final parsed = jsonDecode(value);
    if (parsed is! Map<String, dynamic> ||
        parsed.length != 3 ||
        parsed['schemaVersion'] != 1 ||
        parsed['schemaVersion'] is! int ||
        !parsed.keys.toSet().containsAll({
          'schemaVersion',
          'kind',
          'catalogId',
        })) {
      throw const PackStorageException(PackStorageFailureCode.corrupt);
    }
    final PackSourceDescriptor result;
    if (parsed['kind'] == 'userFile' && parsed['catalogId'] == null) {
      result = const PackSourceDescriptor.userFile();
    } else if (parsed['kind'] == 'configuredCatalog' &&
        parsed['catalogId'] is String) {
      result = PackSourceDescriptor.configuredCatalog(
        parsed['catalogId'] as String,
      );
    } else {
      throw const PackStorageException(PackStorageFailureCode.corrupt);
    }
    if (result.canonicalJson != value) {
      throw const PackStorageException(PackStorageFailureCode.corrupt);
    }
    return result;
  }
}

final class StoredLearningPack {
  const StoredLearningPack({
    required this.id,
    required this.ownerId,
    required this.manifest,
    required this.packageSha256,
    required this.packageByteCount,
    required this.source,
    required this.cacheState,
    required this.isPinned,
    required this.categoryId,
    required this.importId,
    required this.installedAtUtc,
    required this.revision,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.identityConflict,
  });
  final String id;
  final String ownerId;
  final LearningPackManifest manifest;
  final String packageSha256;
  final int packageByteCount;
  final PackSourceDescriptor source;
  final PackCacheState cacheState;
  final bool isPinned;
  final String? categoryId;
  final String? importId;
  final DateTime? installedAtUtc;
  final int revision;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final bool identityConflict;
  bool get isInstalled => categoryId != null;
}

final class PackLexicalBinding {
  const PackLexicalBinding({
    required this.snapshotId,
    required this.wordId,
    required this.wordRevision,
    required this.entry,
    required this.isCurrent,
    this.word,
  });
  final String snapshotId;
  final String wordId;
  final int wordRevision;
  final LearningPackEntry entry;
  final bool isCurrent;
  final VocabularyWord? word;
}

final class PackDetail {
  PackDetail({
    required this.pack,
    required this.content,
    required List<PackLexicalBinding> bindings,
  }) : bindings = List.unmodifiable(bindings);
  final StoredLearningPack pack;
  // Reconstructed canonical content has its own byte hash; use pack.packageSha256
  // for the original downloaded file identity.
  final LearningPack? content;
  final List<PackLexicalBinding> bindings;
}

final class CurrentLexicalContent {
  const CurrentLexicalContent({
    required this.pack,
    required this.binding,
    required this.content,
    required this.word,
  });
  final StoredLearningPack pack;
  final PackLexicalBinding binding;
  final LearningPack content;
  final VocabularyWord word;
  LearningPackEntry get entry => binding.entry;
  LearningPackImage? get image => content.imagesById[entry.imageId];
}

final class PackImportIntent {
  PackImportIntent({
    required this.expectedOwnerId,
    required this.pack,
    required this.source,
    required this.install,
    required this.pinned,
    required this.expectedRevision,
    required this.mutationId,
    required this.atUtc,
    required this.stillCurrent,
  }) {
    requirePackStorageId(expectedOwnerId);
    requirePackStorageId(mutationId);
    requirePackMutationTime(atUtc);
    if (expectedRevision < 0 || expectedRevision >= maxLearningPackRevision) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
  }
  final String expectedOwnerId;
  final LearningPack pack;
  final PackSourceDescriptor source;
  final bool install;
  final bool pinned;
  final int expectedRevision;
  final String mutationId;
  final DateTime atUtc;
  final bool Function() stillCurrent;
}

final class PackCacheIntent {
  PackCacheIntent({
    required this.expectedOwnerId,
    required this.packVersionId,
    required this.expectedPackageSha256,
    required this.expectedRevision,
    required this.pinned,
    required this.remove,
    required this.repair,
    required this.mutationId,
    required this.atUtc,
    required this.stillCurrent,
  }) {
    requirePackStorageId(expectedOwnerId);
    requirePackStorageId(packVersionId);
    requirePackStorageId(mutationId);
    requirePackMutationTime(atUtc);
    if (expectedRevision < 1 ||
        expectedRevision >= maxLearningPackRevision ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedPackageSha256) ||
        (remove && (pinned || repair != null)) ||
        (repair != null && repair!.packageSha256 != expectedPackageSha256)) {
      throw const PackStorageException(PackStorageFailureCode.invalid);
    }
  }
  final String expectedOwnerId;
  final String packVersionId;
  final String expectedPackageSha256;
  final int expectedRevision;
  final bool pinned;
  final bool remove;
  final LearningPack? repair;
  final String mutationId;
  final DateTime atUtc;
  final bool Function() stillCurrent;
}

abstract interface class LearningPackRepository {
  Future<String?> readActiveOwnerId();
  Stream<String?> watchActiveOwnerId();
  Future<List<StoredLearningPack>> list({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });
  Future<PackDetail> detail({
    required String expectedOwnerId,
    required String packVersionId,
    required bool Function() stillCurrent,
  });
  Future<StoredLearningPack> importPack(PackImportIntent intent);
  Future<StoredLearningPack> changeCache(PackCacheIntent intent);
  Future<CurrentLexicalContent?> currentLexical({
    required String expectedOwnerId,
    required String wordId,
    String? packVersionId,
    required bool Function() stillCurrent,
  });
}

void requirePackStorageId(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      utf8.encode(value).length > 256 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const PackStorageException(PackStorageFailureCode.invalid);
  }
}

void requirePackMutationTime(DateTime value) {
  if (!value.isUtc ||
      value.microsecondsSinceEpoch % 1000 != 0 ||
      value.millisecondsSinceEpoch < 0 ||
      value.millisecondsSinceEpoch > 8640000000000000) {
    throw const PackStorageException(PackStorageFailureCode.invalid);
  }
}
