import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/anki_dictionary_exporter_service.dart';

void main() {
  const cards = [
    VocabularyCardExport(
      word: 'opportunity',
      ipa: '/ˌɒpəˈtjuːnəti/',
      translation: 'โอกาส',
      exampleSentence: 'This is a great opportunity.',
    ),
  ];

  test('exportToAnkiTxt formats tab-delimited cards', () {
    final txt = AnkiDictionaryExporterService.exportToAnkiTxt(cards);
    expect(txt, contains('opportunity\t/ˌɒpəˈtjuːnəti/\tโอกาส'));
  });

  test('exportToJsonPackage formats clean JSON package', () {
    final jsonStr = AnkiDictionaryExporterService.exportToJsonPackage(cards);
    expect(jsonStr, contains('"word": "opportunity"'));
    expect(jsonStr, contains('"ipa": "/ˌɒpəˈtjuːnəti/"'));
  });
}
