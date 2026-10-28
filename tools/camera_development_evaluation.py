"""Versioned web-development evidence; never authorizes fresh test or rollout.

The original camera_accuracy F3/F4 protocol remains the fresh four-class gate.
This companion checks actual exported candidate inputs and freezes descriptive
development evidence, including incomplete coverage. It never trains or tunes.
"""
import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

from camera_accuracy import fingerprint

SCHEMA = 'lexiquest-camera-development-freeze-v1'


def _sha(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value):
        raise ValueError('Immutable SHA256 required')
    return value


def _number(value, lower=0, upper=1):
    if (type(value) not in (int, float) or not math.isfinite(value)
            or not lower <= value <= upper):
        raise ValueError('Finite numeric value in range required')
    return value


def _inputs(rows, config, predictions):
    if not isinstance(config, dict) or config.get('scope') != 'web-development':
        raise ValueError('Development-only configuration required')
    labels = config.get('labels')
    if (not isinstance(labels, list) or len(labels) < 2
            or any(not isinstance(s, str) or not s.strip() or s != s.strip()
                   or s == 'unknown' for s in labels) or len(set(labels)) != len(labels)):
        raise ValueError('Unique ordered candidate labels required')
    for key in ('candidate_model', 'baseline_model', 'dataset_sha256'):
        _sha(config.get(key))
    _number(config.get('threshold'))
    if not isinstance(config.get('preprocess'), str) or not config['preprocess'].strip():
        raise ValueError('Preprocessing pin required')
    if not isinstance(rows, list) or not rows:
        raise ValueError('Nonempty development samples required')
    seen, groups = set(), {k: {} for k in ('group', 'sha256', 'author')}
    expected = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('Sample object required')
        for key in ('id', 'group', 'author', 'sourceUrl', 'license'):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError('Missing provenance: ' + key)
        if any(not row[k].startswith(('http://', 'https://')) for k in ('sourceUrl', 'license')):
            raise ValueError('Source/license URL required')
        _sha(row.get('sha256'))
        if row.get('split') not in ('train', 'validation') or row.get('label') not in labels:
            raise ValueError('Only known web development partitions allowed')
        if row['id'] in seen:
            raise ValueError('Duplicate sample ID')
        seen.add(row['id'])
        for key, values in groups.items():
            if values.setdefault(row[key], row['split']) != row['split']:
                raise ValueError('Provenance crosses development splits: ' + key)
        if row['split'] == 'validation':
            expected[row['id']] = row
    if not expected:
        raise ValueError('Validation data required')
    if (not isinstance(predictions, list)
            or any(not isinstance(p, dict) or not isinstance(p.get('id'), str) for p in predictions)
            or len({p['id'] for p in predictions}) != len(predictions)
            or {p['id'] for p in predictions} != set(expected)):
        raise ValueError('Prediction IDs must exactly match validation')
    for p in predictions:
        scores = p.get('probabilities')
        if not isinstance(scores, list) or len(scores) != len(labels):
            raise ValueError('Complete output score vector required')
        for score in scores:
            _number(score)
        if not math.isclose(sum(scores), 1, abs_tol=1e-5):
            raise ValueError('Normalized softmax vector required')
        if (p.get('truth') != expected[p['id']]['label']
                or p.get('prediction') != labels[max(range(len(labels)), key=scores.__getitem__)]):
            raise ValueError('Truth/argmax differs from manifest or scores')
    return expected


def freeze_development(rows, config, predictions):
    expected = _inputs(rows, config, predictions)
    labels = config['labels']
    counts = {label: sum(r['label'] == label for r in expected.values()) for label in labels}
    correct = sum(p['prediction'] == p['truth'] for p in predictions)
    return dict(schema=SCHEMA, scope='web-development', fresh_test_authorized=False,
        decision='retain-baseline', config_sha256=fingerprint(config),
        samples_sha256=fingerprint(rows), validation_sha256=fingerprint(predictions),
        validation_predictions=deepcopy(predictions),
        validation=dict(sample_ids=sorted(expected), counts=counts,
                        top1=dict(numerator=correct, denominator=len(expected), rate=correct/len(expected))),
        coverage=dict(fresh_camera_known={label: 0 for label in labels},
                      fresh_camera_unknown=0, development_unknown=0,
                      minimum_per_class=30, minimum_unknown=200,
                      status='insufficient-coverage'),
        threshold=config['threshold'],
        unknown_gate_calibrated=False,
        threshold_can_reject_uniform=config['threshold'] > 1/len(labels))


