"""Versioned internet development data; never opens a fresh camera test set.

Acquire only images with current, photo-specific CC BY evidence. Files and
failed requests are preserved. The Open Images official validation partition
is used entirely as development data, not claimed as a fresh evaluation.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urlparse

import numpy as np
from PIL import Image, ImageOps

SCHEMA = 'lexiquest-web-development-v1'
LICENSE = 'https://creativecommons.org/licenses/by/2.0/'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                   allow_nan=False) + '\n', encoding='utf-8', newline='\n')


def safe_path(root, value):
    if not isinstance(value, str) or ':' in value or Path(value).is_absolute():
        raise ValueError('Dataset path must be relative')
    root = Path(root).resolve()
    target = (root / value).resolve()
    if not target.is_relative_to(root):
        raise ValueError('Dataset path escapes root')
    return target


def owner_object(page, landing):
    """A footer license is insufficient: require this ImageObject's license."""
    expected = urlparse(landing).path.rstrip('/')
    photo_id = expected.split('/')[-1]
    for payload in re.findall(r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', page, re.S):
        try:
            obj = json.loads(payload)
        except json.JSONDecodeError:
            continue
        items = obj if isinstance(obj, list) else obj.get('@graph', [obj]) if isinstance(obj, dict) else []
        for item in items:
            if not isinstance(item, dict) or item.get('@type') != 'ImageObject':
                continue
            if (urlparse(item.get('acquireLicensePage', '')).path.rstrip('/') == expected
                    and re.search(r'/' + re.escape(photo_id) + r'_', item.get('contentUrl', ''))
                    and item.get('license', '').replace('http:', 'https:') == LICENSE):
                return item
    raise ValueError('No matching photo-specific CC BY 2.0 evidence')


def owner_license(page, landing):
    return owner_object(page, landing)['license'].replace('http:', 'https:')


def owner_author(page, landing):
    author = owner_object(page, landing).get('author', {})
    icon = re.search(r'/buddyicons/([0-9]+@N[0-9]+)\.', author.get('image', ''))
    if icon:
        return 'flickr:' + icon.group(1)
    url = urlparse(author.get('url', ''))
    if url.hostname not in ['flickr.com', 'www.flickr.com'] or not url.path.rstrip('/'):
        raise ValueError('Missing photo author identity')
    return 'flickr:' + url.path.rstrip('/').split('/')[-1]


def perceptual_hash(path, box=None):
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert('RGB')
        if box:
            w, h = im.size
            im = im.crop((int(box[0]*w), int(box[1]*h), int(box[2]*w), int(box[3]*h)))
        values = np.asarray(im.convert('L').resize((32, 32), Image.Resampling.LANCZOS), dtype=float)
    basis = np.cos(np.pi / 32 * (np.arange(32) + 0.5)[None, :] * np.arange(8)[:, None])
    low = (basis @ values @ basis.T).flatten()
    bits = low > np.median(low[1:])
    return f'{sum(int(b) << i for i, b in enumerate(bits)):016x}'


def group_split(rows, seed):
    rows = sorted((dict(r) for r in rows), key=lambda r: r['id'])
    parents = list(range(len(rows)))
    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    for i, row in enumerate(rows):
        for j in range(i):
            other = rows[j]
            near = any((int(row[key], 16) ^ int(other[key], 16)).bit_count() <= 8
                       for key in ['phash', 'cropPhash'] if key in row and key in other)
            product = row.get('productGroup') and row.get('productGroup') == other.get('productGroup')
            if row['author'] == other['author'] or row['sha256'] == other['sha256'] or near or product:
                parents[root(i)] = root(j)
    groups = {}
    for i, row in enumerate(rows):
        groups.setdefault(root(i), []).append(row['id'])
    for i, row in enumerate(rows):
        group = min(groups[root(i)])
        row['group'] = group
        value = int(hashlib.sha256(f'split-v1:{seed}:{group}'.encode()).hexdigest()[:8], 16) / 2**32
        row['split'] = 'validation' if value < .25 else 'train'
    return rows


def deduplicate(rows):
    kept, rejected = [], []
    for row in sorted(rows, key=lambda r: r['id']):
        duplicate = next((other for other in kept if row['sha256'] == other['sha256'] or any(
            (int(row[key], 16) ^ int(other[key], 16)).bit_count() <= 8
            for key in ['phash', 'cropPhash'])), None)
        if duplicate:
            rejected.append(dict(id=row['id'], reason='exact-or-perceptual-duplicate', related=duplicate['id']))
        else:
            kept.append(row)
    return kept, rejected


def curate(acquired, output, exclusions):
    """Curate all candidates before splitting; no metrics influence exclusions."""
    root = acquired.parent
    manifest = json.loads(acquired.read_text(encoding='utf-8'))
    decisions = json.loads(exclusions.read_text(encoding='utf-8'))
    excluded_ids = {r['id'] for r in decisions['excluded']}
    known_ids = {r['id'] for r in manifest['samples']}
    if not excluded_ids <= known_ids:
        raise ValueError('Unknown curation image ID')
    if set(decisions['reviewedIds']) != known_ids:
        raise ValueError('Every acquired image must have a visual review disposition')
    rows = []
    product_groups = decisions.get('productGroups', {})
    if not set(product_groups) <= known_ids:
        raise ValueError('Unknown product-group image ID')
    for row in manifest['samples']:
        if row['id'] in product_groups:
            row['productGroup'] = product_groups[row['id']]
        page = (root / row['rightsPath']).read_text(encoding='utf-8')
        row['sourceAuthorProfile'] = row['author']
        row['author'] = owner_author(page, row['landingUrl'])
        row['canonicalAuthorVerified'] = True
        row['cropPhash'] = perceptual_hash(root / row['path'], row['box'])
        rows.append(row)
    # Preserve relationships through excluded/duplicate bridge images too.
    rows = group_split(rows, manifest['seed'])
    rows = [row for row in rows if row['id'] not in excluded_ids]
    rows, duplicates = deduplicate(rows)
    manifest['samples'] = rows
    manifest.update(version='2026-09-14.1', curation=decisions, duplicateExclusions=duplicates,
                    preprocessing='EXIF transpose; annotated object crop; bilinear resize224; RGB',
                    physicalCamera='pending; no fresh test data acquired', unknownEvaluation='pending',
                    pretrainedOverlap='ImageNet overlap not established; web metrics are development only')
    report = validate_manifest(manifest, root)
    if output.exists():
        raise ValueError('Preserve accepted dataset manifest')
    write_json(output, manifest)
    write_json(output.with_suffix('.audit.json'), report)


def validate_manifest(manifest, root, require_coverage=True):
    if manifest.get('schema') != SCHEMA:
        raise ValueError('Only the web-development protocol is accepted')
    labels = manifest['labels']
    if not labels or len(labels) != len(set(labels)):
        raise ValueError('Unique labels required')
    if require_coverage:
        taxonomy = manifest.get('taxonomy', {})
        entries = taxonomy.get('labels', [])
        if (not taxonomy.get('version') or [r['label'] for r in entries] != labels
                or [r['index'] for r in entries] != list(range(len(labels)))):
            raise ValueError('Labels must match versioned taxonomy indices')
    counts = {s: dict.fromkeys(labels, 0) for s in ['train', 'validation']}
    seen, ids, hashes = {}, set(), set()
    for row in manifest['samples']:
        if row['id'] in ids or row['sha256'] in hashes:
            raise ValueError('Duplicate image or ID')
        ids.add(row['id']); hashes.add(row['sha256'])
        if row['split'] not in counts or row['label'] not in labels:
            raise ValueError('Fresh test/camera/unknown data cannot enter development training')
        if row['license'] != LICENSE or not row['sourceUrl'].startswith('https://'):
            raise ValueError('Missing usage provenance')
        if require_coverage:
            metadata = row['originalMetadata']
            expected_url = ('https://open-images-dataset.s3.amazonaws.com/' +
                            metadata['Subset'] + '/' + row['id'] + '.jpg')
            if (metadata['ImageID'] != row['id'] or row['sourceUrl'] != expected_url
                    or metadata['OriginalLandingURL'] != row['landingUrl']):
                raise ValueError('Image provenance identity mismatch')
        datetime.fromisoformat(row['acquiredAt'])
        for key in ['author', 'group']:
            if not row[key] or seen.setdefault((key, row[key]), row['split']) != row['split']:
                raise ValueError('Source or related group crosses split')
        if row.get('productGroup') and seen.setdefault(('product', row['productGroup']), row['split']) != row['split']:
            raise ValueError('Observed product group crosses split')
        for path_key, hash_key in [('path', 'sha256'), ('rightsPath', 'rightsSha256')]:
            if digest(safe_path(root, row[path_key])) != row[hash_key]:
                raise ValueError('Artifact checksum changed')
        owner_license(safe_path(root, row['rightsPath']).read_text(encoding='utf-8'), row['landingUrl'])
        if row.get('canonicalAuthorVerified') is True and owner_author(
                safe_path(root, row['rightsPath']).read_text(encoding='utf-8'), row['landingUrl']) != row['author']:
            raise ValueError('Canonical author changed')
        if require_coverage and row.get('canonicalAuthorVerified') is not True:
            raise ValueError('Canonical author verification required')
        with Image.open(safe_path(root, row['path'])) as image:
            image.verify()
        if perceptual_hash(safe_path(root, row['path'])) != row['phash']:
            raise ValueError('Perceptual fingerprint changed')
        box = row['box']
        if len(box) != 4 or not 0 <= box[0] < box[2] <= 1 or not 0 <= box[1] < box[3] <= 1:
            raise ValueError('Invalid object box')
        if 'cropPhash' in row and perceptual_hash(safe_path(root, row['path']), box) != row['cropPhash']:
            raise ValueError('Crop fingerprint changed')
        counts[row['split']][row['label']] += 1
    rows = manifest['samples']
    for i, row in enumerate(rows):
        for other in rows[:i]:
            if any((int(row[key], 16) ^ int(other[key], 16)).bit_count() <= 8
                   for key in ['phash', 'cropPhash'] if key in row and key in other):
                raise ValueError('Near duplicate must be curated out')
    if require_coverage and any(n < (8 if s == 'train' else 3)
                               for s in counts for n in counts[s].values()):
        raise ValueError('Insufficient development coverage: ' + json.dumps(counts))
    return dict(status='passed', counts=counts, images=len(rows),
                scope='internet development only; camera and unknown evaluation pending')


def fetch(url, maximum):
    with urllib.request.urlopen(urllib.request.Request(url, headers={
            'User-Agent': 'LexiQuest licensed dataset development'}), timeout=20) as response:
        data = response.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError('Resource size bound exceeded')
    return data


def acquire(metadata, taxonomy, output, limit, seed, partition='validation'):
    output.mkdir(parents=True, exist_ok=True)
    (output / 'images').mkdir(exist_ok=True)
    (output / 'rights').mkdir(exist_ok=True)
    if (output / 'acquired.json').exists():
        raise ValueError('Preserve completed acquisition')
    names = dict(csv.reader((metadata / 'classes.csv').open(encoding='utf-8')))
    info = {r['ImageID']: r for r in csv.DictReader((metadata / 'images.csv').open(encoding='utf-8'))}
    mapping = {s: t['label'] for t in taxonomy['labels'] for s in t['sourceClasses']}
    candidates = {}
    for r in csv.DictReader((metadata / 'boxes.csv').open(encoding='utf-8')):
        label = mapping.get(names[r['LabelName']])
        if not label or any(r[k] != '0' for k in ['IsDepiction', 'IsGroupOf', 'IsInside']):
            continue
        box = [float(r[k]) for k in ['XMin', 'YMin', 'XMax', 'YMax']]
        area = (box[2]-box[0]) * (box[3]-box[1])
        if area < .015:
            continue
        key = r['ImageID']
        # One image contributes one category, selected by largest target box.
        if key not in candidates or area > candidates[key]['area']:
            candidates[key] = dict(id=key, label=label, box=box, area=area, sourceClass=names[r['LabelName']])
    log_path = output / 'requests.jsonl'
    completed = [json.loads(line) for line in log_path.read_text(encoding='utf-8').splitlines()] if log_path.exists() else []
    rows = [r['sample'] for r in completed if r['status'] == 'acquired']
    tried = {r['id'] for r in completed if r.get('reason') != 'No matching photo-specific CC BY 2.0 evidence'}
    counts = {t['label']: sum(r['label'] == t['label'] for r in rows) for t in taxonomy['labels']}
    ordered = sorted(candidates.values(), key=lambda r: hashlib.sha256(f'{seed}:{r["id"]}'.encode()).hexdigest())
    for candidate in ordered:
        image_id, label = candidate['id'], candidate['label']
        if image_id in tried or counts[label] >= limit:
            continue
        record = dict(id=image_id, label=label, at=datetime.now(timezone.utc).isoformat())
        try:
            source = info[image_id]
            if source['License'].replace('http:', 'https:') != LICENSE:
                raise ValueError('Metadata license not approved')
            landing = source['OriginalLandingURL']
            if urlparse(landing).hostname not in ['www.flickr.com', 'flickr.com']:
                raise ValueError('Unsupported owner evidence host')
            rights_path = f'rights/{image_id}.html'
            page = ((output / rights_path).read_bytes() if (output / rights_path).exists()
                    else fetch(landing, 2_000_000))
            if not (output / rights_path).exists():
                (output / rights_path).write_bytes(page)
            license_url = owner_license(page.decode('utf-8'), landing)
            url = f'https://open-images-dataset.s3.amazonaws.com/{partition}/{image_id}.jpg'
            image_path = f'images/{image_id}.jpg'
            raw = fetch(url, 8_000_000)
            (output / image_path).write_bytes(raw)
            with Image.open(output / image_path) as im:
                im.verify()
            row = dict(candidate, path=image_path, sourceUrl=url, originalUrl=source['OriginalURL'],
                       landingUrl=landing, author=source['AuthorProfileURL'], authorName=source['Author'],
                       title=source['Title'], license=license_url, acquiredAt=record['at'],
                       rightsPath=rights_path, rightsSha256=digest(output / rights_path),
                       sha256=digest(output / image_path), phash=perceptual_hash(output / image_path),
                       originalMetadata=source, source=f'Open Images V7 / Flickr; official {partition} used as development')
            rows.append(row); counts[label] += 1
            record.update(status='acquired', sample=row)
        except Exception as exc:
            record.update(status='excluded', reason=str(exc))
        with log_path.open('a', encoding='utf-8', newline='\n') as log:
            log.write(json.dumps(record, ensure_ascii=False) + '\n')
        print(json.dumps(dict(id=image_id, label=label, status=record['status'], counts=counts)), flush=True)
    write_json(output / 'acquired.json', dict(schema=SCHEMA, seed=seed, samples=rows,
               labels=[t['label'] for t in taxonomy['labels']], taxonomy=taxonomy))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    a = sub.add_parser('acquire')
    a.add_argument('--metadata', type=Path, required=True)
    a.add_argument('--taxonomy', type=Path, required=True)
    a.add_argument('--output', type=Path, required=True)
    a.add_argument('--limit', type=int, default=40)
    a.add_argument('--seed', type=int, default=20260914)
    a.add_argument('--partition', choices=['train', 'validation', 'test'], default='validation',
                   help='Upstream partition; every selected image becomes development data before training')
    v = sub.add_parser('validate')
    v.add_argument('manifest', type=Path)
    c = sub.add_parser('curate')
    c.add_argument('acquired', type=Path)
    c.add_argument('output', type=Path)
    c.add_argument('exclusions', type=Path)
    args = parser.parse_args()
    if args.command == 'acquire':
        acquire(args.metadata, json.loads(args.taxonomy.read_text(encoding='utf-8')), args.output, args.limit, args.seed, args.partition)
    elif args.command == 'curate':
        curate(args.acquired, args.output, args.exclusions)
    else:
        print(json.dumps(validate_manifest(json.loads(args.manifest.read_text(encoding='utf-8')), args.manifest.parent)))


if __name__ == '__main__':
    main()
