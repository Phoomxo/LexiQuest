import importlib
import json
from pathlib import Path
import tempfile
import unittest


class CameraWebTrainingTests(unittest.TestCase):
    def api(self):
        self.assertIsNotNone(importlib.util.find_spec('train_camera_web'), 'web training adapter required')
        return importlib.import_module('train_camera_web')

    def test_refuses_fresh_test_and_empty_partitions(self):
        api = self.api()
        for data in [dict(schema='r15-camera-freeze-v2'),
                     dict(schema='lexiquest-web-development-v1', labels=['book'], samples=[]),
                     dict(schema='lexiquest-web-development-v1', labels=['book'],
                          samples=[dict(split='test', label='book')])]:
            with self.assertRaises(ValueError):
                api.training_rows(data)

    def test_run_directory_never_overwrites_checkpoint(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'run'
            api.create_run(target)
            checkpoint = target / 'candidate.keras'
            checkpoint.write_bytes(b'previous evidence')
            with self.assertRaises(FileExistsError):
                api.create_run(target)
            self.assertEqual(checkpoint.read_bytes(), b'previous evidence')

    def test_dataset_pin_checked_before_use(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'manifest.json'
            path.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'checksum'):
                api.read_pinned(path, '0' * 64)


if __name__ == '__main__':
    unittest.main()
