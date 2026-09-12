"""Synthetic fixtures only; these tests do not measure a camera model."""
import unittest
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from copy import deepcopy
import camera_accuracy as accuracy
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


class ModelProtocolTests(unittest.TestCase):
    def rows(self):
        rows = []
        for split in ('validation', 'test'):
            for label in ('book', 'bottle', 'chair', 'cup', 'unknown'):
                for index in range(200 if label == 'unknown' else 30):
                    identity = f'{split}-{label}-{index}'
                    rows.append(dict(id=identity, group=identity, split=split,
                        truth=label, sha256=hashlib.sha256(identity.encode()).hexdigest(),
                        source_url='https://example.org/' + identity,
                        attribution={'License': 'https://creativecommons.org/licenses/by/2.0/'},
                        fresh=True, natural=True, view='full-frame'))
        return rows

    def test_coverage_and_old_test_are_not_fresh(self):
        rows = self.rows()
        self.assertEqual(accuracy.audit_dataset(rows)['status'], 'coverage-ready')
        rows[0]['fresh'] = False
        result = accuracy.audit_dataset(rows)
        self.assertEqual(result['status'], 'insufficient-coverage')
        self.assertEqual(result['counts']['validation']['book'], 29)

    def test_provenance_and_cross_split_content_rejected(self):
        for field in ('source_url', 'sha256', 'attribution'):
            rows = self.rows()
            del rows[0][field]
            with self.assertRaises(ValueError):
                accuracy.audit_dataset(rows)
        rows = self.rows()
        rows[-1]['sha256'] = rows[0]['sha256']
        with self.assertRaises(ValueError):
            accuracy.audit_dataset(rows)
        rows = self.rows()
        rows[-1]['group'] = rows[0]['group']
        with self.assertRaises(ValueError):
            accuracy.audit_dataset(rows)

    def test_crop_siblings_and_ui_do_not_inflate_coverage(self):
        rows = self.rows()
        rows[0]['view'] = 'crop'
        rows[1]['natural'] = False
        result = accuracy.audit_dataset(rows)
        self.assertEqual(result['counts']['validation']['book'], 28)
        rows = self.rows()
        rows[1]['group'] = rows[0]['group']
        self.assertEqual(accuracy.audit_dataset(rows)['counts']['validation']['book'], 29)

    def config(self):
        return dict(baseline_model='a' * 64, candidate_model='b' * 64,
            preprocess='rgb-full-frame-224-v1', threshold=0.6,
            output_classes=4, score_type='softmax', environment='synthetic-test-only')

    def predictions(self, rows, split):
        return [dict(id=r['id'], baseline=r['truth'],
                     candidate='cup' if r['truth'] == 'unknown' else r['truth'],
                     confidence=0.5 if r['truth'] == 'unknown' else 0.9,
                     preprocess='rgb-full-frame-224-v1')
                for r in rows if r['split'] == split]

    def test_invalid_softmax_gate(self):
        config = self.config()
        config['threshold'] = 0.15
        result = accuracy.freeze_validation(self.rows(), config,
                    self.predictions(self.rows(), 'validation'))
        self.assertEqual(result['status'], 'invalid-unknown-gate')
        self.assertEqual(result['decision'], 'retain-baseline')

    def test_frozen_test_metrics_alignment_and_missing_physical(self):
        rows, config = self.rows(), self.config()
        frozen = accuracy.freeze_validation(rows, config, self.predictions(rows, 'validation'))
        predictions = self.predictions(rows, 'test')
        result = accuracy.evaluate_frozen(rows, config, frozen, predictions)
        self.assertEqual(result['candidate']['known_correct_accepted']['numerator'], 120)
        self.assertEqual(result['candidate']['unknown_false_accept']['denominator'], 200)
        self.assertEqual(len(result['candidate']['unknown_false_accept']['wilson95']), 2)
        self.assertEqual(result['decision'], 'retain-baseline')
        self.assertIn('physical/resource evidence unavailable', result['reasons'])
        for changed in ('threshold', 'candidate_model', 'preprocess'):
            other = deepcopy(config)
            other[changed] = 0.7 if changed == 'threshold' else 'changed'
            with self.assertRaises(ValueError):
                accuracy.evaluate_frozen(rows, other, frozen, predictions)
        with self.assertRaises(ValueError):
            accuracy.evaluate_frozen(rows, config, frozen, predictions[:-1])
        predictions[0]['preprocess'] = 'different'
        with self.assertRaises(ValueError):
            accuracy.evaluate_frozen(rows, config, frozen, predictions)

    def test_unknown_acceptance_and_known_rejection(self):
        rows, config = self.rows(), self.config()
        frozen = accuracy.freeze_validation(rows, config, self.predictions(rows, 'validation'))
        predictions = self.predictions(rows, 'test')
        predictions[0]['confidence'] = 0.4
        predictions[-1].update(candidate='cup', confidence=0.9)
        result = accuracy.evaluate_frozen(rows, config, frozen, predictions)
        self.assertEqual(result['candidate']['known_rejected']['numerator'], 1)
        self.assertEqual(result['candidate']['unknown_false_accept']['numerator'], 1)

    def test_nonfinite_and_test_used_for_selection_rejected(self):
        rows, config = self.rows(), self.config()
        predictions = self.predictions(rows, 'validation')
        predictions[0]['confidence'] = float('nan')
        with self.assertRaises(ValueError):
            accuracy.freeze_validation(rows, config, predictions)
        with self.assertRaises(ValueError):
            accuracy.freeze_validation(rows, config, self.predictions(rows, 'test'))

    def test_duplicate_independent_observations_cannot_enter_metrics(self):
        rows = self.rows()
        rows.append({**rows[0], 'id': 'sibling'})
        with self.assertRaises(ValueError):
            accuracy.freeze_validation(rows, self.config(), self.predictions(rows, 'validation'))

    def test_cli_audit_empty_inventory_and_exclusive_report(self):
        with tempfile.TemporaryDirectory() as directory:
            source, report = Path(directory) / 'input.json', Path(directory) / 'report.json'
            source.write_text(json.dumps({'samples': []}))
            command = [sys.executable, str(Path(accuracy.__file__)), str(source), str(report)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(json.loads(report.read_text())['status'], 'insufficient-coverage')
            original = report.read_bytes()
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(report.read_bytes(), original)

    def test_cli_freeze_then_test_is_single_open(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, frozen, result = root / 'input.json', root / 'freeze.json', root / 'result.json'
            rows = self.rows()
            payload = dict(samples=rows, config=self.config(),
                           validation_predictions=self.predictions(rows, 'validation'))
            source.write_text(json.dumps(payload))
            command = [sys.executable, str(Path(accuracy.__file__)), str(source)]
            freeze = subprocess.run(command + [str(frozen), '--mode', 'freeze'], capture_output=True, text=True)
            self.assertEqual(freeze.returncode, 0, freeze.stderr)
            payload['test_predictions'] = self.predictions(rows, 'test')
            source.write_text(json.dumps(payload))
            evaluate = command + [str(result), '--mode', 'evaluate', '--freeze', str(frozen)]
            first = subprocess.run(evaluate, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue(json.loads(result.read_text())['quality_gate'])
            evaluate[3] = str(root / 'second.json')
            second = subprocess.run(evaluate, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertFalse((root / 'second.json').exists())

    def test_training_preflight_has_no_output_side_effect(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps({'samples': []}))
            output = root / 'training'
            result = subprocess.run([sys.executable,
                str(Path(accuracy.__file__).with_name('train_camera_pilot.py')),
                str(root), str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('insufficient-coverage', result.stderr)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
