import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/cefr_interactive_storybook_service.dart';

void main() {
  const service = CefrInteractiveStorybookService();

  test('getChapters returns all chapters when level is unconstrained', () {
    final chapters = service.getChapters();
    expect(chapters.length, 2);
  });

  test('getChapters filters by CEFR level correctly', () {
    final a2 = service.getChapters(level: 'A2');
    expect(a2.length, 1);
    expect(a2.first.title, 'The Smart Journey');

    final b2 = service.getChapters(level: 'B2');
    expect(b2.length, 1);
    expect(b2.first.title, 'Future Horizons');
  });

  test('getAnnotatedWords extracts vocabulary IPA keys', () {
    final chapter = service.getChapters().first;
    final words = service.getAnnotatedWords(chapter);
    expect(words, containsAll(['library', 'discovery', 'ancient']));
  });
}
