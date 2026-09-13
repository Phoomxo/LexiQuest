"""Synthetic contract regressions, never camera quality evidence."""
from copy import deepcopy
import unittest
import tempfile
from pathlib import Path
import hashlib
import json
import zipfile
import subprocess
import sys
import camera_development_evaluation as evaluation


class DevelopmentFreezeTests(unittest.TestCase):
    def fixture(self):
        labels = ['book', 'cup']
        rows = [dict(id='a', label='book', split='validation', group='a',
                     sha256='a'*64, sourceUrl='https://example.org/a',
                     license='https://creativecommons.org/licenses/by/2.0/', author='owner-a'),
                dict(id='b', label='cup', split='validation', group='b',
                     sha256='b'*64, sourceUrl='https://example.org/b',
                     license='https://creativecommons.org/licenses/by/2.0/', author='owner-b')]
        config = dict(labels=labels, threshold=.6, candidate_model='c'*64,
                      baseline_model='d'*64, preprocess='annotated-crop-rgb224',
                      scope='web-development', dataset_sha256='e'*64)
        predictions = [dict(id='a', truth='book', prediction='book', probabilities=[.8, .2]),
                       dict(id='b', truth='cup', prediction='book', probabilities=[.55, .45])]
        return rows, config, predictions

    def test_freeze_recomputes_and_has_no_fresh_authority(self):
        rows, config, predictions = self.fixture()
        frozen = evaluation.freeze_development(rows, config, predictions)
        self.assertEqual(frozen['scope'], 'web-development')
        self.assertFalse(frozen['fresh_test_authorized'])
        self.assertEqual(frozen['decision'], 'retain-baseline')
        self.assertEqual(frozen['validation']['top1']['numerator'], 1)
        self.assertEqual(frozen['validation']['sample_ids'], ['a', 'b'])
        self.assertEqual(evaluation.validate_development(rows, config, frozen), frozen)

    def test_prediction_closure_and_scores_fail_closed(self):
        rows, config, predictions = self.fixture()
        bad = [predictions[:1], predictions + [predictions[0]]]
        for scores in ([float('nan'), .2], [True, 0], [.8], [.8, .8], [-.1, 1.1]):
            copy = deepcopy(predictions); copy[0]['probabilities'] = scores; bad.append(copy)
        for key, value in [('truth', 'cup'), ('prediction', 'cup'), ('id', 'other')]:
            copy = deepcopy(predictions); copy[0][key] = value; bad.append(copy)
        for value in bad:
            with self.subTest(value=value), self.assertRaises(ValueError):
                evaluation.freeze_development(rows, config, value)

    def test_freeze_tampering_rejected(self):
        rows, config, predictions = self.fixture()
        frozen = evaluation.freeze_development(rows, config, predictions)
        for key, value in [('decision', 'release'), ('scope', 'fresh-test'),
                           ('fresh_test_authorized', True), ('validation', {}),
                           ('validation_predictions', []), ('config_sha256', 'f'*64)]:
            changed = deepcopy(frozen); changed[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                evaluation.validate_development(rows, config, changed)

    def test_development_split_provenance_and_config(self):
        rows, config, predictions = self.fixture()
        for key, value in [('split', 'test'), ('sourceUrl', ''), ('license', ''),
                           ('sha256', 'bad'), ('label', 'unknown')]:
            changed = deepcopy(rows); changed[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                evaluation.freeze_development(changed, config, predictions)
        for key in ['group', 'sha256', 'author']:
            changed = deepcopy(rows); train = deepcopy(rows[0]); train['id'] = 'train'
            train['split'] = 'train'; train[key] = rows[1][key]; changed.append(train)
            with self.subTest(key=key), self.assertRaises(ValueError):
                evaluation.freeze_development(changed, config, predictions)
        for key, value in [('threshold', True), ('threshold', float('inf')),
                           ('scope', 'fresh-test'), ('labels', ['book', 'book'])]:
            changed = deepcopy(config); changed[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                evaluation.freeze_development(rows, changed, predictions)

    def test_pinned_cli_actual_bytes_contract_and_exclusive_output(self):
        rows, config, predictions = self.fixture()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / 'candidate.tflite'
            with zipfile.ZipFile(model, 'w') as archive:
                archive.writestr('labels.txt', 'book\ncup\n')
            def pin(name, value):
                path = root / name
                path.write_text(json.dumps(value), encoding='utf-8')
                return dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            manifest = pin('manifest.json', dict(schema='lexiquest-web-development-v1',
                                                 labels=config['labels'], samples=rows))
            config['dataset_sha256'] = manifest['sha256']
            config['candidate_model'] = hashlib.sha256(model.read_bytes()).hexdigest()
            export = dict(labels=config['labels'], expectedSha256=config['candidate_model'],
                expectedBytes=model.stat().st_size, trainingManifestSha256=manifest['sha256'],
                releaseEnabled=False, distributionUri=None, rollback=dict(sha256=config['baseline_model']),
                inputShape=[1,224,224,3], inputType='uint8', inputEncoding='rawUint8Rgb',
                outputType='float32', outputShape=[1,2], backgroundClassIndex=None)
            config['artifacts'] = dict(manifest=manifest,
                acceptance=pin('acceptance.json', dict(status='accepted', manifestSha256=manifest['sha256'],
                               retained=2, splitCounts=dict(validation=2))),
                export=pin('export.json', export),
                model=dict(path=str(model), sha256=config['candidate_model']),
                predictions=pin('predictions.json', predictions))
            self.assertEqual(evaluation.load_inputs(config), (rows, predictions))
            source = root / 'config.json'; source.write_text(json.dumps(config))
            output = root / 'freeze.json'
            command = [sys.executable, evaluation.__file__, str(source), str(output)]
            first = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            original = output.read_bytes()
            second = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            for key, value in [('releaseEnabled', True), ('outputShape', [1,3]), ('labels', ['cup','book'])]:
                changed = deepcopy(export); changed[key] = value
                config['artifacts']['export'] = pin('export.json', changed)
                with self.subTest(key=key), self.assertRaises(ValueError):
                    evaluation.load_inputs(config)
            config['artifacts']['export'] = pin('export.json', export)
            model.write_bytes(model.read_bytes() + b'changed')
            with self.assertRaises(ValueError):
                evaluation.load_inputs(config)


if __name__ == '__main__':
    unittest.main()
