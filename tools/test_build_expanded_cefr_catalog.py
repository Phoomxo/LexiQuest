import unittest
from build_expanded_cefr_catalog import expand

class ExpandedCatalogTest(unittest.TestCase):
    def test_preserves_originals_and_uses_only_new_unique_words(self):
        old = [{'id': 'old', 'word': 'old', 'cefrLevel': 'A1', 'meanings': ['เดิม']}]
        pool = old + [{'id': str(i), 'word': f'word{i}', 'cefrLevel': level}
                      for i, level in enumerate(['B1', 'B1', 'B2', 'B2', 'C1', 'C1', 'C2', 'C2'])]
        pool += [{'id': 'duplicate', 'word': 'OLD', 'cefrLevel': 'C2'}]
        main, supplement = expand(old, pool, {'B1': 1, 'B2': 1, 'C1': 1}, 1)
        self.assertEqual(main[0], old[0])
        self.assertEqual(len(main), 4)
        self.assertEqual(len(supplement), 1)
        self.assertEqual(len({x['word'].lower() for x in main + supplement}), 5)
        self.assertEqual((main, supplement), expand(old, pool, {'B1': 1, 'B2': 1, 'C1': 1}, 1))
    def test_missing_source_never_pads_or_relabels(self):
        with self.assertRaises(ValueError):
            expand([], [], {'C1': 500}, 500)

if __name__ == '__main__': unittest.main()
