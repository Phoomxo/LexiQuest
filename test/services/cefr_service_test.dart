import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/cefr_service.dart';

void main() {
  late CefrService cefrService;

  setUp(() {
    cefrService = CefrService();
  });

  test('CefrService filters multi-dimensionally by level and category', () {
    final b2Business = cefrService.filter(level: 'B2', category: 'Technology');
    expect(b2Business.length, 1);
    expect(b2Business.first.word, 'innovative');

    final toeicWords = cefrService.filter(tag: 'toeic');
    expect(toeicWords.isNotEmpty, true);
    expect(toeicWords.any((w) => w.word == 'achieve'), true);

    final searchResult = cefrService.filter(searchQuery: 'บรรลุ');
    expect(searchResult.length, 1);
    expect(searchResult.first.word, 'achieve');
  });
}
