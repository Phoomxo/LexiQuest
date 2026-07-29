import '../learning/reading_content_source.dart';
import 'ai_models.dart';
import 'content_provider.dart';

/// Optional generated-content adapter. Every provider or validation failure
/// deterministically resolves through the curated source.
final class GeneratedReadingContentSource implements ReadingContentSource {
  const GeneratedReadingContentSource({
    required ContentProvider provider,
    required ReadingContentSource curatedFallback,
    bool generationEnabled = true,
  }) : _provider = provider,
       _curatedFallback = curatedFallback,
       _generationEnabled = generationEnabled;

  final ContentProvider _provider;
  final ReadingContentSource _curatedFallback;
  final bool _generationEnabled;

  @override
  Future<ReadingContentResult> obtain(ReadingContentRequest request) async {
    if (!_generationEnabled) {
      return _curatedFallback.obtain(request);
    }

    final cefr = _parseCefr(request.cefrLevel);
    if (cefr == null ||
        request.targetWords.isEmpty ||
        request.targetWords.any((word) => word.trim().isEmpty)) {
      return _curatedFallback.obtain(request);
    }

    try {
      final normalizedTargets = request.targetWords
          .map((word) => word.trim())
          .toList(growable: false);
      final response = await _provider.generate(
        ContentRequest.create(
          text:
              'Write a short reading passage that naturally uses every '
              'target word: ${normalizedTargets.join(', ')}.',
          kind: ContentKind.story,
          cefr: cefr,
          language: 'en',
        ),
      );

      if (!_isValid(response, cefr, normalizedTargets)) {
        return _curatedFallback.obtain(request);
      }

      final identifierInput = <String>[
        request.cefrLevel,
        ...normalizedTargets,
        response.modelVersion,
        response.text,
      ].join('|');
      final content = ReadingContent(
        contentId:
            'generated-${request.cefrLevel.toLowerCase()}-'
            '${_stableHash(identifierInput).toRadixString(16)}',
        contentVersion: response.modelVersion,
        cefrLevel: request.cefrLevel,
        passage: response.text.trim(),
        targetWords: normalizedTargets,
        provenance: ReadingContentProvenance.generated,
      );
      if (request.preferredContentId != null &&
          request.preferredContentId != content.contentId) {
        return _curatedFallback.obtain(request);
      }
      return ReadingContentAvailable(content);
    } on Object {
      return _curatedFallback.obtain(request);
    }
  }

  bool _isValid(
    ContentResponse response,
    CefrLevel expectedCefr,
    List<String> targetWords,
  ) {
    final passage = response.text.trim();
    if (response.kind != ContentKind.story ||
        response.cefr != expectedCefr ||
        response.language.trim().toLowerCase() != 'en' ||
        response.modelVersion.trim().isEmpty ||
        passage.length < 40 ||
        passage.length > 500) {
      return false;
    }

    final normalizedPassage = passage.toLowerCase();
    return targetWords.every((target) {
      final expression = RegExp(
        r'(?<![A-Za-z0-9])' +
            RegExp.escape(target.toLowerCase()) +
            r'(?![A-Za-z0-9])',
      );
      return expression.hasMatch(normalizedPassage);
    });
  }
}

CefrLevel? _parseCefr(String value) {
  return switch (value.trim().toUpperCase()) {
    'A1' => CefrLevel.a1,
    'A2' => CefrLevel.a2,
    'B1' => CefrLevel.b1,
    'B2' => CefrLevel.b2,
    'C1' => CefrLevel.c1,
    'C2' => CefrLevel.c2,
    _ => null,
  };
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
