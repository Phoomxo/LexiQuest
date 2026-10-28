"""Compare paired top-1 labels on a held-out manifest; never trains or uploads.

Input JSON: baseline_model, candidate_model (immutable artifact IDs), samples.
Each sample has id, group (capture scene/object group), split, truth; test rows
also require baseline and candidate labels. Include train/validation metadata
to detect group leakage. Reported accuracy is descriptive, not certification.
"""
import argparse
import hashlib
import json
from pathlib import Path


def compare(rows):
    if not isinstance(rows, list) or not rows:
        raise ValueError('A nonempty sample manifest is required')
    ids, groups, held_out = set(), {}, []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('Each sample must be an object')
        for key in ('id', 'group', 'split', 'truth'):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError('Missing sample field: ' + key)
        if row['id'] in ids:
            raise ValueError('Duplicate sample ID')
        ids.add(row['id'])
        split = row['split']
        if split not in ('train', 'validation', 'test'):
            raise ValueError('Unknown dataset split')
        previous = groups.setdefault(row['group'], split)
        if previous != split:
            raise ValueError('Capture group crosses dataset splits')
        if split == 'test':
            for key in ('baseline', 'candidate'):
                if not isinstance(row.get(key), str) or not row[key].strip():
                    raise ValueError('Missing held-out prediction: ' + key)
            held_out.append(row)
    if not held_out:
        raise ValueError('No held-out samples')
    classes = sorted({row['truth'] for row in held_out})
    result = {'samples': len(held_out), 'classes': classes,
              'scope': 'paired top-1 held-out comparison; no statistical significance claim',
              'split_metadata': {split: sum(row['split'] == split for row in rows)
                                 for split in ('train', 'validation', 'test')}}
    for model in ('baseline', 'candidate'):
        recalls = {}
        confusion = {}
        for label in classes:
            selected = [row for row in held_out if row['truth'] == label]
            recalls[label] = sum(row[model] == label for row in selected) / len(selected)
            confusion[label] = {}
            for row in selected:
                predicted = row[model]
                confusion[label][predicted] = confusion[label].get(predicted, 0) + 1
        result[model] = {
            'accuracy': sum(row[model] == row['truth'] for row in held_out) / len(held_out),
            'balanced_accuracy': sum(recalls.values()) / len(recalls),
            'recall_by_class': recalls, 'confusion': confusion,
        }
    result['fixed'] = sum(row['baseline'] != row['truth'] and row['candidate'] == row['truth'] for row in held_out)
    result['regressed'] = sum(row['baseline'] == row['truth'] and row['candidate'] != row['truth'] for row in held_out)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    raw = args.manifest.read_bytes()
    manifest = json.loads(raw)
    for key in ('baseline_model', 'candidate_model'):
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            raise ValueError('Model artifact identity required: ' + key)
    report = compare(manifest['samples'])
    report.update({key: manifest[key] for key in ('baseline_model', 'candidate_model')})
    report['input_sha256'] = hashlib.sha256(raw).hexdigest()
    # Exclusive creation preserves earlier comparison evidence.
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write('\n')


if __name__ == '__main__':
    main()
