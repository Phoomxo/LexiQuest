import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/pdf_glossary_exporter_service.dart';

void main() {
  const service = PdfGlossaryExporterService();

  test(
    'generateGlossaryDocument formats wordlist into readable study document text',
    () {
      final wordList = [
        {'word': 'apple', 'translation': 'แอปเปิ้ล', 'example': 'Red apple'},
      ];

      final doc = service.generateGlossaryDocument(wordList);
      expect(doc.contains('LEXIQUEST PERSONAL VOCABULARY GLOSSARY'), true);
      expect(doc.contains('1. apple'), true);
      expect(doc.contains('คำแปล: แอปเปิ้ล'), true);
    },
  );
}
