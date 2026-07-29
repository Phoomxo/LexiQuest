enum ReadingContentProvenance { curated, generated }

final class ReadingContentRequest {
  const ReadingContentRequest({
    required this.cefrLevel,
    required this.targetWords,
    this.preferredContentId,
  });

  final String cefrLevel;
  final List<String> targetWords;
  final String? preferredContentId;
}

final class ReadingContent {
  const ReadingContent({
    required this.contentId,
    required this.contentVersion,
    required this.cefrLevel,
    required this.passage,
    required this.targetWords,
    required this.provenance,
  });

  final String contentId;
  final String contentVersion;
  final String cefrLevel;
  final String passage;
  final List<String> targetWords;
  final ReadingContentProvenance provenance;
}

sealed class ReadingContentResult {
  const ReadingContentResult();
}

final class ReadingContentAvailable extends ReadingContentResult {
  const ReadingContentAvailable(this.content);

  final ReadingContent content;
}

enum ReadingContentFailure { unavailable, invalidRequest }

final class ReadingContentUnavailable extends ReadingContentResult {
  const ReadingContentUnavailable(this.failure);

  final ReadingContentFailure failure;
}

abstract interface class ReadingContentSource {
  Future<ReadingContentResult> obtain(ReadingContentRequest request);
}

final class OfflineCuratedReadingContentSource implements ReadingContentSource {
  static const _supportedLevels = {'A1', 'A2', 'B1', 'B2'};

  @override
  Future<ReadingContentResult> obtain(ReadingContentRequest request) async {
    if (!_supportedLevels.contains(request.cefrLevel) ||
        request.targetWords.isEmpty ||
        request.targetWords.any((word) => word.trim().isEmpty)) {
      return const ReadingContentUnavailable(
        ReadingContentFailure.invalidRequest,
      );
    }
    final normalizedWords = request.targetWords
        .map((word) => word.trim())
        .toList(growable: false);
    final identifier =
        'offline-${request.cefrLevel.toLowerCase()}-'
        '${_contentHash(normalizedWords.join('|')).toRadixString(16)}';
    if (request.preferredContentId != null &&
        request.preferredContentId != identifier) {
      return const ReadingContentUnavailable(ReadingContentFailure.unavailable);
    }
    return ReadingContentAvailable(
      ReadingContent(
        contentId: identifier,
        contentVersion: 'offline-template-v1',
        cefrLevel: request.cefrLevel,
        passage:
            'Read this short practice and connect the target words: '
            '${normalizedWords.join(', ')}. Think about how each word can '
            'describe a real situation.',
        targetWords: normalizedWords,
        provenance: ReadingContentProvenance.curated,
      ),
    );
  }
}

final class CuratedReadingContentSource implements ReadingContentSource {
  CuratedReadingContentSource(List<ReadingContent> content)
    : _content = List<ReadingContent>.unmodifiable(content);

  final List<ReadingContent> _content;

  @override
  Future<ReadingContentResult> obtain(ReadingContentRequest request) async {
    if (!RegExp(r'^[ABC][12]$').hasMatch(request.cefrLevel) ||
        request.targetWords.isEmpty ||
        request.targetWords.any((word) => word.trim().isEmpty)) {
      return const ReadingContentUnavailable(
        ReadingContentFailure.invalidRequest,
      );
    }
    for (final candidate in _content) {
      final preferredMatches =
          request.preferredContentId == null ||
          candidate.contentId == request.preferredContentId;
      if (preferredMatches &&
          candidate.cefrLevel == request.cefrLevel &&
          request.targetWords.every(candidate.targetWords.contains)) {
        return ReadingContentAvailable(candidate);
      }
    }
    return const ReadingContentUnavailable(ReadingContentFailure.unavailable);
  }
}

int _contentHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
