import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/object_vocabulary_database.dart';

void main() {
  const db = ObjectVocabularyDatabase();

  group('ObjectVocabularyDatabase', () {
    test('contains 120+ vocabulary entries', () {
      expect(db.totalEntries, greaterThanOrEqualTo(120));
    });

    test('lookupByMlLabel finds exact match (case-insensitive)', () {
      final result = db.lookupByMlLabel('Laptop');
      expect(result, isNotNull);
      expect(result!.englishWord, 'laptop');
      expect(result.thaiTranslation, 'คอมพิวเตอร์พกพา');
      expect(result.cefrLevel, 'A2');

      // Case-insensitive
      final result2 = db.lookupByMlLabel('laptop');
      expect(result2, isNotNull);
      expect(result2!.englishWord, 'laptop');
    });

    test('lookupByMlLabel returns null for unknown label', () {
      final result = db.lookupByMlLabel('Quantum Flux Capacitor');
      expect(result, isNull);
    });

    test('lookupByMlLabel supports partial match fallback', () {
      final result = db.lookupByMlLabel('coffee cup');
      expect(result, isNotNull);
      // Should match either 'Coffee' or 'Cup'
    });

    test('getByCategory returns entries in specific category', () {
      final tech = db.getByCategory('Technology');
      expect(tech.isNotEmpty, true);
      for (final entry in tech) {
        expect(entry.category, 'Technology');
      }
    });

    test('getByCefrLevel returns entries at specific CEFR level', () {
      final a1 = db.getByCefrLevel('A1');
      expect(a1.isNotEmpty, true);
      for (final entry in a1) {
        expect(entry.cefrLevel, 'A1');
      }
    });

    test('categories returns all unique categories sorted', () {
      final cats = db.categories;
      expect(cats.length, greaterThanOrEqualTo(10));
      // Verify sorted
      for (int i = 1; i < cats.length; i++) {
        expect(cats[i].compareTo(cats[i - 1]), greaterThanOrEqualTo(0));
      }
    });

    test('every entry has all required fields populated', () {
      for (final entry in db.allEntries) {
        expect(
          entry.mlLabel.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing mlLabel',
        );
        expect(
          entry.englishWord.isNotEmpty,
          true,
          reason: '${entry.mlLabel} missing englishWord',
        );
        expect(
          entry.thaiTranslation.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing thaiTranslation',
        );
        expect(
          entry.cefrLevel.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing cefrLevel',
        );
        expect(
          entry.phonetic.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing phonetic',
        );
        expect(
          entry.exampleSentence.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing exampleSentence',
        );
        expect(
          entry.category.isNotEmpty,
          true,
          reason: '${entry.englishWord} missing category',
        );
      }
    });

    test('every entry has valid CEFR level', () {
      const validLevels = {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'};
      for (final entry in db.allEntries) {
        expect(
          validLevels.contains(entry.cefrLevel),
          true,
          reason:
              '${entry.englishWord} has invalid CEFR level: ${entry.cefrLevel}',
        );
      }
    });
  });
}
