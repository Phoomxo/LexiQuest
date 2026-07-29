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