def validate_development(rows, config, frozen):
    if not isinstance(frozen, dict):
        raise ValueError('Complete development freeze required')
    recomputed = freeze_development(rows, config, frozen.get('validation_predictions'))
    if fingerprint(recomputed) != fingerprint(frozen):
        raise ValueError('Development freeze differs from recomputed evidence')
    return recomputed


def _rate(items, predicate):
    n = len(items)
    k = sum(predicate(p) for p in items)
    if not n:
        return dict(numerator=0, denominator=0, rate=None, wilson95=None)
    p, z = k/n, 1.959963984540054
    d = 1 + z*z/n
    center = (p + z*z/(2*n))/d
    margin = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))/d
    return dict(numerator=k, denominator=n, rate=p,
                wilson95=[max(0, center-margin), min(1, center+margin)])


def prediction_metrics(labels, threshold, predictions, baseline=None, mapping=None):
    """Descriptive metrics on exactly paired IDs; caller supplies provenance.

    Numeric quality criteria are not a fresh-data, independence or device gate.
    Unknown is truth outside the declared vocabulary; acceptance is explicit.
    """
    _number(threshold)
    if (not isinstance(labels, list) or len(labels) < 2
            or any(not isinstance(s, str) or not s.strip() or s == 'unknown' for s in labels)
            or len(set(labels)) != len(labels)):
        raise ValueError('Unique known labels required')
    if not isinstance(predictions, list):
        raise ValueError('Prediction list required')
    ids = set()
    for p in predictions:
        if (not isinstance(p, dict) or not isinstance(p.get('id'), str) or not p['id'].strip()
                or p['id'] in ids or p.get('truth') not in [*labels, 'unknown']):
            raise ValueError('Unique ID and declared truth required')
        ids.add(p['id'])
        scores = p.get('probabilities')
        if not isinstance(scores, list) or len(scores) != len(labels):
            raise ValueError('Full score vector required')
        for score in scores:
            _number(score)
        if (not math.isclose(sum(scores), 1, abs_tol=1e-5)
                or p.get('prediction') != labels[max(range(len(labels)), key=scores.__getitem__)]):
            raise ValueError('Invalid probability vector or argmax')
    known = [p for p in predictions if p['truth'] in labels]
    unknown = [p for p in predictions if p['truth'] == 'unknown']
    accepted = lambda p: max(p['probabilities']) >= threshold
    correct = lambda p: accepted(p) and p['prediction'] == p['truth']
    per_class = {label: _rate([p for p in known if p['truth'] == label], correct) for label in labels}
    report = dict(scope='descriptive supplied predictions; no fresh or physical acceptance',
        sample_ids=sorted(ids), top1=_rate(known, lambda p: p['prediction'] == p['truth']),
        known_correct_accepted=_rate(known, correct), known_rejected=_rate(known, lambda p: not accepted(p)),
        unknown_false_accept=_rate(unknown, accepted), per_class=per_class,
        threshold_can_reject_uniform=threshold > 1/len(labels), baseline={'status': 'NOT RUN'},
        quality_gate=None)
    if threshold <= 1/len(labels):
        report['quality_gate'] = False
    elif known and unknown and all(v['denominator'] for v in per_class.values()):
        report['quality_gate'] = (report['known_correct_accepted']['rate'] >= .85
            and report['unknown_false_accept']['rate'] <= .05
            and all(v['rate'] >= .75 for v in per_class.values()))
    if baseline is not None:
        if (not isinstance(mapping, dict) or not mapping
                or any(not isinstance(k, str) or not k.strip() or v not in [*labels, 'unknown']
                       for k, v in mapping.items())
                or not isinstance(baseline, list)
                or any(not isinstance(p, dict) or not isinstance(p.get('id'), str) for p in baseline)
                or len({p['id'] for p in baseline}) != len(baseline)
                or {p['id'] for p in baseline} != ids):
            raise ValueError('Explicit mapping and exact paired baseline IDs required')
        for p in baseline:
            if (type(p.get('accepted')) is not bool or not isinstance(p.get('raw_label'), str)
                    or p['raw_label'] not in mapping):
                raise ValueError('Unmapped baseline label or nonboolean acceptance')
        by_id = {p['id']: p for p in baseline}
        base_accepted = lambda p: by_id[p['id']]['accepted']
        base_correct = lambda p: base_accepted(p) and mapping[by_id[p['id']]['raw_label']] == p['truth']
        report['baseline'] = dict(status='paired-descriptive', sample_ids=sorted(ids),
            known_correct_accepted=_rate(known, base_correct),
            known_rejected=_rate(known, lambda p: not base_accepted(p)),
            unknown_false_accept=_rate(unknown, base_accepted),
            per_class={label: _rate([p for p in known if p['truth'] == label], base_correct) for label in labels})
    return report


