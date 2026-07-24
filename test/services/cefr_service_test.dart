import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/cefr_service.dart';

void main() {
  late CefrService cefrService;

  setUp(() {
    cefrService = CefrService();
  });

  test('CefrService retrieves default words by CEFR level', () {
    final a1Words = cefrService.getWordsByLevel('A1');
    expect(a1Words.isNotEmpty, true);
    expect(a1Words.every((w) => w.cefrLevel == 'A1'), true);

    final c2Words = cefrService.getWordsByLevel('C2');
    expect(c2Words.isNotEmpty, true);
    expect(c2Words.first.word, 'ephemeral');
  });
}
