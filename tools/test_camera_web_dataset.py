"""Behavior checks for the separate web-development protocol."""
import importlib
import hashlib
import json
from pathlib import Path
import tempfile
import unittest


class WebDatasetTests(unittest.TestCase):
    def api(self):
        spec = importlib.util.find_spec('camera_web_dataset')
        self.assertIsNotNone(spec, 'versioned web dataset adapter required')
        return importlib.import_module('camera_web_dataset')

    def test_license_must_belong_to_requested_photo(self):
        api = self.api()
        url = 'https://www.flickr.com/photos/owner/12345'
        obj = {'@type': 'ImageObject', 'license': 'https://creativecommons.org/licenses/by/2.0/',
               'acquireLicensePage': url, 'contentUrl': 'https://live.staticflickr.com/1/12345_hash.jpg'}
        page = '<script type="application/ld+json">' + json.dumps(obj) + '</script>'
        self.assertEqual(api.owner_license(page, url), obj['license'])
        graph = '<script type="application/ld+json">' + json.dumps({'@graph': [obj]}) + '</script>'
        self.assertEqual(api.owner_license(graph, url), obj['license'])
        for bad in [page.replace('12345', '99999'), page.replace('/by/2.0/', '/by-nc/2.0/'),
                    '<a href="https://creativecommons.org/licenses/by/2.0/">footer</a>']:
            with self.assertRaises(ValueError):
                api.owner_license(bad, url)

    def test_related_sources_and_near_images_share_split(self):
        api = self.api()
        rows = [dict(id='a', author='owner1', sha256='a', phash='0000000000000000'),
                dict(id='b', author='owner1', sha256='b', phash='ffffffffffffffff'),
                dict(id='c', author='owner2', sha256='c', phash='fffffffffffffffe'),
                dict(id='d', author='owner3', sha256='d', phash='aaaaaaaaaaaaaaaa')]
        result = api.group_split(rows, 20260914)
        by_id = {r['id']: r for r in result}
        self.assertEqual(by_id['a']['group'], by_id['c']['group'])
        self.assertEqual(by_id['a']['split'], by_id['c']['split'])
        self.assertEqual(result, api.group_split(list(reversed(rows)), 20260914))

    def test_split_hash_is_independent_from_acquisition_order(self):
        api = self.api()
        ids = sorted((str(i) for i in range(1000)),
                     key=lambda x: hashlib.sha256(f'20260914:{x}'.encode()).hexdigest())[:50]
        rows = [dict(id=x, author=x, sha256=x,
                     phash=hashlib.sha256(x.encode()).hexdigest()[:16]) for x in ids]
        result = api.group_split(rows, 20260914)
        self.assertEqual({r['split'] for r in result}, {'train', 'validation'})

    def test_author_aliases_use_stable_flickr_identity(self):
        api = self.api()
        url = 'https://www.flickr.com/photos/old-alias/12345'
        obj = {'@type': 'ImageObject', 'license': api.LICENSE, 'acquireLicensePage': url,
               'contentUrl': 'https://live.staticflickr.com/1/12345_hash.jpg',
               'author': {'url': 'https://www.flickr.com/photos/new-alias',
                          'image': 'https://live.staticflickr.com/1/buddyicons/123@N04.jpg'}}
        page = '<script type="application/ld+json">' + json.dumps(obj) + '</script>'
        self.assertEqual(api.owner_author(page, url), 'flickr:123@N04')

    def test_known_product_views_stay_together(self):
        api = self.api()
        rows = [dict(id='a', author='one', sha256='a', phash='0000000000000000', productGroup='observed-design-1'),
                dict(id='b', author='two', sha256='b', phash='ffffffffffffffff', productGroup='observed-design-1')]
        result = api.group_split(rows, 20260914)
        self.assertEqual(result[0]['group'], result[1]['group'])

    def test_file_paths_cannot_escape_dataset(self):
        api = self.api()
        with tempfile.TemporaryDirectory() as tmp:
            for value in ['../secret', '/outside', 'C:/outside']:
                with self.assertRaises(ValueError):
                    api.safe_path(Path(tmp), value)

    def test_validation_rejects_tampering_and_unrelated_rights(self):
        api = self.api()
        from PIL import Image
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            Image.new('RGB', (64, 64), (23, 56, 89)).save(root / 'a.png')
            row = dict(id='a', path='a.png', sha256=api.digest(root / 'a.png'), label='book',
                       sourceUrl='https://example.org/a', author='owner', acquiredAt='2026-09-14T00:00:00+00:00',
                       license='https://creativecommons.org/licenses/by/2.0/',
                       rightsPath='rights.html', rightsSha256='', split='train', group='a',
                       box=[0, 0, 1, 1], phash=api.perceptual_hash(root / 'a.png'))
            row['landingUrl'] = 'https://www.flickr.com/photos/owner/12345'
            obj = {'@type': 'ImageObject', 'license': row['license'],
                   'acquireLicensePage': row['landingUrl'],
                   'contentUrl': 'https://live.staticflickr.com/1/12345_hash.jpg'}
            (root / 'rights.html').write_text('<script type="application/ld+json">' +
                                             json.dumps(obj) + '</script>', encoding='utf-8')
            row['rightsSha256'] = api.digest(root / 'rights.html')
            valid_rights = (root / 'rights.html').read_bytes()
            manifest = dict(schema='lexiquest-web-development-v1', labels=['book'], samples=[row],
                            seed=20260914, minimumTrain=0, minimumValidation=0)
            api.validate_manifest(manifest, root, require_coverage=False)
            (root / 'rights.html').write_text('unrelated license footer', encoding='utf-8')
            row['rightsSha256'] = api.digest(root / 'rights.html')
            with self.assertRaises(ValueError):
                api.validate_manifest(manifest, root, require_coverage=False)
            (root / 'rights.html').write_bytes(valid_rights)
            row['rightsSha256'] = api.digest(root / 'rights.html')
            (root / 'a.png').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                api.validate_manifest(manifest, root, require_coverage=False)

    def test_cross_split_owner_is_rejected_even_with_different_groups(self):
        api = self.api()
        from PIL import Image
        import numpy as np
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rows = []
            for i, split in enumerate(['train', 'validation']):
                path = f'{i}.png'
                Image.fromarray(np.random.default_rng(i).integers(0, 256, (64, 64, 3), dtype=np.uint8)).save(root / path)
                landing = f'https://www.flickr.com/photos/owner/{12345+i}'
                obj = {'@type': 'ImageObject', 'license': api.LICENSE, 'acquireLicensePage': landing,
                       'contentUrl': f'https://live.staticflickr.com/1/{12345+i}_hash.jpg'}
                rights = f'{i}.html'
                (root / rights).write_text('<script type="application/ld+json">' + json.dumps(obj) + '</script>')
                rows.append(dict(id=str(i), path=path, rightsPath=rights, rightsSha256=api.digest(root/rights),
                                 sha256=api.digest(root/path), phash=api.perceptual_hash(root/path), label='book',
                                 author='same-owner', group=f'different-{i}', split=split, license=api.LICENSE,
                                 sourceUrl='https://example.org/image', landingUrl=landing,
                                 acquiredAt='2026-09-14T00:00:00+00:00', box=[0, 0, 1, 1]))
            manifest = dict(schema=api.SCHEMA, labels=['book'], samples=rows)
            with self.assertRaisesRegex(ValueError, 'crosses split'):
                api.validate_manifest(manifest, root, require_coverage=False)

    def test_fresh_test_is_never_training_input(self):
        api = self.api()
        with self.assertRaises(ValueError):
            api.validate_manifest(dict(schema='r15-camera-freeze-v2'), Path('.'))

    def test_training_labels_must_match_versioned_taxonomy(self):
        api = self.api()
        manifest = dict(schema=api.SCHEMA, labels=['book'], samples=[],
                        taxonomy=dict(version='1', labels=[dict(index=0, label='bottle')]))
        with self.assertRaisesRegex(ValueError, 'taxonomy'):
            api.validate_manifest(manifest, Path('.'))

    def test_curation_rejects_exact_and_crop_near_duplicates(self):
        api = self.api()
        rows = [dict(id='a', sha256='one', phash='0000000000000000', cropPhash='ffffffffffffffff'),
                dict(id='b', sha256='one', phash='0000000000000000', cropPhash='ffffffffffffffff'),
                dict(id='c', sha256='two', phash='aaaaaaaaaaaaaaaa', cropPhash='fffffffffffffffe'),
                dict(id='d', sha256='three', phash='5555555555555555', cropPhash='aaaaaaaaaaaaaaaa')]
        kept, excluded = api.deduplicate(rows)
        self.assertEqual([r['id'] for r in kept], ['a', 'd'])
        self.assertEqual({r['id'] for r in excluded}, {'b', 'c'})


if __name__ == '__main__':
    unittest.main()
