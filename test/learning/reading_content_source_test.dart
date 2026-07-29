import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';

void main() {
  test(
    'curated source returns versioned offline content with provenance',
    () async {
      final source = CuratedReadingContentSource([
        const ReadingContent(
          contentId: 'a2-resilience',
          contentVersion: 'curated-v1',
          cefrLevel: 'A2',
          passage: 'Mali stays resilient when a plan changes.',
          targetWords: ['resilient'],
          provenance: ReadingContentProvenance.curated,
        ),
      ]);

      final result = await source.obtain(
        const ReadingContentRequest(
          cefrLevel: 'A2',
          targetWords: ['resilient'],
        ),
      );

      expect(result, isA<ReadingContentAvailable>());
      expect(
        (result as ReadingContentAvailable).content.provenance,
        ReadingContentProvenance.curated,
      );
    },
  );

  test(
    'returns a typed unavailable result instead of simulated content',
    () async {
      final result = await CuratedReadingContentSource(const []).obtain(
        const ReadingContentRequest(
          cefrLevel: 'B2',
          targetWords: ['ephemeral'],
        ),
      );

      expect(result, isA<ReadingContentUnavailable>());
    },
  );

  test(
    'offline template covers A1 through B2 and rejects higher levels',
    () async {
      final source = OfflineCuratedReadingContentSource();

      for (final level in ['A1', 'A2', 'B1', 'B2']) {
        final result = await source.obtain(
          ReadingContentRequest(
            cefrLevel: level,
            targetWords: const ['resilient', 'adapt'],
          ),
        );
        expect(result, isA<ReadingContentAvailable>(), reason: level);
        final content = (result as ReadingContentAvailable).content;
        expect(content.passage, contains('resilient'));
        expect(content.passage, contains('adapt'));
        expect(content.provenance, ReadingContentProvenance.curated);
      }

      expect(
        await source.obtain(
          const ReadingContentRequest(
            cefrLevel: 'C1',
            targetWords: ['resilient'],
          ),
        ),
        isA<ReadingContentUnavailable>(),
      );
    },
  );
}
