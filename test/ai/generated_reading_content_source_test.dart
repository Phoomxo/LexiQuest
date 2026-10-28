import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/ai/generated_reading_content_source.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';

final class _StubProvider implements ContentProvider {
  _StubProvider({this.response, this.failure});

  final ContentResponse? response;
  final Object? failure;
  int calls = 0;
  ContentRequest? lastRequest;

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    calls++;
    lastRequest = request;
    if (failure case final failure?) {
      throw failure;
    }
    return response!;
  }
}

final class _StubFallback implements ReadingContentSource {
  _StubFallback(this.result);

  final ReadingContentResult result;
  int calls = 0;

  @override
  Future<ReadingContentResult> obtain(ReadingContentRequest request) async {
    calls++;
    return result;
  }
}

const _fallbackContent = ReadingContent(
  contentId: 'curated-a2',
  contentVersion: 'curated-v1',
  cefrLevel: 'A2',
  passage:
      'A careful learner can adapt to a difficult day and keep moving forward.',
  targetWords: ['adapt'],
  provenance: ReadingContentProvenance.curated,
);

ContentResponse _response({
  String text =
      'Mali has to adapt when the library closes early, so she studies '
      'with a friend and finishes her practice before dinner.',
  ContentKind kind = ContentKind.story,
  CefrLevel cefr = CefrLevel.a2,
  String language = 'en',
  String modelVersion = 'reading-model-v3',
}) {
  return ContentResponse(
    text: text,
    kind: kind,
    cefr: cefr,
    language: language,
    modelVersion: modelVersion,
    cached: false,
  );
}

void main() {
  test(
    'accepts validated generated passage with explicit provenance',
    () async {
      final provider = _StubProvider(response: _response());
      final fallback = _StubFallback(
        const ReadingContentAvailable(_fallbackContent),
      );
      final source = GeneratedReadingContentSource(
        provider: provider,
        curatedFallback: fallback,
      );

      final result = await source.obtain(
        const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
      );

      expect(result, isA<ReadingContentAvailable>());
      final content = (result as ReadingContentAvailable).content;
      expect(content.provenance, ReadingContentProvenance.generated);
      expect(content.cefrLevel, 'A2');
      expect(content.contentVersion, 'reading-model-v3');
      expect(content.passage, contains('adapt'));
      expect(content.contentId, startsWith('generated-a2-'));
      expect(provider.lastRequest?.kind, ContentKind.story);
      expect(provider.lastRequest?.cefr, CefrLevel.a2);
      expect(fallback.calls, 0);
    },
  );

  test('falls back when target coverage is invalid', () async {
    final provider = _StubProvider(
      response: _response(
        text:
            'Mali visits the library before dinner and completes every '
            'exercise with a classmate.',
      ),
    );
    final fallback = _StubFallback(
      const ReadingContentAvailable(_fallbackContent),
    );
    final source = GeneratedReadingContentSource(
      provider: provider,
      curatedFallback: fallback,
    );

    final result = await source.obtain(
      const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
    );

    expect(identical(result, fallback.result), isTrue);
    expect(fallback.calls, 1);
  });

  test(
    'falls back on CEFR, language, kind, and passage length drift',
    () async {
      final invalidResponses = <ContentResponse>[
        _response(cefr: CefrLevel.b1),
        _response(language: 'th'),
        _response(kind: ContentKind.explanation),
        _response(text: 'adapt'),
        _response(text: '${List.filled(510, 'a').join()} adapt'),
      ];

      for (final response in invalidResponses) {
        final fallback = _StubFallback(
          const ReadingContentAvailable(_fallbackContent),
        );
        final source = GeneratedReadingContentSource(
          provider: _StubProvider(response: response),
          curatedFallback: fallback,
        );

        final result = await source.obtain(
          const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
        );

        expect(identical(result, fallback.result), isTrue);
        expect(fallback.calls, 1);
      }
    },
  );

  test('uses curated fallback for every provider failure category', () async {
    for (final category in AiFailureCategory.values) {
      final fallback = _StubFallback(
        const ReadingContentAvailable(_fallbackContent),
      );
      final source = GeneratedReadingContentSource(
        provider: _StubProvider(
          failure: AiFailure(category: category, message: 'safe'),
        ),
        curatedFallback: fallback,
      );

      final result = await source.obtain(
        const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
      );

      expect(identical(result, fallback.result), isTrue, reason: category.name);
      expect(fallback.calls, 1, reason: category.name);
    }
  });

  test('disabled generation never calls provider', () async {
    final provider = _StubProvider(response: _response());
    final fallback = _StubFallback(
      const ReadingContentAvailable(_fallbackContent),
    );
    final source = GeneratedReadingContentSource(
      provider: provider,
      curatedFallback: fallback,
      generationEnabled: false,
    );

    final result = await source.obtain(
      const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
    );

    expect(identical(result, fallback.result), isTrue);
    expect(provider.calls, 0);
  });

  test('unexpected provider error is reduced to curated fallback', () async {
    final fallback = _StubFallback(
      const ReadingContentAvailable(_fallbackContent),
    );
    final source = GeneratedReadingContentSource(
      provider: _StubProvider(failure: StateError('private detail')),
      curatedFallback: fallback,
    );

    final result = await source.obtain(
      const ReadingContentRequest(cefrLevel: 'A2', targetWords: ['adapt']),
    );

    expect(identical(result, fallback.result), isTrue);
  });
}
