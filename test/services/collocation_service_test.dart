import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/collocation_service.dart';

void main() {
  const service = CollocationService();

  test('getCollocations returns common collocations for CEFR words', () {
    final decisionCols = service.getCollocations('decision');
    expect(decisionCols.contains('make a decision'), true);

    final defaultCols = service.getCollocations('ephemeral');
    expect(defaultCols.isNotEmpty, true);
  });
}
