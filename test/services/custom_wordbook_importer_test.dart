import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/custom_wordbook_importer.dart';

void main() {
  const importer = CustomWordbookImporter();

  test('parseJson parses valid JSON array into wordlist', () {
    const jsonStr =
        '[{"word": "apple", "translation": "แอปเปิ้ล", "example": "Red apple"}]';
    final result = importer.parseJson(jsonStr);

    expect(result.length, 1);
    expect(result.first['word'], 'apple');
    expect(result.first['translation'], 'แอปเปิ้ล');
    expect(result.first['example'], 'Red apple');
  });

  test('parseCsv parses CSV lines into wordlist', () {
    const csvStr = 'apple,แอปเปิ้ล,Red apple\nbanana,กล้วย,Yellow banana';
    final result = importer.parseCsv(csvStr);

    expect(result.length, 2);
    expect(result.first['word'], 'apple');
    expect(result[1]['word'], 'banana');
    expect(result[1]['translation'], 'กล้วย');
  });
}
