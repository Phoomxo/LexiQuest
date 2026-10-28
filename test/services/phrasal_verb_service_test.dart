import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/phrasal_verb_service.dart';

void main() {
  const service = PhrasalVerbService();

  test('PhrasalVerbService filters phrasal verbs by CEFR level', () {
    final b2List = service.getPhrasalVerbsByLevel('B2');
    expect(b2List.isNotEmpty, true);
    expect(b2List.first.phrase, 'come up with');

    final c1List = service.getPhrasalVerbsByLevel('C1');
    expect(c1List.first.phrase, 'bring about');
  });
}
