"""Synthetic fixtures only; these tests do not measure a camera model."""
import unittest
from camera_accuracy import compare


class AccuracyTests(unittest.TestCase):
    def rows(self):
        return [
            dict(id='a', group='scene-a', split='test', truth='cup', baseline='cup', candidate='cup'),
            dict(id='b', group='scene-b', split='test', truth='book', baseline='cup', candidate='book'),
        ]

    def test_paired_metrics(self):
        result = compare(self.rows())
        self.assertEqual(result['baseline']['accuracy'], 0.5)
        self.assertEqual(result['candidate']['accuracy'], 1.0)
        self.assertEqual(result['fixed'], 1)
        self.assertEqual(result['regressed'], 0)

    def test_training_scene_leakage_rejected(self):
        rows = self.rows()
        rows.append(dict(id='c', group='scene-a', split='train', truth='cup'))
        with self.assertRaises(ValueError):
            compare(rows)

    def test_missing_prediction_and_duplicate_rejected(self):
        rows = self.rows()
        del rows[0]['candidate']
        with self.assertRaises(ValueError):
            compare(rows)
        rows = self.rows()
        with self.assertRaises(ValueError):
            compare(rows + [rows[0]])

    def test_wrong_class_is_counted_as_error(self):
        rows = self.rows()
        rows[0]['candidate'] = 'unknown'
        result = compare(rows)
        self.assertEqual(result['candidate']['accuracy'], 0.5)
        self.assertEqual(result['regressed'], 1)


if __name__ == '__main__':
    unittest.main()
