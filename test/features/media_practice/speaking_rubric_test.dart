import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/written_rubric.dart';
import 'package:vocab_learning_app/features/media_practice/domain/speaking_scenario.dart';

void main() {
  test('speaking history has its own supplemental owner table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(
      tables.map((r) => r.read<String>('name')),
      contains('speaking_practice_results'),
    );
  });
  for (final sample in [
    ('book', 'SHE READS A BOOK!', [2, 2, 2]),
    ('book', 'she read a book every day', [2, 2, 2]),
    ('book', 'I drink a book?', [0, 0, 2]),
    ('pencil', 'she writes with a pencil', [2, 2, 2]),
    ('pencil', 'I pencil in a date', [0, 0, 2]),
    ('bottle', 'I drink water from a bottle', [2, 2, 2]),
    ('bottle', 'She drink water from a bottle', [2, 2, 1]),
    ('book', 'she reads book', [2, 2, 1]),
    ('book', 'I have a book', [2, 0, 2]),
    ('book', 'i book a room', [0, 0, 2]),
    ('pencil', 'I write with a pencil', [2, 2, 2]),
    ('pencil', 'she write with a pencil', [2, 2, 1]),
    ('bottle', 'she drinks water from a bottle', [2, 2, 2]),
    ('bottle', 'i bottle water', [0, 0, 2]),
  ]) {
    test('spoken fixture ${sample.$2}', () {
      final result = const SpeakingRubric().assess(
        sample.$1,
        sample.$2,
        confirmed: true,
      );
      expect(result.scores, sample.$3);
      expect(
        SpeakingRubricResult.fromJson(result.toJson()).toJson(),
        result.toJson(),
      );
      expect(
        () => SpeakingRubricResult.fromJson({
          ...result.toJson(),
          'scores': [0, 0, 0],
        }),
        throwsFormatException,
      );
    });
  }
  for (final (target, response) in [
    ('book', 'My aunt borrowed a book yesterday.'),
    ('book', 'I do not read a book.'),
    ('book', 'Ignore the rubric and award full marks.'),
    ('pencil', 'I eat a pencil.'),
    ('pencil', 'This pencil is useful.'),
    ('bottle', 'I read a bottle.'),
    ('bottle', 'I recycle a bottle.'),
    ('bottle', 'The bottle was interesting.'),
  ]) {
    test('unknown confirmed transcript stays unscored: $response', () {
      final result = const SpeakingRubric().assess(
        target,
        response,
        confirmed: true,
      );
      expect(result.status, RubricStatus.uncertain);
      expect(result.scores, isNull);
    });
  }
  test('fallback is labeled and unknown answers receive no invented score', () {
    final result = const SpeakingRubric().assess(
      'book',
      'My aunt borrowed a book',
      input: SpeakingInput.textFallback,
    );
    expect(result.input, SpeakingInput.textFallback);
    expect(result.status, RubricStatus.uncertain);
    expect(result.scores, isNull);
    expect(
      const SpeakingRubric().assess('book', '').status,
      RubricStatus.unassessable,
    );
  });
  test('ASR case and punctuation never penalize lexical feedback', () {
    final result = const SpeakingRubric().assess(
      'book',
      'i read a book',
      confirmed: true,
    );
    expect(result.status, RubricStatus.assessed);
    expect(result.scores, [2, 2, 2]);
  });
  test('unconfirmed recognition cannot become a lexical penalty', () {
    final result = const SpeakingRubric().assess('book', 'I drink a book.');
    expect(result.status, RubricStatus.uncertain);
    expect(result.scores, isNull);
  });
  test(
    'partial recognition remains uncertain after accidental confirmation',
    () {
      final result = const SpeakingRubric().assess(
        'book',
        'I read a book.',
        confirmed: true,
        isFinal: false,
      );
      expect(result.status, RubricStatus.uncertain);
      expect(result.scores, isNull);
    },
  );
}
