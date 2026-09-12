"""Audit R15 camera data and evaluate a validation-frozen four-class candidate.

CLI defaults to metadata audit. --mode freeze takes samples/config and
validation_predictions; --mode evaluate takes samples/config/test_predictions
and --freeze FILE. All outputs are exclusive; a freeze can open test only once.
Model predictions and curator declarations are supplied evidence, not verified
inference. Legacy compare() remains descriptive only. Never trains or uploads.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

KNOWN = ('book', 'bottle', 'chair', 'cup')
LABELS = (*KNOWN, 'unknown')


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True,
        separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def audit_dataset(rows):
    """Metadata-only preflight; never claims image bytes or licenses were verified.

    Freshness/natural-frame attestations must come from the dataset curator.
    A group/content can contribute only one independent observation per split.
    Legacy rows with no freshness declaration cannot satisfy fresh coverage.
    """
    if not isinstance(rows, list):
        raise ValueError('samples must be a list')
    ids, groups, hashes, counted = set(), {}, {}, set()
    counts = {s: dict.fromkeys(LABELS, 0) for s in ('validation', 'test')}
    inventory = dict.fromkeys(('train', 'validation', 'test', 'regression'), 0)
    for row in rows:
        for key in ('id', 'group', 'split', 'truth', 'sha256', 'source_url'):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError('Missing sample field: ' + key)
        if not re.fullmatch(r'[0-9a-f]{64}', row['sha256']):
            raise ValueError('Invalid content SHA256')
        attribution = row.get('attribution')
        license_url = attribution.get('License') if isinstance(attribution, dict) else None
        if not isinstance(license_url, str) or not license_url.startswith(('https://', 'http://')):
            raise ValueError('Per-image license provenance required')
        if not row['source_url'].startswith(('https://', 'http://')):
            raise ValueError('Source URL required')
        split = row['split']
        if split not in inventory or row['truth'] not in LABELS:
            raise ValueError('Unsupported split or label')
        if row['id'] in ids:
            raise ValueError('Duplicate sample ID')
        ids.add(row['id'])
        for field, seen in (('group', groups), ('sha256', hashes)):
            if seen.setdefault(row[field], split) != split:
                raise ValueError(field + ' crosses dataset splits')
        inventory[split] += 1
        keys = {(split, 'group', row['group']), (split, 'hash', row['sha256'])}
        if (split in counts and row.get('fresh') is True and
                row.get('natural') is True and row.get('view') == 'full-frame' and
                not keys.intersection(counted)):
            counts[split][row['truth']] += 1
            counted.update(keys)
    gaps = [f'{s}/{label}: {counts[s][label]}/{200 if label == "unknown" else 30}'
            for s in counts for label in LABELS
            if counts[s][label] < (200 if label == 'unknown' else 30)]
    return dict(status='insufficient-coverage' if gaps else 'coverage-ready',
        counts=counts, inventory=inventory, gaps=gaps, dataset_sha256=fingerprint(rows),
        decision='retain-baseline', scope='metadata audit; no physical or accuracy acceptance')


def _validate_config(config):
    for key in ('baseline_model', 'candidate_model'):
        if not re.fullmatch(r'[0-9a-f]{64}', str(config.get(key, ''))):
            raise ValueError('Immutable model SHA256 required: ' + key)
    for key in ('preprocess', 'environment'):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError('Missing configuration pin: ' + key)
    threshold = config.get('threshold')
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not math.isfinite(threshold) or not 0 <= threshold <= 1:
        raise ValueError('Invalid threshold')
    if config.get('score_type') != 'softmax' or config.get('output_classes') != 4:
        raise ValueError('This protocol is limited to the four-class softmax pilot')


def _metrics(rows, config, predictions, split):
    expected = {r['id']: r for r in rows if r['split'] == split and
                r.get('fresh') is True and r.get('natural') is True and
                r.get('view') == 'full-frame'}
    selected = list(expected.values())
    if (len({r['group'] for r in selected}) != len(selected) or
            len({r['sha256'] for r in selected}) != len(selected)):
        raise ValueError('Metrics require independent full-frame observations')
    if len({p['id'] for p in predictions}) != len(predictions) or set(expected) != {p['id'] for p in predictions}:
        raise ValueError('Paired image IDs must exactly match the fresh split')
    observations = []
    for prediction in predictions:
        confidence = prediction.get('confidence')
        if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not math.isfinite(confidence) or not 0.25 <= confidence <= 1:
            raise ValueError('Invalid four-class maximum softmax confidence')
        if prediction.get('preprocess') != config['preprocess']:
            raise ValueError('Paired preprocessing mismatch')
        if prediction.get('candidate') not in KNOWN or not isinstance(prediction.get('baseline'), str) or not prediction['baseline']:
            raise ValueError('Missing paired labels')
        accepted = prediction['candidate'] in KNOWN and confidence >= config['threshold']
        observations.append((expected[prediction['id']]['truth'], prediction, accepted))

    def rate(selected, predicate):
        n = len(selected)
        k = sum(predicate(item) for item in selected)
        if not n:
            return dict(numerator=0, denominator=0, rate=None, wilson95=None)
        p, z = k / n, 1.959963984540054
        denominator = 1 + z * z / n
        center = (p + z * z / (2 * n)) / denominator
        margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
        return dict(numerator=k, denominator=n, rate=p,
                    wilson95=[max(0, center - margin), min(1, center + margin)])

    known = [o for o in observations if o[0] in KNOWN]
    unknown = [o for o in observations if o[0] == 'unknown']
    correct = lambda o: o[2] and o[1]['candidate'] == o[0]
    return dict(candidate=dict(
        known_correct_accepted=rate(known, correct),
        known_rejected=rate(known, lambda o: not o[2]),
        unknown_false_accept=rate(unknown, lambda o: o[2]),
        per_class={label: rate([o for o in known if o[0] == label], correct) for label in KNOWN}),
        baseline=dict(known_correct_accepted=rate(known, lambda o: o[1]['baseline'] == o[0]),
            unknown_false_accept=rate(unknown, lambda o: o[1]['baseline'] in KNOWN),
            per_class={label: rate([o for o in known if o[0] == label],
                lambda o: o[1]['baseline'] == o[0]) for label in KNOWN}),
        paired_image_ids=sorted(expected))


def freeze_validation(rows, config, predictions):
    audit = audit_dataset(rows)
    _validate_config(config)
    if audit['status'] != 'coverage-ready':
        return audit
    if config['threshold'] <= 1 / config['output_classes']:
        return dict(status='invalid-unknown-gate', decision='retain-baseline',
                    reason='max softmax >= 0.25; this threshold cannot reject unknowns')
    metrics = _metrics(rows, config, predictions, 'validation')
    return dict(status='validation-frozen', config_sha256=fingerprint(config),
        dataset_sha256=audit['dataset_sha256'], validation_sha256=fingerprint(predictions),
        validation=metrics, decision='retain-baseline')


def evaluate_frozen(rows, config, frozen, predictions):
    audit = audit_dataset(rows)
    _validate_config(config)
    if (frozen.get('status') != 'validation-frozen' or
            frozen.get('config_sha256') != fingerprint(config) or
            frozen.get('dataset_sha256') != audit['dataset_sha256']):
        raise ValueError('Dataset/config/model changed after validation freeze')
    metrics = _metrics(rows, config, predictions, 'test')
    candidate = metrics['candidate']
    quality = (candidate['unknown_false_accept']['rate'] <= 0.05 and
        candidate['known_correct_accepted']['rate'] >= 0.85 and
        all(value['rate'] >= 0.75 for value in candidate['per_class'].values()))
    return dict(status='evaluated', **metrics, quality_gate=quality,
        dataset_sha256=audit['dataset_sha256'], config_sha256=fingerprint(config),
        freeze_sha256=fingerprint(frozen), test_predictions_sha256=fingerprint(predictions),
        decision='retain-baseline', reasons=['physical/resource evidence unavailable',
            'four-class candidate cannot replace broad baseline vocabulary'],
        scope='descriptive fresh test; no rollout authorization')


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
    parser.add_argument('--mode', choices=('audit', 'freeze', 'evaluate'), default='audit')
    parser.add_argument('--freeze', type=Path, help='Previously written validation freeze')
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Preserve existing report')
    frozen = None
    if args.mode == 'evaluate':
        if args.freeze is None:
            raise ValueError('Validation freeze file required')
        frozen = json.loads(args.freeze.read_text(encoding='utf-8'))
        # A test-opening receipt is deliberately never removed on failure.
        # Re-evaluation must be labeled development evidence, not a fresh test.
        with args.freeze.with_suffix(args.freeze.suffix + '.test-opened').open('x') as receipt:
            receipt.write(fingerprint(frozen) + '\n')
    raw = args.manifest.read_bytes()
    manifest = json.loads(raw)
    if args.mode == 'audit':
        report = audit_dataset(manifest['samples'])
    elif args.mode == 'freeze':
        if 'test_predictions' in manifest:
            raise ValueError('Test predictions cannot be opened during validation selection')
        report = freeze_validation(manifest['samples'], manifest['config'],
                                   manifest['validation_predictions'])
    else:
        report = evaluate_frozen(manifest['samples'], manifest['config'], frozen,
                                 manifest['test_predictions'])
    report['input_sha256'] = hashlib.sha256(raw).hexdigest()
    # Exclusive creation preserves earlier comparison evidence.
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write('\n')


if __name__ == '__main__':
    main()
