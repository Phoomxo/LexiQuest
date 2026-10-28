"""Fetch a bounded four-class Open Images pilot with per-image attribution.

No production assets are changed. Official validation images are used for the
pilot train/validation split; official test images remain held out. One object
per source image prevents crop siblings crossing splits. This is a small pilot,
not a substitute for independently collected vivo acceptance images.
"""
import csv
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

BASE = 'https://storage.googleapis.com/openimages/'
CLASSES = {'Book': 'book', 'Coffee cup': 'cup', 'Bottle': 'bottle', 'Chair': 'chair'}


def fetch(url, path, cap=80_000_000):
    if path.exists():
        return path
    with urllib.request.urlopen(url, timeout=45) as response:
        raw = response.read(cap + 1)
    if len(raw) > cap:
        raise ValueError('Download exceeded bounded size')
    with path.open('xb') as output:
        output.write(raw)
    print('downloaded', path.name, len(raw), flush=True)
    return path


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    if (root / 'manifest.json').exists():
        raise ValueError('Existing manifest: preserve prior data selection')
    classes_path = fetch(BASE + 'v7/oidv7-class-descriptions-boxable.csv', root / 'classes.csv')
    with classes_path.open(encoding='utf-8') as source:
        mapping = {mid: CLASSES[name] for mid, name in csv.reader(source) if name in CLASSES}
    if set(mapping.values()) != set(CLASSES.values()):
        raise ValueError('Requested class names not found')
    samples, used = [], set()
    for official_split, count in [('validation', 40), ('test', 10)]:
        limits = {label: (15 if label == 'book' and official_split == 'validation' else count)
                  for label in mapping.values()}
        metadata_path = fetch(BASE + f'2018_04/{official_split}/{official_split}-images-with-rotation.csv', root / f'{official_split}-metadata.csv')
        boxes_path = fetch(BASE + f'v5/{official_split}-annotations-bbox.csv', root / f'{official_split}-boxes.csv')
        with metadata_path.open(encoding='utf-8') as source:
            metadata = {row['ImageID']: row for row in csv.DictReader(source)}
        counts = {label: 0 for label in mapping.values()}
        with boxes_path.open(encoding='utf-8') as source:
            for box in csv.DictReader(source):
                label = mapping.get(box['LabelName'])
                identity = box['ImageID']
                if label is None or counts[label] >= limits[label] or identity in used:
                    continue
                if any(box.get(key) != '0' for key in ('IsOccluded', 'IsTruncated', 'IsGroupOf', 'IsDepiction')):
                    continue
                coords = [float(box[key]) for key in ('XMin', 'YMin', 'XMax', 'YMax')]
                if (coords[2] - coords[0]) * (coords[3] - coords[1]) < 0.10:
                    continue
                meta = metadata.get(identity, {})
                if meta.get('License', '').rstrip('/') not in (
                    'https://creativecommons.org/licenses/by/2.0',
                    'http://creativecommons.org/licenses/by/2.0'):
                    continue
                train_count = 10 if label == 'book' else 30
                split = 'test' if official_split == 'test' else ('train' if counts[label] < train_count else 'validation')
                path = root / f'{identity}.jpg'
                image_url = f'https://open-images-dataset.s3.amazonaws.com/{official_split}/{identity}.jpg'
                fetch(image_url, path, cap=12_000_000)
                samples.append(dict(id=identity, group=identity, split=split, truth=label,
                    official_split=official_split, path=path.name, box=coords,
                    sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    source_url=image_url, attribution={key: meta.get(key) for key in
                    ('OriginalURL', 'OriginalLandingURL', 'Author', 'Title', 'License')}))
                counts[label] += 1
                used.add(identity)
                if all(counts[label] == limits[label] for label in counts):
                    break
        print(official_split, counts, flush=True)
        if any(counts[label] != limits[label] for label in counts):
            raise ValueError('Insufficient eligible samples; do not weaken selection silently')
    result = dict(source='https://storage.googleapis.com/openimages/web/download_v7.html',
        annotation_license='CC BY 4.0', image_license='CC BY 2.0 per metadata',
        purpose='four-class local pilot; not device acceptance', samples=samples)
    with (root / 'manifest.json').open('x', encoding='utf-8') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
    print('complete', len(samples), flush=True)


if __name__ == '__main__':
    main()
