import unittest
from build_cefr_catalog import join_entries, select_entries


class CatalogBuildTest(unittest.TestCase):
    def test_capitalization_and_case_sensitive_senses_are_preserved(self):
        cefr = [{'headword': 'May', 'pos': 'noun', 'CEFR': 'A1'}]
        lex = [{'id': '1', 'e-entry': 'may', 'e-cat': 'N', 't-entry': 'พืชชนิดหนึ่ง'},
               {'id': '2', 'e-entry': 'May', 'e-cat': 'N', 't-entry': 'เดือนพฤษภาคม'}]
        result = join_entries(cefr, lex)[0]
        self.assertEqual(result['word'], 'May')
        self.assertEqual(result['meanings'], ['เดือนพฤษภาคม'])

    def test_join_requires_same_spelling_and_pos_and_retains_provenance(self):
        cefr = [{'headword': 'book', 'pos': 'noun', 'CEFR': 'A1'},
                {'headword': 'book', 'pos': 'verb', 'CEFR': 'A2'},
                {'headword': 'missing', 'pos': 'noun', 'CEFR': 'A1'}]
        lex = [{'id': '1', 'e-entry': 'book', 'e-cat': 'N', 't-entry': 'หนังสือ'},
               {'id': '2', 'e-entry': 'book', 'e-cat': 'VT', 't-entry': 'จอง'}]
        words = join_entries(cefr, lex)
        self.assertEqual(len(words), 1)
        self.assertEqual(words[0]['meanings'], ['หนังสือ'])
        self.assertEqual(words[0]['cefrLevel'], 'A1')
        self.assertEqual(words[0]['lexitronIds'], ['1'])
        self.assertEqual(words[0]['cefrjRow'], 2)

    def test_invalid_translation_is_not_filled_with_placeholder(self):
        cefr = [{'headword': 'test', 'pos': 'noun', 'CEFR': 'A1'}]
        for meaning in ['', 'English only', '\ufffdภาษาไทย', 'คำ\x00เสีย']:
            self.assertEqual(join_entries(cefr, [{'id': '1', 'e-entry': 'test', 'e-cat': 'N', 't-entry': meaning}]), [])

    def test_selection_is_exact_unique_and_not_an_alphabetical_prefix(self):
        entries = [{'id': str(i), 'word': chr(97 + i), 'cefrLevel': 'B1'} for i in range(20)]
        selected = select_entries(entries, 5)
        self.assertEqual(len(selected), 5)
        self.assertEqual(len({x['word'] for x in selected}), 5)
        self.assertEqual(selected, select_entries(entries, 5))
        self.assertGreater(max(x['word'] for x in selected), 'o')
        with self.assertRaises(ValueError):
            select_entries(entries, 21)


if __name__ == '__main__':
    unittest.main()
