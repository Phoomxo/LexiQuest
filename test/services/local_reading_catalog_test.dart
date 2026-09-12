import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/ai_reading_content_adapter.dart';
import 'package:vocab_learning_app/services/local_reading_catalog.dart';

void main() {
  test('six distinct local lessons contain a passage and reflection task', () {
    final lessons = [
      'A1',
      'A2',
      'B1',
      'B2',
      'C1',
      'C2',
    ].map(LocalReadingCatalog.forLevel).toList();
    expect(lessons.map((e) => e.id).toSet(), hasLength(6));
    expect(lessons.map((e) => e.text).toSet(), hasLength(6));
    for (final lesson in lessons) {
      expect(lesson.text.split(RegExp(r'\s+')).length, greaterThan(45));
      expect(lesson.reflection, isNotEmpty);
    }
    expect(() => LocalReadingCatalog.forLevel('unknown'), throwsArgumentError);
  });

  test(
    'local adapter never claims AI generation or absent target coverage',
    () async {
      final adapter = AiReadingContentAdapter();
      final first = await adapter.generatePassage(
        cefrLevel: 'A1',
        targetWords: ['book', 'unrepresentedword'],
      );
      final second = await adapter.generatePassage(
        cefrLevel: 'A1',
        targetWords: ['book'],
        forceOffline: true,
      );
      expect(first.isFallback, isTrue);
      expect(first.contentId, second.contentId);
      expect(first.targetWords, ['book']);
    },
  );
}
