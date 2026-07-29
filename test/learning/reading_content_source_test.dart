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
}