def read_pin(pin):
    if not isinstance(pin, dict) or not isinstance(pin.get('path'), str):
        raise ValueError('Artifact path/hash pin required')
    raw = Path(pin['path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != _sha(pin.get('sha256')):
        raise ValueError('Artifact bytes changed: ' + pin['path'])
    return raw


def load_inputs(config):
    """Reuse accepted curation via immutable receipt, then bind actual model bytes."""
    pins = config['artifacts']
    manifest = json.loads(read_pin(pins['manifest']))
    accepted = json.loads(read_pin(pins['acceptance']))
    exported = json.loads(read_pin(pins['export']))
    model = read_pin(pins['model'])
    predictions = json.loads(read_pin(pins['predictions']))
    if (accepted.get('status') != 'accepted'
            or accepted.get('manifestSha256') != pins['manifest']['sha256']
            or config['dataset_sha256'] != pins['manifest']['sha256']
            or manifest.get('schema') != 'lexiquest-web-development-v1'
            or config['labels'] != manifest.get('labels')
            or config['labels'] != exported.get('labels')
            or exported.get('expectedSha256') != pins['model']['sha256']
            or config['candidate_model'] != pins['model']['sha256']
            or exported.get('expectedBytes') != len(model)
            or exported.get('trainingManifestSha256') != config['dataset_sha256']
            or exported.get('releaseEnabled') is not False
            or exported.get('distributionUri') is not None
            or exported.get('rollback', {}).get('sha256') != config['baseline_model']
            or exported.get('inputShape') != [1, 224, 224, 3]
            or exported.get('inputType') != 'uint8'
            or exported.get('inputEncoding') != 'rawUint8Rgb'
            or exported.get('outputType') != 'float32'
            or exported.get('outputShape') != [1, len(config['labels'])]
            or exported.get('backgroundClassIndex', -1) is not None):
        raise ValueError('Dataset/export/local candidate contract mismatch')
    with zipfile.ZipFile(pins['model']['path']) as archive:
        if archive.read('labels.txt').decode('utf-8').splitlines() != config['labels']:
            raise ValueError('Embedded labels differ from frozen class order')
    rows = manifest['samples']
    if len(rows) != accepted['retained'] or any(
            sum(r['split'] == s for r in rows) != n for s, n in accepted['splitCounts'].items()):
        raise ValueError('Accepted dataset counts differ')
    return rows, predictions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--verify', type=Path, help='Verify an existing freeze without changing it')
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8'))
    rows, predictions = load_inputs(config)
    if args.verify:
        frozen = json.loads(args.verify.read_text(encoding='utf-8'))
        result = validate_development(rows, config, frozen)
        if fingerprint(predictions) != result['validation_sha256']:
            raise ValueError('Pinned predictions differ from freeze')
    else:
        result = freeze_development(rows, config, predictions)
    with args.output.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps(dict(status='verified' if args.verify else 'development-frozen',
                          samples=len(predictions), decision=result['decision'])))


if __name__ == '__main__':
    main()
